# M1.2 infrastructure: GAMS sets and parameters computed by TIMES.jl.
#
# The coefficient stage (maindrv.mod L62-73, v4.9.7: coefmain.mod and the
# extensions' coef_ext) starts from the GAMS state that the ppm dump holds
# (maindrv.mod L56-58) and assigns sets and parameters the way GAMS
# statements do. A computed symbol replaces the dump's record of it in the
# TimesModel's data (`gput!`), so every later `gset`/`gparam` reads the new
# value, as later GAMS statements read the assigned one.

"""
    gassign!(vals, key, x::GNum) -> vals

One GAMS parameter assignment `P(key) = x`: an exact zero removes the entry
(GAMS stores no zero), EPS is stored as an EPS entry (0.0, see
[`GamsParam`](@ref)), any other value as itself.
"""
function gassign!(vals::Dict{NTuple{N,String},Float64}, k::NTuple{N,String}, x::GNum) where {N}
    iszero(x) ? delete!(vals, k) : (vals[k] = x.eps ? 0.0 : x.v)
    return vals
end
gassign!(vals::Dict{NTuple{N,String},Float64}, k::NTuple{N,String}, x::Real) where {N} =
    gassign!(vals, k, GNum(x))

"""
    gv(vals::Dict, key) -> GNum

`gv` on a values dictionary being assigned (from `gvalues`): absent is 0,
0.0 is EPS.
"""
function gv(d::Dict{NTuple{N,String},Float64}, k::NTuple{N,String}) where {N}
    v = get(d, k, nothing)
    return v === nothing ? GZERO : v == 0.0 ? GEPS : GNum(v)
end

"""
    gvalues(tm, name, N) -> Dict

A mutable copy of parameter `name`'s entries (EPS as 0.0), empty when the
dump does not declare it: the starting point of an assignment statement.
"""
gvalues(tm, name::AbstractString, N::Int) = copy(gparam_opt(tm.data, name, N).values)

"""
    gmembers(tm, name, N) -> Set

A mutable copy of set `name`'s members, empty when the dump does not declare it.
"""
gmembers(tm, name::AbstractString, N::Int) = copy(gset_opt(tm.data, name, N).members)

"""
    gput!(tm, name, vals::Dict{NTuple{N,String},Float64}) -> GamsParam
    gput!(tm, name, members::AbstractSet{NTuple{N,String}}) -> GamsSet

Store a computed parameter or set as the current value of `name`, records in
GAMS order (`gams_sort!`), replacing what the dump held.
"""
function gput!(tm, name::AbstractString, vals::Dict{NTuple{N,String},Float64}) where {N}
    keys = collect(Base.keys(vals))
    gams_sort!(keys, tm.data)
    p = GamsParam{N}(uppercase(name), keys, vals)
    tm.data.params[uppercase(name)] = p
    return p
end
function gput!(tm, name::AbstractString, members::AbstractSet{NTuple{N,String}}) where {N}
    keys = collect(members)
    gams_sort!(keys, tm.data)
    s = GamsSet{N}(uppercase(name), keys, Set(keys))
    tm.data.sets[uppercase(name)] = s
    return s
end

"""
    Layer1Diff

Result of [`layer1`](@ref) for one symbol: counts on each side, entries only
on one side, values that differ beyond the tolerance (EPS differs from any
nonzero value), and a few examples.
"""
struct Layer1Diff
    name::String
    kind::Symbol
    n_mine::Int
    n_ref::Int
    only_mine::Int
    only_ref::Int
    values::Int
    examples::Vector{String}
end

Reference.ispass(d::Layer1Diff) = d.only_mine == 0 && d.only_ref == 0 && d.values == 0
Base.show(io::IO, d::Layer1Diff) =
    print(io, d.name, ": ", Reference.ispass(d) ? "PASS" : "FAIL", " (", d.n_mine, " vs ", d.n_ref,
          d.only_mine > 0 ? ", only TIMES.jl $(d.only_mine)" : "", d.only_ref > 0 ? ", only GAMS $(d.only_ref)" : "",
          d.values > 0 ? ", values $(d.values)" : "", ")")

"""
    layer1(tm, ref::DumpData, names; rtol=1e-9, max_examples=5) -> Vector{Layer1Diff}

Layer 1 of the translation guide for the symbols `names`: the current value
of each in `tm` (computed, or the dump's if not computed) against the GAMS
dump `ref` (e.g. the harness's `coef/` dump). Labels compare case-
insensitively, as in GAMS; values with relative tolerance `rtol`.
`exclude[name]`, a predicate on a record's key, leaves records out on both
sides (records a later GAMS statement overwrites).
"""
function layer1(tm, ref::DumpData, names; rtol::Real=1e-9, max_examples::Int=5,
                exclude::AbstractDict=Dict{String,Function}())
    out = Layer1Diff[]
    for name in names
        skip = get(exclude, uppercase(name), k -> false)
        info = get(ref.dump.symbols, uppercase(name), nothing)
        info === nothing && throw(ArgumentError("$name is not in the reference dump"))
        N = info.dimension
        lc(k) = map(lowercase, k)
        ex = String[]
        note(s) = length(ex) < max_examples && push!(ex, s)
        if info.kind == :set
            a = Set(lc(k) for k in gset_opt(tm.data, name, N).keys if !skip(k))
            b = Set(lc(k) for k in gset(ref, name).keys if !skip(k))
            oa, ob = setdiff(a, b), setdiff(b, a)
            foreach(k -> note("only TIMES.jl $(k)"), oa); foreach(k -> note("only GAMS $(k)"), ob)
            push!(out, Layer1Diff(uppercase(name), :set, length(a), length(b), length(oa), length(ob), 0, ex))
        else
            a = Dict(lc(k) => v for (k, v) in gparam_opt(tm.data, name, N).values if !skip(k))
            b = Dict(lc(k) => v for (k, v) in gparam(ref, name).values if !skip(k))
            oa = [k for k in keys(a) if !haskey(b, k)]
            ob = [k for k in keys(b) if !haskey(a, k)]
            foreach(k -> note("only TIMES.jl $(k) = $(a[k] == 0 ? "EPS" : a[k])"), oa)
            foreach(k -> note("only GAMS $(k) = $(b[k] == 0 ? "EPS" : b[k])"), ob)
            nv = 0
            for (k, x) in a
                y = get(b, k, nothing)
                y === nothing && continue
                same = (x == 0) == (y == 0) && isapprox(x, y; rtol=rtol)
                same || (nv += 1; note("$(k): $(x == 0 ? "EPS" : x) vs $(y == 0 ? "EPS" : y)"))
            end
            push!(out, Layer1Diff(uppercase(name), :parameter, length(a), length(b), length(oa), length(ob), nv, ex))
        end
    end
    return out
end
