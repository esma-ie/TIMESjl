# M1.3 preprocessing: plan (31 Oct 2026)

Source: TIMES v4.9.7, etsap-TIMES/TIMES_model @ d9a6a25. Translate one file or
block per change, in execution order; GAMS names kept; every function cites
its lines. Agreed with James on 31 Oct 2026; M1.3 translation starts once the
M1.2 gate passes (CLAUDE.md), change 0 (infrastructure) alongside the M1.2
close-out.

## Scope: from the input dump to the ppm dump

maindrv.mod L55-58 (v4.9.7):

- L55: the extensions' `init_ext` (`init_ext.dsc`, `init_ext.vda` with
  `equcrtp.vda` INIT_EXT; `prepparm.gms` is called from `equcrtp.vda`
  PREP_EXT, L55, and belongs to the prep segment);
- L56: `ppmain.mod` and its includes (`timslice.mod`, `pp_off.mod`,
  `preppm.mod` with `prepxtra.mod`, `fillparm.gms`, `fillvint.gms`,
  `curex.gms`, `preshape.gms`; `filparam.gms`, `filshape.gms`, `pp_qafs.mod`,
  the levelising macros `pp_lvl*.mod`, `pp_chp.mod`, `eqflomrk.mod`,
  `pp_reduce.red` with `dynslite.vda`) and the extension stages inside it
  (`prep_ext.vda` at preppm.mod L217, `pp_prelv.vda` at ppmain.mod L615);
- L58: the extensions' `ppm_ext` (`ppm_ext.dsc`, `ppm_ext.vda` with
  `pp_actef.vda`, `resloadc.vda`, `equcrtp.vda` PPM_EXT, `dynslite.vda`).

Plus `cal_red.red` on the equation side, which REDUCE YES needs (M1.1
refused it; the as_run variants of the suite run REDUCE YES).

About 4,200 lines in about 30 files: roughly five times M1.2. The riskiest
part is the interpolation subsystem (`preppm.mod`, `prepparm.gms`,
`fillparm.gms`, `fillvint.gms`): its options decide almost every parameter
the later stages read.

Refused (UnportedError), as in M1.1 and M1.2: TIMES-MICRO / TIMESED
(`pp_micro.mod`), MACRO (`ppmain.tm`), stochastics (`prep_ext.stc`,
`recurrin.stc`), the ETL, CLI, ABS, ECB and MLF extensions, `INTEXT_ONLY` and
`DATAGDX`, and blending (ppmain.mod L1230-1336) unless a suite model needs it.

## Checkpoints (harness 0.3.0)

The harness dumps every symbol at five points of one GAMS run (the pre-solve
run, `--TJL_CHECKPOINTS=1`; reference/README.md), without editing TIMES:

| Checkpoint | Where (v4.9.7) | How |
| --- | --- | --- |
| `input/` | before `$BATINCLUDE maindrv.mod` | run-file patch |
| `init/` | maindrv.mod L55, after `init_ext.dsc`/`.vda` | `init_ext.tjlref` |
| `prep/` | preppm.mod L217, after `prep_ext.vda` | `prep_ext.tjlref` |
| `prelv/` | ppmain.mod L615, after `pp_prelv.vda` | `pp_prelv.tjlref` |
| `ppm/` | maindrv.mod L58, after `ppm_ext.dsc`/`.vda` | `ppm_ext.tjlref` (M1.2) |

So preprocessing splits into four segments, each started from GAMS's own
state and checked at the next checkpoint. A segment can be translated and
checked on its own; the whole chain (input to ppm, then on to the model) is
tested at the gate. `scripts/m13_inventory.jl` lists what each segment
creates or changes on a reference run.

Symbols created or changed per segment (reduce_off, sets and parameters,
`scripts/m13_inventory.jl`, 31 Oct 2026; cloud pre-solve runs with the PyPI
GAMS 54.6.1):

| Segment | demo12 | OTCGEN | OTNYC |
| --- | ---: | ---: | ---: |
| input → init (init_ext) | 7 | 8 | 9 |
| init → prep (ppmain L1-248, preppm L1-217) | 86 | 97 | 98 |
| prep → prelv (preppm L218-253, ppmain L249-615) | 50 | 57 | 57 |
| prelv → ppm (ppmain L616-1357, ppm_ext) | 76 | 80 | 93 |

