# Layer 2 (matrix) and layer 3 (cross-evaluation) parity on a canonical LP form.

"""
    RowData

One constraint row as an interval `lo <= a'x <= hi` (`lo == hi` for an
equality, `-Inf`/`+Inf` for a one-sided row). Constants in the constraint
function are moved into the bounds, as GAMS does.
"""
struct RowData
    lo::Float64
    hi::Float64
end

sense(r::RowData) = r.lo == r.hi ? :eq : isinf(r.hi) ? :ge : isinf(r.lo) ? :le : :range

"""
    ColData

One column: bounds, objective coefficient and integrality.
"""
mutable struct ColData
    lb::Float64
    ub::Float64
    obj::Float64
    integer::Bool
end

ColData() = ColData(-Inf, Inf, 0.0, false)

"""
    CanonicalLP

A linear model keyed by canonical entity names `NAME(LABEL1,LABEL2,...)`,
uppercased (GAMS names and labels are case-insensitive), so that a JuMP model
and a GAMS CONVERT export can be compared entry by entry. Zero coefficients
are dropped and repeated terms summed.
"""
struct CanonicalLP
    rows::Dict{String,RowData}
    cols::Dict{String,ColData}
    coefs::Dict{Tuple{String,String},Float64}
    objsense::Symbol          # :min, :max or :feasibility
    objconstant::Float64
end

Base.show(io::IO, lp::CanonicalLP) =
    print(io, "CanonicalLP(", length(lp.rows), " rows, ", length(lp.cols), " columns, ", length(lp.coefs),
          " nonzeros, ", lp.objsense, ")")

"""
    canonical_key(name, labels) -> String

`NAME(L1,L2,...)` in upper case; just `NAME` for a scalar entity.
"""
canonical_key(name::AbstractString, labels) =
    isempty(labels) ? uppercase(strip(name)) :
    uppercase(strip(name)) * "(" * join((uppercase(strip(string(l))) for l in labels), ",") * ")"

"""
    jump_name_key(name) -> String

Default key function: turns a JuMP name such as `EQE_COMBAL[REG1,2020,ELC,ANNUAL]`
(or a GAMS-style `EQE_COMBAL(REG1,...)`, with or without quotes around
labels) into its canonical key. Labels must not contain commas or brackets.
"""
function jump_name_key(name::AbstractString)
    isempty(name) && throw(ArgumentError("unnamed entity: every row and column must be named for parity checks"))
    m = match(r"^\s*([^\[\(]+)[\[\(](.*)[\]\)]\s*$", name)
    m === nothing && return canonical_key(name, ())
    labels = [strip(strip(l), ['\'', '"']) for l in split(m.captures[2], ',')]
    return canonical_key(m.captures[1], labels)
end

_interval(s::MOI.EqualTo) = (s.value, s.value)
_interval(s::MOI.GreaterThan) = (s.lower, Inf)
_interval(s::MOI.LessThan) = (-Inf, s.upper)
_interval(s::MOI.Interval) = (s.lower, s.upper)
_interval(s) = throw(ArgumentError("unsupported constraint set $(typeof(s))"))

function _apply_bound!(c::ColData, s)
    if s isa MOI.GreaterThan
        c.lb = s.lower
    elseif s isa MOI.LessThan
        c.ub = s.upper
    elseif s isa MOI.EqualTo
        c.lb = c.ub = s.value
    elseif s isa MOI.Interval
        c.lb, c.ub = s.lower, s.upper
    elseif s isa MOI.Integer
        c.integer = true
    elseif s isa MOI.ZeroOne
        c.integer = true
        c.lb = max(c.lb, 0.0)
        c.ub = min(c.ub, 1.0)
    else
        throw(ArgumentError("unsupported variable set $(typeof(s))"))
    end
    return c
end

