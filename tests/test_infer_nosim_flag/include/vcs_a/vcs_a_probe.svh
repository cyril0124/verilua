// Reached only through the `-I` inferred from `vcs.flags`. Referencing the macro makes an
// undefined macro a compile error, so this also proves the matching `-D` was inferred.
localparam int VCS_A_PROBE_LEVEL = `INFER_FROM_VCS_LEVEL;
