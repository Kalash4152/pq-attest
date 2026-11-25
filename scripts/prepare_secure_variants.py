"""Prepare explicit opt-in source variants; never overwrite live baseline RTL."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'NOC_PQATTEST.srcs/sources_1/new'; D=ROOT/'rtl/dual_lane'; D.mkdir(parents=True,exist_ok=True)
def replace(text,a,b):
    if text.count(a)!=1: raise ValueError('nonunique variant anchor '+a)
    return text.replace(a,b)
pkg=(S/'NOC_PKG.sv').read_text()
pkg=replace(pkg,'ATTEST_CHALLENGE_WIDTH = 160;','ATTEST_CHALLENGE_WIDTH = 224;')
pkg=replace(pkg,"MSG_ATTEST_CHALLENGE: return 5'd5;","MSG_ATTEST_CHALLENGE: return 5'd7;")
(D/'NOC_PKG.sv').write_text('// OPT-IN Q-C/R-B variant. Original baseline is preserved.\n'+pkg,newline='\n')
ni=(S/'noc_network_interface.sv').read_text()
ni=replace(ni,'output logic                           tx_ready,','output logic                           tx_ready,\n    output noc_pkg::head_flit_t             tx_auth_preview,')
anchor='    head_flit_t tx_head;'
preview='''
    // Combinational preview only. No request is accepted by this output.
    // The trusted adapter rechecks it before presenting its final MAC.
    always_comb begin
        tx_auth_preview = '0;
        tx_auth_preview.src_x = LOCAL_COORD.x;
        tx_auth_preview.src_y = LOCAL_COORD.y;
        tx_auth_preview.dest_x = tx_dest_coord.x;
        tx_auth_preview.dest_y = tx_dest_coord.y;
        tx_auth_preview.msg_type = tx_msg_type;
        tx_auth_preview.length = message_length(tx_msg_type);
        tx_auth_preview.control.raw = tx_control;
        if (tx_msg_type == MSG_MEM_RD_REQ || tx_msg_type == MSG_MEM_WR_REQ)
            tx_auth_preview.control.raw[TXN_TAG_WIDTH-1:0] = tx_alloc_tag;
    end
'''
ni=replace(ni,anchor,anchor+preview)
(D/'noc_network_interface.sv').write_text('// OPT-IN authentication preview variant; baseline state machine preserved.\n'+ni,newline='\n')
manifest={p.name:dict(base=hashlib.sha256((S/p.name).read_bytes()).hexdigest(),variant=hashlib.sha256(p.read_bytes()).hexdigest()) for p in [D/'NOC_PKG.sv',D/'noc_network_interface.sv']}
(D/'variant_provenance.json').write_text(json.dumps(manifest,indent=2)+'\n')
