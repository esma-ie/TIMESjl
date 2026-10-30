# TIMES.jl Translation Guide (GAMS → Julia/JuMP)

## Purpose
Port the TIMES model generator from GAMS to Julia/JuMP with exact numerical
parity. Phase 1 is a faithful translation: no reformulation and no
optimisation. Performance work happens in Phase 2.

## Source of truth
- Baseline: TIMES v4.9.7, etsap-TIMES/TIMES_model @ d9a6a25. Pin this commit
  and never translate from any other version.
- Equation reference: jamesglynn/TIMES_Documentation, Part II.
- If the GAMS code and the documentation disagree, the GAMS code is
  authoritative. Log every discrepancy in `docs/discrepancies.md`.

## Porting order (equations outwards)
1. M1.0 Foundations: repo, CI, GAMS reference harness (DEBUG dump,
   post-coef dump, pre-solve dump, CONVERT DumpGDX, solution, timings),
   comparison tool.
2. M1.1 Model generation: variables, core + VDA equations, bounds and
   objective, built from GAMS-dumped data.
3. M1.2 Coefficients (coefmain, coef_*).
4. M1.3 Preprocessing (ppmain, pp_*, VDA prep, REDUCE).
5. M1.4 GAMS-free DD/.run reader.
6. M1.5 Run options (OBJ variants, MID_YEAR, DSCAUTO, VAR_UC, FIXBOH, ...).
7. M1.6 Reporting + Veda .vd output.
8. M1.7 Phase 1 release + baseline benchmarks.
Do not start a milestone until the previous one passes its parity gate.

## Translation rules
- Keep the GAMS names for sets, parameters, variables and equations
  (e.g. `EQ_COMBAL`, `VAR_ACT`, `COEF_CPT`) so each piece can be traced
  back to the GAMS code.
- Every Julia function or constraint block cites its GAMS file and line
  range in a docstring, e.g. `# GAMS: eqcombal.mod L45-112, v4.9.7`.
- Translate one GAMS file or equation family at a time. Make a separate PR
  for each.
- Write `$`-conditions and domain controls as explicit sparse index sets.
  Never build dense Cartesian products.
- Write each equation in the same algebraic form as in GAMS. No
  substitutions, aggregations or "equivalent" rewrites in Phase 1.
- Copy any GAMS defaults, implicit zeros or interpolation behaviour
  exactly, and document them.
- Leave the Phase 2 work (direct mode, triplets, threading, names off)
  until Phase 2.

## Validation (every PR)
| Layer      | Check                                                   | Tolerance |
|------------|---------------------------------------------------------|-----------|
| Data       | Preprocessed sets/params vs GAMS dump                   | 1e-9      |
| Matrix     | Rows, columns, coefficients, RHS, bounds vs DumpGDX     | 1e-9      |
| Solution   | Objective; check each optimum in the other model        | 1e-6      |
| Reporting  | Report parameters vs GAMS outputs                       | 1e-6      |

Test models: only models with a clearly stated open-source or open-data
licence (docs/test-models.md). TIMES_Demo demo12 (CC BY 4.0;
etsap-TIMES/TIMES_Demo @ 962db86; no discrete-capacity data, so not
DSC-dependent; joins at M1.1), TIMES-NZ (MIT; M1.4), OTAI (CC BY-SA 4.0,
Veda Excel only, via xl2times at M1.4). TIM (CC BY-NC-SA 4.0) is a named
exception: local references only, never committed. The DemoS models were
removed on 27 Oct 2026 (no stated licence). `reference/suite.toml` lists
each model's licence and the milestone at which it joins.
Any mismatch blocks the merge. Record known, justified differences in
`docs/known-differences.md`.

## Definition of done (per component)
- Matches GAMS on all test models at the tolerances above
- GAMS source referenced in docstrings
- Unit tests plus a regression fixture
- Timings logged against GAMS
- Discrepancies recorded

## Decisions (confirmed 17 Oct 2026)
- "No reformulation" = same mathematics as GAMS; sparse data structures
  allowed from day one. Confirmed.
- Extension scope: core + VDA in Phase 1; DSC next; MACRO, stochastic,
  ETL, climate, damage after M1.7. Default unless changed.
- Reference solver: CPLEX via James's GAMS licence for reference runs;
  HiGHS on both sides for open-source parity and CI; Gurobi trial
  possible later for benchmarks. Confirmed.
