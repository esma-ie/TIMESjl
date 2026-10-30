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
