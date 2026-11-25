"""Build the owner report only from accepted final release facts. Run with bundled document Python."""
import argparse
import json
from pathlib import Path
from docx import Document
from docx.shared import Inches,Pt,RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT

def table(doc,headers,rows,widths):
    t=doc.add_table(rows=1,cols=len(headers));t.autofit=False
    for i,(h,width) in enumerate(zip(headers,widths)):
        t.columns[i].width=Inches(width);t.rows[0].cells[i].text=h
    repeat=OxmlElement('w:tblHeader');t.rows[0]._tr.get_or_add_trPr().append(repeat)
    for row in rows:
        for cell,value in zip(t.add_row().cells,row):cell.text=str(value)
    for r,row in enumerate(t.rows):
        for c,cell in enumerate(row.cells):
            cell.width=Inches(widths[c]);cell.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
            props=cell._tc.get_or_add_tcPr();borders=OxmlElement('w:tcBorders')
            for edge in ('top','left','bottom','right'):
                e=OxmlElement('w:'+edge);e.set(qn('w:val'),'single');e.set(qn('w:sz'),'4');e.set(qn('w:color'),'D9D9D9');borders.append(e)
            props.append(borders);margins=OxmlElement('w:tcMar')
            for edge in ('top','left','bottom','right'):
                e=OxmlElement('w:'+edge);e.set(qn('w:w'),'85');e.set(qn('w:type'),'dxa');margins.append(e)
            props.append(margins)
            shade=OxmlElement('w:shd');shade.set(qn('w:fill'),'17365D' if r==0 else ('F1F5F9' if r%2==0 else 'FFFFFF'));props.append(shade)
            for p in cell.paragraphs:
                p.paragraph_format.space_after=Pt(2);p.paragraph_format.line_spacing=1.05
                for run in p.runs:
                    run.font.size=Pt(10.5);run.font.color.rgb=RGBColor.from_string('FFFFFF' if r==0 else '000000');run.bold=r==0
    doc.add_paragraph().paragraph_format.space_after=Pt(2)
    return t