"""
    canonical_from_moi(model; keyfn=jump_name_key) -> CanonicalLP

Build the canonical form of any MathOptInterface model with scalar affine
constraints and an affine (or single-variable) objective. `keyfn` maps the
model's own row and column names to canonical keys.
"""
function canonical_from_moi(src::MOI.ModelLike; keyfn=jump_name_key)
    vars = MOI.get(src, MOI.ListOfVariableIndices())
    vkey = Dict{MOI.VariableIndex,String}()
    cols = Dict{String,ColData}()
    for v in vars
        k = keyfn(MOI.get(src, MOI.VariableName(), v))
        haskey(cols, k) && throw(ArgumentError("duplicate column key $k"))
        vkey[v] = k
        cols[k] = ColData()
    end
    rows = Dict{String,RowData}()
    coefs = Dict{Tuple{String,String},Float64}()
    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
            f = MOI.get(src, MOI.ConstraintFunction(), ci)
            s = MOI.get(src, MOI.ConstraintSet(), ci)
            if F == MOI.VariableIndex
                _apply_bound!(cols[vkey[f]], s)
            elseif F == MOI.ScalarAffineFunction{Float64}
                k = keyfn(MOI.get(src, MOI.ConstraintName(), ci))
                haskey(rows, k) && throw(ArgumentError("duplicate row key $k"))
                lo, hi = _interval(s)
                c0 = MOI.constant(f)
                rows[k] = RowData(lo - c0, hi - c0)
                for t in MOI.Utilities.canonical(f).terms
                    t.coefficient == 0 && continue
                    coefs[(k, vkey[t.variable])] = t.coefficient
                end
            else
                throw(ArgumentError("unsupported constraint type $F-in-$S"))
            end
        end
    end
    sense = MOI.get(src, MOI.ObjectiveSense())
    objsense = sense == MOI.MIN_SENSE ? :min : sense == MOI.MAX_SENSE ? :max : :feasibility
    objconstant = 0.0
    if objsense != :feasibility
        FT = MOI.get(src, MOI.ObjectiveFunctionType())
        f = MOI.get(src, MOI.ObjectiveFunction{FT}())
        if f isa MOI.VariableIndex
            cols[vkey[f]].obj = 1.0
        elseif f isa MOI.ScalarAffineFunction{Float64}
            for t in MOI.Utilities.canonical(f).terms
                cols[vkey[t.variable]].obj = t.coefficient
            end
            objconstant = MOI.constant(f)
        else
            throw(ArgumentError("unsupported objective type $FT"))
        end
    end
    return CanonicalLP(rows, cols, coefs, objsense, objconstant)
end

"""
    canonical_from_jump(model; keyfn=jump_name_key) -> CanonicalLP

Canonical form of a JuMP model. Every variable and constraint must be named;
container names such as `VAR_ACT[R,V,T,P,S]` become `VAR_ACT(R,V,T,P,S)`.
The model's own backend is read (no copy), so a model of a million rows or
more is held once; a model in direct mode is copied first.
"""
function canonical_from_jump(model::JuMP.GenericModel{Float64}; keyfn=jump_name_key)
    JuMP.mode(model) == JuMP.DIRECT || return canonical_from_moi(JuMP.backend(model); keyfn)
    dest = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    MOI.copy_to(dest, JuMP.backend(model))
    return canonical_from_moi(dest; keyfn)
end

"""
    canonical_from_mps(path; keyfn=jump_name_key) -> CanonicalLP

Canonical form of an MPS file (plain or gzipped), read with
`MathOptInterface.FileFormats`. For a GAMS CONVERT export, pass a `keyfn` that
translates CONVERT's scalar names through its dictionary; the dictionary
format is confirmed on the first reference run (docs/discrepancies.md, U2).
"""
function canonical_from_mps(path::AbstractString; keyfn=jump_name_key)
    m = MOI.FileFormats.Model(format=MOI.FileFormats.FORMAT_MPS)
    MOI.read_from_file(m, path)
    return canonical_from_moi(m; keyfn)
end

"""
    convert_name_map(dictmap) -> (rows, cols)

The CONVERT dictionary as two maps from scalar labels to canonical keys:
`rows["e6"] = "EQ_ACTFLO(REG1,2005,2005,DTPSCOA,ANNUAL)"` and the same for
columns. A `DictMap` GDX (docs/discrepancies.md, U2) holds one set per TIMES
family, `<equation>_EM` and `<variable>_VM`, whose records carry the scalar
row/column label first and the family's own indices after it.
"""
function convert_name_map(dictmap::ReferenceDump)
    rows = Dict{String,String}()
    cols = Dict{String,String}()
    for name in symbol_names(dictmap)
        u = uppercase(name)
        (endswith(u, "_EM") || endswith(u, "_VM")) || continue
        fam = name[1:end-3]
        into = endswith(u, "_EM") ? rows : cols
        for k in read_symbol(dictmap, name).keys
            scalar = lowercase(String(k[1]))
            haskey(into, scalar) && throw(ArgumentError("$(scalar) mapped twice in the CONVERT dictionary"))
            into[scalar] = canonical_key(fam, k[2:end])
        end
    end
    return rows, cols
end

