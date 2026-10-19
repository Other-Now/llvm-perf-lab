//===- RangeCheckVersioning.cpp - range-check elimination by loop versioning ===//
//
// A Java-style bounds check inside a loop
//
//     for (i = lo; i < n; ++i) {
//       if ((unsigned)i >= (unsigned)len) throw_or_trap(i);   // never returns
//       ... a[i] ...
//     }
//
// is, to the optimizer, just a second loop exit whose target ends in
// `unreachable`.  That exit is never taken on the common path, but its mere
// presence makes the loop multi-exit, which blocks the loop vectorizer and
// keeps a compare+branch on the critical path of every iteration.
//
// This pass treats every exit that leads to an `unreachable` block as a
// "check exit" and every other exit as a "normal exit", and asks
// ScalarEvolution for the exact exit count of each.  If
//
//     NormalEC  <  CheckEC        (or <= when the normal exit is evaluated
//                                  first in the iteration)
//
// then the loop leaves through a normal exit before the check could ever
// fire.  When SCEV can prove that statically, the check is deleted outright.
// Otherwise the loop is versioned:
//
//     preheader:  cond = NormalEC < CheckEC_1 && NormalEC < CheckEC_2 ...
//                 br cond, fast.ph, slow.ph
//     fast loop:  original body with the proven check exits removed
//     slow loop:  untouched clone -- so if a check *does* fail, it fails at
//                 exactly the same iteration, after exactly the same side
//                 effects, as in the original program (precise exceptions).
//
// Working on exit counts rather than on `icmp` patterns means the pass does
// not care whether the check is still `icmp ult %iv, %len` or has already
// been rewritten by IndVarSimplify into `icmp ne %iv.wide, %len.wide` -- the
// form it is in by the time the vectorizer runs.  That is the main practical
// difference from upstream IRCE, which pattern-matches the former.
//
// Limitations (deliberate, see README): only innermost loops; only checks
// whose exiting block dominates the latch (SCEV does not compute exit counts
// for the others); one version per loop, no pre/main/post iteration-space
// splitting.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/AssumptionCache.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/Debug.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/Utils/Local.h"
#include "llvm/Transforms/Utils/LoopSimplify.h"
#include "llvm/Transforms/Utils/LoopUtils.h"
#include "llvm/Transforms/Utils/ScalarEvolutionExpander.h"
#include "llvm/Transforms/Utils/ValueMapper.h"

using namespace llvm;

#define DEBUG_TYPE "rce-version"

STATISTIC(NumLoopsVersioned, "Loops versioned on a range-check guard");
STATISTIC(NumChecksVersioned, "Check exits removed from a fast loop");
STATISTIC(NumChecksStatic, "Check exits removed without versioning");

namespace {

/// An exit whose target ends in `unreachable` (a call to a noreturn
/// bounds-failure handler, a trap, ...).
bool isCheckExitTarget(const BasicBlock *BB) {
  return isa<UnreachableInst>(BB->getTerminator());
}

struct CheckExit {
  BranchInst *Br;
  BasicBlock *Exit;  // the trap block
  BasicBlock *Stay;  // the in-loop successor
  const SCEV *EC;
  bool Inclusive;    // NormalEC <= EC suffices (normal exits are tested first)
};

class RangeCheckVersioningPass
    : public PassInfoMixin<RangeCheckVersioningPass> {
public:
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM);
  static bool isRequired() { return false; }

private:
  bool processLoop(Loop *L, LoopInfo &LI, DominatorTree &DT,
                   ScalarEvolution &SE, AssumptionCache &AC,
                   OptimizationRemarkEmitter &ORE);
};

void removeCheckExit(const CheckExit &C) {
  Value *Cond = C.Br->getCondition();
  C.Exit->removePredecessor(C.Br->getParent());
  BranchInst::Create(C.Stay, C.Br->getIterator());
  C.Br->eraseFromParent();
  // The pass runs immediately before the vectorizer with no cleanup in
  // between. A dead compare left here is still counted by its cost model and
  // register-pressure estimate, and cost the 3-point stencil half its
  // interleave count (IC 2 -> 1, +5% cycles) before this line existed.
  RecursivelyDeleteTriviallyDeadInstructions(Cond);
}

