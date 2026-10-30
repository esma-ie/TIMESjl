# Phase 2 notes

Things learnt in Phase 1 that belong to Phase 2 (performance and numerical
robustness). Phase 1 changes none of them unless a parity check needs it.

## Backlog

| # | Item | Raised | Notes |
| --- | --- | --- | --- |
| P2-1 | Tighter solver and parity tolerances | 21 Oct 2026, James (with K1) | 1e-6 is loose for optimality. Run the GAMS references with tighter CPLEX tolerances (feasibility and optimality, e.g. `eprhs`/`epopt` 1e-9) and HiGHS likewise, then tighten the layer-3 cross-evaluation and retire K1's "as feasible as in its own LP" rule (scripts/m11_probe.jl `as_feasible_as`). |

## Model generation: where the time goes (21 Oct 2026)

Measured on a local-only model of about a million rows (TIM, 21 Oct 2026;
its figures are not recorded in this repository, CLAUDE.md), with GAMS on
James's machine; to be measured again on an open model of that size
(TIMES-NZ, OTUS9r or JRC-EU-TIMES). The findings are about TIMES.jl's own
code and hold for any large model: four generators (eq_combal!,
eq_acteff!, eq_floshr!, eq_capact!) take most of the time, each makes
exactly GAMS's rows, and allocation per row is the clearest symptom.

### Profile of the slow generators (CPU samples)

Two data-handling patterns explain most of the time; neither is in the
equations themselves. Both can be fixed without touching what is generated.

1. **Untyped context caches** (most of eq_combal!'s samples). Each generator
   keeps its index maps in `tm.cache::Dict{String,Any}` (`combal_context`,
   `stg_context`, ...). The value comes back as `Any`, so every field access
   in the inner loops (`x.rs_fr`, `x.varf_of_rtpc`, ... in `cal_fflo!`,
   src/model/eqcombal.jl L121-142) is a dynamic lookup on a NamedTuple of
   about 30 fields, and every result is dynamically dispatched and boxed.
   That is where eq_combal! allocates. Fix: a function barrier or
   a concrete type for each context (a struct, or a typed
   `get!(...)::ContextType`).
2. **Sorting rows into GAMS order** (a large share of eq_acteff!,
   eq_floshr! and eq_capact!).
   `gams_sort!` (src/model/gams_data.jl L333-338) sorts string tuples with
   `by = k -> ntuple(i -> rank(k[i]))`; `sort!` calls `by` on every
   comparison, and `rank` lowercases (allocates) each label and looks it up
   in `Dict{String,Int}`: O(n log n) times N string allocations and hashes.
   Fix: map each key once to integer ranks (a `Vector{NTuple{N,Int32}}`) and
   sort that, or keep labels interned as integers throughout (below).

Smaller, everywhere:

3. **String-tuple keys.** Variables are looked up by `NTuple{6,String}` in
   `getvar!` (src/model/mod_vars.jl L159-172): each lookup hashes six
   strings; every parameter value read (`gv`) and every set test hashes
   tuples of strings too. Interning labels as integers (the GDX UEL index)
   at load would make keys bit-tuples, hashing cheap and sorting trivial.
4. **Names.** Every variable and constraint gets a string name
   (`colname`, `@variable base_name`, `addeq!`) for the parity checks; in
   production runs names can be off (`set_string_names_on_creation`), with
   a name map kept outside JuMP for parity mode.
5. **Per-row temporaries.** `gconstraint!` builds a `Dict{VariableRef,Float64}`
   for every row to apply the GAMS rule that rows whose terms cancel are not
   generated (`_all_cancel`), and `JuMP.@constraint(lhs == rhs)` builds a
   new expression from `lhs - rhs`. A single pass on a canonicalised
   expression would do both.
6. **Lazy dump reads inside generators.** The first generator to use a set
   or parameter reads it from Arrow (`read_symbol`), so read time lands in
   whichever generator comes first (usually eq_combal!). Phase 2 can load once, in columnar form, with integer labels.

## Memory

- A million-row model takes several GB of resident memory (the JuMP model
  with named rows and columns, plus the dump caches and index contexts).
- At that size the JuMP model plus HiGHS's own copy did not fit in 6 GB
  (HiGHS was killed in its interior point after presolve). Direct mode
  (Phase 2) builds the model in the solver once instead of in JuMP's cache
  and again in the solver.
- The parity tools hold whole LPs keyed by name strings
  (`Dict{Tuple{String,String},Float64}`, millions of entries per side at
  that size); scripts/m11_large.jl splits the check into processes to fit
  8 GB. Interned integer ids would make million-row parity checks a single
  process.

## Solving

- James's GAMS licence has no GAMS/HiGHS; GAMS-side HiGHS references stop at
  the 2,000-row demo limit.
