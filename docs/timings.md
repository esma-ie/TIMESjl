# Model-generation timings, TIMES.jl against GAMS

The translation guide's definition of done asks for timings logged against
GAMS; the Phase 1 target is model generation (preprocessing to solver
hand-off) no worse than 5x GAMS, warm, at M1.7, measured on one machine.
Produced with `scripts/m11_timing.jl` (see its header for what each column
means).

From 29 Oct 2026 local runs on James's workstation keep to the run limits in
`CLAUDE.md` (at most 12 threads per run, at most 4 heavy runs at a time).
Timings made before then used each solver's own setting (GAMS default: one
solver thread) and are not directly comparable with later ones.

## M1.2 coefficient stage, 31 Oct 2026 (indicative: same machine, the cloud workspace)

`scripts/m12_timing.jl`: each coefficient file of TIMES.jl on the ppm dump
(first pass with compilation, then warm), against the GAMS profile of the
same coefficient stage summed over each file's listing lines (nested
includes with their file; the harness's dumps left out). Both sides on one
machine, the cloud workspace (Linux, 2 cpus, 8 GB): GAMS 54.6.1 from PyPI
(the pre-solve run of `make_reference.py --only presolve`, demo licence: no
solve needed), Julia 1.13.3, main at 6ac29e4. Both sides run this stage on
one thread. The workstation measurement (the M1.2 gate's) is still to come:
`julia --project=test scripts\m12_timing.jl C:\git\esma\timesjl-reference --root ... <model>`.

| Model (reduce_off) | coef_cpt | coef_ptr | coef_obj | coef_alt | coef_shp | coef_ext | Stage, TIMES.jl warm | Stage, GAMS | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 0.165 | 0.023 | 0.282 | 0.044 | 0.055 | 0.151 | 0.72 s | 0.016 s | 45 |
| OTNYC-s1_nyc_ref | 17.95 | 30.61 | 13.50 | 0.004 | 5.05 | 51.98 | 119.1 s | 0.79 s | 152 |

TIMES.jl seconds per file (warm; coef_nio is 0 on both). On OTNYC
(504,698 rows) the stage takes two minutes against under a second in GAMS:
coef_ext (52 s against 0.15 s), coef_ptr (31 s against 0.22 s) and
coef_cpt (18 s against 0.22 s) lead. It is the same data-handling cost as
the M1.1 generators (docs/phase2-notes.md: string-tuple keys, untyped
caches, per-record dictionaries), at a larger scale: against the Phase 1
target (generation incl. preprocessing within 5x GAMS) the coefficient stage
alone is 30 times over. Phase 2 work; nothing in Phase 1 changes for it.
OTCGEN (1.26 M rows) does not fit the workspace's 8 GB.

## M1.1, 21 Oct 2026, same machine (James's workstation)

Both sides on one machine: 2x Intel Xeon Gold 6256 (24 cores, 48 threads,
3.6 GHz), 767 GB, Windows 11 Pro for Workstations.

- GAMS: GAMS 52.1.0, the licensed reference runs of 21 Oct (CPLEX solve:
  profile and log), as in the indicative section below.
- TIMES.jl: Julia 1.13.2 (juliaup, one thread), JuMP 1.32.1,
  MathOptInterface 1.54.0, HiGHS 1.26.1, a pre-publication commit of 21 Oct 2026 (the public history starts on 30 Oct); warm = second build
  in the same process. Built from the GAMS pre-solve dump, so preprocessing
  is not included on this side (M1.3).
- Logs: `C:\timesjl-work\m11_timing.log`; the same run's
  `m11_probe.log` passes layers 2 and 3 on demo12.

| Model (reduce_off) | Rows | GAMS compile | GAMS execution to hand-off | GAMS equations + Solve Fini | TIMES.jl generation incl. bounds, warm | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 8,695 | 0.32 s | 0.21 s | 0.07 s | 0.43 s | 6.8 |

Large-model timings (a generator-by-generator breakdown on a model of about
a million rows) were measured on TIM, which is local to James's machine; its
figures are not recorded in this repository (CLAUDE.md, Test-model licences)
and are to be measured again on an open model of that size (TIMES-NZ, OTUS9r
or JRC-EU-TIMES). On demo12, generation alone is 2.0x GAMS's whole execution
to hand-off.

## M1.1, 21 Oct 2026 (indicative: two machines; superseded by the section above)

- GAMS: James's machine (Windows 11, 48 cpus), GAMS 52.1.0, the licensed
  reference runs of 21 Oct (CPLEX solve: profile and log).
- TIMES.jl: the cloud workspace (Linux, 2 cpus Xeon 2.8 GHz, 8 GB), Julia
  1.13.2, JuMP 1.32.1, MathOptInterface 1.54.0; warm = second build in the
  same process. Built from the GAMS pre-solve dump, so preprocessing is not
  included on this side (M1.3).

| Model (reduce_off) | Rows | GAMS compile | GAMS execution to hand-off | GAMS equations + Solve Fini | TIMES.jl generation incl. bounds, warm | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 8,695 | 0.32 s | 0.21 s | 0.07 s | 0.51 s | 8.1 |

The same-machine measurement above replaces these figures.