## Order (one change each)

| # | GAMS | Lines | Checked at |
| --- | --- | --- | --- |
| 0 | infrastructure: harness 0.3.0 checkpoints, `--only presolve`, `m13_inventory.jl`, demo12 checkpoint fixtures, `m13_probe.jl` | | |
| 1 | init_ext.dsc; init_ext.vda with equcrtp.vda (INIT_EXT) | 11-23; 52-156; 15-38 | init |
| 1b | crafted demo12 states for the init_ext.vda paths no core model reaches (OFF-ranges, peaking, storage, partial loads, UC_ACTBET, ...) | | init |
| 2 | ppmain.mod: declarations, control sets, storage sets, NCAP_PASTI spread | 1-137 | prep |
| 3 | ppmain.mod with filparam.gms (G_OFFTHD): years, periods, B/E/D/M, LEAD/LAG, EOHYEARS | 138-191 | prep |
| 4 | timslice.mod, pp_off.mod | 1-123; 1-23 | prep |
| 5 | ppmain.mod: PASTI migration, START/NOFF, RTP_OFF | 199-247 | prep |
| 6 | preppm.mod with prepxtra.mod, fillparm.gms, fillvint.gms, curex.gms, prepparm.gms (interpolation); prep_ext.vda with equcrtp.vda (PREP_EXT). May split in two. | 1-217; 1-82 | prep |
| 7 | preppm.mod with preshape.gms; ppmain.mod: horizon, topology, PG/SPG, commodity and process timeslice levels, RTPCS_VAR | 218-253; 249-460 | prelv |
| 8 | ppmain.mod: lifetimes, capacity transfer, capacity bounds, availability years, PRC_ACTFLO; pp_prelv.vda | 462-614; 1-124 | prelv |
| 9 | ppmain.mod with pp_qafs.mod, filshape.gms, filparam.gms: SHAPE/MULTI, defaults, capacity-only flows | 616-682 | ppm |
| 10 | ppmain.mod with pp_lvlfc.mod, pp_lvlbr.mod, pp_lvlpk.mod: commodity and availability attributes by timeslice | 683-799 | ppm |
| 11 | ppmain.mod with pp_chp.mod, pp_lvlff.mod, pp_lvlfs.mod, eqflomrk.mod: flow attributes, FLO_SHAR, FLO_MARK | 800-845 | ppm |
| 12 | ppmain.mod with pp_lvlif.mod: trade and marketplaces | 846-935 | ppm |
| 13 | ppmain.mod with pp_lvlbd.mod: balance types, IRE conversion, bounds, cumulative constraints | 936-1060 | ppm |
| 14 | ppmain.mod: storage | 1061-1101 | ppm |
| 15 | ppmain.mod with pp_lvlus.mod, prepxtra.mod UCINT: user constraints | 1102-1229 | ppm |
| 16 | ppmain.mod: blending (refused unless needed; any non-blending statements in the block translated) | 1230-1336 | ppm |
| 17 | pp_reduce.red, dynslite.vda, ppmain.mod end; cal_red.red | 1-188; 1-129; 1337-1357; 1-59 | ppm (as_run), layer 2 |
| 18 | ppm_ext.dsc; ppm_ext.vda with pp_actef.vda, resloadc.vda, equcrtp.vda (PPM_EXT) | 1-16; 1-169 | ppm |

## Parity (per change)

Layer 1 at 1e-9 at the change's checkpoint, starting from GAMS's state at
the previous checkpoint, on the core tier (TIMES_Demo demo12, TIMES-NZ
steady, OTCGEN, OTNYC, OTUS9r reference), reduce_off and as_run, and TIM-bau
on James's machine (results stay there). A change is compared on the
symbols it settles that nothing later in its segment changes (the M1.2 rule
for later files); scratch symbols (CNT, F, FIL, FIL2, MY_*, YK1, Z, ...) only
where the GAMS code reads them again. Branches no suite model reaches are
checked against GAMS itself on crafted demo12 states (scripts/gams_replay.jl).
Between them the core models reach the unusual branches: OTNYC the FLO_SHARE
auto-relaxation (pp_qafs.mod L66-89), OTUS9r the dynamic user constraints
(equcrtp.vda), TIMES-NZ the flow marks (eqflomrk.mod), OTCGEN and OTNYC the
plain objective (OBJ AUTO without OBLONG).

