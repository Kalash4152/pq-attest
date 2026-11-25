set S [file dirname [info script]]
set P xc7a100tcsg324-1
set N C:/vivado_verilog_proj/NOC_PQATTEST/NOC_PQATTEST.srcs/sources_1/new
set out [open $S/results.txt w]
foreach {tag top gen} {
  enc_shared_base probe_enc {SPEC=0 SHARED=1}
  enc_shared_a3   probe_enc {SPEC=1 SHARED=1}
  enc_l2_base     probe_enc {SPEC=0 SHARED=0}
  enc_l2_a3       probe_enc {SPEC=1 SHARED=0}
  cnt32           probe_cnt {SAT16=0 N=16}
  cnt16sat        probe_cnt {SAT16=1 N=16}
} {
  close_project -quiet
  create_project -in_memory -part $P
  read_verilog -sv [list $N/kmac_pkg.sv $N/kmac_encode.sv $S/kmac_encode_a3.sv $S/probes.sv]
  set g {}; foreach kv $gen { lappend g -generic $kv }
  synth_design -top $top -part $P -mode out_of_context -flatten_hierarchy rebuilt -directive AreaOptimized_high {*}$g
  report_utilization -file $S/util_$tag.rpt
  set lut [llength [get_cells -hier -filter {PRIMITIVE_GROUP==LUT}]]
  set ff  [llength [get_cells -hier -filter {PRIMITIVE_GROUP==FLOP_LATCH}]]
  puts $out "$tag LUT=$lut FF=$ff"; flush $out
}
close $out
