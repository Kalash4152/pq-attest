"""Build the owner completion report as HTML from accepted facts only (Claude takeover, 2026-11-12).
Word converts the HTML to .docx / .pdf (scripts/render_completion_report.ps1). Replaces the python-docx builder for
this machine (python-docx is not installed); content follows scripts/build_completion_report.py with corrections.
Usage: python -I scripts/build_completion_report_html.py <facts.json> <out.html>
"""
import html
import json
import sys
from pathlib import Path

f = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
for k in ('i24', 'i25', 'i26'):
    assert f[k]['gate'] == 'PASS', k
assert f['i24']['seeds'] == 1000 and f['secure']['gate'] == 'PASS' and f['fixed']['gate'] == 'PASS' and f['worker']['gate'] == 'PASS'
E = html.escape


def table(headers, rows, widths=None):
    out = ['<table>', '<tr>' + ''.join(f'<th{" width=" + chr(34) + str(w) + "%" + chr(34) if widths else ""}>{E(h)}</th>'
                                      for h, w in zip(headers, widths or [0] * len(headers))) + '</tr>']
    for i, r in enumerate(rows):
        out.append(f'<tr class="{"alt" if i % 2 else ""}">' + ''.join(f'<td>{E(str(c)).replace(chr(10), "<br>")}</td>' for c in r) + '</tr>')
    return '\n'.join(out) + '\n</table>'


def p(t): return f'<p>{E(t)}</p>'
def h1(t, brk=False): return ('<br clear="all" style="page-break-before:always">' if brk else '') + f'<h1>{E(t)}</h1>'
def bullets(items): return '<ul>' + ''.join(f'<li>{E(i)}</li>' for i in items) + '</ul>'


s, x = f['secure'], f['fixed']
delta = s['lut'] - x['lut']
B = []
B.append('<p class="title">Combined RTL verification and FPGA release report</p>')
B.append(p(f'Prepared for Kalash Bheda  |  {f["date"]}  |  NoC + PQ-Attest + two RISC-V CPU tiles on xc7a100tcsg324-1'))
B.append(p('The approved work through steps 1 to 11 is complete for the FPGA release candidate described here. Two real RISC-V CPU '
           'tiles, the six-tile NoC and PQ-Attest are combined in one gated image. The board run on the exact final image (step 12) '
           'belongs to Kalash and has not been done for this image. ASIC / GDSII work has not started.'))
B.append(h1('Final combined FPGA results'))
B.append(table(['Configuration', 'LUT', 'FF', 'BRAM36', 'WNS ns', 'WHS ns'],
               [['Secure release (production candidate)', f'{s["lut"]:,}', f'{s["ff"]:,}', s['bram36'], f'+{s["wns"]:.3f}', f'+{s["whs"]:.3f}'],
                ['Fixed-admission experiment (research only)', f'{x["lut"]:,}', f'{x["ff"]:,}', x['bram36'], f'+{x["wns"]:.3f}', f'+{x["whs"]:.3f}']],
               [40, 12, 12, 12, 12, 12]))
B.append(p('Part xc7a100tcsg324-1; one 20 ns design clock from the 100 MHz board input through the MMCM. LUT hard stop 47,550: within. '
           'Route errors 0, DRC errors 0, timing checks clean, firmware present in both CPUs. The same secure numbers were reproduced by three '
           'separate builds (I-25 harness, detached release helper, I-26 clean-directory replay). The hold margin is small (+0.009 ns): it meets '
           'the criterion and is reported as measured. The fixed-admission image is a research ablation and must never be programmed as the secure release.'))
B.append(h1('Evidence boundaries'))
B.append(p('Implemented, reference-checked, registered XSim-simulated, mutation-tested and routed-FPGA results are kept separate in the gate reports. '
           'HARDWARE_VALIDATED = NO for this image (the 7 November owner-reported board PASS belongs to the earlier v1 image). '
           'SOC_INTEGRATION_COMPLETE = NO pending the exact-image board record. FORMAL_PROOF = NO.'))