The checkpoint dumps of the public models can be made in the cloud workspace
with the PyPI GAMS (no solve: `make_reference.py --only presolve`); James's
workstation stays the reference of record (`run_references.ps1 -Checkpoints`).

## Gate

- Input dump to `ppm/` at 1e-9 on every core model, reduce_off and as_run
  (TIM-bau locally).
- In CI on demo12: input, preprocessing, coefficients and the model, with the
  matrix (layer 2) and the objective (layer 3), REDUCE off and on.
- Preprocessing timed against GAMS (docs/timings.md).

## Findings so far

- (1) init_ext.dsc, init_ext.vda with equcrtp.vda INIT_EXT (31 Oct 2026):
  the input -> init segment matches GAMS on every set and parameter at the
  init checkpoint (824-825 symbols, nothing excluded) on the five core
  models, reduce_off and as_run (GAMS 54.6.1 checkpoints), and on demo12 in
  CI; TIM-bau was probed locally (results stay on James's machine).
  `prepparm.gms` is not part of this segment: equcrtp.vda calls it in its
  PREP_EXT section (L55), so it moves to change 6. DSC: no core model has
  discrete or semi-continuous capacity data, so no init_ext.dsc statement
  applies and %DSC% becomes NO; such data is refused until crafted cases
  check L12-17 (`T--ORD(T)` on a subset, `OPTION` onto the parameter
  PRC_SEMI). `$IF DEFINED x` is read as "x has records in the input dump"
  (G1, G35): nothing compiled before init_ext.dsc assigns PRC_DSCNCAP,
  NCAP_DISC or RCAP_BLK, so only DD data can define them. The compile-time
  switches the segment sets (%DSC%, %POWERFLO%) go into `tm.switches`.
  Paths no core model reaches are listed in docs/gams-julia-map.md; they
  get crafted demo12 states run through init_ext.vda by GAMS in change 1b.
- (1b) (1 Nov 2026) Two crafted demo12 input states ("flags", "offrange",
  test/unit/init_ext_case.jl) run through init_ext.vda with equcrtp.vda by
  GAMS 54.6.1 match init_ext! on the 55 symbols the files write, nothing
  excluded (CI). GAMS confirms: MOD keeps the sign of its first argument
  (L124 keeps an 'N' bound of YEARVAL-1, and -1 at '0'); a bound above
  %EOTIME% is capped before L123 takes the lead; L117 removes an EPS
  NCAP_START, which L121 may then set again; the FLO_COST clean-up leaves
  UNCD7 with '' labels (G36). At the input checkpoint COM_GMAP holds only
  the user's commodity groups (the TIMES groups such as NRG come in
  preprocessing), which L65 reads. init_ext.dsc stays refused for discrete
  or semi-continuous capacity data (the DSC extension follows core and VDA,
  translation-guide.md, Decisions).