bool RangeCheckVersioningPass::processLoop(Loop *L, LoopInfo &LI,
                                           DominatorTree &DT,
                                           ScalarEvolution &SE,
                                           AssumptionCache &AC,
                                           OptimizationRemarkEmitter &ORE) {
  bool Changed = simplifyLoop(L, &DT, &LI, &SE, &AC, nullptr, false);
  Changed |= formLCSSARecursively(*L, DT, &LI, &SE);

  BasicBlock *PH = L->getLoopPreheader();
  BasicBlock *Latch = L->getLoopLatch();
  if (!PH || !Latch)
    return Changed;

  SmallVector<BasicBlock *, 8> Exiting;
  L->getExitingBlocks(Exiting);

  SmallVector<CheckExit, 4> Checks;
  SmallVector<const SCEV *, 4> NormalECs;
  SmallVector<BasicBlock *, 4> NormalBlocks;
  unsigned UnprovableChecks = 0;

  for (BasicBlock *BB : Exiting) {
    auto *BI = dyn_cast<BranchInst>(BB->getTerminator());
    if (!BI || !BI->isConditional())
      continue;
    bool In0 = L->contains(BI->getSuccessor(0));
    bool In1 = L->contains(BI->getSuccessor(1));
    if (In0 == In1)
      continue;
    BasicBlock *Exit = BI->getSuccessor(In0 ? 1 : 0);
    BasicBlock *Stay = BI->getSuccessor(In0 ? 0 : 1);
    const SCEV *EC = SE.getExitCount(L, BB);

    if (isCheckExitTarget(Exit)) {
      if (isa<SCEVCouldNotCompute>(EC)) {
        ++UnprovableChecks;
        continue;
      }
      Checks.push_back({BI, Exit, Stay, EC, false});
    } else if (!isa<SCEVCouldNotCompute>(EC)) {
      // A normal exit we cannot count (data-dependent `break`) can only make
      // the loop shorter, so it is safe to ignore.
      NormalECs.push_back(EC);
      NormalBlocks.push_back(BB);
    }
  }

  Function *F = L->getHeader()->getParent();
  if (Checks.empty()) {
    if (UnprovableChecks)
      ORE.emit([&] {
        return OptimizationRemarkMissed(DEBUG_TYPE, "NoComputableCheck",
                                        L->getStartLoc(), L->getHeader())
               << "range check(s) not versioned: exit count not computable "
                  "(non-affine index, or check does not dominate the latch)";
      });
    return Changed;
  }
  if (NormalECs.empty()) {
    ORE.emit([&] {
      return OptimizationRemarkMissed(DEBUG_TYPE, "NoTripCount",
                                      L->getStartLoc(), L->getHeader())
             << "range check(s) not versioned: loop trip count not computable";
    });
    return Changed;
  }

  const SCEV *NormalEC = SE.getUMinFromMismatchedTypes(NormalECs);

  // Decide, per check, whether it is statically dead, needs a runtime guard,
  // or always fires (in which case versioning is pointless).
  SmallVector<CheckExit, 4> Static, Guarded;
  for (CheckExit &C : Checks) {
    C.Inclusive = all_of(NormalBlocks, [&](BasicBlock *NB) {
      return NB != C.Br->getParent() && DT.dominates(NB, C.Br->getParent());
    });
    Type *Ty = SE.getWiderType(NormalEC->getType(), C.EC->getType());
    const SCEV *A = SE.getNoopOrZeroExtend(NormalEC, Ty);
    const SCEV *B = SE.getNoopOrZeroExtend(C.EC, Ty);
    C.EC = B;
    ICmpInst::Predicate P = C.Inclusive ? ICmpInst::ICMP_ULE : ICmpInst::ICMP_ULT;
    if (SE.isKnownPredicate(P, A, B))
      Static.push_back(C);
    else if (!SE.isKnownPredicate(ICmpInst::getInversePredicate(P), A, B))
      Guarded.push_back(C);
  }

  for (const CheckExit &C : Static) {
    removeCheckExit(C);
    ++NumChecksStatic;
  }
  if (!Static.empty()) {
    // A trap block whose only predecessors were the removed checks is dead.
    // (Several checks may share one trap block: dedupe before deleting.)
    SmallPtrSet<BasicBlock *, 4> Dead;
    for (const CheckExit &C : Static)
      if (pred_empty(C.Exit))
        Dead.insert(C.Exit);
    for (BasicBlock *BB : Dead) {
      LI.removeBlock(BB);
      DeleteDeadBlock(BB);
    }
    DT.recalculate(*F);
    SE.forgetLoop(L);
    ORE.emit([&] {
      return OptimizationRemark(DEBUG_TYPE, "CheckEliminated", L->getStartLoc(),
                                L->getHeader())
             << "removed " << ore::NV("NumChecks", (unsigned)Static.size())
             << " range check(s) proven in bounds at compile time";
    });
    Changed = true;
  }
  if (Guarded.empty())
    return Changed;

  // Make sure every guard can be materialised in the preheader.
  const DataLayout &DL = F->getDataLayout();
  SCEVExpander Exp(SE, DL, "rce");
  Instruction *PHTerm = PH->getTerminator();
  if (!Exp.isSafeToExpandAt(NormalEC, PHTerm) ||
      any_of(Guarded, [&](const CheckExit &C) {
        return !Exp.isSafeToExpandAt(C.EC, PHTerm);
      })) {
    ORE.emit([&] {
      return OptimizationRemarkMissed(DEBUG_TYPE, "UnsafeExpansion",
                                      L->getStartLoc(), L->getHeader())
             << "range check(s) not versioned: guard is not safe to expand";
    });
    return Changed;
  }

  // 1. Guard in the old preheader.
  IRBuilder<> B(PHTerm);
  Value *Cond = nullptr;
  for (const CheckExit &C : Guarded) {
    Type *Ty = C.EC->getType();
    Value *N = Exp.expandCodeFor(SE.getNoopOrZeroExtend(NormalEC, Ty), Ty,
                                 PHTerm->getIterator());
    Value *E = Exp.expandCodeFor(C.EC, Ty, PHTerm->getIterator());
    Value *Ok = C.Inclusive ? B.CreateICmpULE(N, E, "rce.ok")
                            : B.CreateICmpULT(N, E, "rce.ok");
    Cond = Cond ? B.CreateAnd(Cond, Ok, "rce.ok") : Ok;
  }

  // 2. New (empty) preheader for the fast loop; clone loop + preheader.
  BasicBlock *FastPH = SplitBlock(PH, PHTerm, &DT, &LI, nullptr,
                                  L->getHeader()->getName() + ".rce.fast.ph");
  PH->setName(L->getHeader()->getName() + ".rce.check");

  SmallVector<BasicBlock *, 4> ExitBlocks;
  L->getUniqueExitBlocks(ExitBlocks);

  ValueToValueMapTy VMap;
  SmallVector<BasicBlock *, 16> SlowBlocks;
  Loop *Slow = cloneLoopWithPreheader(FastPH, PH, L, VMap, ".rce.slow", &LI,
                                      &DT, SlowBlocks);
  remapInstructionsInBlocks(SlowBlocks, VMap);

  Instruction *OldTerm = PH->getTerminator();
  BranchInst::Create(FastPH, Slow->getLoopPreheader(), Cond,
                     OldTerm->getIterator());
  OldTerm->eraseFromParent();

  // 3. Both loops now feed the original exit blocks; extend the LCSSA phis.
  for (BasicBlock *X : ExitBlocks)
    for (PHINode &P : X->phis()) {
      unsigned N = P.getNumIncomingValues();
      for (unsigned I = 0; I < N; ++I) {
        BasicBlock *In = P.getIncomingBlock(I);
        if (!L->contains(In))
          continue;
        Value *V = P.getIncomingValue(I);
        if (Value *M = VMap.lookup(V))
          V = M;
        P.addIncoming(V, cast<BasicBlock>(VMap[In]));
      }
    }

  // 4. Drop the proven checks from the fast (original) loop only.
  for (const CheckExit &C : Guarded)
    removeCheckExit(C);

  // Exit blocks changed predecessors; rebuild the tree rather than patch it.
  DT.recalculate(*F);
  SE.forgetLoop(L);

  NumLoopsVersioned++;
  NumChecksVersioned += Guarded.size();
  ORE.emit([&] {
    return OptimizationRemark(DEBUG_TYPE, "LoopVersioned", L->getStartLoc(),
                              L->getHeader())
           << "versioned loop on " << ore::NV("NumChecks", (unsigned)Guarded.size())
           << " range check(s); fast copy is check-free";
  });
  LLVM_DEBUG(dbgs() << "rce-version: versioned " << *L << "\n");
  return true;
}

