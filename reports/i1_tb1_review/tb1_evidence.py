"""Recognize TB1's deliberate diagnostics without hiding real assertions."""
from collections import Counter
import re


class TB1EvidenceError(ValueError):
    pass


PHASES = (
    '[FIFO] write-biased, overflow attempts (DUT assertion off)',
    '[FIFO] read-biased, underflow attempts (DUT assertion off)',
    '[FIFO] balanced legal traffic, DUT assertions armed',
    '[FIFO] reset asserted mid-traffic',
    '[DP  ] NORTH-only traffic, port independence',
    '[DP  ] all ports write-heavy, fills all 15 FIFOs',
    '[DP  ] multi-hot VC select, priority resolution',
    '[DP  ] drain all 15 FIFOs, DUT assertions armed',
    '[DP  ] deterministic burst: fill NORTH VC0+VC1+VC2 together',
    '[NEG ] negative control - deliberate defect injection',
)
FIFO_PHASES = set(PHASES[:2])
DP_PHASES = set(PHASES[5:7])
MESSAGES = {
    'noc_fifo: FLIT DROPPED - write attempted while full. Credit flow control is missing or broken.':
        ('overflow', 'NOC_FIFO.sv', 279, 280),
    'noc_fifo: read attempted while empty':
        ('underflow', 'NOC_FIFO.sv', 292, 293),
    'noc_router_datapath: multiple VCs selected on NORTH input':
        ('multi_hot', 'NOC_DATAPTAH.sv', 852, 853),
}
GUARDED_COVERAGE = (
    'FIFO full', 'FIFO empty', 'FIFO simultaneous r/w at full',
    'FIFO simultaneous r/w mid', 'FIFO overflow attempted',
    'FIFO underflow attempted', 'FIFO depth-6 full',
    'XBAR legal selects', 'XBAR illegal selects',
    'XY route EAST', 'XY route WEST', 'XY route NORTH', 'XY route SOUTH',
    'XY route LOCAL', 'XY route rejected', 'DP VC0 write', 'DP VC1 write',
    'DP VC2 write', 'DP all three VCs full', 'DP all five ports active',
    'DP multi-hot VC select',
)
BLOCK = re.compile(
    r'^Time: (?P<time>\d+(?:\.\d+)? (?:ps|ns|us|ms)) Started: \d+(?:\.\d+)? (?:ps|ns|us|ms) '
    r'Scope: (?P<scope>/\S+) File: (?P<file>[^\r\n]+) Line:(?P<line>\d+)\r?\n'
    r'Error: (?P<message>[^\r\n]+)\r?\n'
    r'Time: (?P=time) +Iteration: \d+ +Process: \S+ +'
    r'Scope: (?P<scope2>\S+) +File: (?P<file2>[^\r\n]+) Line: (?P<line2>\d+)\r?\n',
    re.M,
)


def one(text, pattern, label):
    values = re.findall(pattern, text, re.M)
    if len(values) != 1:
        raise TB1EvidenceError(f'TB1 {label}: expected exactly one, observed {len(values)}')
    return values[0]


def adjudicate_tb1(text):
    """Return text with only proven intentional diagnostic blocks removed."""
    phase_events = list(re.finditer(r'^\[(?:FIFO|DP  |NEG )\][^\r\n]*$', text, re.M))
    phases = [p.group().rstrip('\r') for p in phase_events]
    if phases != list(PHASES):
        raise TB1EvidenceError('TB1 missing, repeated or out-of-order stimulus phase')
    for name in ('noc_pkg', 'noc_fifo', 'noc_crossbar', 'noc_xy_routing',
                 'noc_router_datapath', 'negative control'):
        one(text, r'^\s*' + re.escape(name) + r'\s*:\s*(PASS)\s+\(0 failures\)\s*$', name)
    coverage = {}
    for name in GUARDED_COVERAGE:
        value = int(one(text, r'^\s*' + re.escape(name) + r'\s*:\s*(\d+)\s*$', name))
        if value == 0:
            raise TB1EvidenceError('TB1 unexercised guarded state: ' + name)
        coverage[name] = value
    one(text, r'^\s*NEG defects injected/detected\s*:\s*(2 / 2)\s*$', 'negative controls')
    one(text, r'^\s*(All guarded states were exercised\.)\s*$', 'coverage completion')
    one(text, r'^\s*(Negative control fired: this testbench can fail\.)\s*$', 'negative completion')
    if 'COVERAGE HOLE' in text:
        raise TB1EvidenceError('TB1 coverage hole')
    counts = Counter()
    by_phase = Counter()

    def strip(block):
        b = block.groupdict()
        phase = next((p.group().rstrip('\r') for p in reversed(phase_events)
                      if p.start() < block.start()), '')
        spec = MESSAGES.get(b['message'])
        if spec is None:
            return block.group()
        kind, filename, source_line, action_line = spec
        scope = b['scope']
        scope_matches = b['scope2'] == scope.lstrip('/').replace('/', '.')
        file_matches = (b['file'] == b['file2'] and
                        b['file'].replace('\\', '/').endswith('/' + filename))
        lines_match = int(b['line']) == source_line and int(b['line2']) == action_line
        fifo_scope = bool(re.fullmatch(r'/tb_noc_stage2/dut_fifo_[ab]', scope))
        dp_fifo_scope = bool(re.fullmatch(
            r'/tb_noc_stage2/dut_dp/(north|south|east|west|local)_vc[012]_fifo', scope))
        intended = ((kind in ('overflow', 'underflow') and
                     ((phase in FIFO_PHASES and fifo_scope) or
                      (phase in DP_PHASES and dp_fifo_scope))) or
                    (kind == 'multi_hot' and phase == PHASES[6] and
                     scope == '/tb_noc_stage2/dut_dp'))
        if not (scope_matches and file_matches and lines_match and intended):
            return block.group()
        counts[kind] += 1
        by_phase[(phase, kind)] += 1
        return ''

    cleaned = BLOCK.sub(strip, text)
    if not all(counts[k] > 0 for k in ('overflow', 'underflow', 'multi_hot')):
        raise TB1EvidenceError('TB1 deliberate diagnostic control did not fire')
    if counts['multi_hot'] != coverage['DP multi-hot VC select']:
        raise TB1EvidenceError('TB1 multi-hot diagnostics disagree with observed coverage')
    return cleaned, dict(coverage=coverage, intentional_diagnostics=dict(counts),
                         diagnostics_by_phase=[dict(phase=p, kind=k, count=n)
                                               for (p, k), n in sorted(by_phase.items())])