- (2) ppmain.mod L1-137 (1 Nov 2026): matches GAMS at the prep checkpoint
  on the symbols it settles (`ppmain_head_symbols`, 27 on every core model)
  on the five core models, reduce_off and as_run, and on demo12 in CI;
  TIM-bau was probed locally (results stay on James's machine). TIMES-NZ
  reaches the guessed primary group (L59-63) and four core models the
  STG/STK/STS storage defaults. Four crafted demo12 states ("storage",
  "stslim", "nopg", "pasty", test/unit/ppmain_head_case.jl) run through an
  unchanged copy of L1-137 by GAMS 54.6.1 match on the 30 symbols it writes
  (CI). GAMS confirms (G37): `NOT` ranks below `+`, so L61 leaves out ENV and
  FIN outputs; an NCAP_PASTY of 2.5 spreads at lags 1.5 and 0.5, rounded to
  2 and 1; an EPS past investment spreads as EPS. PASTYEAR is not settled in
  L1-137 (L160, L201 change it) and is checked with change 3. L35 writes
  only the QA log (open items).
- (3) ppmain.mod L138-191 with filparam.gms (G_OFFTHD) (1 Nov 2026):
  matches GAMS at the prep checkpoint on the symbols it settles
  (`ppmain_years_symbols`, 20 on every core model: no core model has
  INT_DEFAULT('PASTI'), so B, E, D, M, PASTYEAR and PASTMILE are checked
  here; with it, L200-207 change them and change 5 checks them) on the five
  core models, reduce_off and as_run, and on demo12 in CI; TIM-bau was
  probed locally (results stay on James's machine). demo12 runs with OBJ
  MOD, so it takes the alternative objective's periods (L150-155); the
  other four drop ALTOBJ to 0; demo12, TIMES-NZ and OTUS9r pass the OBLONG
  check. No core model has G_OFFTHD data. Eight crafted demo12 states
  ("altobj", "altobj_mod", "offthd5", "offthd1", "offthd2", "offthd14",
  "offthdneg", "offthdeps", test/unit/ppmain_years_case.jl) run through an
  unchanged copy of L1-191 by GAMS 54.6.1 match on the 20 symbols L138-191
  writes (CI). GAMS confirms (G38): `$` binds before `-` at L154; leads and
  lags on T move along the milestones; `ROUND(EPS)` is 0, so an EPS option
  at G_OFFTHD('0') counts as none (my first version extrapolated both ways
  there; fixed). The OBLONG ABORT (L159) is a Julia error, tested in Julia
  only.
- (4) timslice.mod with pp_off.mod (1 Nov 2026): matches GAMS at the prep
  checkpoint on the 24 symbols it writes (`timslice_symbols`; ppmain.mod
  L199-248, preppm.mod L1-217 with its includes, prep_ext.vda, resloadc.vda
  and powerflo.vda only read them) on the five core models, reduce_off and
  as_run, and on demo12 in CI; TIM-bau was probed locally (results stay on
  James's machine). The core models reach three levels, four (TIMES-NZ:
  WEEKLY), external regions (L18, L43) and season fractions filled from
  their children (L45-46); none has TS_OFF, DYNTS, RP_UPR/RP_UPT, zero
  fractions, fractions to normalise or TS_CYCLE data. Six crafted demo12
  states ("norm", "zerofrac", "tsoff_first", "tsoff_later", "dynts", "uc",
  test/unit/timslice_case.jl) run through an unchanged copy of ppmain.mod
  L1-196 by GAMS 54.6.1 match on the 24 symbols (CI); the replay needs
  `$onMulti` (`gams_replay(...; onmulti=true)`), as L34 declares TS_OFF
  again. GAMS confirms (G39): a LOOP's `$`-condition is read element by
  element (L63: RLUP holds the next coarser level only); `SET TS_OFF //;`
  under `$ONMULTI` keeps the data; RS_UP and JS take the G26 pairing (child
  first, parent last). The `uc` case does not make L118's MOD argument
  negative; MOD's sign rule is from (1b). The ABORTs (L24, L74) are Julia
  errors, tested in Julia only. pp_off.mod is split into `pp_off_fil` and
  `pp_off_periods` for its four later callers.

- (0) The pre-solve run's dumps lack the report-only symbols (the reports are
  skipped at maindrv.mod L114), so the checkpoint `ppm/` has fewer symbols
  than the solve run's; on demo12 the 824 sets and parameters both hold are
  equal at 1e-9 (GAMS 54.6.1, cloud, against the licensed GAMS 52.1.0
  reference of 21 Oct).
- (0) `execute_unload` without a symbol list writes every symbol of the
  compiled program, so the input dump also holds symbols declared later in
  the source, with their compile-time data.

## Open items

- QA log: `pp_qaput` calls write QA_CHECK.LOG and set PUTOUT, PUTGRP and
  ERRLEV (first in ppmain.mod L35, `$IF WARNINGS`, which depends on GAMS
  compile warnings that no dump records; then timslice.mod L81-82, a
  warning when year fractions are normalised, and L101-104, a FATAL line,
  ERRLEV 99, for a timeslice with several parents, which pp_qack.mod L378
  acts on). TIMES.jl does not write the log yet; decide where it is
  translated, and whether ERRLEV aborts are checked, before the M1.3 gate.
  Until then the scalars are not compared.