B.append(table(['Item', 'Value'],
               [['Code revision', f['code_commit']],
                ['Release image (detached helper, merged_result)', s['bitstream_sha256']],
                ['I-25 harness image', f['i25']['bitstream_sha256']],
                ['I-26 clean-replay image', f['i26']['bitstream_sha256']],
                ['Why three hashes', 'A bitstream embeds its build time, so identical sources give different hashes. Record the hash of the image you program.']],
               [32, 68]))

B.append(h1('Approved work completion checklist', True))
checklist = [
    ('1', 'Scope and revision 9 contract', 'Signed decisions; physical and protocol boundaries unchanged'),
    ('2', 'Real CPU error acceptance', 'I-18: handler entry and ordering, causal IRQ control'),
    ('3', 'RTL corrections and interfaces', 'I-19: timeout propagation, parameter guards, debug tap, NI status registers'),
    ('4', 'Firmware and provisioning', 'I-20: bounded v2 firmware, independent reference qualification'),
    ('5', 'Merged adversarial scenarios', 'I-21, I-23, I-25: error, revoke, in-flight revoke, recovery, contention'),
    ('6', 'Coverage closure', 'I-25: 56 phase revoke / reset checks, mixed-operation conformance, requirement matrix'),
    ('7', 'Final affected regression', 'I-24: 36 jobs, 1,000 independent seeds; I-25 final lifecycle and error re-runs'),
    ('8', 'Vivado build hardening', 'Full gate before image write, source provenance, overlap refusal, isolated update test, 6 routed controls + wrong-top control'),
    ('9', 'Final combined image', 'Both CPUs, NoC and attestation; routed gate PASS; image hash recorded'),
    ('10', 'Matched research measurements', 'Secure vs fixed-admission area; registered memory latency, attestation and revoke cycle data'),
    ('11', 'Release and documentation', 'I-26 clean-directory replay, source manifest, release package, this report')]
B.append(table(['Step', 'State', 'Completed scope'], [(n, '[x] PASS', t + '\n' + e) for n, t, e in checklist], [8, 14, 78]))
B.append(p('[ ] Step 12 remains with Kalash: program the exact final secure image and record the LED, UART, reset, revoke and re-attestation '
           'observations. ASIC flow and optional feature extensions were excluded from this authorization.'))

B.append(h1('Verification and traceability', True))
B.append(table(['Increment', 'Accepted scope', 'Result'],
               [['I-18, I-19', 'Real CPU remote-read, remote-write and local-unmapped error behaviour; handler ordering; NI status registers; parameter guards', 'PASS'],
                ['I-20', '12 firmware checks; reference-qualified config and 64-byte measured boot window; causal IRQ control', 'PASS'],
                ['I-21, I-23', '14 lifecycle checks, 6 merged error checks, in-flight revoke, real traffic during attestation; each with a killed control', 'PASS'],
                ['I-24', f'36 jobs; {f["i24"]["seeds"]:,} independent XSim seed processes, each counted from its own log', 'PASS'],
                ['I-25', '17 jobs: final lifecycle and error re-runs, 56 phase checks + control, mixed operations, four matched memory cases, two routed builds, routed gate controls', 'PASS'],
                ['Detached helper', 'Started from a Vivado session, built alone, gate before image, result re-validated, idempotent re-source', 'PASS'],
                ['I-26', 'Clean-directory replay: project update, lifecycle (14 checks), secure routed build; 0 files from outside the clean copy', 'PASS']],
               [16, 72, 12]))