"""
    canonical_from_dump(matrix_dir, dictmap_dir; objsense=:min) -> CanonicalLP

Canonical form of a GAMS CONVERT `DumpGDX` export (the `matrix/` dump of the
reference harness), with scalar row and column labels (`e1`, `x58`) renamed
to family keys through the `DictMap` export (`matrix_dictmap/`); layouts per
docs/discrepancies.md U1-U2. Row senses and right-hand sides come from the
`e` bounds, column bounds from `x`, coefficients from `A`, and the objective
from `objcoef`/`objconst` on the `jobj` column. The sense is not in the dump:
TIMES always solves `MINIMIZING objZ` (solve.mod L37, v4.9.7; the MACRO case
L34 maximizes and is out of Phase 1 scope), so `:min` is the default.
"""
function canonical_from_dump(matrix_dir::AbstractString, dictmap_dir::AbstractString; objsense::Symbol=:min)
    m = load_dump(matrix_dir)
    rowmap, colmap = convert_name_map(load_dump(dictmap_dir))
    rename(map, label) = get(map, lowercase(String(label))) do
        throw(ArgumentError("$(label) is not in the CONVERT dictionary"))
    end

    e = read_symbol(m, "e")
    rows = Dict{String,RowData}()
    for (i, k) in enumerate(e.keys)
        e.values["scale"][i] == 1.0 || throw(ArgumentError("row $(k[1]) is scaled; parity needs unscaled models"))
        rows[rename(rowmap, k[1])] = RowData(e.values["lower"][i], e.values["upper"][i])
    end

    x = read_symbol(m, "x")
    cols = Dict{String,ColData}()
    for (i, k) in enumerate(x.keys)
        cols[rename(colmap, k[1])] = ColData(x.values["lower"][i], x.values["upper"][i], 0.0, false)
    end

    A = read_symbol(m, "A")
    coefs = Dict{Tuple{String,String},Float64}()
    for (i, k) in enumerate(A.keys)
        v = A.values["value"][i]
        v == 0.0 && continue
        coefs[(rename(rowmap, k[1]), rename(colmap, k[2]))] = v
    end

    jobj = read_symbol(m, "jobj").keys
    length(jobj) == 1 || throw(ArgumentError("expected exactly one objective column, got $(length(jobj))"))
    objcoef = only(read_symbol(m, "objcoef").values["value"])
    objconst = only(read_symbol(m, "objconst").values["value"])
    cols[rename(colmap, only(jobj)[1])].obj = objcoef

    return CanonicalLP(rows, cols, coefs, objsense, objconst)
end

family(key::AbstractString) = (i = findfirst('(', key); i === nothing ? key : key[1:prevind(key, i)])

"""
    LPComparison

Result of [`compare_lp`](@ref). `counts` gives the number of mismatches by
kind; `families` the row or column count per equation/variable family on each
side; `examples` up to `max_examples` example differences as text.
"""
struct LPComparison
    counts::Dict{Symbol,Int}
    families::Dict{String,Tuple{Int,Int}}
    examples::Vector{String}
end

ispass(c::LPComparison) = sum(values(c.counts); init=0) == 0

function Base.show(io::IO, c::LPComparison)
    print(io, "LPComparison(", ispass(c) ? "PASS" : "FAIL")
    for (k, v) in sort!(collect(c.counts))
        v > 0 && print(io, ", ", k, "=", v)
    end
    print(io, ")")
end

