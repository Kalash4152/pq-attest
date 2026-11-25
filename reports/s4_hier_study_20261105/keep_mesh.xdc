# H1 (measurement only): keep the protected NoC hierarchy (mesh and every cell under it) out of cross-boundary optimisation.
set_property KEEP_HIERARCHY TRUE [get_cells mesh]
set_property KEEP_HIERARCHY TRUE [get_cells -hierarchical -filter {NAME =~ mesh/* && IS_PRIMITIVE == 0}]
