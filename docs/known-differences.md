# Known differences from GAMS

Justified, reviewed differences between TIMES.jl output and the GAMS
reference. Anything not listed here is a parity failure.

| # | Component | Test model(s) | Difference | Justification | Approved by |
| --- | --- | --- | --- | --- | --- |
| K1 | Layer-3 cross-evaluation (`scripts/m11_probe.jl`, `scripts/m11_large.jl`) | Found on local-only TIM runs (21 Oct 2026; their figures are not recorded in this repository, CLAUDE.md); to be shown again on an open model | A GAMS/CPLEX optimum can violate a TIMES.jl row by more than the 1e-6 cross-evaluation tolerance. | The same row has the same activity in the GAMS CONVERT LP itself: CPLEX returned a point outside 1e-6 in its own model. The matrices must still be identical at 1e-9 (layer 2), the HiGHS optimum of TIMES.jl feasible in the GAMS LP and the objectives equal at 1e-6. The cross-evaluation accepts a GAMS optimum that violates no TIMES.jl row more than the same row of the GAMS LP (`as_feasible_as`). Revisit in Phase 2: tighter solver tolerances for the reference runs and the checks (docs/phase2-notes.md, P2-1). | James Glynn, 21 Oct 2026, for Phase 1 |
