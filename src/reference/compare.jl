# Layer 1 (data) parity: compare symbols of two dumps, or TIMES.jl data with a dump.

"""
    Mismatch

One difference between two symbols. `kind` is one of

- `:missing_left` / `:missing_right`: the record exists only on the other side
  (for parameters an absent entry counts as 0, so only a non-zero or `EPS`
  value is reported);
- `:value`: numbers differ beyond tolerance;
- `:special`: special values differ (e.g. `EPS` against an ordinary 0);
- `:order`: a one-dimensional set lists its common elements in another order;
- `:dimension` / `:kind`: the symbols are not comparable at all.
"""
struct Mismatch
    symbol::String
    kind::Symbol
    key::Tuple
    column::String
    left::Float64
    right::Float64
    left_special::SpecialValue
    right_special::SpecialValue
end

function Base.show(io::IO, m::Mismatch)
    k = isempty(m.key) ? "" : "(" * join(m.key, ",") * ")"
    print(io, m.symbol, k, " ", m.kind)
    isempty(m.column) || print(io, " [", m.column, "]")
    if m.kind in (:value, :special, :missing_left, :missing_right)
        print(io, ": ", _fmt(m.left, m.left_special), " vs ", _fmt(m.right, m.right_special))
    end
end

_fmt(x, s) = s == SV_NONE ? repr(x) : string(s)[4:end]

"""
    SymbolComparison

Result for one symbol: record counts, number of mismatches by kind, and up to
`max_examples` example mismatches.
"""
struct SymbolComparison
    name::String
    kind::Symbol
    n_left::Int
    n_right::Int
    counts::Dict{Symbol,Int}
    examples::Vector{Mismatch}
end

n_mismatches(c::SymbolComparison) = sum(values(c.counts); init=0)
ispass(c::SymbolComparison) = n_mismatches(c) == 0

"""
    ComparisonReport

Result of [`compare_dumps`](@ref): per-symbol comparisons, plus the symbols
requested that exist on only one side.
"""
struct ComparisonReport
    symbols::Vector{SymbolComparison}
    only_left::Vector{String}
    only_right::Vector{String}
    rtol::Float64
    atol::Float64
end

"""
    ispass(report) -> Bool

`true` when no symbol has a mismatch and no requested symbol is missing on
either side.
"""
ispass(r::ComparisonReport) = isempty(r.only_left) && isempty(r.only_right) && all(ispass, r.symbols)

function Base.show(io::IO, r::ComparisonReport)
    bad = count(!ispass, r.symbols)
    print(io, "ComparisonReport(", length(r.symbols), " symbols compared, ", bad, " with mismatches, ",
          length(r.only_left), " only left, ", length(r.only_right), " only right)")
end

"""
    _numeq(x, y, rtol, atol)

Tolerance test used for every value comparison: infinities must match
exactly; otherwise `|x - y| <= max(atol, rtol * max(|x|, |y|))`.
"""
function _numeq(x::Float64, y::Float64, rtol::Float64, atol::Float64)
    x == y && return true
    (isinf(x) || isinf(y) || isnan(x) || isnan(y)) && return false
    return abs(x - y) <= max(atol, rtol * max(abs(x), abs(y)))
end

struct _Collector
    name::String
    counts::Dict{Symbol,Int}
    examples::Vector{Mismatch}
    max_examples::Int
end

function _add!(c::_Collector, kind, key, col="", l=NaN, r=NaN, ls=SV_NONE, rs=SV_NONE)
    c.counts[kind] = get(c.counts, kind, 0) + 1
    length(c.examples) < c.max_examples &&
        push!(c.examples, Mismatch(c.name, kind, Tuple(key), col, l, r, ls, rs))
    return nothing
end

"""
    compare_symbol(left, right; columns=nothing, rtol=1e-9, atol=0.0,
                   check_order=false, max_examples=10) -> SymbolComparison

Compare two `SymbolRecords` of the same symbol.

- Sets: the sets of label tuples must be equal; element text is ignored. With
  `check_order=true` a one-dimensional set must also list its common elements
  in the same order (GAMS ordered-set semantics).
- Parameters: an absent entry equals `0.0`, as GAMS does not store zeros; an
  `EPS` entry is not equal to an absent one.
- Variables and equations: records must exist on both sides; `columns`
  restricts which attributes are compared (default: all present on both).

Special values must match exactly; `+INF`/`-INF` must match exactly. The
default tolerance is the layer-1 tolerance of the translation guide
(relative 1e-9) with no absolute slack.
"""
function compare_symbol(a::SymbolRecords{N}, b::SymbolRecords{M}; columns=nothing, rtol::Real=1e-9,
                        atol::Real=0.0, check_order::Bool=false, max_examples::Int=10) where {N,M}
    name = a.info.name
    c = _Collector(name, Dict{Symbol,Int}(), Mismatch[], max_examples)
    kind = a.info.kind
    if N != M
        _add!(c, :dimension, ())
        return SymbolComparison(name, kind, length(a), length(b), c.counts, c.examples)
    end
    if (kind == :set) != (b.info.kind == :set)
        _add!(c, :kind, ())
        return SymbolComparison(name, kind, length(a), length(b), c.counts, c.examples)
    end
    if kind == :set
        _compare_sets!(c, a, b, check_order)
    else
        _compare_numeric!(c, a, b, columns, Float64(rtol), Float64(atol), kind == :parameter)
    end
    return SymbolComparison(name, kind, length(a), length(b), c.counts, c.examples)
