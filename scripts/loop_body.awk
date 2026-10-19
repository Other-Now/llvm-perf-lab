# Prints the body of the first innermost loop (as tagged by LLVM's
# "Inner Loop Header" comment) inside function FN whose text matches PAT,
# without its label -- ready to feed to llvm-mca.
#   awk -v FN=micro8x8 -v PAT=vfmadd -f loop_body.awk file.s
$0 ~ "^" FN ":" { infn = 1; next }
infn && /^\.Lfunc_end/ { infn = 0 }
!infn || done { next }
/Inner Loop Header/ {
  label = $1; sub(":", "", label); body = ""; cap = 1; next
}
cap {
  if ($0 ~ /^\s*(\.|#|\/\/)/) next          # directives and comments
  body = body $0 "\n"
  n = split($0, f, /[ \t,]+/)
  if (f[n] == label) {                      # back-edge to the header
    cap = 0
    if (body ~ PAT) { printf "%s", body; done = 1 }
  }
}
