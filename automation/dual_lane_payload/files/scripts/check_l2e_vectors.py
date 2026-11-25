"""Job l2e_vectors_check: regenerate the step-c engine vectors with the pinned teammate kmac128 and compare with the
committed files (scripts/gen_l2e_vectors.py --check). Prints L2E_VECTORS_CHECK: PASS or exits non-zero."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.argv = [sys.argv[0], '--check']
import gen_l2e_vectors
gen_l2e_vectors.main()
