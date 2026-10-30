# GAMS reference harness

Produces the GAMS reference dumps that every TIMES.jl parity test compares
against. It runs the unmodified TIMES v4.9.7 source under GAMS; it never edits
TIMES files.

## What it produces

For each model and variant, under `<out>/<model>/<variant>/`:

| Path | Content | Used for |
| --- | --- | --- |
| `ppm/` | Every symbol after preprocessing (after `ppm_ext`, the point of the `DEBUG` dump) | Layer 1, M1.3 |
| `coef/` | Every symbol after coefficient calculation (after `coef_ext`) | Layer 1, M1.2 |
| `presolve/` | Every symbol just before the SOLVE statement: a third run with `SOLVE_NOW=NO`, so `solve.mod` L22 skips the solve and `maindrv.mod` L114 the reports. The state equations are generated from, after `eqmain`, `bndmain`, `pp_qack` and `pp_clean` | Input data for M1.1; layer 1 for sets the equation files compute (e.g. `AFS`) |
| `final/` | Every symbol at the end of the run (`gdx=`), including levels and marginals | Layers 3–4 |
| `matrix/`, `matrix_dictmap/` | CONVERT `DumpGDX` and `DictMap` of the scalar model | Layer 2 |
| `raw/` | CONVERT dictionary and MPS file, listings, logs, GAMS profile, each run's patched run file (`tjl_<run>.run`, harness 0.2.2+) | Debugging, timings, switches for `scripts/m11_probe.jl` |
| `manifest.json` | TIMES version and commit, GAMS version, solver and options, wall times, model attributes (`resGen`, `resUsd`, `numEqu`, `numVar`, `numNZ`, `objVal`, ...), input checksums | Provenance, benchmarks |

