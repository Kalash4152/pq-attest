"""Generate a separate N-6 bench; keep every original check and DUT assertion."""
import difflib
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'NOC_PQATTEST.srcs/sources_1/new/tb6_1.sv'
OUTPUT = 'sim/dual_lane/n6_credit_window/tb6_1.sv'


def generate(root=ROOT):
    root = Path(root)
    original = root / SOURCE
    raw = original.read_bytes()
    before = hashlib.sha256(raw).hexdigest()
    text = original.read_text(encoding='utf-8-sig')
    declaration = '    initial begin\n        checks = 0; errors = 0; cycle_count = 0; stress_tx_count = 0;'
    call = '        test_credit_exhaustion_return;\n'
    if text.count(declaration) != 1 or text.count(call) != 1:
        raise ValueError('Nonunique N-6 bench generation anchor')
    variant = text.replace(declaration,
        "    // Simulation-only window for the credit-loss negative control.\n"
        "    logic credit_mutation_active = 1'b0;\n\n" + declaration)
    variant = variant.replace(call,
        "        credit_mutation_active = 1'b1;\n"
        '        $display("MUTATION_WINDOW: T5 ENTER");\n' + call +
        "        @(negedge clk); credit_mutation_active = 1'b0;\n"
        '        $display("MUTATION_WINDOW: T5 EXIT");\n')
    if hashlib.sha256(original.read_bytes()).hexdigest() != before:
        raise ValueError('Original N-6 bench changed during generation')
    target = root / OUTPUT
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(variant, encoding='utf-8', newline='\n')
    delta = dict(source=SOURCE, source_sha256=before, variant=OUTPUT,
                 variant_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                 scope='Credit loss active only inside the original T4/T5 task; all 126 checks retained',
                 original_unchanged=True,
                 diff=''.join(difflib.unified_diff(text.splitlines(True), variant.splitlines(True),
                                                fromfile=SOURCE, tofile=OUTPUT)))
    (target.parent / 'source_delta.json').write_text(json.dumps(delta, indent=2) + '\n',
                                                   encoding='utf-8', newline='\n')
    return delta


if __name__ == '__main__':
    generate()