B.append(p(f'Registered gate runs: I-24 {f["i24"]["run"]}; I-25 {f["i25"]["run"]}; I-26 {f["i26"]["run"]}.'))
B.append(h1('Takeover verification and repairs (11 to 12 November)', True))
B.append(p('The work was taken over from the previous AI session after its I-25 run failed. Before continuing, the earlier claims were checked independently: '
           'gate reports I-18 to I-24 match their raw run records; the 1,000 seed logs were counted individually; no frozen count, oracle, source list or '
           'protected file had been changed. Four tooling defects were then repaired, each without touching the design, a count or a check:'))
B.append(table(['Failure', 'Cause', 'Repair'],
               [['Project-update test INVALID', 'Vivado passes its own Python 3.8 environment to child processes', 'Children start isolated (-E); 2 unit tests added'],
                ['Lifecycle simulation timeout', 'Laptop entered standby 3 s after the simulation started', 'Re-run awake; same bench passed'],
                ['Secure build gate FAIL', 'Gate compared the design session label with the top module name', 'Gate reads the TOP property; wrong-top control added'],
                ['Clean replay refused', 'Copy helper skipped 4 payload files without a text extension', 'Helper copies the whole payload']],
               [26, 40, 34]))
B.append(p('A timeout or interrupted attempt is never counted as a pass. Every failed run is kept on record; acceptance comes only from the later accepted runs.'))
B.append(h1('Security claim limits'))
B.append(p('Measurement covers the qualified first 64 IMEM bytes and the defined 16-byte config, not the whole application. Demo keys and nonce are fixed '
           'provisioned data readable from the image. SHA-3 / KMAC verification is symmetric: it is not a public-key post-quantum signature. No claim is made '
           'about denial of service, physical attacks, side channels or random-number quality. Attestation starts only from the RoT side (revision 9).'))

L = f['latency']
rows = []
for mode in ('secure', 'fixed', 'secure_contended', 'fixed_contended'):
    for op in ('read', 'write'):
        d = L[mode]['latency'][op]
        rows.append([mode.replace('_', ' '), op, d['count'], d['minimum_cycles'], round(d['mean_cycles'], 3), d['maximum_cycles']])
B.append(h1('Matched research measurements', True))
B.append(table(['Condition', 'Operation', 'Count', 'Min cycles', 'Mean cycles', 'Max cycles'], rows, [30, 14, 12, 14, 16, 14]))
B.append(p(f'The secure combined design uses {delta:,} more LUTs than the fixed-admission design ({100 * delta / x["lut"]:.1f} percent relative to the '
           'fixed-admission design). Both builds use the same two CPUs, memory sizes, clock, pins, firmware and implementation settings. Removing the security '
           'logic also lets synthesis remove logic that only it used, so the difference is a system-level cost, not the size of one module.'))
B.append(p('Each memory case runs the same 32 checked write / read pairs from a dedicated benchmark program. Latency is RTL simulation in cycles from request to '
           'response; no board latency is claimed. The contended cases issue an attestation request after traffic begins. Raw per-transaction CSV files and the '
           '21 attestation / 7 revocation cycle measurements are in the release evidence.'))

B.append(h1('Vivado update and owner hand-over', True))
B.append(p('Open the main NOC_PQATTEST project in Vivado and run this in its Tcl console:'))
B.append('<pre>' + E(f['final_tcl']) + '</pre>')
B.append(p('The first line backs up the project file, synchronises the combined source, constraint and simulation sets in place (nothing is deleted) and starts '
           'the gated build in the background (about 25 minutes); the Vivado window stays usable. merged_result reports RUNNING, or the final LUT / WNS / WHS and '
           'the image hash. A result is reported as PASS only when the full gate, the image and the source hashes all check. Do not bypass an error.'))
B.append(h1('Exact-image board record still required'))
B.append(bullets(['[ ] Program the secure bitstream NOC_PQATTEST.runs_merged/merged_board/pq_merged_board_top.bit and record the SHA-256 printed by merged_result.',
                  '[ ] Record both CPU UART outputs (sw[0] selects the CPU; 115,200 baud 8N1), the LED state and the reset behaviour.',
                  '[ ] Record initial authorization and memory success, refusal after revoke (btn[2]), then re-attestation (btn[1]) and recovery.',
                  '[ ] Record what you actually see, including failures. Do not infer observations from the expected firmware text.']))