PreservedAnalyses RangeCheckVersioningPass::run(Function &F,
                                                FunctionAnalysisManager &FAM) {
  auto &LI = FAM.getResult<LoopAnalysis>(F);
  auto &DT = FAM.getResult<DominatorTreeAnalysis>(F);
  auto &SE = FAM.getResult<ScalarEvolutionAnalysis>(F);
  auto &AC = FAM.getResult<AssumptionAnalysis>(F);
  auto &ORE = FAM.getResult<OptimizationRemarkEmitterAnalysis>(F);

  // Snapshot first: versioning adds sibling loops we must not revisit.
  SmallVector<Loop *, 8> Worklist;
  for (Loop *L : LI.getLoopsInPreorder())
    if (L->isInnermost())
      Worklist.push_back(L);

  bool Changed = false;
  for (Loop *L : Worklist)
    Changed |= processLoop(L, LI, DT, SE, AC, ORE);

  if (!Changed)
    return PreservedAnalyses::all();
  PreservedAnalyses PA;
  PA.preserve<LoopAnalysis>();
  PA.preserve<DominatorTreeAnalysis>();
  return PA;
}

} // namespace

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "RangeCheckVersioning", "0.1",
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name != "rce-version")
                    return false;
                  FPM.addPass(RangeCheckVersioningPass());
                  return true;
                });
            // With `clang -fpass-plugin=` / `opt -O3`, run right before the
            // loop vectorizer: that is where a check-free loop pays off.
            PB.registerVectorizerStartEPCallback(
                [](FunctionPassManager &FPM, OptimizationLevel Level) {
                  if (Level.getSpeedupLevel() >= 2)
                    FPM.addPass(RangeCheckVersioningPass());
                });
          }};
}
