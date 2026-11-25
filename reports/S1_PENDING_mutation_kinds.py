"""Next session (apply once, with the B-4 registration): contract sec. 1/2/5 mutation kinds for scripts/dual_lane.py.
Each anchor was checked against the RTL at 61d0e39. Routing: 'vrev_' -> pq_rot_verifier.sv; 'l2e_' -> l2_kmac_engine.sv;
'p7s_' -> pq_noc_subsystem_p7.sv (quarantine/parser instance parameters)."""
from pathlib import Path
p = Path(r'C:/vivado_verilog_proj/NOC_PQATTEST/scripts/dual_lane.py'); t = p.read_text(encoding='utf-8')
NEW_L2E = '''               'l2e_owner_select':[("                E_IDLE:  if (grant) begin owner <= grant_id;","                E_IDLE:  if (grant) begin owner <= grant_id ^ 2'd1;   // MUT-L2E owner select")],
               'l2e_done_route':[("                E_RUN:   if (kdone) es <= E_IDLE;","                E_RUN:   begin owner <= grant_id; if (kdone) es <= E_IDLE; end   // MUT-L2E completion routed to the arbiter's pick")],
               'l2e_word_off':[("for (int k = 0; k < NWORDS; k++) if (wcnt == 6'(k)) emsg[k*32 +: 32] <= wd[owner];","for (int k = 0; k < NWORDS; k++) if (wcnt == 6'(k + 1)) emsg[k*32 +: 32] <= wd[owner];   // MUT-L2E transcript one word off")],
               'l2e_key_live':[(".key_in(key_q)",".key_in(owner[1] ? key_34 : key_43) /* MUT-L2E key read live */")],
'''
NEW_P7S = '''               'p7s_q_nested_off':[(".NESTED_CHECK(1'b1)",".NESTED_CHECK(1'b0) /* MUT-P7S */")],
               'p7s_q_gap_any':[(".GAP_NEEDS_READY(1'b1)",".GAP_NEEDS_READY(1'b0) /* MUT-P7S */")],
               'p7s_q_no_cap':[(".LENGTH_CAP(1'b1)",".LENGTH_CAP(1'b0) /* MUT-P7S */")],
               'p7s_q_partial':[(".COMMIT_WHOLE(1'b1)",".COMMIT_WHOLE(1'b0) /* MUT-P7S */")],
               'p7s_q_src_off':[(".SRC_CHECK(1'b1)",".SRC_CHECK(1'b0) /* MUT-P7S */")],
'''
NEW_VREV = '''    if kind.startswith('vrev_'):
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
'''
R = [("        multi={'l2e_a3_long_job':", "        multi={" + NEW_L2E.strip() + "\n               'l2e_a3_long_job':"),
     ("               'p7s_no_src_check':", NEW_P7S + "               'p7s_no_src_check':"),
     ("    if kind.startswith(('l2e_','l2p7_','p7s_')):", NEW_VREV + "    if kind.startswith(('l2e_','l2p7_','p7s_')):"),
     ("        name='l2_kmac_engine.sv' if job['mutant'].startswith('l2e_') else", "        name='pq_rot_verifier.sv' if job['mutant'].startswith('vrev_') else 'l2_kmac_engine.sv' if job['mutant'].startswith('l2e_') else")]
for a, b in R:
    if t.count(a) != 1: raise SystemExit('anchor count %d: %r' % (t.count(a), a[:70]))
    t = t.replace(a, b)
p.write_text(t, encoding='utf-8', newline='')
print('mutation kinds added')
