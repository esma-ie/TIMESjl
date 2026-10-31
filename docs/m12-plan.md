# M1.2 coefficients: plan (21 Oct 2026)

Source: TIMES v4.9.7, etsap-TIMES/TIMES_model @ d9a6a25. Translate one file per
change, in coefmain.mod order; GAMS names kept; every function cites its
lines.

## Scope: from the ppm dump to the coef dump

The harness dumps `ppm/` right after ppmain and the extensions' ppm_ext
(maindrv.mod L56-58) and `coef/` right after coefmain and the extensions'
coef_ext (L72-73). M1.2 is everything in between:

- maindrv.mod L62-70: the DEBUG dump (no effect), `%SW_NOTAGS%` (compile-time
  macros, setglobs.gms L348: `%SOW%`, `%SWT%`, ... empty without STAGES) and
  `DISCSHIFT 0.5` with MID_YEAR.
- coefmain.mod L11-29 and its includes.
- coef_ext of the active extensions: VDA (coef_ext.vda); DSC has no coef_ext;
  ETL, ABS and CLI are outside Phase 1.

Symbols the stage creates or changes on demo12 (ppm against coef dump): COEF_AF, COEF_CPT, COEF_PTRAN, COEF_PVT,
OBJ_DISC, OBJ_IPRIC, OBJ_LINT, OBJ_PVT, OBJ_RFR, OB_ACT, OB_FOM, OB_ICOST,
OPYEAR, PERDINV, RB, R_DF, SOW, SW_T, TPULSE, TPULSEYR, TS_ANN, VDA_DISC, Y,
YK, Y_EOH, G_DRATE, G_RCUR; changed: ACT_EFF, RPCC_FFUNC, NCAP_PASTI and
RCS_COMBAL. Scratch symbols (CNT, F, FIL, FIL2, MY_*, YK1, Z, ...)
are not compared.

## Order (one change each)

| # | GAMS | Lines | Main outputs |
| --- | --- | --- | --- |
| 0 | infrastructure | | writable GAMS state seeded from `ppm/`; layer-1 check of a symbol list against `coef/`; ppm/coef fixtures |
| 1 | coefmain.mod L11, coef_cpt.mod, pp_shapr.mod | 11; 13-63; 15-46 | SOW, SW_T, COEF_CPT, COEF_AF; per-year B/E/M/D; NCAP_AF, NCAP_AFS |
| 2 | coef_nio.mod | 13-71 | COEF_ICOM, COEF_OCOM, COEF_RCOM, NCAP_OCOM, NCAP_CLAG, NCAP_CLED |
| 3 | coef_ptr.mod | 9-54 | COEF_PTRAN, ACT_FLO, RPCC_FFUNC, PRC_CG |
| 4 | coef_obj.mod with filparam.gms, fillcost.gms | 1-205 | discounting (G_DRATE, OBJ_DISC, G_RCUR, OBJ_PVT, COEF_PVT, OBJ_RFR), the OB_* cost caches and OBJ_COMNT/OBJ_COMPD/OBJ_IPRIC, Y, YK, Y_EOH, TS_ANN |
| 5 | coef_alt.lin (VARCOST LIN) | 1-161 | OBJ_LINT and the linear-cost variants; TPULSE, TPULSEYR, PERDINV, R_DF, RB; COEF_CPT under %CTST% |
| 6 | coef_shp.mod | 1-97 | shapes of COEF_PTRAN and COEF_CPT (FLO_FUNCX, NCAP_CPX), OPYEAR |
| 7 | coef_ext.vda with fillwave.gms, eqlducs.vda, eqashar.vda, powerflo.vda | 1-83 | VDA_DISC, ACT_EFF, COEF_PTRAN (RP_CGC), RPCC_FFUNC, PRC_RESID/NCAP_PASTI/COEF_CPT, COEF_AFUPS, ACT_CSTUP, COEF_ILED |

## Parity (per change)