Variants: `reduce_off` (forces `$SET REDUCE NO`, used first for matrix
parity) and `as_run` (the model's own settings).

Symbols are stored as Arrow IPC files; the format is described at the top of
[`python/gdx2arrow.py`](python/gdx2arrow.py).

## How it hooks into TIMES

The harness passes the extension tag `TJLREF` to `$BATINCLUDE initmty.mod`.
TIMES adds it to its extension list (initmty.mod L472-473) and `main_ext.mod`
then includes [`gams/ppm_ext.tjlref`](gams/ppm_ext.tjlref) and
[`gams/coef_ext.tjlref`](gams/coef_ext.tjlref) after the standard extensions
at those two stages. A short block after `$BATINCLUDE maindrv.mod` saves the
model attributes. Each change to the run file is recorded in the manifest.

## Requirements

- GAMS with a licence for the reference solver (CPLEX by default)
- Python 3.11 or later with `pyarrow`, `pandas` and the GAMS Python API:
  `pip install pyarrow pandas "gamsapi[transfer]==<your GAMS version>"`
- Local clones of the TIMES source and the test models:

| Root | Repository | Commit |
| --- | --- | --- |
| `times_source` | `etsap-TIMES/TIMES_model` | `d9a6a25` (v4.9.7; checked) |
| `times_demo` | `etsap-TIMES/TIMES_Demo` | `962db86` |
| `times_nz_dd` | local folder `timesjl-sources/TIMES-NZ` (DD export of EECA main 8165e1d, TIMES-NZ 3.0.8) | pinned by the SHA-256 of `dd/manifest.json` |
| `otus` | `esma-ie/OTUS9r` (`dd/`: the Veda DD export of 28 Oct 2026; EPA original at tag `epaus9rt-v20.4`) | `598e179` |
| `tim` | local folder `timesjl-sources/TIM` (James's export; the licence exception, local only) | pinned by the SHA-256 of `dd/manifest.json` |
| `jrc_eu_times` | local folder `timesjl-sources/JRC-EU-TIMES`: DD and run files extracted from the dumps in `gitea.psi.ch/WIMBY/JRC-EU-TIMES` @ `c18a076` | not git; pinned by the SHA-256 of `dd/manifest.json` (`reference/suite.toml` header) |

TIM returns as a research-only exception once its DD files are in an esma-ie
fork of `MaREI-EPMG/times-ireland-model`. Nothing from the `esma-cgep`
archive is used.

Only models under a clearly stated open-source or open-data licence are
used (see [`docs/test-models.md`](../docs/test-models.md)). Each model's
licence and whether material derived from it may be published with this
repository (`redistribute = public | summary | private`; `summary`: only the
summary results in `summary.csv`, never references or fixtures) is recorded in
`reference/suite.toml`, and `reference/python/test_suite.py` fails on a model
without an open licence unless its entry names an exception (TIM is the only
one). The DemoS models were removed on 27 Oct 2026 (no stated licence);
TIMES-GEO and PROTO on 22 Oct 2026; ETSAP-TIAM is never used.

## Run limits

On James's workstation every run uses at most 12 solver threads and at most
4 GAMS runs run at the same time (James, 29 Oct 2026), so that the machine
stays usable and every test gets the same resources. `make_reference.py`
passes `threads=12` to GAMS and rewrites the `threads` line of each model's
solver option file (e.g. PSI's `threads -1`) in the run's work folder, never
in the source; the manifest records both (`limits`, `patch.solver_option_changes`).
Before each GAMS run it takes one of 4 machine-wide slots (lock files in
`<temp>/timesjl-run-slots`, `reference/python/runlimits.py`) and waits while all
are taken; the wait is recorded as `slot_wait_s` and is not part of `wall_s`.
Change the limits with `--threads`, `--max-parallel` and `--slot-dir` (or
`TIMESJL_THREADS`, `TIMESJL_MAX_PARALLEL`, `TIMESJL_SLOT_DIR`;
`run_references.ps1 -Threads -MaxParallel`); 0 disables a limit. GAMS's own
default is one solver thread, so models without a `threads` option now solve
with 12.

## Running it

**Windows, licensed GAMS (recommended):** one script does all of the above
and the run itself, one model at a time, small models first:

```
powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1            # whole suite
powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Set M1.1  # M1.1 models only
```

It checks that CPLEX (and HiGHS) solve a one-row LP under your licence, clones
and pins every repository above into `..\timesjl-sources` (your own clones are
not touched), builds a venv with the GAMS Python API for your GAMS version,
using the first 64-bit Python 3.11+ it finds that has wheels for that API
(GAMS 52.1.0's `gamsapi` stops at Python 3.14, so a default Python 3.15 is
skipped and `py -3.13` used instead), runs this harness, runs the M1.0 gate if Julia is on PATH, and writes
`summary.csv` plus one zip per model in `_packed\`. `-Resume` skips finished
runs; `-Models a,b` picks models. It also runs under PowerShell 7 on Linux.

By hand, one model (both variants):

```
python reference/python/make_reference.py \
    --out ../timesjl-reference \
    --root times_source=../TIMES_model \
    --root times_demo=../TIMES_Demo \
    --model TIMES_Demo-demo12
```

Whole suite, with HiGHS as a second solver:

```
python reference/python/make_reference.py \
    --out ../timesjl-reference --solvers CPLEX,HIGHS \
    --root times_source=../TIMES_model --root times_demo=../TIMES_Demo \
    --root times_nz_dd=../timesjl-sources/TIMES-NZ
```

Each model/variant ends with `OK` or `CHECK`; `CHECK` means a GAMS run returned
an error or an expected dump is missing, and `raw/` holds the listings. A
model whose `--root` is missing stops the run before any GAMS call.

## Without a licensed GAMS

The demo licence of the PyPI GAMS system runs the harness itself, but it
solves and exports only models up to 2,000 rows or columns:

```
pip install pyarrow pandas "gamsapi[transfer]==54.6.0" gamspy_base==54.6.0 gamspy_highs==54.6.0
python reference/python/register_highs.py          # one-off: add HiGHS to the PyPI GAMS system
python reference/python/make_reference.py --out ../timesjl-reference \
    --root times_source=../TIMES_model --root times_demo=../TIMES_Demo \
    --model TIMES_Demo-demo12 --solvers HIGHS,CPLEX \
    --gams "$(python -c 'import gamspy_base;print(gamspy_base.directory)')/gams"
```

No model in the suite fits that limit at present: TIMES_Demo demo12 has
8,695 rows with REDUCE off, and TIMES-NZ and TIM are larger, so their solves,
CONVERT exports and all timings need a licensed GAMS. The pre-solve dump needs
no solve and can be made under the demo licence for any model. The M1.0 gate
first passed on 18 Oct 2026 under the demo licence; see `docs/discrepancies.md` ("Settled") for
the CONVERT layouts found by the first run.