def adjudicate_n6_mutant(text, kind, expected_checks, errors):
    """Admit only assertions caused by the particular injected N-6 defect."""
    allowed_phases = {'n6_a': ('T11', 'T12'), 'n6_b_t5': ('T4/T5',), 'n6_c': ('T13',)}[kind]
    phase_events = list(re.finditer(r'^=== (\S+)[^\r\n]*===$', text, re.M))
    outcomes = list(re.finditer(r'^\[(PASS|FAIL)\] ([^\r\n]+)$', text, re.M))
    if len(outcomes) != expected_checks or sum(o[1] == 'FAIL' for o in outcomes) != errors:
        raise TB1EvidenceError('N-6 mutant result counters disagree with per-check log')
    for outcome in outcomes:
        phase = next((p[1] for p in reversed(phase_events) if p.start() < outcome.start()), '')
        if outcome[1] == 'FAIL' and phase not in allowed_phases:
            raise TB1EvidenceError('N-6 mutant failed outside its targeted test: ' + outcome[2])
    result_pos = text.index('N-6 TWO-TILE STRESS RESULT')
    counts = Counter()
    specs = {
        'n6_a': {
            'noc_router: LOCAL out_flit changed before acceptance':
                ('router_hold', '/tb_n6_two_tile_stress/r1', 'noc_router.sv', 675, 677),
            'M10: upstream dropped or changed a stalled RX flit':
                ('ni_hold', '/tb_n6_two_tile_stress/ni1', 'noc_network_interface.sv', 1756, 1757),
        },
        'n6_b_t5': {},
        'n6_c': {
            'noc_fifo: FLIT DROPPED - write attempted while full. Credit flow control is missing or broken.':
                ('local_overflow', '/tb_n6_two_tile_stress/r0/u_datapath/local_vc0_fifo', 'NOC_FIFO.sv', 279, 280),
        },
    }[kind]

    def strip(block):
        b = block.groupdict()
        spec = specs.get(b['message'])
        phase = next((p[1] for p in reversed(phase_events) if p.start() < block.start()), '')
        if not spec or phase not in allowed_phases or block.start() >= result_pos:
            return block.group()
        name, scope, filename, first_line, action_line = spec
        if (b['scope'] != scope or b['scope2'] != scope.lstrip('/').replace('/', '.') or
                b['file'] != b['file2'] or not b['file'].replace('\\', '/').endswith('/' + filename) or
                int(b['line']) != first_line or int(b['line2']) != action_line):
            return block.group()
        counts[name] += 1
        return ''

    cleaned = BLOCK.sub(strip, text)
    if kind == 'n6_b_t5':
        one(text, r'^(MUTATION_WINDOW: T5 ENTER)$', 'credit mutation entry')
        one(text, r'^(MUTATION_WINDOW: T5 EXIT)$', 'credit mutation recovery')
    elif not counts:
        raise TB1EvidenceError('N-6 targeted DUT assertion did not fire')
    return cleaned, dict(targeted_diagnostics=dict(counts), per_check_count=len(outcomes),
                         failing_checks=[o[2] for o in outcomes if o[1] == 'FAIL'])
