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
| 6a | preppm.mod with prepxtra.mod SAVE, curex.gms (refused), prepret.dsc PREP, fillvint.gms, filparam.gms, prepparm.gms, fillparm.gms (interpolation) | 1-212 | prep |
| 6b | preppm.mod L213-217: prep_ext.vda with equcrtp.vda (PREP_EXT); the segment's all-symbols check; MY_SUM kept by timslice.mod | 213-217; 1-83; 40-62 | prep |
| 7a | preppm.mod with preshape.gms; ppmain.mod: timestep control, horizon, commodity groups and RC, PG/SPG | 218-252; 249-328 | prelv |
| 7b | ppmain.mod: commodity and process timeslice levels (pp_off.mod for COM_OFF), peaking, RPCS_VAR | 329-460 | prelv |
| 8a | ppmain.mod: lifetimes, refits, capacity transfer, capacity bounds, availability years (pp_off.mod for PRC_AOFF, PRC_FOFF), PRC_ACTFLO | 461-611 | prelv |
| 8b | pp_prelv.vda with pp_lvlfc.mod (FLO_FR); the segment's all-symbols check | 1-125 | prelv |
| 9 | ppmain.mod with pp_qafs.mod, filshape.gms, filparam.gms: SHAPE/MULTI, defaults, capacity-only flows | 616-682 | ppm |
| 10 | ppmain.mod with pp_lvlfc.mod, pp_lvlbr.mod, pp_lvlpk.mod: commodity and availability attributes by timeslice | 683-797 | ppm |
| 11a | ppmain.mod with pp_lvlfc.mod (the flow attributes), pp_chp.mod: flow attributes by timeslice, the FLO_PKCOI default, CHP | 800-821; 1-71 | ppm |
| 11b | ppmain.mod with pp_lvlff.mod, pp_lvlfs.mod, pp_lvlbr.mod (FLO_SHAR), eqflomrk.mod: FLO_FUNC, FLO_SUM, FLO_SHAR, FLO_MARK | 823-845 | ppm |
| 12 | ppmain.mod with pp_lvlif.mod: trade and marketplaces | 846-935 | ppm |
| 13a | ppmain.mod with pp_lvlbd.mod: balance types, IRE conversion, bounds | 936-1001 | ppm |
| 13b | ppmain.mod: cumulative constraints, VAR_COMxxx on the balance RHS | 1003-1056 | ppm |
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
- (5) ppmain.mod L199-247 (2 Nov 2026): matches GAMS at the prep checkpoint
  on the symbols it settles (`ppmain_rtp_symbols`: PRC_NOFF, RTP_OFF, VNT,
  COEF_RTP and RTP on every core model, RVP on OTCGEN and OTNYC, which have no
  PRC_VINT; fillvint.gms L18 and preppm.mod L61 add vintage years to RVP) on
  the five core models, reduce_off and as_run, and on demo12 in CI; TIM-bau
  was probed locally (results stay on James's machine). PRC_YMAX is not
  compared at prep (prep_ext.vda L48 clears it). Every core model has
  NCAP_START (L215-225); TIMES-NZ, OTNYC and OTUS9r have delayed processes
  with past investment (L227-231); none has INT_DEFAULT('PASTI'), user
  PRC_NOFF ranges or G_OFFTHD data. Three crafted demo12 states ("pasti",
  "noff", "noff_offthd", test/unit/ppmain_rtp_case.jl) run through an
  unchanged copy of ppmain.mod L1-247 by GAMS 54.6.1 match on the 18 symbols
  the block writes, PRC_YMAX, TRACKP, UNCD1 and PASTSUM included (CI); the
  replay needs %RL% (setglobs.gms L317) for the QA line at L230. GAMS
  confirms the known rules: `3+0.1+1-1` at L202 keeps its rounding
  (3.0999999999999996), a non-integer NCAP_START leads by the rounded amount
  (G29: 2012.4 gives the range BOH-2011, 2012.6 BOH-2012), SMAX over nothing
  is -INF (G31) and stays in PRC_YMAX. A delayed process with past investment
  keeps the RTP_OFF of its delayed periods (L224) while L231 puts them back
  in RTP. No new discrepancy entry.
- (6a) preppm.mod L1-212 (2 Nov 2026): matches GAMS at the prep checkpoint on
  the 109 symbols it settles (`preppm_symbols`: every parameter its macro
  calls interpolate but NCAP_TLIFE and NCAP_ILED, which prep_ext.vda L66-67
  changes; the year sets; the merged OBJ_COMNT/OBJ_COMPD and UC_COM; the
  flags and defaults; the prepret.dsc and fillvint.gms sets; RTP and RVP) on
  the five core models, reduce_off and as_run, and on demo12 in CI; TIM-bau
  was probed locally (results stay on James's machine). The core models reach
  options -1, 1, 2, 3, 5 and 15, the bounds' default 10 (years inside a
  period moved to the milestone), cost options (NCAP_COST, NCAP_FOM,
  ACT_COST), FLO_MARK (TIMES-NZ), PRC_VINT (demo12, TIMES-NZ, OTUS9r), the
  COM and UC merges, and prepret.dsc with RCAP_BND and refits (OTUS9r). %PGPRIM%
  is 'ACT' by default, so %RETIRE% is YES in every run (initmty.mod L454).
  Four crafted demo12 states ("fill_opts", "prep_opts", "costs_uc_ret",
  "nointerp", test/unit/preppm_case.jl), run through unchanged copies of
  ppmain.mod L1-247 and preppm.mod L1-212 by GAMS 54.6.1, match on the 125
  symbols the block writes, the macros' scratch (UNCD7, MY_ARRAY, MY_FIL2 and
  the scalars) included (CI); under G_NOINTERP no macro runs, so Z and MY_F
  keep what ppmain.mod L215 and timslice.mod L71-77 left, which changes 4-5 do
  not keep, and are not compared in that case. GAMS confirmed that an empty
  data statement makes a symbol DEFINED (G40: with PRC_REFIT data,
  prepret.dsc runs on without retirement bounds) and that CARD of a string is
  its length (G41); the GAMS replay now declares such symbols without data
  (`bare`). Refused: currency conversion (curex.gms, no suite model has
  it), %INTEXT_ONLY% and %PREP_ANS% YES, %RETIRE% other than YES. On OTUS9r
  the step takes about 105 s.