"""
    compare_lp(left, right; rtol=1e-9, atol=0.0, max_examples=20) -> LPComparison

Entry-by-entry comparison of two canonical LPs: rows and columns present on
one side only, coefficients, row bounds (right-hand sides), column bounds,
objective coefficients and sense. This is the layer-2 check of the
translation guide (tolerance 1e-9).
"""
function compare_lp(a::CanonicalLP, b::CanonicalLP; rtol::Real=1e-9, atol::Real=0.0, max_examples::Int=20)
    rtol, atol = Float64(rtol), Float64(atol)
    counts = Dict{Symbol,Int}()
    examples = String[]
    note(kind, msg) = (counts[kind] = get(counts, kind, 0) + 1;
                       length(examples) < max_examples && push!(examples, string(kind, ": ", msg)))
    eq(x, y) = _numeq(Float64(x), Float64(y), rtol, atol)

    a.objsense == b.objsense || note(:objsense, "$(a.objsense) vs $(b.objsense)")
    eq(a.objconstant, b.objconstant) || note(:objconstant, "$(a.objconstant) vs $(b.objconstant)")
    for (k, r) in a.rows
        s = get(b.rows, k, nothing)
        if s === nothing
            note(:row_only_left, k)
        elseif !(eq(r.lo, s.lo) && eq(r.hi, s.hi))
            note(:row_bounds, "$k [$(r.lo), $(r.hi)] vs [$(s.lo), $(s.hi)]")
        end
    end
    for k in keys(b.rows)
        haskey(a.rows, k) || note(:row_only_right, k)
    end
    for (k, c) in a.cols
        d = get(b.cols, k, nothing)
        if d === nothing
            note(:col_only_left, k)
            continue
        end
        (eq(c.lb, d.lb) && eq(c.ub, d.ub)) || note(:col_bounds, "$k [$(c.lb), $(c.ub)] vs [$(d.lb), $(d.ub)]")
        eq(c.obj, d.obj) || note(:obj_coef, "$k $(c.obj) vs $(d.obj)")
        c.integer == d.integer || note(:integrality, k)
    end
    for k in keys(b.cols)
        haskey(a.cols, k) || note(:col_only_right, k)
    end
    for (rc, v) in a.coefs
        w = get(b.coefs, rc, nothing)
        if w === nothing
            (haskey(b.rows, rc[1]) && haskey(b.cols, rc[2])) && note(:coef_only_left, "$(rc[1]) x $(rc[2]) = $v")
        elseif !eq(v, w)
            note(:coef_value, "$(rc[1]) x $(rc[2]): $v vs $w")
        end
    end
    for (rc, w) in b.coefs
        haskey(a.coefs, rc) && continue
        (haskey(a.rows, rc[1]) && haskey(a.cols, rc[2])) && note(:coef_only_right, "$(rc[1]) x $(rc[2]) = $w")
    end
    fam = Dict{String,Tuple{Int,Int}}()
    for (side, lp) in ((1, a), (2, b)), k in Iterators.flatten((keys(lp.rows), keys(lp.cols)))
        f = family(k)
        n = get(fam, f, (0, 0))
        fam[f] = side == 1 ? (n[1] + 1, n[2]) : (n[1], n[2] + 1)
    end
    return LPComparison(counts, fam, examples)
end

"""
    evaluate_point(lp, x; tol=1e-6) -> NamedTuple

Layer-3 cross-evaluation: evaluate a solution `x` (column key => value) from
one model in the other model's canonical LP. Returns the objective value, the
largest row and bound violations (scaled by `max(1, |bound|)`), whether both
are within `tol`, the columns of `lp` missing from `x` (taken as 0) and the
worst rows.
"""
function evaluate_point(lp::CanonicalLP, x::AbstractDict{<:AbstractString,<:Real}; tol::Real=1e-6, nworst::Int=10)
    val(k) = Float64(get(x, k, 0.0))
    missing_cols = [k for k in keys(lp.cols) if !haskey(x, k)]
    obj = lp.objconstant + sum((c.obj * val(k) for (k, c) in lp.cols if c.obj != 0); init=0.0)
    act = Dict{String,Float64}(k => 0.0 for k in keys(lp.rows))
    for ((r, c), a) in lp.coefs
        haskey(act, r) && (act[r] += a * val(c))
    end
    viol(v, lo, hi) = max(lo - v, v - hi, 0.0) / max(1.0, abs(isinf(lo) ? 0.0 : lo), abs(isinf(hi) ? 0.0 : hi))
    rowv = sort!([(viol(act[k], r.lo, r.hi), k) for (k, r) in lp.rows]; rev=true)
    bndv = maximum((viol(val(k), c.lb, c.ub) for (k, c) in lp.cols); init=0.0)
    maxrow = isempty(rowv) ? 0.0 : rowv[1][1]
    return (objective=obj, max_row_violation=maxrow, max_bound_violation=bndv,
            feasible=(maxrow <= tol && bndv <= tol), missing_columns=missing_cols,
            worst_rows=[(k, v) for (v, k) in rowv[1:min(nworst, length(rowv))] if v > 0])
end

"""
    solution_levels(dump; columns=nothing) -> Dict{String,Float64}

The level of every variable record in a GAMS end-of-run dump (`final/`),
keyed like the canonical LP columns (`VAR_ACT(REG1,2005,...)`, `OBJZ`), for
[`evaluate_point`](@ref). With `columns` (e.g. `keys(lp.cols)`), only those.
A level stored as EPS reads as 0.
"""
function solution_levels(d::ReferenceDump; columns=nothing)
    out = Dict{String,Float64}()
    want = columns === nothing ? nothing : Set{String}(columns)
    for info in values(d.symbols)
        info.kind == :variable || continue
        r = read_symbol(d, info.name)
        lv = get(r.values, "level", Float64[])
        for (i, k) in enumerate(r.keys)
            key = canonical_key(info.name, k)
            (want === nothing || key in want) || continue
            out[key] = lv[i] == 0 ? 0.0 : lv[i]
        end
    end
    return out
end
solution_levels(dir::AbstractString; kwargs...) = solution_levels(load_dump(dir); kwargs...)
