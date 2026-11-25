p='rtl/dual_lane/pq_noc_subsystem_p7.sv'; t=open(p,encoding='utf-8').read()
def rep(a,b):
    global t
    assert t.count(a)==1,a[:70]; t=t.replace(a,b)
# I-7 bench hooks: (1) the L2 pair (tiles 3, 4) receives through the same TBI injector as the plain tiles (L2 replay);
# (2) tile 3's response substitution (a compromised tile 3: attacker-chosen RESPONSE status / words, L2-authenticated).
rep("""   logic drop4=0;
   for(genvar k=0;k<6;k++) begin: S""","""   logic drop4=0;
   logic ep_sub=0;              // I-7: tile 3 sends ep_ctl / ep_words instead of its computed RESPONSE
   logic [10:0] ep_ctl='0;
   logic [511:0] ep_words='0;
   for(genvar k=0;k<6;k++) begin: S""")
rep("""   assign tbi_gv=gv; assign tbi_gsrc=gsrc; assign tbi_gmsg=gmsg; assign tbi_gctl=gctl; assign tbi_drop4=drop4;
 end else begin: NOTBI""","""   assign tbi_gv=gv; assign tbi_gsrc=gsrc; assign tbi_gmsg=gmsg; assign tbi_gctl=gctl; assign tbi_drop4=drop4;
   assign tbi_ep_sub=ep_sub; assign tbi_ep_ctl=ep_ctl; assign tbi_ep_words=ep_words;
 end else begin: NOTBI""")
rep("""   assign tbi_gv='0; assign tbi_gsrc='0; assign tbi_gmsg='{default:MSG_ATTEST_GRANT}; assign tbi_gctl='0; assign tbi_drop4=1'b0;
 end""","""   assign tbi_gv='0; assign tbi_gsrc='0; assign tbi_gmsg='{default:MSG_ATTEST_GRANT}; assign tbi_gctl='0; assign tbi_drop4=1'b0;
   assign tbi_ep_sub=1'b0; assign tbi_ep_ctl='0; assign tbi_ep_words='0;
 end""")
rep(""" logic tbi_drop4;
 if(TB_INJECT) begin: TBI""",""" logic tbi_drop4;
 logic tbi_ep_sub;
 logic [10:0] tbi_ep_ctl;
 logic [511:0] tbi_ep_words;
 if(TB_INJECT) begin: TBI""")
rep(""".noc_rx_flit(mesh_out[4:3]),.noc_rx_valid(mesh_ov[4:3]),.noc_rx_ready(mesh_or[4:3]),""",
    """.noc_rx_flit(ni_rx_f[4:3]),.noc_rx_valid(ni_rx_v[4:3]),.noc_rx_ready(mesh_or[4:3]),   // ni_rx_* == mesh_out/ov unless TB_INJECT""")
open(p,'w',encoding='utf-8',newline='\n').write(t); print('hooks ok (endpoint mux applied separately)')