- Repo: esma-ie/TIMESjl (from 27 Oct 2026; the earlier esma-ie/TIMES.jl is
  archived, private). Licence GPL-3.0-or-later, same as TIMES_model; to go
  public before the MVP as an open experiment in AI-assisted translation.
  Olexandr Balyk and ETSAP members consulted. Confirmed.
- Veda .vd output: in Phase 1 (M1.6). Default unless changed.
- Phase 1 performance target (confirmed 18 Oct 2026): model generation
  (preprocessing to solver hand-off) no worse than 5x GAMS, warm, at M1.7.
  Correctness comes first; speed is Phase 2's job.

## Status
Entries up to 22 Oct 2026 summarise the pre-publication work. Until 27 Oct
2026 the translation was also checked on models without an open licence;
those checks, their figures and their crafted cases are not published
(docs/test-models.md). The evidence on open models is in the entries from
27 Oct 2026 on and in docs/gams-julia-map.md.

- 18 Oct 2026: M1.0 gate PASS with the PyPI GAMS 54.6.0 demo system (HiGHS
  and demo CPLEX); U1-U4 settled (docs/discrepancies.md). Licensed-GAMS
  references for larger models still to be produced on James's machine.
- 18 Oct 2026: TIMES_Demo demo12 added to the suite. The harness hooks work on
  it under v4.9.7 (ppm and coef dumps written), but the model is 8,695 rows x
  9,669 columns with REDUCE off and 3,233 x 4,485 with REDUCE on, above the
  2,000-row demo limit, so its references need licensed GAMS.
  `scripts/run_references.ps1` runs the whole suite on Windows.
- 20 Oct 2026: M1.1 input switched from the coef dump to a pre-solve dump
  (harness run with SOLVE_NOW=NO). pp_qack.mod runs after eqmain and before
  the solve and changes sets the equations read (RTP_VNTBYR, PRC_CG, AFS);
  the pre-solve dump is the state the SOLVE statement generates from. It
  needs no solve, so it can be produced under the demo licence for every
  model.
- 20 Oct 2026: first whole-model parity: a model generated entirely by
  TIMES.jl from the pre-solve dump (EQ_ACTFLO, EQ_CAPACT, EQ_PTRANS,
  EQ_CUMFLO, EQ_COMBAL, the objective rows, bounds) is identical to the
  CONVERT export (layer 2), and the TIMES.jl HiGHS optimum equals the GAMS
  HiGHS and CPLEX objectives, each optimum feasible and optimal in the other
  model (layer 3). Next: a generation driver that refuses data for
  untranslated equation families; `scripts/m11_probe.jl` lists, per model,
  the families still missing and checks layers 2 and 3 where none are.
- 20-21 Oct 2026: the M1.1 equation families, one GAMS file per change:
  EQ_PEAK; EQ_IRE (bilateral trade) and the non-dynamic user constraints
  (EQE_UCT/UCRT/UCTS/UCRTS with VAR_UC YES, their bounds from bnd_ucw.mod);
  EQ(l)_CPT, EQ(l)_INSHR/OUTSHR and EQE_ACTEFF (VDA); EQ(l)_ACTBND; the
  dynamic user constraints (EQE_UCSU/UCRSU/UCRSUS/UCSUS, LHS direction,
  GROWTH attribute); EQ(l)_ASHAR (standard processes); EQE/EQL_CAFLAC and
  EQL_CAPFLO (VDA commodity availabilities, with the AFS removal of
  equ_ext.vda L79, `afs_solve`, used by EQ_CAPACT too; GAMS gives x/INF = 0,
  G17); EQE_UCRS (timeslice-level user constraints, UC_DS, with the
  eqmain.mod L224 map; UC_TIME cancels in two-sided constraints, D24);
  storage (EQ_STGTSS and EQ_STSBAL, EQ_STGAUX, EQ(l)_STGIN/STGOUT,
  cal_stgn.mod in EQ_COMBAL and EQ_PEAK, the EQ_CAPACT storage term, storage
  flow costs in EQ_OBJVAR, the storage terms of EQ(l)_CAFLAC and
  EQL_CAPFLO, bnd_stg.mod; D25-D30, G18-G20); carbon budgets (EQ_CUMNET/
  EQ_CUMPRD, the COM_CUM part of bnd_cum.mod, and the multi-period user
  constraints EQE_UC/EQE_UCR, equcwrap.mod L22/L24, %8 = 2: FPD-weighted
  period sums, UC_CUMFLO and UC_CUMCOM terms). Rows with no variable left,
  after combining terms, are not generated, as in GAMS (G22). Still refused:
  storage flexibility (%STSFLX%: EQ_STSLEV and the VAR_UDP/VAR_STS terms),
  inter-period storage (EQ_STGIPS, STK) and EQ(l)_ASHAR of storage
  processes. Families that only occur above the demo licence's size limit
  were checked on crafted cases at the time; on open models, demo12 reaches
  most of them and the rest wait for crafted cases on demo12 or TIMES-NZ
  (docs/gams-julia-map.md, "no open-model check yet").
