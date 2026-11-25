# TITAN Stage 0 commands

Run the I-9 generator and checker on the baseline. The Stage 0 generator and checker are:

    python -E scripts/prepare_titan.py
    python -E scripts/check_titan.py
    python -E scripts/make_merged_sources.py --titan

Use the pinned byte-preserving replay noted in the S0 report if a Windows checkout has normalized baseline inputs.
From the replay directory, run the existing harness:

    python -E scripts/dual_lane.py preflight
    python -E scripts/dual_lane.py run --select I-T0

From the TITAN branch, compare the two variants after the harness finishes:

    python -E scripts/titan/compare_stage0.py <path-to-run-directory>

Stage 1 starts after all eight Stage 0 jobs pass fresh and paired observations and completion cycles match.
