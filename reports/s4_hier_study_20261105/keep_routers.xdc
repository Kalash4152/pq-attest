# H2 (measurement only): keep only the six router boundaries; mesh link logic and router internals may still be optimised.
set_property KEEP_HIERARCHY TRUE [get_cells -hierarchical -filter {NAME =~ mesh/GEN_R*.r && IS_PRIMITIVE == 0}]
