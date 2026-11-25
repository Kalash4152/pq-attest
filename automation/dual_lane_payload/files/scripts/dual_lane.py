"""Installed dual-lane scheduler. Prepared code only; no runtime AI dependency."""
from __future__ import annotations
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
from dual_lane_verify import *
from dual_lane_preflight import source_names, PreflightFailure, lint_runtime_offset_writes, lint_with_waivers, lint_chained_cast_init

ROOT=Path(__file__).resolve().parents[1]
def atomic(path, value):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    tmp.write_text(value if isinstance(value,str) else json.dumps(value,indent=2)+'\n',encoding='utf-8',newline='\n')
    # Windows readers may briefly hold the destination against replacement.
    # Retry only this same atomic rename; never restart a simulation/build.
    for attempt in range(6):
        try:
            os.replace(tmp,path);break
        except PermissionError:
            if os.name!='nt' or attempt==5:raise
            time.sleep(0.02*(attempt+1))
def now(): return dt.datetime.now(dt.timezone.utc).isoformat()
def digest(value): return hashlib.sha256(json.dumps(value,sort_keys=True).encode()).hexdigest()
def safe(root,rel):
    root=Path(root).resolve(); p=(root/rel).resolve()
    if not p.is_relative_to(root) or p==root: raise InvalidEvidence(f'path escape: {rel}')
    return p
def install(root,manifest,dry=False,rollback=False):
    root=Path(root); manifest=Path(manifest); data=json.loads(manifest.read_text())
    seen=set(); updates=[]; journal=manifest.parent/'install_journal.json'
    for row in data['files']:
        dest=safe(root,row['path']); payload=safe(manifest.parent,row['payload'])
        if str(dest).lower() in seen: raise InvalidEvidence('duplicate installation destination')
        seen.add(str(dest).lower())
        if not payload.is_file() or sha(payload)!=row['after']: raise InvalidEvidence(f'payload hash mismatch {dest}')
        current=sha(dest) if dest.exists() else None
        if current not in (row['before'],row['after']): raise InvalidEvidence(f'dirty-file conflict {dest}: expected {row["before"]}, got {current}')
        updates.append((row,dest,payload,current))
    if rollback:
        if not journal.exists(): raise InvalidEvidence('no installation journal')
        j=json.loads(journal.read_text())
        for row in reversed(j['written']):
            dest=safe(root,row['path'])
            if not dest.exists() or sha(dest)!=row['after']: raise InvalidEvidence(f'rollback conflict {dest}')
            if row['backup']: shutil.copyfile(safe(manifest.parent,row['backup']),dest)
            else: dest.unlink()
        j['state']='ROLLED_BACK'; atomic(journal,j); return
    if dry: return [dict(path=r['path'],state='ALREADY_INSTALLED' if c==r['after'] else 'READY') for r,d,p,c in updates]
    j=json.loads(journal.read_text()) if journal.exists() else dict(state='INSTALLING',written=[],started=now())
    if j.get('state')=='ROLLED_BACK': j=dict(state='INSTALLING',written=[],started=now())
    if j.get('pending'):
        pending=j['pending']; dest=safe(root,pending['path'])
        if dest.is_file() and sha(dest)==pending['after']:
            if pending not in j['written']: j['written'].append(pending)
        elif not any(r['path']==pending['path'] and c==r['before'] for r,d,p,c in updates):
            raise InvalidEvidence('interrupted install has conflicting pending file')
        j.pop('pending',None)
    atomic(journal,j)
    for row,dest,payload,current in updates:
        if current==row['after']: continue
        # Recheck immediately before each write; full-set preflight already passed.
        if (sha(dest) if dest.exists() else None)!=row['before']: raise InvalidEvidence(f'concurrent edit {dest}')
        backup=None
        if dest.exists():
            backup='backups/'+row['path']; bp=safe(manifest.parent,backup); bp.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(dest,bp)
        intent=dict(path=row['path'],after=row['after'],backup=backup)
        j['pending']=intent; atomic(journal,j)
        dest.parent.mkdir(parents=True,exist_ok=True); tmp=dest.with_name(dest.name+'.install.tmp')
        shutil.copyfile(payload,tmp); os.replace(tmp,dest)
        j['written'].append(intent); j.pop('pending',None); atomic(journal,j)
    j['state']='INSTALLED'; j['ended']=now(); atomic(journal,j)
    return 'INSTALLED'

def snapshot(paths): return {str(p):sha(p) for p in paths}
def rtl_lint_preflight():
    # D-SYN-2 + B-1: no runtime-offset part-select write in any statement of an rtl/dual_lane variant, unless a
    # line-hash-pinned waiver in scripts/rtl_lint_waivers.json covers it (stale waivers fail too).
    findings=lint_with_waivers(sorted((ROOT/'rtl/dual_lane').glob('*.sv')),ROOT/'scripts/rtl_lint_waivers.json')
    if findings: raise PreflightFailure('RTL lint (runtime-offset part-select write): '+'; '.join(findings))
    # S1 bench rule (2026-10-22): no chained automatic declaration with a cast initializer in any bench or bench include
    benches=sorted((ROOT/'NOC_PQATTEST.srcs/sim_1/new').glob('tb_*.sv'))+sorted((ROOT/'sim').rglob('*.svh'))
    findings=lint_chained_cast_init(benches)
    if findings: raise PreflightFailure('bench lint (chained automatic declaration with a cast initializer): '+'; '.join(findings))
def protected_preflight():
    baseline=json.loads((ROOT/'automation/dual_lane_payload/baseline_before.json').read_text())
    protected={p:h for p,h in baseline['files'].items() if
        ('/sources_1/new/' in p and not Path(p).name.startswith('tb')) or
        Path(p).name in ('tb_ni_n81.sv','tb_noc_n81.sv')}
    changed=[p for p,h in protected.items() if not (ROOT/p).is_file() or sha(ROOT/p)!=h]
    if changed:raise PreflightFailure('protected-source hash mismatch: '+', '.join(changed))
    return protected
def quote_tcl(s):
    s=str(s).replace('\\','/')
    if re.search(r'[{}\r\n]',s): raise InvalidEvidence('unsupported Tcl path')
    return '{'+s+'}'
def command_token(s):
    s=str(s)
    if re.search(r'[\r\n"%!&^|<>]',s): raise InvalidEvidence('unsupported batch token')
    return '"'+s+'"'
# Start-stall retry (Kalash 2026-10-21 23:42): the first launch of a freshly compiled xsimk sometimes never starts
# (kernel at ~0 CPU, simulate.log stops at its header). Such a launch never executed, so ONE relaunch of the SAME
# snapshot is allowed; it is recorded (SIM_ATTEMPTS = 2 + reason). A second stall is INVALID. A simulation that has
# produced output is never retried.
STALL_WINDOW_S = 180
def sim_started(log_text):
    return bool(re.search(r'^(Time resolution|CONFIG\s*:|run |## run )', log_text, re.M))
def stall_decision(log_text, elapsed, kernel_cpu, attempt):
    """'ok' (output seen: never retry), 'wait', 'retry' (first attempt never started), 'invalid' (second stall)."""
    if sim_started(log_text): return 'ok'
    if elapsed < STALL_WINDOW_S: return 'wait'
    if kernel_cpu is not None and kernel_cpu >= 1.0: return 'wait'
    return 'retry' if attempt == 1 else 'invalid'
def kernel_cpu(workdir):
    q = ("$w='" + str(workdir).replace("'", "''") + "'; $c = Get-CimInstance Win32_Process -Filter \"Name='xsimk.exe'\" | "
         "Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($w, [StringComparison]::OrdinalIgnoreCase) }; "
         "if ($c) { ($c | ForEach-Object { (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).CPU } | Measure-Object -Maximum).Maximum } else { 'NONE' }")
    r = subprocess.run(['powershell.exe', '-NoProfile', '-Command', q], capture_output=True, text=True)
    v = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else 'NONE'
    try: return float(v)
    except ValueError: return None

def supervise(out, bat, timeout, label):
    if label != 'simulate': return supervise_once(out, bat, timeout, label)
    log = Path(bat).parent / 'simulate.log'; attempts = []
    for attempt in (1, 2):
        if log.exists() and attempt == 2: log.replace(log.with_name('simulate_attempt1.log'))
        status, reason = supervise_once(out, bat, timeout, label, watch=lambda el: stall_decision(
            log.read_text(errors='replace') if log.exists() else '', el, kernel_cpu(Path(bat).parent), attempt))
        if reason is None:
            status['attempts'] = attempt; status['retry_history'] = attempts
            return status
        attempts.append(dict(attempt=attempt, reason=reason, at=now()))
        atomic(out / 'sim_attempts.json', dict(SIM_ATTEMPTS=attempt + 1, history=attempts))
        if reason == 'invalid': break
    raise InvalidEvidence(f'{label}: launch stall on the second attempt (SIM_ATTEMPTS=2; never executed)')