end

function _compare_sets!(c::_Collector, a::SymbolRecords{N}, b::SymbolRecords{N}, check_order::Bool) where {N}
    sa = Set(a.keys)
    sb = Set(b.keys)
    for k in a.keys
        k in sb || _add!(c, :missing_right, k)
    end
    for k in b.keys
        k in sa || _add!(c, :missing_left, k)
    end
    if check_order && N == 1
        common_a = [k for k in a.keys if k in sb]
        common_b = [k for k in b.keys if k in sa]
        for (ka, kb) in zip(common_a, common_b)
            if ka != kb
                _add!(c, :order, ka)
                break
            end
        end
    end
    return nothing
end

function _compare_numeric!(c::_Collector, a::SymbolRecords{N}, b::SymbolRecords{N}, columns, rtol, atol,
                           absent_is_zero::Bool) where {N}
    cols = columns === nothing ? sort!(collect(intersect(keys(a.values), keys(b.values)))) :
           [String(x) for x in columns]
    idx_b = Dict{NTuple{N,String},Int}(k => i for (i, k) in enumerate(b.keys))
    seen_b = falses(length(b.keys))
    for (i, k) in enumerate(a.keys)
        j = get(idx_b, k, 0)
        if j == 0
            if absent_is_zero
                for col in cols
                    v, s = a.values[col][i], a.special[col][i]
                    (s == SV_NONE && v == 0.0) || _add!(c, :missing_right, k, col, v, 0.0, s, SV_NONE)
                end
            else
                _add!(c, :missing_right, k)
            end
            continue
        end
        seen_b[j] = true
        for col in cols
            va, sa = a.values[col][i], a.special[col][i]
            vb, sb = b.values[col][j], b.special[col][j]
            if sa != sb
                _add!(c, :special, k, col, va, vb, sa, sb)
            elseif sa == SV_NONE && !_numeq(va, vb, rtol, atol)
                _add!(c, :value, k, col, va, vb, sa, sb)
            end
        end
    end
    for (j, k) in enumerate(b.keys)
        seen_b[j] && continue
        if absent_is_zero
            for col in cols
                v, s = b.values[col][j], b.special[col][j]
                (s == SV_NONE && v == 0.0) || _add!(c, :missing_left, k, col, 0.0, v, SV_NONE, s)
            end
        else
            _add!(c, :missing_left, k)
        end
    end
    return nothing
end

"""
    compare_dumps(left, right; symbols=nothing, kinds=(:set, :parameter),
                  rtol=1e-9, atol=0.0, check_order=true, max_examples=10)

Compare two dumps symbol by symbol. `symbols` (names, case-insensitive)
defaults to every symbol of the requested `kinds` found in either dump;
symbols found on only one side are listed in `only_left`/`only_right`.
`check_order` applies to one-dimensional sets.
"""
function compare_dumps(a::ReferenceDump, b::ReferenceDump; symbols=nothing, kinds=(:set, :parameter),
                       rtol::Real=1e-9, atol::Real=0.0, check_order::Bool=true, max_examples::Int=10,
                       columns=nothing)
    names = if symbols === nothing
        ks = Set{String}()
        for d in (a, b), (k, info) in d.symbols
            info.kind in kinds && push!(ks, k)
        end
        sort!(collect(ks))
    else
        sort!(unique(uppercase.(String.(symbols))))
    end
    results = SymbolComparison[]
    only_l, only_r = String[], String[]
    for n in names
        ha, hb = haskey(a.symbols, n), haskey(b.symbols, n)
        if ha && !hb
            push!(only_l, a.symbols[n].name)
        elseif hb && !ha
            push!(only_r, b.symbols[n].name)
        elseif ha && hb
            push!(results, compare_symbol(read_symbol(a, n), read_symbol(b, n); rtol, atol, check_order,
                                          max_examples, columns))
        end
    end
    return ComparisonReport(results, only_l, only_r, Float64(rtol), Float64(atol))
end

"""
    summary_table(report; only_failures=true) -> String

Plain-text table of a comparison report, one line per symbol.
"""
function summary_table(r::ComparisonReport; only_failures::Bool=true)
    io = IOBuffer()
    println(io, "rtol=", r.rtol, " atol=", r.atol, "  ", ispass(r) ? "PASS" : "FAIL")
    for s in r.symbols
        (only_failures && ispass(s)) && continue
        kinds = join(("$(k)=$(v)" for (k, v) in sort!(collect(s.counts))), " ")
        println(io, rpad(s.name, 24), " ", rpad(string(s.kind), 10), " left=", s.n_left, " right=", s.n_right,
                "  ", isempty(kinds) ? "ok" : kinds)
        for m in s.examples
            println(io, "    ", m)
        end
    end
    isempty(r.only_left) || println(io, "only in left: ", join(r.only_left, ", "))
    isempty(r.only_right) || println(io, "only in right: ", join(r.only_right, ", "))
    return String(take!(io))
end