- (6b) preppm.mod L213-217 (main_ext.mod prep_ext: prep_ext.dsc exits, then
  prep_ext.vda with equcrtp.vda PREP_EXT) ends the init -> prep segment: from
  GAMS's init dump through every translated step, TIMES.jl matches the prep
  dump on every set and parameter (821 on demo12, TIMES-NZ, OTCGEN and
  OTNYC, 822 on OTUS9r; PUTOUT, PUTGRP and ERRLEV left out, open items) on
  the five core models, reduce_off and as_run, and on demo12 in CI; MY_SUM
  is now kept by `timslice!`. The core models reach the ACT_EFF groups
  (RPG_1ACE on OTUS9r), the VDA fill-ins (NCAP_AFC, VDA_EMCB, VDA_FLOP,
  FLO_EMIS), the PRC_RESID run-down and RTP_CPTYR (every model; PRC_RESID
  options on OTUS9r), COM_LIM 'FX' (TIMES-NZ, OTCGEN, OTUS9r) and the
  dynamic process bounds (OTUS9r). Three crafted demo12 states ("vda_resid",
  "uc_bounds", "dynuc", test/unit/prep_ext_case.jl), run through
  ppmain.mod L1-247, preppm.mod L1-212 and prep_ext.vda by GAMS 54.6.1,
  match on 159 symbols each (CI): PRC_RESID options 5 and 15, a year as the
  '0' value, the G_TLIFE run-down, NCAP_AFAC/NCAP_AFCS, ACT_FLO, the
  unit-commitment parameters, UC_FLOBET, COM_CSTBAL, FLO_ASHAR, RPC_CAPFLO,
  cost-neutral ILEDs (NCAP_BND 'N') and PRC_DYNUC with every side and
  option. GAMS confirmed how `SUM(COM_TYPE(CG(R)),1)` counts (G42, L71).
  Refused: STAGES, POWERFLO, WAVER YES, %VINTOPT% 1, GR_VARGEN data, the
  ECB, MACRO, ETL, CLI, ABS and MCA extensions, and UC_ACTBET data (whether
  UC_FLOBET is DEFINED then depends on the DD files). On OTUS9r the step
  takes about 3 min, OTCGEN 80 s.