B.append(h1('Reproducibility and next boundary'))
B.append(p('The release archive keeps original paths and contains the explicit RTL, firmware, reference dependencies, scripts, gate reports, raw data, manifest and the '
           'secure image, with SHA256SUMS. Clean-directory replay result: PASS (I-26). After the exact-image board record is accepted, the separately approved ASIC '
           'hand-over can begin: core and pad boundary, clock and reset replacement, memory macros and initialisation, key provisioning, SDC and library corners, test '
           'strategy, equivalence and physical sign-off. No GDSII or ASIC readiness is claimed here.'))

B.append(h1('Project work carried into this release', True))
B.append(table(['Completed area', 'Work and evidence'],
               [['[x] NoC lane', 'Six-tile mesh, credit flow, routing and arbitration, NI transactions and framing, transport guards and recovery (increments I-1 to I-8).'],
                ['[x] PQ-Attest lane', 'SHA-3 / KMAC derivation, measurement, challenge-response, RoT verification and grant enforcement; replay, epoch, identity and memory-protection checks. Pinned Python reference, 32-byte tile keys.'],
                ['[x] S4 area work', 'Qualified KMAC variants, rebuilt synthesis with the area directive, separately synthesised mesh checkpoint.'],
                ['[x] I-9 to I-12', 'Application response export, NI slot timeout, external shared BRAM front end, 64-byte qualification, Engineer 4 verification suite (389 / 15).'],
                ['[x] RISC-V A1 to A10', 'Adapter capture guard, conformance, real CPU errors and IRQ ordering, randomised latency, assertions, two-program coverage, reset and decoder, memories and measurement port, firmware, tile implementation (I-13 to I-16, I-18 to I-25).'],
                ['[x] RISC-V B1 to B7', 'NoC bridge, integrated CPU tile, measurement reader, status registers, protocol checker, merged co-simulation, tile synthesis. The final image contains both real CPU tiles.'],
                ['[x] I-17 to I-26', 'Board-top implementation gate, revision 9 closure, final regression, matched experiments, gated release flow, clean replay.']],
               [24, 76]))
B.append(p('Source scope is set by explicit lists, not by compiling every historical or experimental RTL file. Unselected variants, earlier bitstreams and scratch '
           'results are kept as history and do not replace the final release evidence.'))

CSS = ('body{font-family:Calibri,Arial,sans-serif;font-size:11pt;line-height:1.15}'
       'p{margin:0 0 7pt 0}.title{font-size:24pt;font-weight:bold;margin:0 0 6pt 0}'
       'h1{font-size:16pt;margin:14pt 0 6pt 0;color:#000}'
       'table{border-collapse:collapse;width:100%;margin:0 0 8pt 0}'
       'th{background:#17365D;color:#fff;font-size:10.5pt;text-align:left;border:1px solid #D9D9D9;padding:3pt 5pt}'
       'td{font-size:10.5pt;border:1px solid #D9D9D9;padding:3pt 5pt;vertical-align:top}tr.alt td{background:#F1F5F9}'
       'pre{font-family:Consolas,monospace;font-size:9.5pt;background:#F1F5F9;border:1px solid #D9D9D9;padding:5pt}'
       'li{margin:0 0 4pt 0}@page{size:8.5in 11in;margin:0.7in 0.8in}')
doc = ('<html><head><meta charset="utf-8"><title>Combined RTL verification and FPGA release report</title><style>' + CSS +
       '</style></head><body>' + '\n'.join(B) + '</body></html>')
out = Path(sys.argv[2]); out.parent.mkdir(parents=True, exist_ok=True); out.write_text(doc, encoding='utf-8')
print('COMPLETION_HTML_CREATED', out)
