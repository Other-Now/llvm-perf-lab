import os
import lit.formats

config.name = "rce-version"
config.test_format = lit.formats.ShTest(True)
config.suffixes = [".ll"]
config.test_source_root = os.path.dirname(__file__)

build = os.environ.get("LPL_BUILD", os.path.expanduser("~/lpl-build"))
plugin = os.path.join(build, "RangeCheckVersioning.so")
config.substitutions.append(("%opt", "opt -load-pass-plugin " + plugin))
config.substitutions.append(("%irce", "opt -passes=irce -irce-skip-profitability-checks"))

# FileCheck / not / opt come from the LLVM on PATH (scripts/env.sh).
config.environment["PATH"] = os.environ["PATH"]
config.environment["LD_LIBRARY_PATH"] = os.environ.get("LD_LIBRARY_PATH", "")