- (7a) preppm.mod L218-252 (the twelve preshape.gms calls, PRC_MARK from
  FLO_MARK, DATAYEAR) and ppmain.mod L249-328 (RT_PP, DUR_MAX, EOHYEARS,
  EACHYEAR, PERIODYR, the commodity groups and RC, NRG_GMAP, PRC_CG,
  RPC_CAPFLO, the primary and shadow primary groups) match the prelv dump on
  the 39 symbols they settle (`preppm_shape_symbols`,
  `ppmain_topo_symbols`; DEM, PRC_CG, RPC_PG, UNCD7, RXX and the scratch Z,
  F, TRACKP are changed again later in the segment) on the five core models,
  reduce_off and as_run, and on demo12 in CI. No core model has data for
  the preshape parameters, NCAP_ICOM, NCAP_OCOM or NCAP_COM, a commodity
  group named like a commodity, a user PRC_SPG or a trade process with
  untraded PG commodities; FLO_MARK into PRC_MARK is TIMES-NZ's. Two crafted
  demo12 states ("shapes", "topology", test/unit/ppmain_topo_case.jl), run
  through unchanged copies of ppmain.mod L1-247 and L249-328, preppm.mod
  L1-212 and L218-252 and prep_ext.vda by GAMS 54.6.1, match on 192 symbols
  each (CI): every preshape.gms option (the default intra-period move, 1-5,
  2 without data, 11, 15, 1012, -1), rounding and EPS in the step, the
  group-integrity removal (L272-277), L301, a user and a material shadow
  group, and the capacity-related flows. GAMS confirmed that MOD keeps the
  sign of its first argument (G43). Refused: %VINTOPT% 1 (L245-251). L253
  (`SET SUBT(T) / SET.T /`) is a compile-time data statement, in every dump.
- (7b) ppmain.mod L329-460 (the commodity and process timeslice levels:
  levels a region lacks, COM_TS/COM_TSL, RCS, RCS_COMTS, COM_OFF through
  pp_off.mod, RTC, RTCS_VARC, COM_PEAK/COM_PKTS, PRC_TS/PRC_TSL, storage
  (RP_SGS, PRC_MAP, RP_STG), the shadow levels (RPS_S1, RPS_S2, PRC_SGL),
  RPS_PRCTS, RP_PGFLO, RPC_STG, PRC_NSTTS, RPCS_VAR) matches the prelv dump
  on the 24 symbols it settles (`ppmain_tslvl_symbols`; COM_BNDPRD,
  TS_ARRAY, RXX, PRC_ACT, TRACKP, TRACKPC, F and Z are changed again later in
  the segment) on the five core models, reduce_off and as_run, and on demo12
  in CI. The core models reach WEEKLY levels (TIMES-NZ), peak timeslices
  given (OTCGEN, OTNYC, OTUS9r) and not (demo12), storage (TIMES-NZ, OTCGEN,
  OTNYC, OTUS9r) and SGS storage (OTUS9r). Two crafted demo12 states
  ("levels", "offpeak", test/unit/ppmain_tslvl_case.jl), run through
  unchanged copies of ppmain.mod L1-247 and L249-460, preppm.mod L1-212 and
  L218-252 and prep_ext.vda by GAMS 54.6.1, match on 217 symbols each (CI):
  a level moved up and one kept (the count rule of L336-337), user COM_TS
  and PRC_TS (the first timeslice sets the level, G30; timeslices removed or
  left out, RCS), COM_OFF ranges, COM_PKTS moved up and down, a group
  COM_PEAK, a peak commodity outside RC, and night storage at DAYNITE and
  ANNUAL with SGS and STS. GAMS confirmed how L380's nested loop domain
  matches labels (G44). On OTUS9r the step takes about 50-60 s.