def supervise_once(out, bat, timeout, label, watch=None):
    spec=dict(bat=str(bat),cwd=str(out),logPrefix=str(out/f'process_{label}'),timeout=timeout)
    p=out/f'{label}.process-spec.json'; atomic(p,spec)
    cmd=['powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'scripts/dual_lane_support.ps1'),'-Spec',str(p)]
    env=os.environ.copy(); env['XILINX_VIVADO']=str(Path(CONFIG['vivado']).parent.parent)
    proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
    atomic(out/f'process_{label}.owner.json',dict(pid=proc.pid,scheduler_pid=os.getpid(),started=now(),command=cmd))
    if watch is not None:
        start=time.time()
        while proc.poll() is None:
            d=watch(time.time()-start)
            if d=='ok': break
            if d in ('retry','invalid'):
                subprocess.run(['taskkill.exe','/PID',str(proc.pid),'/T','/F'],capture_output=True)
                try: proc.communicate(timeout=30)
                except subprocess.TimeoutExpired: pass
                return None, ('first launch never started (no output past the header, kernel idle) after %d s' % STALL_WINDOW_S if d=='retry' else 'invalid')
            time.sleep(5)
        remaining=max(30,timeout+30-(time.time()-start))
    else: remaining=timeout+30
    try: stdout,stderr=proc.communicate(timeout=remaining)
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill.exe','/PID',str(proc.pid),'/T','/F'],capture_output=True)
        raise InvalidEvidence(f'{label}: supervisor wall timeout')
    except KeyboardInterrupt:
        subprocess.run(['taskkill.exe','/PID',str(proc.pid),'/T','/F'],capture_output=True)
        proc.communicate(timeout=15)
        raise
    if proc.returncode:
        raise InvalidEvidence(f'{label}: native supervision failed: {stderr[-2000:]}')
    status=json.loads((out/f'process_{label}.status.json').read_text())
    if status['exitCode']!=0 or status['timedOut']: raise InvalidEvidence(f'{label}: process failed')
    return (status, None) if watch is not None else status

def check_mesh_split(job):
    """S4-F3 job field synth_mesh_split: absent or true; only on ooc / implementation jobs with exactly one noc_mesh_3x2.sv
    in the sources and the split script + black-box declaration in oracle_files (so they are part of the job identity)."""
    v=job.get('synth_mesh_split')
    if v is None: return
    if v is not True: raise InvalidEvidence('unsupported synth_mesh_split')
    if job.get('kind') not in ('ooc','implementation'): raise InvalidEvidence('synth_mesh_split on a non-implementation job')
    if sum(1 for s in job.get('sources',[]) if s.endswith('/noc_mesh_3x2.sv') or s=='noc_mesh_3x2.sv')!=1: raise InvalidEvidence('synth_mesh_split needs exactly one noc_mesh_3x2.sv')
    if not {'scripts/s4_mesh_split.tcl','synth/s4/noc_mesh_3x2_bb.sv'}<=set(job.get('oracle_files',[])): raise InvalidEvidence('synth_mesh_split files not in oracle_files')
    if any(s.endswith('noc_mesh_3x2_bb.sv') for s in job.get('sources',[])): raise InvalidEvidence('mesh black-box declaration in a source list')

RV_MUTANT_FILES={'rva_':'picorv32_adapter.sv','rvc_':'cpu_tile_noc.sv','rvb_':'tmem_app_bridge.sv','rvm_':'meas_window_reader.sv','rvt_':'tile_top.sv'}
RV_MUTANT_FILES.update({'rvo_':'pq_soc_merged_core.sv','rvg_':'noc_attest_gate.sv'})
RV_MUTANT_FILES.update({'rvh_':'meas_imem_hasher.sv','rvd_':'addr_decode.sv'})
RV_MUTANT_PREFIXES=tuple(RV_MUTANT_FILES)
def mutation(text, kind):
    if kind in ('n6_a','n6_b','n6_b_t5','n6_c'):
        anchors={
            'n6_a':('assign eject_rd = out_valid_local & out_ready_local;',
                    'assign eject_rd = out_valid_local; // MUT-N6A ignores LOCAL ready'),
            'n6_b':("assign credit_out[PORT_WEST ] = {credit_west_vc2,  credit_west_vc1,  credit_west_vc0 };",
                    "assign credit_out[PORT_WEST ] = {credit_west_vc2,  credit_west_vc1,  1'b0 }; // MUT-N6B loses credit"),
            'n6_b_t5':("assign credit_out[PORT_WEST ] = {credit_west_vc2,  credit_west_vc1,  credit_west_vc0 };",
                    "assign credit_out[PORT_WEST ] = {credit_west_vc2, credit_west_vc1, (tb_n6_two_tile_stress.credit_mutation_active ? 1'b0 : credit_west_vc0)}; // MUT-N6B credit loss only in T4/T5"),
            'n6_c':("else                                     in_ready_local = 1'b1;",
                    "else                                     in_ready_local = 1'b1;\n        in_ready_local = 1'b1; // MUT-N6C ignores full")}
        a,b=anchors[kind]
        if re.search(r'MUT[-_]N6',text):raise InvalidEvidence('live router already mutated')
        if text.count(a)!=1:raise InvalidEvidence('nonunique current router mutation anchor '+kind)
        return text.replace(a,b)
    if kind.startswith('ep_'):
        # PQ-2 endpoint mutants (rtl/dual_lane/pq_attest_endpoint.sv); targeted checks in tb_pq_endpoint_unit.
        anchors={
          'ep_tag_swap':('else                   tx_payload_data = internal_response[520 + 32*(int\'(word_index) - 8) +: 32];',
                         'else                   tx_payload_data = internal_response[520 + 32*(15 - int\'(word_index)) +: 32]; // MUT-EP tag word swap'),
          'ep_nonce_offset':('nonce <= challenge[207:80];','nonce <= challenge[215:88]; // MUT-EP nonce offset'),
          'ep_wrong_reply':('assign tx_dest_coord = reply_to;','assign tx_dest_coord = rx_src_coord; // MUT-EP live source, not latched reply-to'),
          'ep_rx_stall':('assign rx_ready = 1\'b1;','assign rx_ready = !busy; // MUT-EP rx_ready stall')}
        a,b=anchors[kind]
        if 'MUT-EP' in text:raise InvalidEvidence('endpoint already mutated')
        if text.count(a)!=1:raise InvalidEvidence('nonunique endpoint mutation anchor '+kind)
        return text.replace(a,b)
    if kind.startswith('dsyn2_'):
        # D-SYN-2 mutant (rtl/dual_lane/pq_measurement.sv): imem source off by one, i.e. imem[k-7-config_len+1];
        # killed by MEAS_EQUIV_DIGEST in tb_dsyn2_measurement_equiv.
        anchors={'dsyn2_imem_off_by_one':('                        imem_sh_q          <= imem;',
                                          '                        imem_sh_q          <= imem >> 8;   // MUT-DSYN2 imem source off by one')}
        a,b=anchors[kind]
        if 'MUT-DSYN2' in text:raise InvalidEvidence('measurement already mutated')
        if text.count(a)!=1:raise InvalidEvidence('nonunique measurement mutation anchor '+kind)
        return text.replace(a,b)
    if kind.startswith('arb_'):
        # Step c arbiter mutants (rtl/dual_lane/l2_arbiter.sv): A0 pointer moves only when both P are pending (model: P 396 >
        # 269); no aging guard (model: Q unbounded under continuous P).
        anchors={'arb_a0_pointer':("                    rrp    <= (grant_id == 2'd0);                 // A0: prefer the other P requester next",
                                   "                    if (p0 && p1) rrp <= (grant_id == 2'd0);   // MUT-ARB A0 pointer only when both pending"),
                 'arb_a2_ovh':("                busy <= 1'b0; idle <= 3'(OVH);",
                               "                busy <= 1'b0; idle <= 3'(OVH + 3);   // MUT-ARB A2 overhead 7 > 4"),
                 'arb_no_aging':("        pick_p   = any_p && !(consec >= 2 && any_q);",
                                 "        pick_p   = any_p;   // MUT-ARB no aging guard")}
        a,b=anchors[kind]
        if 'MUT-ARB' in text:raise InvalidEvidence('arbiter already mutated')
        if text.count(a)!=1:raise InvalidEvidence('nonunique arbiter mutation anchor '+kind)
        return text.replace(a,b)
    if kind.startswith(('s3p_','s3k_','s3m_','s3a_')):
        # S3 mutants (docs/decisions/S3_T1_A1_CONTRACT.md sec. 3): s3p_ on rtl/dual_lane/pq_attest_protocol_s3.sv,
        # s3k_ on pq_keccak_f1600.sv, s3m_ on pq_measurement_xp.sv, s3a_ on kmac_128_xp.sv. Each must be KILLED by its oracle.
        multi={'s3p_done_both':[("    assign kp_done = sp_done && !owner_meas_q;","    assign kp_done = sp_done;   // MUT-S3P done to both"),
                                ("    assign mp_done = sp_done &&  owner_meas_q;","    assign mp_done = sp_done;   // MUT-S3P done to both")],
               's3p_state_in_kmac':[("    always_comb sp_state_in = mp_start ? mp_state_in : kp_state_in;",
                                     "    always_comb sp_state_in = kp_state_in;   // MUT-S3P core always loads the KMAC state")],
               's3k_lane_stuck':[("                        KECCAK_IDLE: if (start) state_reg[x][y] <= state_in[x][y];",
                                  "                        KECCAK_IDLE: if (start && !(x == 0 && y == 0)) state_reg[x][y] <= state_in[x][y];   // MUT-S3K lane [0][0] stuck")],
               's3m_pad_135':[("msg_block_q[b*8 +: 8] <= (b == RATE_BYTES-1) ? 8'h86 : 8'h06;",
                               "msg_block_q[b*8 +: 8] <= 8'h06;   // MUT-S3M byte 135 loses the end bit")],
               's3a_absorb_zero':[("        if (ctrl_state == KMAC_BLOCK0) absorb_base = '{default:'0};",
                                   "        if (1'b1) absorb_base = '{default:'0};   // MUT-S3A blocks 1-2 absorb from zero")]}
        if re.search(r'MUT-S3[PKMA]',text): raise InvalidEvidence('S3 source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique S3 mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith('kshare_'):
        # B-3 D mutant (rtl/dual_lane/pq_kmac_share.sv): the request mux selects the wrong owner - the tag job is computed
        # over the KDF message bundle; killed by s8_golden's TAG checks.
        anchors={'kshare_wrong_owner':("        k_msg        = a_start ? {200'd0, a_msg} : b_msg;",
                                       "        k_msg        = {200'd0, a_msg};   // MUT-KSHARE wrong owner")}
        a,b=anchors[kind]
        if 'MUT-KSHARE' in text:raise InvalidEvidence('kmac share already mutated')
        if text.count(a)!=1:raise InvalidEvidence('nonunique kmac share mutation anchor '+kind)
        return text.replace(a,b)
    if kind.startswith('l2trim_'):
        # B-2 mutant (rtl/dual_lane/noc_l2_auth.sv, trim T1): MAC-word capture off by one flit; killed by L2TRIM_EQUIV_CYCLE.
        anchors={'l2trim_tag_off_by_one':("if(rc==6'(rn)-6'd4+6'(k)) tag_q[k*32+:32]<=noc_rx_flit.flit_data;   // T1",
                                          "if(rc==6'(rn)-6'd3+6'(k)) tag_q[k*32+:32]<=noc_rx_flit.flit_data;   // MUT-L2TRIM off by one")}
        a,b=anchors[kind]
        if 'MUT-L2TRIM' in text:raise InvalidEvidence('l2 wrapper already mutated')
        if text.count(a)!=1:raise InvalidEvidence('nonunique l2 trim mutation anchor '+kind)
        return text.replace(a,b)
    if kind.startswith(('ingq_','ingp_')):
        # contract sec. 1d module-default mutants (noc_ingress_quarantine.sv / noc_ingress_parser.sv): the subsystem sets
        # every parameter explicitly, so the default reaches only tb_p7_ingress's standalone u_q / u_p (QGAP_ / QP_ checks)
        multi={'ingq_gap_any':[("  parameter bit GAP_NEEDS_READY = 1'b1, //   0 = gap also counts cycles with in_ready == 0",
                                "  parameter bit GAP_NEEDS_READY = 1'b0, //   MUT-ING gap counts with in_ready == 0")],
               'ingp_src_off':[("  parameter bit CHECK_SRC = 1'b1      // mutant hook: 0 disables the source check",
                                "  parameter bit CHECK_SRC = 1'b0      // MUT-ING source check off")]}
        if 'MUT-ING' in text: raise InvalidEvidence('ingress source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique ingress mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith('vrev_'):
        # contract sec. 2 mutants (rtl/dual_lane/pq_rot_verifier.sv); killed by tb_verifier_revoke
        multi={'vrev_req_cancel':[("        V_REQ: if(tx_ready) begin index<=0;vs<=V_FILL;end   // never left without the handshake",
                                   "        V_REQ: if(cancel) vs<=V_REVOKE; else if(tx_ready) begin index<=0;vs<=V_FILL;end   // MUT-VREV cancel without handshake")],
               'vrev_level':[("  assign rev_edge=revoke && !revoke_q;","  assign rev_edge=revoke;   // MUT-VREV level-triggered")],
               'vrev_check_success':[("        V_CHECK: if(cancel) begin vs<=V_REVOKE;timer<=0;end","        V_CHECK: if(1'b0) begin vs<=V_REVOKE;timer<=0;end   // MUT-VREV"),
                                     ("          else vs<=V_TSTART;","          else begin vs<=V_TSTART; rv_pend<=0; end   // MUT-VREV success wins over pending")]}
        if 'MUT-VREV' in text: raise InvalidEvidence('verifier already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique verifier mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(('s2p_','s2w_')):
        # S2 / I-5 negative controls (contract sec. 8): each disables one mechanism so that its tb_s2_attacks row's attack
        # succeeds observably. s2p_ -> noc_l2_p7_pair.sv (BYPASS defaults), s2w_ -> noc_l2_auth_p7.sv.
        P="  parameter bit BYPASS_MAC=0, BYPASS_SEQUENCE=0, BYPASS_EPOCH=0"
        multi={'s2p_mac_off':[(P,"  parameter bit BYPASS_MAC=1 /* MUT-S2 */, BYPASS_SEQUENCE=0, BYPASS_EPOCH=0")],
               's2p_seq_off':[(P,"  parameter bit BYPASS_MAC=0, BYPASS_SEQUENCE=1 /* MUT-S2 */, BYPASS_EPOCH=0")],
               's2p_epoch_off':[(P,"  parameter bit BYPASS_MAC=0, BYPASS_SEQUENCE=0, BYPASS_EPOCH=1 /* MUT-S2 */")],
               's2w_bind_ctl':[("  assign rx_hdr={64'b0,rfresh[63:0],rfresh[143:64],8'd1,8'(ph.vc_id),ph.flit_data};",
                                "  assign rx_hdr={64'b0,rfresh[63:0],rfresh[143:64],8'd1,8'(ph.vc_id),ph.flit_data[31:11],11'b0};   // MUT-S2 control unbound")],
               's2w_id_off':[("  assign to_p = h_peer;                // SF-1 steering on the stamped source (trusted after the ingress check)",
                              "  assign to_p = in_src_ok;   // MUT-S2 identity check off")],
               's2w_st_dest':[("           peer(coord_t'({h.dest_x,h.dest_y}))!=TILE || vc!=message_to_vc(h.msg_type) ||",
                               "           /* MUT-S2 dest check off */ vc!=message_to_vc(h.msg_type) ||")],
               's2w_st_vc':[("           peer(coord_t'({h.dest_x,h.dest_y}))!=TILE || vc!=message_to_vc(h.msg_type) ||",
                             "           peer(coord_t'({h.dest_x,h.dest_y}))!=TILE || /* MUT-S2 VC check off */")],
               's2w_len_off':[("           n!=p7_length(h.msg_type)+5 || pad!=0;","           /* MUT-S2 length check off */ pad!=0;")],
               's2w_seq_wrap':[("(rfresh[63:0]==0 || rfresh[63:0]<=rx_seq))",
                                "(rfresh[63:0]==0 || (rfresh[63:0]<=rx_seq && rx_seq!=64'hFFFF_FFFF_FFFF_FFFF)))   /* MUT-S2 wrap */")]}
        if 'MUT-S2' in text: raise InvalidEvidence('S2 source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique S2 mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(('l2e_','l2p7_','p7s_')):
        # B-4 step c/d mutants: shared engine (l2_kmac_engine.sv), P7 wrapper (noc_l2_auth_p7.sv), P7 subsystem
        # (pq_noc_subsystem_p7.sv). Each is killed by its bench's targeted check.
        multi={'l2e_owner_select':[("                E_IDLE:  if (grant) begin owner <= grant_id;","                E_IDLE:  if (grant) begin owner <= grant_id ^ 2'd1; /* MUT-L2E owner select */")],
               'l2e_done_route':[("                E_RUN:   if (kdone) es <= E_IDLE;","                E_RUN:   begin owner <= grant_id; if (kdone) es <= E_IDLE; end   // MUT-L2E completion routed to the arbiter's pick")],
               'l2e_word_off':[("for (int k = 0; k < NWORDS; k++) if (wcnt == 6'(k)) emsg[k*32 +: 32] <= wd[owner];","for (int k = 0; k < NWORDS; k++) if (wcnt == 6'(k + 1)) emsg[k*32 +: 32] <= wd[owner];   // MUT-L2E transcript one word off")],
               'l2e_key_live':[(".key_in(key_q)",".key_in(owner[1] ? key_34 : key_43) /* MUT-L2E key read live */")],
               'l2e_a3_long_job':[("    localparam int        NWORDS = 22;","    localparam int        NWORDS = 50;   // MUT-L2E A3 job > J_MAX")],
               'l2p7_a1_hold_req':[("  assign tx_req=ts==T_REQ;","  assign tx_req=ts==T_REQ || ts==T_WAIT;   // MUT-L2P7 A1 request held through the job")],
               'l2p7_peer_drop':[("  assign p_hold = is_q==I_IDLE && noc_rx_valid && in_head && in_ctl && to_p && ps!=P_FREE;   // D2: hold, never drop",
                                  "  assign p_hold = 1'b0;   // MUT-L2P7 D2 drop-when-busy restored")],
               'l2p7_single_slot':[("  assign to_p = h_peer;                // SF-1 steering on the stamped source (trusted after the ingress check)",
                                    "  assign to_p = 1'b1;   // MUT-L2P7 single slot"),
                                   ("  assign p_hold = is_q==I_IDLE && noc_rx_valid && in_head && in_ctl && to_p && ps!=P_FREE;   // D2: hold, never drop",
                                    "  assign p_hold = 1'b0;   // MUT-L2P7 drop-when-busy")],
               'p7s_q_nested_off':[(".NESTED_CHECK(1'b1)",".NESTED_CHECK(1'b0) /* MUT-P7S */")],
               'p7s_q_no_cap':[(".LENGTH_CAP(1'b1)",".LENGTH_CAP(1'b0) /* MUT-P7S */")],
               'p7s_q_partial':[(".COMMIT_WHOLE(1'b1)",".COMMIT_WHOLE(1'b0) /* MUT-P7S */")],
               'p7s_q_src_off':[(".SRC_CHECK(1'b1)",".SRC_CHECK(1'b0) /* MUT-P7S */")],
               'p7s_no_src_check':[(".CHECK_SRC(1'b1)",".CHECK_SRC(1'b0) /* MUT-P7S source check off */")],
               'p7s_no_watchdog':[(".WATCHDOG(1'b1)",".WATCHDOG(1'b0) /* MUT-P7S watchdog off */")],
               'l2p7_rl_off':[("            if(in_src_ok && rl[in_src]!=0) begin d_reason<=6; is_q<=I_DROP; end",
                               "            if(1'b0 && in_src_ok && rl[in_src]!=0) begin d_reason<=6; is_q<=I_DROP; end   // MUT-L2P7 rate limit off")],
               'p7s_control_allowed':[(".CONTROL_ALLOWED(1'b0)",".CONTROL_ALLOWED(1'b1) /* MUT-P7S */"),
                                      (".ATTESTABLE(g==3 || g==4)",".ATTESTABLE(1'b1) /* MUT-P7S */")],
               # sec. 9 gate-data row (S2-N2P7): the plain-tile gates pass data without authorization
               'p7s_gate_bypass':[(".BYPASS_GATE(BYPASS_GATE)",".BYPASS_GATE(BYPASS_GATE || !(g==3 || g==4)) /* MUT-P7S plain-tile gate bypass */")]}
        if re.search(r'MUT-(L2E|L2P7|P7S)',text): raise InvalidEvidence('step c/d source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique step c/d mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(('s4a_','s4x_')):
        # S4-A5 controls (docs/decisions/S4_AREA_CONTRACT.md): blocks 1-2 absorb from zero instead of the held state_out.
        # s4a_ -> kmac_128_a5.sv (E3 / E4), s4x_ -> kmac_128_xp_a5.sv (E1).
        a_="        if (ctrl_state == KMAC_BLOCK0) absorb_base = '{default:'0};"
        b_="        if (1'b1) absorb_base = '{default:'0};   // MUT-S4A blocks 1-2 absorb from zero"
        if 'MUT-S4A' in text: raise InvalidEvidence('S4 source already mutated')
        if text.count(a_)!=1: raise InvalidEvidence('nonunique S4 mutation anchor '+kind)
        return text.replace(a_,b_)
    if kind.startswith(('i7s_','i7v_','i7l_')):
        # I-7 SEC-matrix controls (docs/decisions/I7_SEC_MATRIX.md sec. 3): each makes its attack succeed or changes its stated
        # reason; killed by tb_i7_sec. i7s_ -> pq_noc_subsystem_p7.sv, i7v_ -> pq_rot_verifier.sv, i7l_ -> noc_l2_auth_p7.sv.
        multi={'i7s_tag_off':[(".BYPASS_TAG(BYPASS_TAG)",".BYPASS_TAG(1'b1) /* MUT-I7 tag check off */")],
               'i7s_meas_off':[(".BYPASS_MEASUREMENT(BYPASS_MEASUREMENT)",".BYPASS_MEASUREMENT(1'b1) /* MUT-I7 whitelist off */")],
               'i7s_l2_seq_off':[(".BYPASS_SEQUENCE(BYPASS_SEQUENCE)",".BYPASS_SEQUENCE(1'b1) /* MUT-I7 L2 sequence off */")],
               'i7s_l2_epoch_off':[(".BYPASS_EPOCH(BYPASS_EPOCH)",".BYPASS_EPOCH(1'b1) /* MUT-I7 L2 epoch off */")],
               'i7v_nonce_stale':[("epoch_q<=epoch;outstanding_nonce<=nonce;","epoch_q<=epoch;if(outstanding_nonce==0) outstanding_nonce<=nonce;   /* MUT-I7 stale nonce */")],
               'i7v_error_accepted':[("else if(hdr_status!=1) begin failed<=1;fail_reason<=9;","else if(1'b0) begin failed<=1;fail_reason<=9;   /* MUT-I7 error status accepted */")],
               'i7l_peer_src_off':[("  assign to_p = h_peer;","  assign to_p = 1'b1;   /* MUT-I7 peer source steering off */")]}
        if 'MUT-I7' in text: raise InvalidEvidence('I-7 source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique I-7 mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(('i11r_','i11p_','i11s_')):
        # I-11 (E4 Step 18 triage): routing order (NOC_XY_ROUTING.sv) and VC map (NOC_PKG.sv), killed by tb_i11_noc_spec;
        # BRAM window overshoot (pq_noc_subsystem_p7_i9.sv), killed by tb_i9_integ I9_WINDOW_OUT_ERR. Text normalised to LF.
        text=text.replace('\r\n','\n')
        yx_old=('        if (dest_coord.x > current_coord.x) begin\n            computed_port = PORT_EAST;\n        end\n'
                '        else if (dest_coord.x < current_coord.x) begin\n            computed_port = PORT_WEST;\n        end\n'
                '        else if (dest_coord.y > current_coord.y) begin\n            computed_port = PORT_SOUTH;\n        end\n'
                '        else if (dest_coord.y < current_coord.y) begin\n            computed_port = PORT_NORTH;\n        end')
        yx_new=('        if (dest_coord.y > current_coord.y) begin   // MUT-I11 YX order\n            computed_port = PORT_SOUTH;\n        end\n'
                '        else if (dest_coord.y < current_coord.y) begin\n            computed_port = PORT_NORTH;\n        end\n'
                '        else if (dest_coord.x > current_coord.x) begin\n            computed_port = PORT_EAST;\n        end\n'
                '        else if (dest_coord.x < current_coord.x) begin\n            computed_port = PORT_WEST;\n        end')
        multi={'i11r_yfirst':[(yx_old,yx_new)],
               'i11p_attest_vc0':[('            MSG_ATTEST_REVOKE:\n                return VC_ATTESTATION;',
                                   '            MSG_ATTEST_REVOKE:\n                return VC_REQUEST;   // MUT-I11 attestation on VC 0')],
               'i11s_window_over':[('(a_now[23:0]>>MEM_ADDR_BITS)==0','(a_now[23:0]>>(MEM_ADDR_BITS+1))==0 /* MUT-I11 window one bit too wide */')]}
        if 'MUT-I11' in text: raise InvalidEvidence('I-11 source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique I-11 mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(RV_MUTANT_PREFIXES):
        # I-14 (RISC-V takeover; Lane 1 2026-11-07): one RTL edit each in rtl/riscv (file chosen by prefix, RV_MUTANT_FILES).
        # rva_ picorv32_adapter.sv, rvc_ cpu_tile_noc.sv, rvb_ tmem_app_bridge.sv, rvm_ meas_window_reader.sv. Text normalised to LF.
        text=text.replace(chr(13)+chr(10),chr(10))
        multi={'rvh_skip_word':[("block_shift<={meas_rd_data_i,block_shift[1087:32]};",
                               "if(word_next!=13'd17)block_shift<={meas_rd_data_i,block_shift[1087:32]}; // MUT-RV skip IMEM word 16")],
               'rvd_fetch_guard_off':[("if (local_is_fetch_i && !is_imem) begin","if (1'b0) begin // MUT-RV instruction guard removed")],
               'rvt_irq_off':[(".irq       (32'(bus_fault) << BUS_ERR_IRQ)",".irq       (32'b0) // MUT-RV IRQ disconnected")],
               'rvo_drop_busy':[("app_valid[CPU[k]] = c_valid[k];","app_valid[CPU[k]] = c_valid[k] && !rot_busy;")],
               'rvg_drop_grant':[("else if(control[10:7]==1) authorized<=1;","else if(control[10:7]==1) authorized<=0; // MUT-RV drop grant")],
               'rvg_ignore_revoke':[("if(!BYPASS_REVOKE) authorized<=0;","if(1'b0) authorized<=0;")],
               'rvt_ni_count_zero':[("8: ni_rdata <= {16'b0,ni_refused_count_i};","8: ni_rdata <= 32'b0; // MUT-RV lost refusal counter")],
               'rvt_debug_data':[("else if (mem_valid && mem_ready && mem_instr) dbg_pc_o <= mem_addr;","else if (mem_valid && mem_ready) dbg_pc_o <= mem_addr; // MUT-RV data address as debug PC")],
               'rva_no_poison':[("localparam logic [31:0] POISON      = 32'hBADB_E000;","localparam logic [31:0] POISON      = 32'h0000_0000;   // MUT-RV no poison")],
               'rva_no_guard':[("wire capture         = capture_attempt && !mem_ready_q;","wire capture         = capture_attempt;   // MUT-RV A1 guard removed")],
               'rvc_sideband_zero':[(".tmem_err_code_i({1'b0, last_err_kind}),",".tmem_err_code_i(4'd0),   // MUT-RV A3 sideband disconnected")],
               'rvb_auth_removed':[("assign app_valid_o         = (st == S_HEAD) && authorized_i;","assign app_valid_o         = (st == S_HEAD);   // MUT-RV auth gate removed"),
                                   ("end else if (!authorized_i) begin","end else if (1'b0) begin"),
                                   ("if (!authorized_i) begin","if (1'b0) begin")],
               'rvm_word_order':[("meas_imem_o[pend_idx_q*32 +: 32] <= meas_rd_data_i;","meas_imem_o[(15 - pend_idx_q)*32 +: 32] <= meas_rd_data_i;   // MUT-RV word order reversed")]}
        if 'MUT-RV' in text: raise InvalidEvidence('RISC-V source already mutated')
        if kind not in multi: raise InvalidEvidence('unknown RISC-V mutant '+kind)
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique RISC-V mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith('i10e_'):
        # I-10 (I9-D2): K-3 64-byte IMEM profile in the endpoint (pq_attest_endpoint.sv); killed by tb_i10_d2.
        multi={'i10e_k3_imem_unchecked':[("(config_len != K3_CONFIG_LEN || imem_len != K3_IMEM_LEN)","(config_len != K3_CONFIG_LEN /* MUT-I10 imem_len unchecked */)")],
               'i10e_window16':[(".root_secret, .context_in, .context_len, .config_data, .config_len, .imem, .imem_len,",".root_secret, .context_in, .context_len, .config_data, .config_len, .imem, .imem_len(7'd16) /* MUT-I10 measurement window 16 */,")]}
        if 'MUT-I10' in text: raise InvalidEvidence('I-10 source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique I-10 mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(('i9n_','i9s_')):
        # I-9 (M-F1 rev 8): NI slot timeout (noc_network_interface_p7_i9.sv) and the subsystem's app_rx / BRAM port
        # (pq_noc_subsystem_p7_i9.sv); killed by tb_i9_integ.
        multi={'i9n_no_timeout':[("            if (NI_SLOT_TIMEOUT > 0) begin\n","            if (1'b0) begin   // MUT-I9 slot timeout off\n")],
               'i9n_stale_deliver':[("                if (txn_valid_q[rx_resp_tag] && !txn_stale_q[rx_resp_tag] &&\n",
                                     "                if (txn_valid_q[rx_resp_tag] && /* MUT-I9 stale slot delivered */\n")],
               'i9s_rx_all':[("   assign app_rx_head_valid[g]=CPU_TILES[g] && rhv[g] && is_resp;","   assign app_rx_head_valid[g]=CPU_TILES[g] && rhv[g];   // MUT-I9 every type exported")],
               'i9s_bram_lanes':[("if(mmsg==MSG_MEM_WR_RESP) mem_we=request_ctl[10:7];",
                                  "if(mmsg==MSG_MEM_WR_RESP) mem_we={request_ctl[7],request_ctl[8],request_ctl[9],request_ctl[10]};   // MUT-I9 lanes")],
               'i9s_window_1k':[("(a_now[23:0]>>MEM_ADDR_BITS)==0","(a_now[23:0]>>10)==0 /* MUT-I9 BRAM window 1 KiB */")]}
        if 'MUT-I9' in text: raise InvalidEvidence('I-9 source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique I-9 mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(('i6v_','i6s_')):
        # I-6 controls (docs/decisions/I6_CONTRACT.md sec. 5): verifier busy retry (pq_rot_verifier.sv) and the P7 subsystem's
        # gate / trusted / fault-status / K-3 / C-5 wiring (pq_noc_subsystem_p7.sv); killed by tb_i6_retry / tb_i6_gate.
        multi={'i6v_retry_unbounded':[("else if(hdr_status==3 && busy_retries!=MAX_BUSY_RETRIES)","else if(hdr_status==3 /* MUT-I6 retry unbounded */)")],
               'i6v_no_retry':[("else if(hdr_status==3 && busy_retries!=MAX_BUSY_RETRIES)","else if(1'b0 /* MUT-I6 BUSY fails at once */)")],
               'i6s_gate_bypass':[(".BYPASS_GATE(BYPASS_GATE)",".BYPASS_GATE(1'b1) /* MUT-I6 gate bypass */")],
               'i6s_issuer_off':[(".BYPASS_ISSUER(BYPASS_ISSUER)",".BYPASS_ISSUER(1'b1) /* MUT-I6 issuer check off */")],
               'i6s_revoke_ignored':[(".BYPASS_REVOKE(BYPASS_REVOKE)",".BYPASS_REVOKE(1'b1) /* MUT-I6 revoke ignored */")],
               'i6s_trusted_off':[(".trusted_fail(t_fail),.trusted_timeout(t_timeout)",".trusted_fail(1'b0),.trusted_timeout(1'b0) /* MUT-I6 trusted inputs off */")],
               'i6s_fs_off':[(".event_valid(fs_ev)",".event_valid(1'b0) /* MUT-I6 fault status not recorded */")],
               'i6s_k3_off':[(".K3_ENFORCE(1'b1)",".K3_ENFORCE(1'b0) /* MUT-I6 K-3 off */")],
               'i6s_window_old':[("address[31:28]==4'h2 &&","address[31:28]==4'h8 /* MUT-I6 old window */ &&")]}
        if 'MUT-I6' in text: raise InvalidEvidence('I-6 source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique I-6 mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    if kind.startswith(('f2_','f3_','f3p7_','f4_')):
        # Codex F2-F4 fixes (Kalash addendum B): each mutant restores the old behaviour; killed by tb_sys_f234.
        multi={'f2_revoke_idle_only':[("  assign cancel=rv_pend || rev_edge || fault_now;   // F2: a revoke wins in every active state",
                                       "  assign cancel=1'b0;   // MUT-F2 revoke handled only in V_IDLE")],
               'f3_live_owner':[("     if(g==3 && own3_ep) begin","     if(g==3 && endpoint_busy) begin   // MUT-F3 live owner"),
                                ("     if(g==2 && own2_mem) begin","     if(g==2 && mtv) begin   // MUT-F3 live owner"),
                                ("assign ertready=tready[3] && own3_ep;assign ertpready=pready[3] && own3_ep;","assign ertready=tready[3];assign ertpready=pready[3];   // MUT-F3"),
                                ("     if(ms==M_REPLY && tready[2] && own2_mem) ms<=mmsg==MSG_MEM_RD_RESP?M_DATA:M_IDLE;\n     if(ms==M_DATA && pready[2] && own2_mem) ms<=M_IDLE;",
                                 "     if(ms==M_REPLY && tready[2]) ms<=mmsg==MSG_MEM_RD_RESP?M_DATA:M_IDLE;\n     if(ms==M_DATA && pready[2]) ms<=M_IDLE;   // MUT-F3")],
               'f3p7_live_owner':[("   assign sel_ep=g==3 && own3_ep;  assign sel_v=g==4;  assign sel_m=g==2 && own2_mem;",
                                   "   assign sel_ep=g==3 && endpoint_busy;  assign sel_v=g==4;  assign sel_m=g==2 && mtv;   // MUT-F3 live owner"),
                                  ("assign ertready=tready[3] && own3_ep;assign ertpready=pready[3] && own3_ep;","assign ertready=tready[3];assign ertpready=pready[3];   // MUT-F3"),
                                  ("     else if(ms==M_REPLY && own2_mem) begin","     else if(ms==M_REPLY) begin   // MUT-F3"),
                                  ("     if(ms==M_DATA && pready[2] && own2_mem) ms<=M_IDLE;","     if(ms==M_DATA && pready[2]) ms<=M_IDLE;   // MUT-F3")],
               'f4_head_auth_only':[("         allowed_now=src_ok_now(mdest);   // F4: authorization at the side-effect point",
                                     "         allowed_now=1'b1;   // MUT-F4 authorization sampled at the HEAD only")]}
        if 'MUT-F' in text: raise InvalidEvidence('F-fix source already mutated')
        for a,b in multi[kind]:
            if text.count(a)!=1: raise InvalidEvidence('nonunique F-fix mutation anchor '+kind+': '+a[:60])
            text=text.replace(a,b)
        return text
    anchors={
      'lost_measurement':("response[33*8 +: 256] <= measurement;","response[33*8 +: 256] <= '0;"),
      'lost_tag':("response[65*8 +: 256] <= tag;","response[65*8 +: 256] <= '0;"),
      'key_length':('.key_len_sel      (2\'b01)', '.key_len_sel      (2\'b00)'),
      'wrong_transcript':('.nonce        (nonce_q)', '.nonce        (~nonce_q)'),
      'field_order':('response[7*8 +: 80]  <= epoch_q;', 'response[7*8 +: 80]  <= nonce_q[79:0];'),
      'stale_nonce':('nonce_q   <= nonce;', "if (nonce_q == '0) nonce_q <= nonce;"),
      'wrong_key':('.tile_key     (kdf_derived_key)', '.tile_key     (~kdf_derived_key)'),
      # B-3 D: tag start also raised while the KDF owns the shared kmac (controller variant only).
      'ksx_tag_during_kdf':("            S_TAG_START:\n                tag_start = 1'b1;\n",
                            "            S_TAG_START, S_KDF_WAIT:   // MUT-KSX tag start while the KDF is busy\n                tag_start = 1'b1;\n")}
    a,b=anchors[kind]
    if text.count(a)!=1: raise InvalidEvidence(f'nonunique current mutation anchor {kind}')
    return text.replace(a,b)

def execute(job,out):
    atomic(out/'source_preflight.json',source_names(ROOT,job))
    paths=[safe(ROOT,p) for p in job['sources']]
    paths += [ROOT/'scripts/dual_lane_export.tcl',ROOT/'scripts/dual_lane.py',ROOT/'scripts/dual_lane_verify.py',ROOT/'scripts/controlled_diagnostics.py',ROOT/'scripts/dual_lane_preflight.py',ROOT/'scripts/dual_lane_support.ps1',ROOT/'scripts/wp0_support.ps1',ROOT/'docs/decisions/dual_lane_config.json',ROOT/'scripts/dual_lane_jobs.json']
    paths += [safe(ROOT,p) for p in job.get('oracle_files',[])]
    before=snapshot(paths); atomic(out/'sources_before.json',before)
    copied=[]
    for p in paths[:len(job['sources'])]:
        dst=out/'snapshot'/p.relative_to(ROOT); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(p,dst); copied.append(dst)
    if job.get('mutant'):
        name=RV_MUTANT_FILES.get(job['mutant'][:4]) or ('NOC_XY_ROUTING.sv' if job['mutant'].startswith('i11r_') else 'NOC_PKG.sv' if job['mutant'].startswith('i11p_') else 'pq_noc_subsystem_p7_i9.sv' if job['mutant'].startswith('i11s_') else 'pq_attest_endpoint.sv' if job['mutant'].startswith('i10e_') else 'noc_network_interface_p7_i9.sv' if job['mutant'].startswith('i9n_') else 'pq_noc_subsystem_p7_i9.sv' if job['mutant'].startswith('i9s_') else 'kmac_128_a5.sv' if job['mutant'].startswith('s4a_') else 'kmac_128_xp_a5.sv' if job['mutant'].startswith('s4x_') else 'pq_noc_subsystem_p7.sv' if job['mutant'].startswith('i7s_') else 'pq_rot_verifier.sv' if job['mutant'].startswith('i7v_') else 'noc_l2_auth_p7.sv' if job['mutant'].startswith('i7l_') else 'pq_rot_verifier.sv' if job['mutant'].startswith('i6v_') else 'pq_noc_subsystem_p7.sv' if job['mutant'].startswith('i6s_') else 'pq_attest_protocol_s3.sv' if job['mutant'].startswith('s3p_') else 'pq_keccak_f1600.sv' if job['mutant'].startswith('s3k_') else 'pq_measurement_xp.sv' if job['mutant'].startswith('s3m_') else 'kmac_128_xp.sv' if job['mutant'].startswith('s3a_') else 'noc_l2_p7_pair.sv' if job['mutant'].startswith('s2p_') else 'noc_l2_auth_p7.sv' if job['mutant'].startswith('s2w_') else 'noc_ingress_quarantine.sv' if job['mutant'].startswith('ingq_') else 'noc_ingress_parser.sv' if job['mutant'].startswith('ingp_') else 'pq_rot_verifier.sv' if job['mutant'].startswith('vrev_') else 'l2_kmac_engine.sv' if job['mutant'].startswith('l2e_') else 'noc_l2_auth_p7.sv' if job['mutant'].startswith('l2p7_') else 'pq_noc_subsystem_p7.sv' if job['mutant'].startswith('p7s_') else 'pq_rot_verifier.sv' if job['mutant'].startswith('f2_') else ('pq_noc_subsystem_p7.sv' if any(c.name=='pq_noc_subsystem_p7.sv' for c in copied) else 'pq_noc_subsystem.sv') if job['mutant'].startswith(('f3_','f3p7_','f4_')) else 'noc_router.sv' if job['mutant'].startswith('n6_') else 'pq_attest_endpoint.sv' if job['mutant'].startswith('ep_') else 'pq_measurement.sv' if job['mutant'].startswith('dsyn2_') else 'noc_l2_auth.sv' if job['mutant'].startswith('l2trim_') else 'pq_kmac_share.sv' if job['mutant'].startswith('kshare_') else 'l2_arbiter.sv' if job['mutant'].startswith('arb_') else 'pq_attest_protocol.sv')
        # I-9 lists carry the same-module variants under *_i9.sv names (never together with the original): an older control
        # re-run on an I-9 list mutates the variant of the file it names.
        if not any(p.name==name for p in copied) and any(p.name==name[:-3]+'_i9.sv' for p in copied): name=name[:-3]+'_i9.sv'
        p=next(p for p in copied if p.name==name)
        p.write_text(mutation(p.read_text(),job['mutant']),encoding='utf-8')
    atomic(out/'compiled_sources.json',snapshot(copied))
    includes=[]
    for rel in job.get('include_dirs',[]):
        src=safe(ROOT,rel); dest=out/'snapshot'/rel; shutil.copytree(src,dest); includes.append(dest)
    if job.get('mutant'):atomic(out/'mutant_source_preflight.json',source_names(out/'snapshot',job))
    extra={}
    for key,field in [('XDC','constraints'),('GATE','gate_script')]:
        if field in job:
            src=safe(ROOT,job[field]);dest=out/'snapshot'/job[field]
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest);extra[key]=quote_tcl(dest)
    if any(not re.fullmatch(r'[A-Za-z_]\w*(=[A-Za-z0-9_]+)?',d) for d in job.get('defines',[])): raise InvalidEvidence('unsafe define')
    # S4-F1 / F2 (docs/decisions/S4_AREA_CONTRACT.md): optional synthesis options for implementation children
    if job.get('synth_flatten','none') not in ('none','rebuilt'): raise InvalidEvidence('unsupported synth_flatten')
    if job.get('synth_directive','') not in ('','AreaOptimized_high'): raise InvalidEvidence('unsupported synth_directive')
    for key,field in [('SYNTH_FLATTEN','synth_flatten'),('SYNTH_DIRECTIVE','synth_directive')]:
        if job.get(field): extra[key]=quote_tcl(job[field])
    # S4-F3 (docs/decisions/S4_AREA_CONTRACT.md sec. 6): mesh split, implementation children only
    check_mesh_split(job)
    if job.get('synth_mesh_split'):
        for key,rel in [('SYNTH_MESH_SPLIT','scripts/s4_mesh_split.tcl'),('SYNTH_MESH_BB','synth/s4/noc_mesh_3x2_bb.sv')]:
            src=safe(ROOT,rel);dest=out/'snapshot'/rel
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest);extra[key]=quote_tcl(dest)
    spec='\n'.join('set '+k+' '+v for k,v in {
        'KIND':quote_tcl(job['kind']),'OUT':quote_tcl(out),'PART':quote_tcl(CONFIG['part']),
        'TOP':quote_tcl(job['top']),'SOURCES':'[list '+' '.join(map(quote_tcl,copied))+']',
        'INCLUDES':'[list '+' '.join(map(quote_tcl,includes))+']',
        'GENERICS':'[list '+' '.join(map(quote_tcl,job.get('generics',[])))+']',
        'DEFINES':'[list '+' '.join(map(quote_tcl,job.get('defines',[])))+']',**({'PNR':'1'} if job.get('pnr') else {}),**extra}.items())+'\n'
    atomic(out/'job.tcl',spec)
    child=ROOT/job.get('child_script','scripts/dual_lane_export.tcl')
    args=[CONFIG['vivado'],'-mode','batch','-source',str(child),'-log',str(out/'vivado.log'),'-journal',str(out/'vivado.jou'),'-tclargs',str(out/'job.tcl')]
    bat=out/'launch.bat'; atomic(bat,'@echo off\ncall '+' '.join(map(command_token,args))+'\nexit /b %errorlevel%\n')
    process={'export':supervise(out,bat,job.get('build_timeout',1200),'export')}
    if re.search(r'^ERROR:',(out/'vivado.log').read_text(errors='replace'),re.M): raise InvalidEvidence('Vivado build/export diagnostic error')
    if job['kind']=='implementation':
        summary=(out/'gate_summary.txt').read_text()
        verdict=unique(summary,r'^VERDICT (PASS|FAIL)\b','implementation verdict')
        if verdict!='PASS':raise GateFailure(job.get('gate_label','mesh implementation')+' timing/route/DRC gate failed; see gate_summary.txt')
        if 'clock period 20.000 ns' not in summary:raise InvalidEvidence('unproven 20ns implementation target')
        after=snapshot(paths);atomic(out/'sources_after.json',after)
        if before!=after:raise InvalidEvidence('source changed during implementation')
        return dict(observed=dict(result='PASS',summary=summary),process=process,
                    source_manifest=before,scope=job.get('scope','mesh only; NI/crypto not included'))
    if job['kind']=='ooc':
        m=dict(l.split('=',1) for l in (out/'metrics.txt').read_text().splitlines() if '=' in l)
        ooc_gate(m,job)   # hardened OOC acceptance (dual_lane_verify.ooc_gate)
        if job.get('lutram_instances'): lutram_gate((out/'util_hier.rpt').read_text(errors='replace'),job['lutram_instances'])
        if job.get('pnr'):   # contract sec. 6 integrated P&R checkpoint (dual_lane_verify.pnr_gate)
            pm=out/'pnr_metrics.txt'
            if not pm.is_file(): raise InvalidEvidence('P&R job without pnr_metrics.txt')
            pnr=dict(l.split('=',1) for l in pm.read_text().splitlines() if '=' in l)
            pnr_gate(pnr); m.update(pnr)
        after=snapshot(paths); atomic(out/'sources_after.json',after)
        if before!=after: raise InvalidEvidence('source change during OOC')
        return dict(observed=m,process=process,scope='OOC; assumed in/out 5ns budgets; not integrated timing')
    work=Path((out/'export-path.txt').read_text().strip())
    if not work.is_relative_to(out): raise InvalidEvidence('export workspace escape')
    if list(work.rglob('*.sdb')): raise InvalidEvidence('cached compiled SDB before job')
    cbat=work/'compile.bat'; text=cbat.read_text()
    line=unique(text,r'^(call xvlog[^\r\n]*)$','compiler command')
    if re.search(r'\s-d\s',line): raise InvalidEvidence('unrequested inherited compiler defines')
    defs=job.get('defines',[])
    if any(not re.fullmatch(r'[A-Za-z_]\w*(=[A-Za-z0-9_]+)?',d) for d in defs): raise InvalidEvidence('unsafe define')
    injected=line.replace(' -prj ',' '+' '.join('-d "'+d+'"' for d in defs)+' -prj ',1) if defs else line
    if defs and injected==line: raise InvalidEvidence('compiler has no -prj anchor')
    cbat.write_text(text.replace(line,injected),newline='\r\n')
    actual=re.findall(r'\s-d\s+"([^"]+)"',injected)
    if actual!=defs: raise InvalidEvidence('compiler define proof mismatch')
    compiled=[]
    for p in work.glob('*_vlog.prj'):
        compiled += [Path(s) for s in re.findall(r'"([^"]+)"',p.read_text()) if Path(s).suffix.lower() in ['.sv','.v']]
    if not compiled or any(p not in copied and p.name!='glbl.v' for p in compiled):
        raise InvalidEvidence('unexpected source in compiler project')
    top_file=next((p for p in copied if re.search(r'\bmodule\s+'+re.escape(job['top'])+r'\b',p.read_text())),None)
    if top_file not in compiled: raise InvalidEvidence('selected top missing from compiler project')
    atomic(out/'runtime_compiled_sources.json',snapshot(compiled))
    limit=job.get('tb_time_limit','25ms')
    if not re.fullmatch(r'\d+(us|ms)',limit): raise InvalidEvidence('unsafe TB time limit')
    sim_tcl=work/(job['top']+'.tcl'); sim_tcl.write_text('run '+limit+'\nquit\n')
    scripts=[*work.glob('*.bat'),*work.glob('*_vlog.prj'),sim_tcl]
    scripts_before=snapshot(scripts)
    for step in ['compile','elaborate','simulate']:
        process[step]=supervise(work,work/(step+'.bat'),job.get('sim_timeout',600) if step=='simulate' else job.get('build_timeout',1200),step)
        log=work/(step+'.log')
        if not log.is_file() or not log.stat().st_size: raise InvalidEvidence(f'missing fresh {step} log')
        if step!='simulate' and re.search(r'^\s*(ERROR:|FATAL:)',log.read_text(errors='replace'),re.M|re.I): raise InvalidEvidence(f'{step} diagnostic error')
    kernel=work/'xsim.dir'/(job['top']+'_behav')/'xsimk.exe'
    sdb=work/'xsim.dir/xil_defaultlib'/(job['top']+'.sdb')
    if not kernel.is_file() or not sdb.is_file(): raise InvalidEvidence('missing compiled kernel/top')
    if scripts_before!=snapshot(scripts): raise InvalidEvidence('generated script changed during job')
    after=snapshot(paths); atomic(out/'sources_after.json',after)
    observed=judge((work/'simulate.log').read_text(errors='replace'),job,process,before,after)
    return dict(observed=observed,process=process,defines_applied=actual,top=job['top'],source_manifest=before,retry_history=[])

# RTL-vs-teammate-reference comparison jobs (bit-exact golden bench and its post-mutant control).
COMPAT_JOBS=('s8_golden','s8_control_after')
def python_rtl_compatibility(records):
    """MATCH: every comparison job that ran in this run passed and s8_golden is among them.
    MISMATCH: a comparison job completed and reported errors (as FAIL, or INVALID with observed errors > 0).
    NOT_RUN: otherwise (not selected, blocked, interrupted, or invalid for a non-comparison reason)."""
    ran={j:records[j] for j in COMPAT_JOBS if j in records}
    for r in ran.values():
        errs=(r.get('observed') or {}).get('errors')
        if r.get('state')=='FAIL' or (isinstance(errs,int) and errs>0 and r.get('state') not in PASS) \
           or re.search(r'observed \d+/[1-9]\d*',str(r.get('reason',''))):
            return 'MISMATCH'
    if ran.get('s8_golden',{}).get('state') in PASS and all(r.get('state') in PASS for r in ran.values() if r.get('state') not in ('NOT_RUN','BLOCKED') and r.get('reason')!='not selected'):
        return 'MATCH'
    return 'NOT_RUN'

def report(out, records, registry):
    stages={}
    for stage in registry['stages']:
        req=stage['jobs']; states=[records.get(j,{}).get('state','NOT_RUN') for j in req]
        state='PASS_FRESH' if states and all(s in PASS for s in states) else ('FAIL' if 'FAIL' in states or 'INVALID' in states else 'BLOCKED' if 'BLOCKED' in states else 'NOT_RUN')
        upstream=[d for d in stage['dependencies'] if stages.get(d,{}).get('state') not in PASS]
        if state in PASS and upstream: state='BLOCKED'
        stages[stage['id']]=dict(state=state,jobs=req,dependencies=stage['dependencies'])
    status=dict(schema=1,run_id=out.name,stages=stages,jobs=records,hardware_validated=False,soc_integration_complete=False,
                status='PASS' if complete(stages) else 'FAIL' if any(s['state']=='FAIL' for s in stages.values()) else 'BLOCKED' if any(s['state']=='BLOCKED' for s in stages.values()) else 'INCOMPLETE')
    active=registry.get('active_increment')
    if active:
        req=registry['increments'][active];states=[records.get(j,{}).get('state','NOT_RUN') for j in req]
        inc='PASS' if states and all(s in PASS for s in states) else 'FAIL' if any(s in ('FAIL','INVALID') for s in states) else 'NOT_RUN'
        status.update(active_increment=active,increment_status=inc)
    atomic(out/'status.json',status); atomic(ROOT/'reports/dual_lane_latest.json',dict(evidence_dir=str(out),status=status['status']))
    lines=['# Dual-lane results',f'Run: {out.name}',f'Status: **{status["status"]}**','', '| Package | State |','|---|---|']
    lines += [f'| {k} | {v["state"]} |' for k,v in stages.items()]
    lines+=['','| Job | State | Reason |','|---|---|---|']
    lines += [f'| {k} | {v["state"]} | {str(v.get("reason","" )).replace(chr(10)," ").replace("|","/")} |' for k,v in records.items()]
    atomic(out/'summary.md','\n'.join(lines)+'\n')
    atomic(out/'NEXT_ACTION.md','\n'.join(f'- {k}: {v.get("reason",v["state"])}' for k,v in records.items() if v['state'] not in PASS)+'\n')
    with (out/'job_matrix.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f); w.writerow(['job','state','expected','observed','original_run','reason'])
        for j in registry['jobs']:
            r=records.get(j['id'],{}); w.writerow([j['id'],r.get('state','NOT_RUN'),j.get('checks'),json.dumps(r.get('observed')),r.get('original_run',''),r.get('reason','')])
    return status

def run(selection):
    global CONFIG
    CONFIG=json.loads((ROOT/'docs/decisions/dual_lane_config.json').read_text())
    registry=json.loads((ROOT/'scripts/dual_lane_jobs.json').read_text())
    if registry.get('active_increment')!=CONFIG.get('active_increment'):raise InvalidEvidence('increment/configuration mismatch')
    protected_preflight(); rtl_lint_preflight()
    allowed=set(registry.get('increments',{}).get(CONFIG.get('active_increment','I-1'),[]))
    if not allowed:raise InvalidEvidence('active increment has no frozen job list')
    out=ROOT/'reports'/('dual_lane_10_'+dt.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:8]); out.mkdir(parents=True)
    records={}; lock=ROOT/'automation/dual_lane.lock'
    try: fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    except FileExistsError: raise InvalidEvidence('active/interrupted scheduler lock; inspect owner before recovery')
    os.write(fd,json.dumps(dict(pid=os.getpid(),started=now(),evidence=str(out))).encode()); os.close(fd)
    try:install(ROOT,ROOT/'automation/dual_lane_payload/update_manifest.json')
    except BaseException:
        lock.unlink(missing_ok=True);raise
    atomic(out/'registry.json',registry); atomic(out/'configuration.json',CONFIG)
    baseline=json.loads((ROOT/'automation/dual_lane_payload/baseline_before.json').read_text())
    atomic(out/'intake_baseline.json',baseline)
    atomic(out/'git_identity.json',dict(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),branch=subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip(),dirty=subprocess.check_output(['git','status','--porcelain=v1'],cwd=ROOT,text=True)))
    prior=[]
    for p in sorted((ROOT/'reports').glob('dual_lane_10_*/status.json'),reverse=True):
        if p.parent!=out:
            try: prior.extend(json.loads(p.read_text())['jobs'].values())
            except (ValueError,KeyError): pass
    try:
        for job in registry['jobs']:
            jid=job['id']; record=dict(state='NOT_RUN',expected=job,started=None,ended=None)
            records[jid]=record
            if jid not in allowed:
                record.update(state='BLOCKED',reason='outside active '+CONFIG['active_increment']+'; later increment requires accepted prerequisite');continue
            if selection!='all' and selection!='i1' and job.get('selection')!=selection and job['kind']!='reuse':
                record['reason']='not selected'; continue
            if job.get('unimplemented'):
                record.update(state='BLOCKED',reason=job['unimplemented']); continue
            pending=[d for d in job.get('decisions',[]) if CONFIG['decisions'][d]['state']!='ACCEPTED']
            if pending:
                record.update(state='BLOCKED',reason='pending decisions: '+', '.join(pending)); continue
            if not job.get('independent',False) and not dependencies_ok(job,records):
                record.update(state='BLOCKED',reason='required dependency is not accepted'); continue
            jd=out/jid; jd.mkdir(); record.update(state='RUNNING',started=now(),fresh_run=out.name)
            try:
                atomic(jd/'source_preflight.json',source_names(ROOT,job))
                inputs=[safe(ROOT,p) for p in job.get('sources',[])+job.get('oracle_files',[])]+[ROOT/'scripts/dual_lane.py',ROOT/'scripts/dual_lane_verify.py',ROOT/'scripts/controlled_diagnostics.py',ROOT/'scripts/dual_lane_preflight.py',ROOT/'scripts/dual_lane_support.ps1',ROOT/'scripts/wp0_support.ps1',ROOT/job.get('child_script','scripts/dual_lane_export.tcl'),ROOT/'docs/decisions/dual_lane_config.json',ROOT/'scripts/dual_lane_jobs.json']
                inputs_before=snapshot(inputs)
                ident=digest(dict(job=job,config=CONFIG,files=inputs_before,export=sha(ROOT/'scripts/dual_lane_export.tcl')))
                record['identity']=ident;report(out,records,registry);print(f'RUN {jid}',flush=True)
                reused=next((p for p in prior if p.get('identity')==ident and p.get('state') in PASS and artifacts_valid(p)),None)
                if reused:
                    record.update(reused); record.update(state='PASS_REUSED',original_run=reused.get('original_run',reused.get('fresh_run')),reuse_checked=now())
                elif job['kind']=='reuse': record.update(reuse_wp0(ROOT,safe(ROOT,job['evidence']),job))
                elif job['kind']=='python':
                    args=[CONFIG['python'],str(ROOT/job['script'])]
                    if job.get('output_argument'):args+=['--out',str(jd)]
                    p=subprocess.run(args,capture_output=True,text=True,encoding='utf-8',timeout=job.get('sim_timeout',60))
                    atomic(jd/'stdout.log',p.stdout); atomic(jd/'stderr.log',p.stderr)
                    if p.returncode:
                        if (jd/'audit.json').exists():raise GateFailure('Python reference audit failed; see python_ref/audit.json and raw suite logs')
                        raise InvalidEvidence(f'Python exit {p.returncode}: {p.stderr[-2000:]}')
                    if job.get('positive_marker') and not re.search(job['positive_marker'],p.stdout,re.M):raise InvalidEvidence('missing Python positive marker')
                    after=snapshot(inputs);atomic(jd/'sources_before.json',inputs_before);atomic(jd/'sources_after.json',after)
                    if inputs_before!=after:raise InvalidEvidence('Python input identity changed during job')
                    record.update(state='PASS_FRESH',observed=dict(exitCode=0),source_manifest=inputs_before)
                else: record.update(execute(job,jd),state='PASS_FRESH')
                if 'artifacts' not in record:
                    artifact_root=safe(ROOT,job['evidence']) if job['kind']=='reuse' else jd
                    record['artifacts']={str(p):sha(p) for p in artifact_root.rglob('*') if p.is_file() and p.suffix in ['.log','.txt','.json','.tsv','.rpt','.tcl','.bat','.prj','.exe','.dcp']}
            except Exception as e:
                record.update(state='FAIL' if isinstance(e,(PreflightFailure,GateFailure)) else 'INVALID' if isinstance(e,InvalidEvidence) else 'FAIL',reason=str(e))
            record['ended']=now(); atomic(jd/'result.json',record); report(out,records,registry)
            print(f'{jid}: {record["state"]} {record.get("reason","")}',flush=True)
        status=report(out,records,registry)
        protected=protected_preflight()
        changed={p:dict(before=h,after=sha(ROOT/p) if (ROOT/p).exists() else None) for p,h in protected.items() if not (ROOT/p).is_file() or sha(ROOT/p)!=h}
        atomic(out/'protected_source_comparison.json',dict(changed=changed,original_count=len(protected)))
        print(f'NOC_PACKAGES_ACCEPTED={sum(v["state"] in PASS for k,v in status["stages"].items() if k.startswith("NOC"))}/5\nPQ_PACKAGES_ACCEPTED={sum(v["state"] in PASS for k,v in status["stages"].items() if k.startswith("PQ"))}/5\nDUAL_LANE_STATUS={status["status"]}\nSOURCE_IDENTITY={digest(protected)}\nPYTHON_REFERENCE_ZIP={CONFIG["python_reference"]["zip"]}\nPYTHON_REFERENCE_SHA256={CONFIG["python_reference"]["sha256"]}\nTILE_KEY_BYTES=32\nPYTHON_RTL_COMPATIBILITY={python_rtl_compatibility(records)}\nEVIDENCE_DIR={out}\nHARDWARE_VALIDATED=NO\nSOC_INTEGRATION_COMPLETE=NO',flush=True)
        print(f'ACTIVE_INCREMENT={CONFIG["active_increment"]}\nINCREMENT_STATUS={status["increment_status"]}',flush=True)
        # I-1 completion is distinct from ten-package release acceptance.
        return 0 if status['increment_status']=='PASS' else 2
    finally: lock.unlink(missing_ok=True)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('action',choices=['run','preflight','rollback']); ap.add_argument('--select',default='all'); a=ap.parse_args()
    if a.action=='run': return run(a.select)
    if a.action=='preflight':
        protected_preflight(); rtl_lint_preflight()
        rows=install(ROOT,ROOT/'automation/dual_lane_payload/update_manifest.json',dry=True)
        registry=json.loads((ROOT/'scripts/dual_lane_jobs.json').read_text())
        for job in registry['jobs']:source_names(ROOT,job)
        print(f'PREFLIGHT: PASS ({len(rows)} guarded files; {len(registry["jobs"])} source lists)');return 0
    install(ROOT,ROOT/'automation/dual_lane_payload/update_manifest.json',rollback=True); return 0
if __name__=='__main__': sys.exit(main())
