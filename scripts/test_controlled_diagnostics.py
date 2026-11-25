"""Fault injections into synthetic logs, never presented as simulator evidence."""
import unittest
from controlled_diagnostics import PHASES, GUARDED_COVERAGE
from dual_lane_verify import InvalidEvidence, judge


def block(scope, filename, line, action, message):
    return (f'Time: 10 ns Started: 10 ns Scope: {scope} File: C:/fixture/{filename} Line:{line}\n'
            f'Error: {message}\n'
            f'Time: 10 ns  Iteration: 2  Process: /fixture '
            f'Scope: {scope.lstrip("/").replace("/", ".")}  File: C:/fixture/{filename} Line: {action}\n')


OVERFLOW = 'noc_fifo: FLIT DROPPED - write attempted while full. Credit flow control is missing or broken.'
UNDERFLOW = 'noc_fifo: read attempted while empty'
HOT = 'noc_router_datapath: multiple VCs selected on NORTH input'
FIFO_BLOCK = block('/tb_noc_stage2/dut_fifo_a', 'NOC_FIFO.sv', 279, 280, OVERFLOW)


def tb1_fixture():
    chunks = []
    for phase in PHASES:
        chunks.append(phase + '\n')
        if phase == PHASES[0]:
            chunks += [FIFO_BLOCK, block('/tb_noc_stage2/dut_fifo_b', 'NOC_FIFO.sv', 292, 293, UNDERFLOW)]
        elif phase == PHASES[6]:
            chunks.append(block('/tb_noc_stage2/dut_dp', 'NOC_DATAPTAH.sv', 852, 853, HOT))
    chunks += [f'{name} : PASS (0 failures)\n' for name in
               ('noc_pkg', 'noc_fifo', 'noc_crossbar', 'noc_xy_routing', 'noc_router_datapath', 'negative control')]
    chunks.append('OVERALL : PASS (0 failures)\n')
    chunks += [f'{name} : 1\n' for name in GUARDED_COVERAGE]
    chunks += ['NEG defects injected/detected : 2 / 2\n', 'All guarded states were exercised.\n',
               'Negative control fired: this testbench can fail.\n']
    return ''.join(chunks)


def n6_fixture(kind='n6_a'):
    phase, label = {'n6_a': ('T11', 'T11 head flit held stable'),
                    'n6_b_t5': ('T4/T5', 'T5 credit propagates back to R0 EAST'),
                    'n6_c': ('T13', 'T13 in_ready_local=0')}[kind]
    chunks = ['MUTATION_WINDOW: T5 ENTER\n'] if kind == 'n6_b_t5' else []
    chunks += [f'=== {phase} targeted test ===\n', '[PASS] prior check\n' * 125, f'[FAIL] {label}\n']
    if kind == 'n6_a':
        chunks += [block('/tb_n6_two_tile_stress/r1', 'noc_router.sv', 675, 677,
                         'noc_router: LOCAL out_flit changed before acceptance'),
                   block('/tb_n6_two_tile_stress/ni1', 'noc_network_interface.sv', 1756, 1757,
                         'M10: upstream dropped or changed a stalled RX flit')]
    if kind == 'n6_c':
        chunks.append(block('/tb_n6_two_tile_stress/r0/u_datapath/local_vc0_fifo',
                            'NOC_FIFO.sv', 279, 280, OVERFLOW))
    if kind == 'n6_b_t5':
        chunks.append('MUTATION_WINDOW: T5 EXIT\n')
    chunks.append('N-6 TWO-TILE STRESS RESULT\nChecks = 126\nErrors = 1\nRESULT = FAIL\n')
    return ''.join(chunks)


class ControlledDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.proc = {s: dict(exitCode=0, timedOut=False) for s in ('compile', 'elaborate', 'simulate')}
        self.tb1 = dict(judge='tb1', checks=0)

    def check(self, text, job=None):
        return judge(text, self.tb1 if job is None else job, self.proc, {}, {})

    def reject(self, text, job=None):
        with self.assertRaises(InvalidEvidence):
            self.check(text, job)

    def n6_job(self, kind='n6_a'):
        return dict(mutant=kind, checks=126, oracle=r'^\[FAIL\] T(?:5|11|13) ')

    def test_intended_tb1_controls_are_retained_in_observation(self):
        self.assertEqual(self.check(tb1_fixture())['intentional_diagnostics'],
                         dict(overflow=1, underflow=1, multi_hot=1))

    def test_same_assertion_in_legal_phase_is_rejected(self):
        self.reject(tb1_fixture().replace(PHASES[2] + '\n', PHASES[2] + '\n' + FIFO_BLOCK))

    def test_other_instance_is_rejected(self):
        self.reject(tb1_fixture().replace('dut_fifo_a', 'dut_fifo_unknown'))

    def test_wrong_source_location_is_rejected(self):
        self.reject(tb1_fixture().replace('Line: 280', 'Line: 999'))

    def test_unrelated_assertion_in_negative_phase_is_rejected(self):
        self.reject(tb1_fixture().replace(OVERFLOW, 'noc_fifo: occupancy corrupt'))

    def test_guarded_coverage_hole_with_pass_is_rejected(self):
        self.reject(tb1_fixture().replace('XY route WEST : 1', 'XY route WEST : 0'))

    def test_missing_negative_control_is_rejected(self):
        self.reject(tb1_fixture().replace('2 / 2', '1 / 2'))

    def test_missing_phase_is_rejected(self):
        self.reject(tb1_fixture().replace(PHASES[8] + '\n', ''))

    def test_multi_hot_count_disagrees_with_coverage(self):
        self.reject(tb1_fixture().replace('DP multi-hot VC select : 1', 'DP multi-hot VC select : 2'))

    def test_all_n6_targeted_results(self):
        for kind in ('n6_a', 'n6_b_t5', 'n6_c'):
            self.assertEqual(self.check(n6_fixture(kind), self.n6_job(kind))['result'], 'KILLED')

    def test_n6_unrelated_assertion_is_rejected(self):
        self.reject(n6_fixture() + 'Error: unrelated datapath assertion\n', self.n6_job())

    def test_n6_wrong_assertion_scope_is_rejected(self):
        self.reject(n6_fixture().replace('/tb_n6_two_tile_stress/r1', '/tb_n6_two_tile_stress/r0'), self.n6_job())

    def test_n6_failure_outside_target_is_rejected(self):
        self.reject(n6_fixture().replace('=== T11 targeted test ===', '=== T8 other test ==='), self.n6_job())

    def test_n6_counters_must_match_raw_checks(self):
        self.reject(n6_fixture().replace('Errors = 1', 'Errors = 2'), self.n6_job())

    def test_n6_timeout_after_target_is_never_a_kill(self):
        self.reject(n6_fixture() + '[FATAL] N-6 STRESS TIMEOUT\n', self.n6_job())

    def test_credit_window_requires_exit(self):
        self.reject(n6_fixture('n6_b_t5').replace('MUTATION_WINDOW: T5 EXIT\n', ''), self.n6_job('n6_b_t5'))