- (8a) ppmain.mod L461-611 (lifetimes and lead times, refits, COEF_RPTI,
  VNT and RTP_CPTYR, capacity bounds, the periods without new capacity,
  RTP_VARA with PRC_AOFF, RTPC, RTPCS_OUT with PRC_FOFF, PRC_SIMV, RPC_PG,
  RP_STD, RPC_ACT, CHP, PRC_CAPACT, PRC_ACTFLO, RP_PGACT) matches the prelv
  dump on the 30 symbols it settles (`ppmain_life_symbols`; NCAP_TLIFE and
  PRC_ACTFLO are changed again by pp_prelv.vda, RVP only with TS_OFF data)
  on the five core models, reduce_off and as_run, and on demo12 in CI. The
  core models reach %CTST% **0 (demo12, TIMES-NZ, OTUS9r: G_ILEDNO -1) and
  empty (OTCGEN, OTNYC, with lead times), ALTOBJ 1 (demo12) and 0,
  lifetimes beyond AGE (TIMES-NZ), refits with PRC_RCAP (OTUS9r), capacity
  bounds (TIMES-NZ, OTCGEN, OTNYC, OTUS9r), STK (OTCGEN, OTNYC) and CHP
  (OTCGEN). Three crafted demo12 states ("life", "altobj", "validate",
  test/unit/ppmain_life_case.jl), run through unchanged copies of ppmain.mod
  L1-247 and L249-611, preppm.mod L1-212 and L218-252 and prep_ext.vda by
  GAMS 54.6.1, match on 233 symbols each (CI): short and EPS lifetimes,
  rounded and dropped lead times, past investment on a milestone (PHYR),
  refit options, every capacity-bound path, NCAP_BND FX EPS, PRC_AOFF,
  PRC_FOFF, a PG commodity flagged non-interpolated, OBJ LIN (the relaxed
  capacity transfer), %VALIDATE% and PRC_SIMV. The replay now sets %OBLONG%
  (OBJ MOD) as initmty.mod L427 does, so ppmain.mod L159 is checked there
  too. IFQ is 1 unless a region is named like a commodity type (prep_ext.vda
  L71), so the `IFQ<10` branch of L528 is the only one data can reach. On
  OTUS9r the step takes about 4 min, OTCGEN 100 s (not profiled).