def main():
    ap=argparse.ArgumentParser();ap.add_argument('facts',type=Path);ap.add_argument('out',type=Path);a=ap.parse_args()
    f=json.loads(a.facts.read_text())
    assert f['i24']['gate']=='PASS' and f['i24']['seeds']==1000 and f['i25']['gate']=='PASS'
    assert f['secure']['gate']=='PASS' and f['fixed']['gate']=='PASS' and f['replay']=='PASS'
    doc=Document();section=doc.sections[0]
    section.page_width=Inches(8.5);section.page_height=Inches(11)
    section.top_margin=section.bottom_margin=Inches(.7);section.left_margin=section.right_margin=Inches(.8)
    normal=doc.styles['Normal'];normal.font.name='Calibri';normal.font.size=Pt(11)
    normal.paragraph_format.space_after=Pt(7);normal.paragraph_format.line_spacing=1.08
    for name in ('Title','Heading 1','Heading 2'):
        doc.styles[name].font.name='Calibri';doc.styles[name].font.color.rgb=RGBColor(0,0,0)
    doc.styles['Title'].font.size=Pt(25);doc.styles['Heading 1'].font.size=Pt(17)
    foot=section.footer.paragraphs[0];foot.alignment=WD_ALIGN_PARAGRAPH.CENTER
    foot.add_run('NOC PQ Attest  |  Kalash Bheda  |  Page ').font.size=Pt(9)
    fld=OxmlElement('w:fldSimple');fld.set(qn('w:instr'),'PAGE');foot._p.append(fld)
    doc.core_properties.title='Combined RTL verification and FPGA release report'
    doc.core_properties.author='Kalash Bheda'
    doc.add_paragraph('Combined RTL verification and FPGA release report','Title')
    doc.add_paragraph('Prepared for Kalash Bheda  |  '+f['date'])
    doc.add_paragraph('The approved work through steps 1 to 11 is complete for the stated FPGA release candidate. Two real RISC V CPU tiles, the six tile NoC and PQ Attest are combined in the gated image. The exact image board record remains Kalash\'s next action. This report does not establish ASIC or formal sign off.')
    doc.add_heading('Final combined FPGA results',1)
    rows=[]
    for label,key in [('Secure release','secure'),('Fixed admission experiment','fixed')]:
        r=f[key];rows.append([label,r['lut'],r['ff'],r['bram36'],r['wns'],r['whs']])
    table(doc,['Configuration','LUT','FF','BRAM36','WNS ns','WHS ns'],rows,[2.1,.85,.85,.9,1,1.2])
    doc.add_paragraph('Part xc7a100tcsg324-1; one 20 ns functional clock derived from the existing 100 MHz board input. The secure image is the production candidate. The fixed admission image is a separately identified research ablation and must not be programmed as the secure release.')
    doc.add_heading('Evidence boundaries',1)
    doc.add_paragraph('Implemented, reference checked, registered XSim simulated, mutation tested and routed FPGA results are distinguished below. HARDWARE_VALIDATED=NO; SOC_INTEGRATION_COMPLETE=NO pending the exact image acceptance record; FORMAL_PROOF=NO. Historical owner reported board PASS belongs to its earlier image hash.')
    doc.add_paragraph('Code revision '+f['code_commit']+'\nSecure bitstream SHA 256 '+f['secure']['bitstream_sha256'])

    doc.add_page_break();doc.add_heading('Approved work completion checklist',1)
    checklist=[
      ('1','Scope and revision 9 contract','Signed decisions and unchanged physical and protocol boundaries'),
      ('2','Real CPU error acceptance','I18 handler entry and ordering plus causal IRQ control'),
      ('3','RTL corrections and interfaces','I19 timeout propagation, parameter guards, debug tap and NI status MMIO'),
      ('4','Firmware and provisioning','I20 bounded v2 firmware and independent reference qualification'),
      ('5','Merged adversarial scenarios','I21 I23 I25 error, revoke, active reset, recovery and contention'),
      ('6','Coverage closure','Requirement matrix and directed operation and protocol phase coverage'),
      ('7','Final affected regression','I24 counted independent seeds; I25 final merged and mixed operation tests'),
      ('8','Vivado build hardening','Full gate before image write, exact provenance, overlap refusal and isolated update test'),
      ('9','Final combined image','Both CPUs, NoC and attestation; routed physical gate and image hash'),
      ('10','Matched research measurements','Secure and fixed admission area; raw memory, attestation and revoke cycle data'),
      ('11','Release and documentation','Source manifest, clean replay, local release record and this report')]
    table(doc,['Step','State','Completed scope'],[(n,'[x] PASS',title+'\n'+e) for n,title,e in checklist],[.5,1,5.4])
    doc.add_paragraph('[ ] Step 12 remains with Kalash: program the exact final secure image and record the specified LED, UART, reset, revoke and reattestation observations. ASIC flow part G and optional feature extensions were excluded from this authorization.')

    doc.add_page_break();doc.add_heading('Verification and traceability',1)
    table(doc,['Evidence','Accepted scope'],[
      ('I18 and I19','Real CPU remote read, remote write and local unmapped error behavior; handler ordering; status and supported parameter behavior'),
      ('I20','Twelve firmware checks, reference qualified config and 64 byte measured boot window, causal IRQ control'),
      ('I21 and I23','Fourteen lifecycle checks, six merged error checks, accepted in flight revoke and actual traffic during attestation'),
      ('I24 final regression','1000 independent XSim seed processes with exact completion ledger; preserved 1000 transaction conformance and affected regression'),
      ('I25 final closure','Final lifecycle and error reruns; 56 read write phase revoke and reset checks; 1000 mixed transfers over eight operation classes; four matched memory cases'),
      ('Build acceptance','Positive routed gate and injected failure controls; both CPU IMEM initialization; part, clocks, route, DRC, timing and resource checks'),
      ('Release replay','Isolated project update and idempotence plus clean directory replay recorded in the release evidence')],[1.8,5.1])
    doc.add_paragraph('Registered source runs\nI24 '+f['i24']['run']+'\nI25 '+f['i25']['run'])
    doc.add_paragraph('A timeout or interrupted attempt is never a pass. The version query, Windows argument forwarding and interrupted seed campaign attempts remain in history. Final acceptance comes from the later accepted records, not from relabelling those attempts.')
    doc.add_heading('Security claim limits',1)
    doc.add_paragraph('Measurement covers the qualified first 64 IMEM bytes and the defined 16 byte config, not the entire application. Demo keys and nonce are fixed provisioned data readable from the image. SHA3 and KMAC verification is not a public key post quantum signature implementation. No universal denial of service, physical fault, side channel or formal security proof is claimed. Python model tests supplement the RTL evidence.')

    doc.add_page_break();doc.add_heading('Matched research measurements',1)
    latency=f['latency'];rows=[]
    for mode in ('secure','fixed','secure_contended','fixed_contended'):
        for op in ('read','write'):
            d=latency[mode]['latency'][op];rows.append([mode.replace('_',' '),op,d['count'],d['minimum_cycles'],round(d['mean_cycles'],5),d['maximum_cycles']])
    table(doc,['Condition','Operation','Count','Min cycles','Mean cycles','Max cycles'],rows,[2.1,.9,.65,1,1.2,1.05])
    delta=f['secure']['lut']-f['fixed']['lut'];pct=100*delta/f['fixed']['lut']
    doc.add_paragraph(f'The secure combined design uses {delta:,} additional LUTs versus the fixed admission design, or {pct:.2f} percent relative to that fixed admission denominator. Both builds use the same two CPUs, memory sizes, clock, pins, firmware and implementation settings. Removal of security logic permits synthesis to prune dependent circuitry; this is part of the declared ablation.')
    doc.add_paragraph('Each memory case contains the same 32 checked write read pairs in a dedicated benchmark program shared by both conditions. The physical area builds both use the board demo firmware v2; no board latency is claimed from the RTL benchmark. The contended cases issue an attestation request after traffic begins; the fixed admission ablation has no attestation engine. Initial attestation and settling are excluded from steady memory latency. These are deterministic workload observations, not a statistical distribution or a universal performance bound. One cycle is 20 ns.')
    doc.add_paragraph('Attestation and revoke measurements use explicit core request inputs and authorization transitions after measurement is valid, with raw cycles and nanoseconds in the release CSV files. Board button debounce and MMCM startup are excluded. Revocation correctness begins at authorization low under the signed propagation bound; it does not mean instantaneous cancellation at the raw button edge. Power, maximum clock frequency and ASIC area were not measured.')

    doc.add_page_break();doc.add_heading('Vivado update and owner handoff',1)
    doc.add_paragraph('Open the main NOC_PQATTEST project and run the verified command below in its Tcl console. The combined source set is dl_merged_src; the explicit merged flow is authoritative for the complete system. Legacy native project runs do not replace this combined build.')
    p=doc.add_paragraph();r=p.add_run(f['final_tcl']);r.font.name='Consolas';r.font.size=Pt(9.5)
    doc.add_paragraph('The update backs up the project and synchronizes its explicit combined files. The detached build keeps the GUI responsive and withholds a successful result unless the full gate, image and source hashes pass. Use merged_result for the final result. Preserve any error rather than bypassing its gate.')
    doc.add_heading('Exact image board record still required',1)
    for text in ['Program the secure bitstream and record its exact merged_result SHA 256. Page 1 identifies the image validated for this report; a later rebuild produces its own recorded hash.',
                 'Record both CPU UART outputs, LED state and reset behavior. Select the UART channel between messages.',
                 'Record initial authorization and memory success, active post revoke refusal, then reattestation and successful recovery.',
                 'Record actual repetitions and failures. Do not infer observations from the expected firmware text.']:
        doc.add_paragraph('[ ] '+text)
    doc.add_heading('Reproducibility and next boundary',1)
    doc.add_paragraph('The path preserving archive includes the explicit RTL, firmware, reference dependencies, scripts, gate reports, raw data, manifest and secure image. SHA256SUMS and the archive sidecar identify its contents. Clean replay result: '+f['replay']+'. No archive was restored over the working project.')
    doc.add_paragraph('After the owner accepts the exact image record, begin the separately approved ASIC handover: core and pad boundary, clock and reset replacement, memory macros and initialization, boot and key provisioning, real SDC and library corners, test strategy, equivalence and physical sign off. No GDSII or ASIC readiness is implied by FPGA timing closure.')
    doc.add_page_break();doc.add_heading('Project work carried into this release',1)
    doc.add_paragraph('The release continues the accepted earlier project work below. Historical gates retain their original dates and source identities; they are not relabelled as new runs. The affected final design is requalified by the later closure gates listed in this report.')
    table(doc,['Completed area','Work and evidence'],[
      ('[x] NoC lane','Six tile mesh, credit flow, routing and arbitration, NI transactions and framing, transport guards and recovery. Original NoC package evidence and the lane completion audit are retained in the release.'),
      ('[x] PQ Attest lane','SHA3 and KMAC based derivation, measurement, challenge response, RoT verification and grant enforcement, plus replay, epoch, identity, control framing and memory protection checks. Pinned Python reference profile uses 32 byte tile keys.'),
      ('[x] I6 to I8 release','Retry and fault status, security matrix and negative controls, complete subsystem implementation and release packaging. See the dated I6, I7 and I8 gate reports.'),
      ('[x] S4 area work','Qualified KMAC variants, rebuilt synthesis with area directive, and separately synthesized protected mesh checkpoint. Lookahead router experiments were parked rather than silently selected.'),
      ('[x] I9 to I12 integration','Application response export, NI slot timeout, external shared BRAM front end, 64 byte qualification, verification intake and model evidence. RTL and Python evidence layers remain separate.'),
      ('[x] RISC V A1 to A5','Adapter capture guard, conformance, real CPU errors and IRQ ordering, randomized latency, assertions and two program coverage. I13 to I16 and I18 to I25 provide their scoped acceptance.'),
      ('[x] RISC V A6 to A10','Reset and decoder integration, tile identity, memories and measurement port, bounded firmware, tile implementation evidence and reproducible submission.'),
      ('[x] RISC V B1 to B7','NoC bridge, integrated CPU tile, measurement reader, status MMIO, protocol checker, real merged co simulation and CPU tile synthesis. The final combined image contains both real CPU tiles.')],[1.8,5.1])
    doc.add_paragraph('Source scope is determined by explicit lists, not by compiling every historical or experimental RTL file in the repository. Unselected variants, earlier bitstreams and scratch results are retained as history and do not replace the final release evidence.')
    a.out.parent.mkdir(parents=True,exist_ok=True);doc.save(a.out)
    print('COMPLETION_DOCX_CREATED '+str(a.out))

if __name__=='__main__':main()