Layer 1 at 1e-9 against the `coef/` dumps of every reference run of the
public suite models (demo12 in CI, and the public suite references (TIMES-NZ x2, OTUS9r x2; 30 Oct 2026)), the crafted demo12 states, and
TIM locally (its results stay on James's machine). Until 27 Oct 2026 the
changes were also checked on models without an open licence; those checks
are not published (`docs/test-models.md`). A change is compared on the symbols it writes
that no later file changes on that model (for example COEF_CPT, which
coef_alt.lin changes only with %CTST% and coef_shp.mod only with NCAP_CPX);
after change 7, on every symbol the stage changes. If a symbol cannot be
checked until later, the change says so; intermediate dumps between the coef
files can be added to the harness if that leaves a file unchecked.

No new GAMS runs are needed: every reference zip already has ppm/ and coef/.

## Findings so far

- (1) coef_cpt.mod: with OBLONG YES or OBJ MOD (every reference run but an
  OBLONG NO case, for which no open-model check exists yet) `%CTST%` is `**0`, `NOT 0**0` is false
  (G23) and COEF_CPT is not computed until coef_alt.lin (change 5). COEF_CPT
  at the PYR_S vintages of processes with a positive PRC_RESID is
  overwritten by coef_ext.vda L19-23 (change 7); scripts/m12_probe.jl leaves
  those records out until then (`later_overwrites`).
- (3) coef_ptr.mod: passes layer 1 on demo12 and the public suite references (TIMES-NZ x2, OTUS9r x2; 30 Oct 2026). Records that coef_ext.vda
  assigns later (COEF_PTRAN L72 for RP_CGC = RPG_1ACE less TRACKPC, ACT_FLO
  L63 for TRACKPC, RPCC_FFUNC L74) are left out until change 7
  (`later_overwrites`, now in src/coef/later.jl); none of the records
  coef_ptr computes falls among them. The FLO_FUNC paths (forward and
  reverse FLO_FUNC with FLO_SUM, L18, L23; both directions; EPS FLO_SUM in
  L27 and L34; a FLO_SUM outside the model years, kept by L16, G27; L51) were
  checked before 27 Oct 2026 on a crafted state that GAMS ran through
  coef_ptr.mod itself; that state was built on a model without an open
  licence and is to be rebuilt on demo12 (no open-model check yet). The
  reduced-flow conversion (L38-40, L42) needs KEEP_FLOF or RPCG_PTRAN, which
  only REDUCE fills, and is refused. GAMS projection semantics confirmed:
  G26-G28.
- (4) coef_obj.mod with filparam.gms and fillcost.gms: passes layer 1 on
  demo12 and the public suite references (TIMES-NZ x2, OTUS9r x2; 30 Oct 2026) (42 symbols). Every
  reference run has one currency per region and one discount-rate year, and
  none has G_RFRIR, flow taxes or subsidies, NCAP_ISPCT, OBJ_COMPD or storage
  flow costs, so those paths are checked on a crafted state that GAMS runs
  through coef_obj.mod itself. For that, scripts/gams_replay.jl writes any
  TimesModel state back as GAMS declarations and data and $BATINCLUDEs the
  TIMES files unchanged; replaying the unmodified TIMES_Demo demo12 state
  reproduces its coef dump exactly (all 42 symbols; scripts/check_replay.jl),
  which validates the replay. Since 28 Oct 2026 the crafted state is built on
  demo12 (test/unit/coef_obj_case.jl) and CI checks the 42 symbols on the
  demo12 fixture (test/fixtures/public_fixtures.toml). With `%OBMAC%` YES (GAMS 23+) the investment, fixed, variable and
  flow costs live in the OB_* caches only. The plan's earlier list for this
  change named TPULSE, PERDINV, OPYEAR, R_DF and RB: those come from
  coef_alt.lin and coef_shp.mod (changes 5, 6). New GAMS semantics: G29-G32.
- (5) coef_alt.lin: passes layer 1 on demo12 and the public suite references (TIMES-NZ x2, OTUS9r x2; 30 Oct 2026) (17 symbols).
  Every reference run takes the OBLONG/OBJ MOD branch (%CTST% **0), where
  this file, not coef_cpt.mod, computes COEF_CPT; the OBJ ALT, OBJ LIN,
  OBLONG+ALT and INT_DEFAULT('PASTI') paths are checked against coef_alt.lin
  run by GAMS on crafted states (scripts/make_coef_alt_unit.jl; built on
  TIMES_Demo demo12 since 28 Oct 2026, and CI checks the 17 symbols,
  COEF_CPT included, on the demo12 fixture). COEF_CPT records that
  coef_shp.mod L52-74 rescales (NCAP_CPX) are left out until change 6
  (`later_overwrites`) (the earlier note that no reference run has shapes was about
  NCAP_AFX/FLO_FUNCX; it stands for those). G33: L79 leaves past-vintage
  records alone, which can be negative.
  OTCGEN and OTNYC (31 Oct 2026) are the first suite models with OBJ AUTO and
  no OBLONG: %CTST% is empty, so the include ends at L59 and YK1 keeps the
  (T,Y_EOH) pairs L32 sets (L66 and L160, which clear it, are not reached).
  coef_alt! stored YK1 only at L160, so 1,261 (OTCGEN) and 280 (OTNYC) YK1
  records were in GAMS only; it now stores it at L32. On that path the file
  writes nothing of L65-87, so `scripts/m12_probe.jl` compares those symbols
  (RTP_CAPVL, RB, R_DF, COEF_CPT, PASTSUM, FIL2, MY_ARRAY, NCAP_ILED) only when
  %CTST% is set: MY_ARRAY in the coef dump is then the scratch of the last
  fillcost.gms call (L28) in coef_obj.mod L120-151, which every later reader
  (coef_alt.lin L75, eqobjfix.mod L67, eqobjinv.mod L119) assigns before reading. A fifth
  crafted case (OBJ AUTO, OBLONG NO) checks the L59 exit against GAMS.
  (31 Oct 2026) The layer-1 check of the files before coef_shp.mod again
  leaves out the COEF_CPT records that coef_shp.mod L73 rescales (the
  NCAP_CPX that L52 keeps): the rule was dropped when change 6 merged, but
  `scripts/m12_probe.jl` checks every file against the one coef dump, which
  holds the rescaled values, so it applies until coef_shp has run
  (`later_overwrites(tm; after=<file>)`). No public suite model has NCAP_CPX;
  `test/unit/test_coef_shp.jl` checks the rule on the crafted "cpt" state.
- (6) coef_shp.mod L10-37, L43-74 (28 Oct 2026): OPYEAR, the FLO_FUNCX shapes
  (RTP_CAPYR, RTP_FFCX) and the NCAP_CPX rescaling of COEF_CPT (RTP_CPX). demo12
  has neither FLO_FUNCX nor NCAP_CPX, so its layer 1 confirms OPYEAR (210
  pairs, Z = 20), Z = 500.5 and the cleared work symbols only; the shaping paths
  are checked on two crafted demo12 states (scripts/make_coef_shp_unit.jl):
  indexes removed at L17/L52, the year-'0' row outside RTP, the ACTCG row, the
  rounded NCAP_ILED lead, a non-integer index rounding to the next SHAPE row,
  repeated investments through OPYEAR (and a forced lifetime beyond Z, which
  empties the sum and removes the COEF_CPT record), the non-vintaged FLO_FUNC
  ratios (L45). The COEF_CPT exclusion for NCAP_CPX leaves `later_overwrites`;
  RTP_CAPYR (cleared by coef_ext.vda L76) and the RTP_FFCX rows coef_ext.vda
  L67-69 rewrite join it. Refused, as in coef_nio: the capacity-related
  commodity flows (L39-42 COEF_CIO, L77-94 the COEF_OCOM/COEF_RCOM override,
  L96 RCAP_OCAP) - one change with coef_nio.mod L15-71. GAMS semantics: G34.
- (7) coef_ext.vda L12-83 (28 Oct 2026), the last file of the stage: residual
  capacities (TRACKP, RTFORC for PRC_RCAP, NCAP_PASTI, PRC_RESID, COEF_CPT at
  the PYR_S vintage), RP_STL without STSFLX, COEF_AFUPS, the ACT_CSTUP
  annuity (TSL(S): levels that are timeslices, i.e. ANNUAL), the commodity
  balance pruning (TRACKC from TOP IN, RPC_IRE EXP, IRE_FLOSUM auxiliaries,
  DEM, RPC_NOFLO; UCU commodities: RTCS_VARC, RPC_CONLY, TOP_IRE), UC_TIME
  -13 switching UC_ON off, the singleton ACT_EFF groups as COEF_PTRAN with
  RPCC_FFUNC and ACT_EFF zeroed, COEF_PVT defaulting to FPD, VDA_DISC,
  COEF_ILED. eqlducs.vda and eqashar.vda are included (no-ops without
  unit-commitment data and FLO_ASHAR, apart from clearing CG_GRP and UNCD7);
  powerflo.vda CSTBAL only when COM_CSTBAL has data (G35). demo12 exercises
  L21-27, L42-47 (TOTCO2 loses its balance), L60-74 (237 groups, 2742
  COEF_PTRAN records) and L81-82; two crafted demo12 states cover the rest
  (scripts/make_coef_ext_unit.jl). With the stage complete the layer-1 chain
  on demo12 compares 126 symbols with nothing excluded; `later_overwrites`
  stays for the per-file steps of scripts/m12_probe.jl. Refused: WAVER YES
  (fillwave.gms), the ETL/CLI/ABS/MACRO extensions, reduced flows
  (RPC_FFUNC, RPCG_PTRAN: L62-69, refused by coef_ptr too), unit-commitment
  data (eqlducs.vda L12-41), FLO_ASHAR (eqashar.vda L16-33, pp_lvlfc.mod),
  COM_CSTBAL (powerflo.vda L372-396).
- M1.2 gate (to declare, James): every translated coefficient file passes
  layer 1 on demo12 with no exclusion (CI) and on TIM locally
  (scripts/m12_probe.jl; TIM results stay on James's machine); the stage's
  timing against GAMS's coefficient stage goes in docs/timings.md. Left for
  later changes, all refused explicitly: capacity-related commodity flows
  (coef_nio L15-71, coef_shp L39-42/L77-96), shaped availabilities
  (coef_cpt/pp_shapr), reduced flows (coef_ptr L38-42, coef_ext L62-69),
  FLO_ASHAR and unit-commitment preprocessing, the other extensions.
- No reference run has shaped availabilities (NCAP_AFM/AFX/AFSM/AFSX): the
  shape paths of coef_cpt.mod and pp_shapr.mod are refused until a crafted
  case has them.