- (8b) pp_prelv.vda (ppmain.mod L615, with pp_lvlfc.mod for FLO_FR) ends
  the prep -> prelv segment: from GAMS's prep dump through every translated
  step, TIMES.jl matches the prelv dump on every set and parameter (821;
  PUTOUT, PUTGRP and ERRLEV left out, open items) on the five core models,
  reduce_off and as_run, and on demo12 in CI. The core models reach
  NCAP_TLIFE for RESID (every model), the ACT_EFF filter of VDA_FLOP with
  KEEP_FLOF, ACT_FLO, RPC_AFLO and RP_XRED (OTUS9r, OTNYC), the VDA_FLOP
  groups, FLO_EMIS into FLO_SUM, IRE_FLOSUM (TIMES-NZ, OTCGEN) and FLO_EFF
  (OTCGEN's CHP), and the dummy imports out of TOP_IRE (every model). Two
  crafted demo12 states ("flofr", "groups", test/unit/pp_prelv_case.jl), run
  through unchanged copies of ppmain.mod L1-247 and L249-614, preppm.mod
  L1-212 and L218-252, prep_ext.vda and pp_prelv.vda by GAMS 54.6.1, match on
  246 symbols each (CI): FLO_FR copied, aggregated and inherited
  (pp_lvlfc.mod) with its 'N' fractions and RVPCSL, NCAP_CHPR 'N', the 'N'
  defaults of COM_BNDNET and COM_BNDPRD, IRE_BND (NE), FLO_SHAR of a storage
  process, %SHELL% ANSWER and the VDA_FLOP group paths. GAMS showed that
  `OPTION a < b` compares domains as declared, not through aliases (G45,
  refining G26). Refused: TS_OFF data (dynslite.vda, no core model has any)
  and %POWERFLO% YES. On OTCGEN the step takes about 2-2.5 min, OTUS9r
  3-3.5 min (not profiled). The every-symbol check found one slip in 8a's
  code, fixed here: F keeps an EPS (ppmain.mod L526-531).
- (9) ppmain.mod L616-682 starts the prelv -> ppm segment in two probe
  steps: pp_qafs (pp_qafs.mod, the FLO_SHAR checks) and ppmain_dflt (SHAPE
  and MULTI with filshape.gms and filparam.gms, the defaults, the
  capacity-only flows). At the ppm checkpoint they are compared on the 17-19
  symbols nothing later changes, PASS on the five core models, reduce_off
  and as_run, and on demo12 in CI. FLO_SHAR (pp_chp.mod, pp_lvlbr.mod),
  NCAP_CHPR and NCAP_BPME (pp_chp.mod, on CHP models), RTP_GRP, UC_CAPFLO,
  RPC_NOFLO, RPCS_VAR and the scratch change again before ppm, so a new
  replay check (scripts/m13_replay.jl) runs GAMS on ppmain.mod L616-682 from
  each core model's own prelv dump and compares every symbol the lines
  write (34) at L682 (PASS on the five core models, both variants), and
  lists the checks GAMS's QA log shows. The core models reach the sum of
  fixed shares (TIMES-NZ 28 groups, OTUS9r 24), the FX+UP auto-relaxation
  (OTNYC 50, OTUS9r 864), the STG_EFF default (OTCGEN, OTNYC, OTUS9r) and
  the CHP default (OTCGEN); none reaches FX with LO/UP, the FX+LO excess or
  a share outside its group, and none has SHAPE, MULTI, COM_ELASTX,
  NCAP_OCOM, NCAP_ICOM or RPC_NOFLO data. Three crafted demo12 states ("qafs", "dflt",
  "notgrp", test/unit/ppmain_dflt_case.jl) start from the prelv dump, so
  GAMS 54.6.1 runs only ppmain.mod L616-682 on them; they match on 34
  symbols each (CI). GAMS showed that a scalar `$`-condition in a loop
  domain is evaluated per member, so pp_qafs drops only the first share
  above the limit, and that `$` binds before NOT (G46); and that a `$IF`
  with nothing after its condition applies to the next line, as %SHARELAX%
  NO needs (G47). The steps take under a minute on OTUS9r.
- (10) ppmain.mod L683-797 is one probe step, ppmain_tsattr: the commodity
  attributes levelled to COM_TS (pp_lvlfc.mod, `lvlfc!`), COM_IE and
  COM_FR defaulted, COM_FR summed and normalised, RS_FR and RTCS_FR, the
  elastic demand steps, NCAP_AF levelled to PRC_TS (pp_lvlbr.mod,
  `lvlbr!`) and defaulted with PRC_TS, RPCS_VAR and RTPCS_OUT, and
  pp_lvlpk.mod. At the ppm checkpoint it is compared on the 15-18 symbols
  nothing later changes, among them RPCS_VAR, which change 9 left to the
  replay (NCAP_AF and PRC_TS without RP_STS, NCAP_PKCNT without CHP,
  RPC_PKC with %REDUCE% NO and no STG_SIFT): PASS on the five core models,
  reduce_off and as_run, and on demo12 in CI. DEM (L945), FLO_PKCOI (L808,
  L817), RTPCS_OUT (L1062, cleared at L1350) and RPC_PKF (pp_reduce.red
  L185, which follows its REDDONE label and so runs without REDUCE too)
  change again before ppm, so the replay check now runs ppmain.mod L616-797
  and compares every symbol the lines write (65) at L797: PASS on the five
  core models, both variants. GAMS's QA log shows the COM_FR normalisation
  on demo12 (2 commodities) and TIMES-NZ (16); NCAP_AFS (TIMES-NZ),
  OBJ_COMNT (TIMES-NZ, OTUS9r) and storage processes (all but demo12) are
  reached; no core model has an NCAP_AF bound conflict, nor COM_ELAST,
  COM_BPRICE, COM_BQTY, COM_PKFLX, OBJ_COMPD, PRC_PKAF or PRC_PKNO data.
  Three crafted demo12 states ("com", "af", "pk",
  test/unit/ppmain_tsattr_case.jl) cover those paths, 65 symbols each at
  L797 (CI). The replay showed two things the source does not make plain:
  the `IF(Z, ...)` that pp_lvlbr.mod L27 opens closes only at the end of
  L31, so a value below a target timeslice is neither inherited down nor
  levelled from (the indentation suggests otherwise; only the scratch Z
  showed it, as no such value has targets below it); and L729 divides for
  every timeslice, so an ANNUAL COM_FR of 0 stops GAMS even where COM_FR
  has no record (G48): a commodity with COM_FR needs it in every milestone.
  The step takes about 3 minutes on OTUS9r (2.1 million GAMS records
  compared; the gams_sort! of the large symbols dominates, not profiled).
- (11a) ppmain.mod L800-821 is the probe step ppmain_flo: the eight
  pp_lvlfc.mod calls for the flow attributes (FLO_COST, FLO_DELIV, FLO_SUB,
  FLO_TAX with %11 N, FLO_PKCOI, FLO_BDLVL twice, ACT_FLO with %11 0),
  for which `lvlfc!` became the general `pp_lvlfc!` (all its arguments
  but %6 S2; change 10's calls re-checked), the FLO_PKCOI default of 1, and
  pp_chp.mod. Change 11 is split in two (11a, 11b) like 6, 7 and 8. At the
  ppm checkpoint it is compared on the 13-14 symbols nothing later changes
  (NCAP_PKCNT, NCAP_CHPR and NCAP_BPME, which changes 9 and 10 left to the
  replay when CHP has members, are now among them): PASS on the five core
  models, reduce_off and as_run, and on demo12 in CI. The replay check now
  runs ppmain.mod L616-821 and compares 82 symbols at L821: PASS on the five
  core models, both variants. The core models reach FLO_DELIV (TIMES-NZ,
  OTUS9r), ACT_FLO (OTUS9r), the FLO_PKCOI default (all) and CHP with FX
  ratios and no NCAP_CDME (OTCGEN, 8 processes). Three crafted demo12 states
  ("flo", "chp", "chpnrg", test/unit/ppmain_flo_case.jl) cover the rest of
  pp_lvlfc.mod's arguments (the year-'0' flag of %11 N and its deletions, a
  year outside DATAYEAR, the group and commodity calls of FLO_BDLVL) and of
  pp_chp.mod (NCAP_CDME and NCAP_BPME, slopes below and above 1,
  back-pressure units through COM_LIM 'N', FX with LO, FLO_EFF, a
  one-commodity primary group, the share over NRG, NCAP_PKCNT), 82 symbols
  each at L821 (CI). pp_chp.mod L23 replaces PRC_ACT and L71 clears it,
  so PRC_ACT is empty after L821 until pp_reduce.red L10 sets it again.
  The step takes about 4 minutes on OTUS9r and 3 on OTCGEN (copying and
  sorting FLO_SUM and FLO_SHAR, not profiled).
- (11b) ppmain.mod L823-843 is the probe step ppmain_flofs: pp_lvlff.mod
  and pp_lvlfs.mod (FLO_FUNC and FLO_SUM levelled), FLO_SUM and IRE_FLOSUM
  from PRC_ACTFLO for the processes in RPC_ACT, pp_lvlbr.mod for FLO_SHAR
  (its general `lvlbr!` with %2 ',C,CG', %5 1, %6 0, %7 C,) and
  eqflomrk.mod with RPC_NOFLO. At the ppm checkpoint it is compared on the
  8-10 symbols nothing later changes (FLO_SUM only without VDA_EMCB,
  ppm_ext.vda L20; IRE_FLOSUM only without records at %PGPRIM%, ppmain.mod
  L924-926): PASS on the five core models, reduce_off and as_run, and on
  demo12 in CI. The replay check now runs ppmain.mod L616-843 and compares
  101 symbols at L843: PASS on the five core models, both variants. The
  core models reach FLO_FUNC and the FLO_SUM levelling (OTUS9r), the
  PRC_ACTFLO sums (all), FLO_SHAR below and above the flow timeslices (all)
  and PRC_MARK from FLO_MARK (TIMES-NZ). Two crafted demo12 states ("ffs",
  "mark", test/unit/ppmain_flofs_case.jl) cover the rest, 101 symbols each
  at L843 (CI). The replay confirmed that eqflomrk.mod L27's `T--ORD(T)`
  is the last milestone (G49). pp_lvlfs.mod L42 runs after L41 clears
  FSCKS and so does nothing, in GAMS as here. The step is slow on the large
  models: about 11-12 minutes on OTCGEN and 7.5 on OTUS9r (the FLO_SHAR
  and FLO_SUM levelling; to be profiled). Profiled: the time went to
  gams_sort! in the two gput! of FLO_SUM, which ranked the labels at every
  comparison; ranked once per key it gives the same order about 140 times
  faster (PR #35, separate).
- (12) ppmain.mod L846-933 is the probe step ppmain_ire: IRE_PRICE and
  IRE_FLOSUM levelled (pp_lvlfc.mod), IRE_FLO levelled (pp_lvlif.mod), the
  trade indicators, the marketplaces and their import commodities, links
  and IRE_FLO, RPC_EQIRE and RPC_MARKET IMP, RTPC of shut-down periods,
  RP_AIRE, IRE_FLOSUM of the activity moved to the PG commodities and the
  IRE_FLO defaults. At the ppm checkpoint it is compared on the 11 symbols
  nothing later changes: PASS on the five core models, reduce_off and
  as_run, and on demo12 in CI. The replay check now runs ppmain.mod L616-933
  and compares 112 symbols at L933: PASS on the five core models, both
  variants. Two crafted demo12 states ("ire", "dist",
  test/unit/ppmain_ire_case.jl) make REG1 a marketplace (two import
  commodities in REG2) and, in "dist", a distribution process, and level
  the trade attributes, 112 symbols each at L933 (CI). The replay needs
  %PGPRIM% as initmty.mod L138 sets it ("'ACT'", quoted, which COM holds as
  a member, L141), now set in scripts/ppmain_replay.jl.
- (13a) ppmain.mod L936-1001 is the probe step ppmain_bnd: the commodity
  subsets and COM_LIM defaults, the trade timeslice and commodity
  conversions (IRE_TSCVT; IRE_CCVT, its reverse from `OPTION RC_RC <
  IRE_CCVT`, which swaps the region and commodity pairs, G26), the five
  pp_lvlbd.mod calls and FLO_BND and ACT_BND from FLO_BDLVL; TIMES-MACRO and
  TIMES-MICRO (L962-963) refused. Change 13 is split in two (13a, 13b). At
  the ppm checkpoint it is compared on the 16-17 symbols nothing later
  changes (DEM, which change 10 left to the replay, among them; ACT_BND
  only with %REDUCE% NO): PASS on the five core models, reduce_off and
  as_run, and on demo12 in CI. The replay check now runs ppmain.mod
  L616-1001 (under $onMulti, as pp_lvlbd.mod declares BDVAL and TS_BD at
  each of its five inclusions) and compares 126 symbols at L1001: PASS on
  the five core models, both variants. One crafted demo12 state ("bnd",
  test/unit/ppmain_bnd_case.jl) covers the aggregation of pp_lvlbd.mod
  (sums, FX where LO and UP meet, a value at the target and below, an UP
  not covering the target, negative bounds), the rate bounds and the
  reverse conversion, 126 symbols at L1001 (CI). With the faster
  gams_sort! (PR #35) the replayed chain ppmain.mod L616-1001 takes 32 s in
  TIMES.jl on OTUS9r, GAMS 60 s (it took 17 minutes before).
- (13b) ppmain.mod L1003-1056 is the probe step ppmain_cum: the
  cumulative bounds moved from BOH and EOH to the first and last years
  (`BOHYEAR+BEOH(BOHYEAR)` leads along BOHYEAR: BOH is 1960, EOH 2200 in
  the suite), UC_CUMACT and ACT_CUM as flows of %PGPRIM%, RPC_CUMFLO and
  RC_CUMCOM, and the commodities on the RHS of the balance (RC_AGP,
  RTC_NET, RTC_PRD, the COM_CSTNET and COM_CSTPRD flags at year '0' and
  the last timeslice). At the ppm checkpoint it is compared on the 15
  symbols nothing later changes (RHS_COMBAL and RHS_COMPRD are changed
  again at L1067 and L1209-1226): PASS on the five core models, reduce_off
  and as_run, and on demo12 in CI. The replay check now runs ppmain.mod
  L616-1056 and compares 140 symbols at L1056: PASS on the five core
  models, both variants. The core models reach ACT_CUM up to EOH (demo12)
  and COM_AGG; two crafted demo12 states ("cum", "lin",
  test/unit/ppmain_cum_case.jl) cover the other cumulative bounds, the cost
  flags and the bound checks of L1051 and L1055 (CI).

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
  acts on; ppmain.mod L213 resets PUTGRP and L229-230 warn when a delayed
  process has past investment). TIMES.jl does not write the log yet; decide where it is
  translated, and whether ERRLEV aborts are checked, before the M1.3 gate.
  Until then the scalars are not compared.
- Scratch scalars of changes 2-5: ppmain_rtp! and timslice! do not keep Z
  and MY_F (ppmain.mod L215, timslice.mod L67-78). Later loops overwrite
  them in every suite model; only a run with G_NOINTERP and neither a
  PRC_RESID '0' record nor an NCAP_BND 'N' would show the difference. MY_SUM, which nothing overwrites,
  is kept since 6b.