- 21 Oct 2026: first licensed references, from James's machine (GAMS 52.1.0
  with CPLEX, harness 0.2.1, both variants). TIMES_Demo-demo12 passes layers
  2 and 3 (reduce_off: objective and cross-evaluation against CPLEX). The
  licence has no GAMS/HiGHS, so above the 2,000-row demo limit the GAMS
  HiGHS solve stops with return code 3 and summary.csv shows CHECK; for
  those models HiGHS parity is the TIMES.jl HiGHS optimum against GAMS
  CPLEX. The CPLEX optimum of a reference run can miss its own GAMS LP at a
  row by more than 1e-6 (known-differences K1).
- 21 Oct 2026: **M1.1 gate PASS** (James). Layers 2 and 3 pass (reduce_off)
  on every model of the M1.1 set at the time; on open models that is
  TIMES_Demo demo12. K1 approved for Phase 1, with tighter tolerances for
  Phase 2 (docs/phase2-notes.md, P2-1); timings in docs/timings.md. REDUCE
  YES (the as_run variants) stays with M1.3. M1.2 starts.
- 21 Oct 2026: M1.2 (0) and (1). `src/coef/state.jl`: computed GAMS sets and
  parameters replace the dump's (`gput!`, `gassign!`), and `layer1` checks
  them against a dump; `scripts/m12_probe.jl` runs the translated steps on
  each reference run's ppm dump against its coef dump. coefmain.mod L11 and
  coef_cpt.mod L13-63 (with pp_shapr.mod's base assignment). With OBLONG YES
  or OBJ MOD `%CTST%` is `**0` and coef_cpt.mod computes no COEF_CPT (G23);
  L19-21 need an OBLONG NO run (harness 0.2.3 model overrides). COEF_CPT at
  the PYR_S vintages of PRC_RESID processes is overwritten later by
  coef_ext.vda L19-23. Shaped availability (NCAP_AFM/AFX/AFSM/AFSX),
  VALIDATE and STAGES are refused.
- 21 Oct 2026: M1.2 (2): coef_nio.mod for models without capacity-related
  commodity flows (NCAP_ICOM, NCAP_OCOM, RCAP_OCAP, NCAP_COM and NCAP_CLED
  are refused, as cal_cap.mod is in M1.1). The dump reader now reads a zero
  scalar as absent: GDX writes `Scalar CNT / 0 /` (unlike any indexed zero),
  which read as EPS before.
- 21 Oct 2026: M1.2 (3): coef_ptr.mod L9-54, with the FLO_FUNC paths checked
  on a crafted state run through coef_ptr.mod by GAMS (docs/m12-plan.md,
  finding 3; that state has since been removed and is to be rebuilt on
  demo12). The reduced-flow conversion (L38-40, L42) is refused until REDUCE
  (M1.3). `OPTION` projection semantics confirmed (discrepancies G26-G28).
- 21 Oct 2026: M1.1 timings on one machine (James's workstation, Julia
  1.13.2 against GAMS 52.1.0; docs/timings.md): TIMES.jl generation is 6.8x
  GAMS equations + hand-over on demo12.
- 21 Oct 2026: M1.2 (4): coef_obj.mod with filparam.gms and fillcost.gms,
  with a crafted state replayed through coef_obj.mod by GAMS
  (scripts/gams_replay.jl). Refused: ANNCOST LEV, VALIDATE, elastic demand
  shapes, blending, investment costs outside RDCUR.
- 22 Oct 2026: M1.2 (5): coef_alt.lin (the coefmain.mod call), with four
  crafted switch settings replayed through GAMS. COEF_CPT is now computed
  (coef_alt.lin under OBLONG) for every reference run; NCAP_CPX-shaped
  records wait for coef_shp.mod. G33.
- 27 Oct 2026: the DemoS models leave the suite, the harness and the tests
  (no licence stated by IEA-ETSAP, KanORS-EMR or E4SMA; James). Rule from now
  on: open-licence models only, TIM as a named local-only exception, and no
  learning from closed models (docs/test-models.md). On open models, the
  evidence that stands is TIMES_Demo demo12 passing layers 2 and 3 (licensed
  run, 21 Oct) and the coefficient files passing layer 1 on demo12. CI checks
  no equation family against GAMS until a demo12 fixture is added
  (test/fixtures/public_fixtures.toml).
- 27 Oct 2026: moved to a new private repository with a filtered history:
  the fixtures, crafted cases and crafted states built on the removed models
  were taken out of every commit, with no release assets and no tags
  (published as esma-ie/TIMESjl on 30 Oct 2026 with a fresh history: one
  first commit). Primary test models from here on: TIMES_Demo
  demo12 (CC BY 4.0, CI fixtures), TIM (named exception, James's machine
  only) and OTUS9r (once it is published with an open licence). The M1.0 to
  M1.2 evidence earned on the removed models is to be re-earned on these
  models.
- 28 Oct 2026: M1.2 (4) re-earned on an open model. coef_obj.mod passes layer
  1 on TIMES_Demo demo12 (42 symbols, in CI through
  test/fixtures/public_fixtures.toml) and on a crafted state built on demo12
  and replayed through coef_obj.mod by GAMS (coefobj_unit_gams regenerated;
  scripts/check_replay.jl validates the replay by reproducing demo12's own
  coef dump). The earlier crafted state went with the removed fixtures.
- 28 Oct 2026: M1.2 (5) re-earned on an open model: coef_alt.lin passes layer
  1 on TIMES_Demo demo12 (17 symbols, COEF_CPT included, in CI) and on its
  four crafted switch settings rebuilt on demo12 (coefalt_unit_gams
  regenerated).
- 28 Oct 2026: M1.2 (6): coef_shp.mod L10-37, L43-74 passes layer 1 on
  TIMES_Demo demo12 (no shaping data there: OPYEAR, Z and the cleared work
  symbols) and on two crafted demo12 states (FLO_FUNCX and NCAP_CPX shapes)
  replayed through coef_shp.mod by GAMS. Refused with coef_nio's
  capacity-related commodity flows: L39-42, L77-94, L96. G34.
- 28 Oct 2026: M1.2 (7): coef_ext.vda L12-83, the last file of the
  coefficient stage, passes layer 1 on TIMES_Demo demo12 and on two crafted
  demo12 states replayed through coef_ext.vda by GAMS (eqlducs.vda and
  eqashar.vda included). The whole stage now matches demo12's coef dump on
  126 symbols with nothing excluded (CI). Refused: WAVER, the ETL/CLI/ABS/
  MACRO extensions, reduced flows, unit-commitment preprocessing, FLO_ASHAR,
  COM_CSTBAL. G35. The M1.2 gate waits on James: TIM locally and the stage
  timing against GAMS.
- 29 Oct 2026: the TIM figures of 20-21 Oct (row and column counts, timings,
  objectives, record counts, which features it uses) are removed from the
  repository: they came from a TIM source that is no longer used (the
  archived esma-cgep organisation, CLAUDE.md), and TIM material is never
  committed. TIM's new export (esma-ie fork, 28 Oct) is checked on James's
  machine only. The million-row timings and memory figures are to be measured
  again on an open model (TIMES-NZ, OTUS9r or JRC-EU-TIMES).
- 30 Oct 2026: references for TIMES-NZ 3.0.8 (steady-v308, shift-v308) and
  OTUS9r (reference, tax1_wo_mou) on James's workstation (GAMS 52.1.0 +
  CPLEX). Every coefficient file passes layer 1 on all five reference runs
  of the public suite models (demo12, TIMES-NZ x2, OTUS9r x2): 35 checks,
  29.6 M records at 1e-9, no mismatch (docs/dashboard/suite-public.json).
  Layer 2 is refused on TIMES-NZ (EQ(l)_FLOMRK, EQ_SLSIFT) and OTUS9r
  (EQ(l)_UCRTP, EQN_UCRTC). The repository is published as esma-ie/TIMESjl
  with a fresh history, and OTUS9r as esma-ie/OTUS9r (the EPA original at tag
  epaus9rt-v20.4, the DD export in dd/); the suite pins OTUS9r by commit.
  The suite gets two tiers: core (one baseline case per model, the default
  batch) and milestone (policy and secondary scenarios, very large models);
  OTUS9r-tax1_wo_mou is paused in the milestone tier.
