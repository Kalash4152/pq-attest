"""Negative controls for the coverage runner's mandatory tool diagnostics."""
from pathlib import Path
import tempfile
import unittest
from run_r10_coverage import checked_log,module_scores

class DiagnosticControls(unittest.TestCase):
    def test_logs(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'tool.log'
            for bad in ['', 'ERROR: compile failed\n',' FATAL: runtime aborted\n',
                        'WARNING: [XSIM 43-5031] Code Coverage Options cannot be used in standalone mode\n']:
                p.write_text(bad)
                with self.subTest(bad=bad),self.assertRaises(RuntimeError):checked_log(p)
            p.write_text('INFO: simulation complete\n')
            self.assertEqual(checked_log(p),'INFO: simulation complete\n')

    def test_score_parser(self):
        with self.assertRaises(RuntimeError):module_scores('<table></table>')
        row='<tr>'+''.join('<td>'+c+'</td>' for c in
            ['1','<a>dut</a>','2','tb.dut','98.5','30','50','60','dut.sv','1'])+'</tr>'
        scores=module_scores(row)
        self.assertEqual(scores[0]['statement_percent'],'98.5')
        self.assertEqual(scores[0]['module'],'dut')

if __name__=='__main__':unittest.main()
