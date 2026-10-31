# Parity dashboard

`index.html` is the TIMES.jl parity board: three 16:9 panels (translation
progress and headline figures; the parity matrix of every check by model and
stage; objective agreement and generation timings against GAMS), in the ESMA
palette, exportable panel by panel to a slide deck. Open it from a checkout
or as the private artifact James keeps.

## Data

- `demo12.json`: the parity report of the public fixtures
  (`test/fixtures/public_fixtures.toml`), written by
  `scripts/parity_report.jl`. One record per check: layer (1 coefficient file,
  2 equation family or whole matrix, 3 GAMS solver), status (pass, fail,
  refused, skipped), records compared and excluded, mismatches, seconds; plus
  the run (model, variant, licence, matrix size) and the commit. No model
  data.
- The same report is embedded in `index.html` (`--embed`), so the page works
  opened as a file. Refresh both after a change that touches parity:

      julia --project=test scripts/parity_report.jl docs/dashboard/demo12.json --embed

- `suite-public.json`: the parity report of the reference runs of the public
  suite models (`redistribute = "public"` in `reference/suite.toml`), made on
  James's workstation from `timesjl-reference`, embedded in the page's
  `report-suite` block (`--embed-as report-suite`; the embedding refuses any
  run that is not `redistribute = "public"`). It covers the core tier's public
  models (`tier = "core"`); milestone-tier models are added when a milestone
  run makes them:

      julia --project=test scripts/parity_report.jl docs/dashboard/suite-public.json --embed-as report-suite --ref ../timesjl-reference --root otus=../timesjl-sources/OTUS9r --root times_nz_dd=../timesjl-sources/TIMES-NZ --root otcgen=../timesjl-sources/OTCGEN --root otnyc=../timesjl-sources/OTNYC TIMES_Demo-demo12 TIMES-NZ-steady-v308 OTUS9r-reference OTCGEN-gc_ref OTNYC-s1_nyc_ref

  A model probed in a separate run gets its own file and block
  (`suite-public-<name>.json`, `report-suite-<name>`); the page merges every
  `report*` block, and its header shows the last block's commit and date. The
  next run that covers all of them writes `suite-public.json` alone and the
  extra file and block are removed. Before committing a report, set
  `meta.host` to `"workstation"` (the script records the machine name).
  Reports of 30 Oct 2026: `suite-public.json` (demo12, TIMES-NZ steady,
  OTUS9r reference, at 6f3d91e) and `suite-public-otcgen-otnyc.json` (OTCGEN,
  OTNYC, at 2fde1e3; `src/` is the same at both commits).

- Local runs (TIM, on James's machine) are reported the same way from a
  reference directory and loaded into the open page with its "Load results
  JSON" button; those files hold counts and statuses only and are not
  committed:

      julia --project=test scripts/parity_report.jl tim.json --ref ../timesjl-reference TIM-bau TIM-mitigation_cb2024-300mt TIM-mitigation_cb2024-300mt-myopic

- The pipeline strip (GAMS files and their status), the M1.1 timings and the
  suite's models not yet reported are written into the page by hand
  (`PIPELINE`, `TIMINGS`, `PLANNED_RUNS` in its script); update them when a
  file is translated, `docs/timings.md` changes or the suite changes. Only
  open models go in `TIMINGS`: TIM's timings stay on James's machine.

## Encoding

Matrix cells: fill = status; inner square = records compared, log scale;
yellow hairline = records left to a later coefficient file
(`later_overwrites`); dashed outline = not run. Objective chart: relative
difference per GAMS solver on a log axis against the 1e-6 gate, with
cross-feasibility ticks (ours in GAMS's matrix, theirs in ours). Timing
chart: GAMS execution to hand-off against TIMES.jl generation, with the
Phase 1 5x target per model.
