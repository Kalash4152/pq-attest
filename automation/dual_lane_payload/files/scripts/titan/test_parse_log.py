"""Exercise the Stage 1 golden log reader before any HDL jobs run."""
from parse_log import parse

VALID = "CHECKS : 6\nERRORS : 0\nRESULT : PASS\n$finish called at time : 200 ns\n"
if parse(VALID, 6) != "10":
    raise SystemExit("valid log did not yield the expected cycle count")

controls = {
    "pass_with_error": VALID + "$error: unexpected assertion\n",
    "missing_pass": VALID.replace("RESULT : PASS\n", ""),
    "truncated_after_pass": VALID.split("$finish")[0],
}
for name, log in controls.items():
    try:
        parse(log, 6)
    except ValueError:
        print(f"{name}: rejected")
    else:
        raise SystemExit(f"{name}: accepted invalid log")
print("TITAN_PARSE_LOG: PASS cases=4 rejected=3")
