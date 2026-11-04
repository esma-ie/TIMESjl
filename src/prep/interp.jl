# M1.3 (6a): the interpolation macros of preppm.mod: prepparm.gms (options and
# defaults for cost and bound parameters), fillparm.gms (default
# interpolation of the regular parameters) and filparam.gms (dense
# interpolation), $BATINCLUDEd once per parameter by preppm.mod L76-211 and
# prepret.dsc L25-28, and by prep_ext.vda and equcrtp.vda PREP_EXT (6b);
# (7a) preshape.gms (the SHAPE and multiplier indexes), $BATINCLUDEd by
# preppm.mod L222-233.
#
# GAMS: prepparm.gms L1-77, fillparm.gms L1-57, filparam.gms L1-43,
# preshape.gms L1-49, v4.9.7.
#
# A call passes the macro's arguments as written at the GAMS call site: the
# control sets before the year index (%2) and after it (%3), as their GAMS
# names (an alias such as R or P filters a key position to its set's members,
# ITEM and other aliases of the universe filter nothing); the UNCD7 padding
# (%4); the target years (%5: V, T, PASTMILE, MILESTONYR); the condition on
# the target records (%6, a function of the parameter key); and the rest by
# keyword. The option of a record is the parameter's value at year '0'
# (%DFLBL%, initmty.mod L367).
#
# Rows (the UNCD7 tuples) run in GAMS order; data years run in the order of
# DM_YEAR (or %5) as GAMS iterates them, the ALLYEAR order. EPS counts as a
# data point (`$MY_ARRAY(DM_YEAR)`, G3) and `IF(LAST_VAL, ...)` is true for
# an EPS (G12, G25); `$=` writes only a nonzero or EPS value (G24); a
# statement reads the values from before it (G11). ROUND(EPS) is a plain 0
# (G38). The scratch the macros leave (UNCD7, MY_ARRAY, MY_FIL2 and the
# scalars CNT, DFUNC, MY_F, F, Z, LAST_VAL, FIRST_VAL, MY_FYEAR) is carried in
# `InterpState` and stored when the caller is done, as GAMS leaves it.

"""
    InterpState

What the interpolation macros read besides the parameter itself (the year
sets of preppm.mod L17-25, the defaults of L55-56, G_NOINTERP) and the
scratch they leave behind, carried from one call to the next as in GAMS.
`reset` is %RESET% (0 in preppm.mod, L9).
"""
mutable struct InterpState
    tm::Any
    ax::YearAxis
    dm_year::Vector{String}               # DM_YEAR in GAMS order
    dm_set::Set{String}
    datayear::Set{String}
    my_fil::Vector{String}                # MY_FIL in GAMS order
    fil2::Dict{Tuple{String},Float64}
    miyr_1::Vector{String}
    def_iebd::Float64                     # %DEF_IEBD% (preppm.mod L55)
    reset::Float64                        # %RESET%
    g_nointerp::Bool
    int_default::Set{Tuple{String}}
    ie_default::Dict{Tuple{String},Float64}
    ctl::Dict{String,Union{Nothing,Set{String}}}
    CNT::GNum
    DFUNC::GNum
    MY_F::GNum
    F::GNum
    Z::GNum
    LAST_VAL::GNum
    FIRST_VAL::GNum
    MY_FYEAR::GNum
    my_array::Dict{Tuple{String},Float64}
    my_fil2::Dict{Tuple{String},Float64}
    uncd7::Set{NTuple{7,String}}
end

const INTERP_SCALARS = ("CNT", "DFUNC", "MY_F", "F", "Z", "LAST_VAL", "FIRST_VAL", "MY_FYEAR")

"""
    InterpState(tm; reset=0.0) -> InterpState

The state for the macros on `tm`, read after preppm.mod L17-25 and L55-56
have set DM_YEAR, DATAYEAR, MY_FIL, FIL2 and IE_DEFAULT. The scratch starts
from what `tm` holds.
"""
function InterpState(tm; reset=0.0)
    ax = YearAxis(tm)
    dm = gset_opt(tm.data, "DM_YEAR", 1).members
    myf = gset_opt(tm.data, "MY_FIL", 1).members
    miyr = gset_opt(tm.data, "MIYR_1", 1).members
    sc(n) = gv(gparam_opt(tm.data, n, 0), ())
    st = InterpState(tm, ax, [y for y in ax.years if (y,) in dm], Set(k[1] for k in dm),
                     Set(k[1] for k in gset_opt(tm.data, "DATAYEAR", 1).members),
                     [y for y in ax.years if (y,) in myf], gvalues(tm, "FIL2", 1), [y for y in ax.years if (y,) in miyr],
                     parse(Float64, strip(gswitch(tm, "DEF_IEBD", "10"))), Float64(reset),
                     !iszero(gscalar(tm, "G_NOINTERP")), gmembers(tm, "INT_DEFAULT", 1), gvalues(tm, "IE_DEFAULT", 1),
                     Dict{String,Union{Nothing,Set{String}}}(),
                     sc("CNT"), sc("DFUNC"), sc("MY_F"), sc("F"), sc("Z"), sc("LAST_VAL"), sc("FIRST_VAL"), sc("MY_FYEAR"),
                     gvalues(tm, "MY_ARRAY", 1), gvalues(tm, "MY_FIL2", 1), gmembers(tm, "UNCD7", 7))
    return st
end

"Store the macros' scratch in `tm`, as GAMS leaves it."
function put_interp_scratch!(st::InterpState)
    tm = st.tm
    for n in INTERP_SCALARS
        x = getfield(st, Symbol(n))
        gput!(tm, n, iszero(x) ? Dict{Tuple{},Float64}() : Dict{Tuple{},Float64}(() => x.v))   # EPS is stored as 0.0
    end
    gput!(tm, "MY_ARRAY", st.my_array)
    gput!(tm, "MY_FIL2", st.my_fil2)
    gput!(tm, "UNCD7", st.uncd7)
    gput!(tm, "INT_DEFAULT", st.int_default)
    return tm
end

"The members of the set a control index names (an alias resolved); `nothing` for the universe."
function ctlset(st::InterpState, name::AbstractString)
    return get!(st.ctl, name) do
        info = st.tm.data.dump.symbols[uppercase(name)]
        target = info.kind == :alias ? info.alias_with : info.name
        target == "*" ? nothing : Set{String}(k[1] for k in gset(st.tm, target).keys)
    end
end
"The filters of a comma-separated list of control indices (`'P,TS,BD'`, `'UC_N,R,'`)."
ctlsets(st::InterpState, spec::AbstractString) = [ctlset(st, strip(s)) for s in split(spec, ',') if !isempty(strip(s))]

"Whether key `k` passes the control-set filters `fs` (the year position holds `nothing`)."
passes(k, fs) = all(i -> fs[i] === nothing || k[i] in fs[i], eachindex(fs))

grnd(x::GNum) = GNum(round(x.v, RoundNearestTiesAway))       # ROUND; ROUND(EPS) is a plain 0 (G38)
gyear(y::Real) = GNum(Float64(y))

# MY_ARRAY(DM_YEAR) = %1(%2,DM_YEAR,%3): the row's data years (EPS included) in DM_YEAR order
function row_array(st::InterpState, P, row, yi)
    out = Tuple{String,GNum}[]
    for y in st.dm_year
        k = Base.setindex(row, y, yi)
        haskey(P, k) && push!(out, (y, gv(P, k)))
    end
    return out
end

# MY_ARRAY after a macro call: the last row's values on DM_YEAR, the rest as before
function set_my_array!(st::InterpState, arr)
    foreach(y -> delete!(st.my_array, (y,)), st.dm_year)
    foreach(((y, x),) -> (st.my_array[(y,)] = x.v), arr)
end

"""
    fillparm!(st, name, pre, post, pad, years, cond, test; cache=false)

fillparm.gms with the arguments of one `\$BATINCLUDE fillparm` call: `name`
(%1), the control indices `pre` (%2) and `post` (%3), the UNCD7 padding `pad`
(%4, labels), the target years `years` (%5, labels), the condition `cond(k)`
on the key of a target record (%6) and the test `test(dfunc, k)` on the
option (%7, `DFUNC GE 0`); `cache` when %8 names a write cache.

Default (no option): linear interpolation between the data years and
constant extrapolation both ways. Options (`ROUND(%1(...,'0',...))`): 1
interpolation only; 2 EPS outside the data; 3 interpolation and
extrapolation; 4 no forward, 5 no backward extrapolation; 11-15 as their last
digit; above 999 exponential beyond that year (the data then a growth rate).

GAMS: fillparm.gms L20-56, v4.9.7.
"""
function fillparm!(st::InterpState, name, pre, post, pad, years, cond, test; cache::Bool=false)
    # L26: IF(NOT G_NOINTERP, ...): the whole macro, the option reset (L54) included
    st.g_nointerp && return st
    fpre, fpost = ctlsets(st, pre), ctlsets(st, post)
    fs = vcat(fpre, Union{Nothing,Set{String}}[nothing], fpost)
    P = gvalues(st.tm, name, length(fs))
    _fillparm!(st, P, fs, length(fpre) + 1, String.(pad), years, cond, test, cache)
    gput!(st.tm, name, P)
    return st
end

function _fillparm!(st::InterpState, P::Dict{NTuple{N,String},Float64}, fs, yi, pad, years, cond, test, cache) where {N}
    ax, yv = st.ax, st.ax.yearval
    dfl = "0"                                                   # %DFLBL%
    uncd7(row) = NTuple{7,String}((row[1:yi-1]..., row[yi+1:N]..., pad...))
    # L26-27: OPTION CLEAR=UNCD7; LOOP(DATAYEAR, UNCD7(%2,%3%4)$%1(%2,DATAYEAR,%3) = YES)
    rowset = Set{NTuple{N,String}}()
    for k in keys(P)
        (k[yi] in st.datayear && passes(k, fs)) && push!(rowset, Base.setindex(k, dfl, yi))
    end
    rows = gams_sort!(collect(rowset), st.tm.data)
    st.uncd7 = Set{NTuple{7,String}}(uncd7(r) for r in rows)
    C = Dict{NTuple{N,String},Float64}()                       # %8, the write cache
    last_arr = nothing
    # L28: LOOP(UNCD7(%2,%3%4), DFUNC = ROUND(%1(%2,'%DFLBL%',%3));
    for row in rows
        dfunc = grnd(gv(P, row))
        st.DFUNC = dfunc
        # L29: IF(DFUNC %7, OPTION CLEAR=MY_FIL2; CNT = (DFUNC LE 999);
        test(dfunc.v, row) || continue
        my_fil2 = Dict{Tuple{String},Float64}()
        cnt = dfunc.v <= 999
        st.CNT = GNum(cnt ? 1.0 : 0.0)
        # L30: MY_ARRAY(DM_YEAR) = %1(%2,DM_YEAR,%3); LAST_VAL=0; F = 0; Z = 0;
        arr = row_array(st, P, row, yi)
        last_arr = arr
        last_val, F, Z = GZERO, 0.0, 0.0
        my_f, first_val, my_fyear = st.MY_F, st.FIRST_VAL, st.MY_FYEAR.v
        # L32-44: LOOP(DM_YEAR$MY_ARRAY(DM_YEAR), ...)
        for (y, x) in arr
            my_f = x
            Z = yv[y]
            if !iszero(last_val)                                # IF(LAST_VAL, ...): EPS is true
                if cnt || Z <= dfunc.v
                    # L36-37: linear interpolation of the years strictly between, into %1 or MY_FIL2 (%ITEM%)
                    for t in years
                        yt = yv[t]
                        (Z > yt && yt > my_fyear) || continue
                        x5 = last_val + (my_f - last_val) / gyear(Z - my_fyear) * gyear(yt - my_fyear)
                        cache ? gassign!(my_fil2, (t,), x5) : gassign!(P, Base.setindex(row, t, yi), x5)
                    end
                else
                    # L39-42: exponential growth at rate MY_F from the last value; the data point is overwritten
                    for t in years
                        yt = yv[t]
                        (Z > yt && yt > my_fyear) || continue
                        x5 = last_val * gpower(GNum(1.0) + my_f, glead(yt - my_fyear)) + GEPS
                        cache ? gassign!(my_fil2, (t,), x5) : gassign!(P, Base.setindex(row, t, yi), x5)
                    end
                    my_f = last_val * gpower(GNum(1.0) + my_f, glead(Z - my_fyear)) + GEPS
                    gassign!(P, Base.setindex(row, y, yi), my_f)
                end
            else
                F, first_val = Z, my_f                          # L43
            end
            last_val, my_fyear = my_f, Z                        # L44
        end
        d = dfunc.v
        # L45-47: IF(DFUNC GT 1, IF(CNT, DFUNC=MOD(DFUNC,10); 2: EPS both ways; 4: Z=INF; 5: F=0))
        if d > 1 && cnt
            d = rem(d, 10)
            if d == 2
                first_val, last_val = GEPS, GEPS
            elseif d == 4
                Z = Inf
            elseif d == 5
                F = 0.0
            end
        end
        if d != 1
            # L50: %DATA%$%6 $= FIRST_VAL$(YEARVAL(%5) LT F) %ADD% + LAST_VAL$(YEARVAL(%5) GT Z)
            for t in years
                k = Base.setindex(row, t, yi)
                cond(k) || continue
                yt = yv[t]
                x5 = cache ? gif(first_val, yt < F) + gv(my_fil2, (t,)) + gif(last_val, yt > Z) :
                             gif(first_val, yt < F) + gif(last_val, yt > Z)
                iszero(x5) || gassign!(cache ? C : P, k, x5)
            end
        elseif cache
            # L51: ELSE %DATA%$%6 $= MY_FIL2(%5)
            for t in years
                k = Base.setindex(row, t, yi)
                (cond(k) && haskey(my_fil2, (t,))) && gassign!(C, k, gv(my_fil2, (t,)))
            end
        end
        st.DFUNC = GNum(d)
        st.MY_F, st.F, st.Z, st.LAST_VAL, st.FIRST_VAL, st.MY_FYEAR = my_f, gyear(F), gyear(Z), last_val, first_val, gyear(my_fyear)
        st.my_fil2 = my_fil2
    end
    last_arr === nothing || set_my_array!(st, last_arr)
    # L54: %1(%2,'%DFLBL%',%3)$%1(%2,'%DFLBL%',%3) = MIN(%RESET%,%1(%2,'%DFLBL%',%3))
    for k in collect(keys(P))
        (k[yi] == dfl && passes(k, fs)) || continue
        gassign!(P, k, gmin(GNum(st.reset), gv(P, k)))
    end
    # L55: %1(%2,%5,%3) $= %8(%2,%3,%5); OPTION KILL = %8
    for (k, v) in C
        P[k] = v
    end
    return P
end

"""
    prepparm!(st, name, pre, post, pad, years, cond, opt7; iebd=nothing, cache=false, arg10="")

prepparm.gms with the arguments of one `\$BATINCLUDE prepparm` call: `name`
(%1), `pre` and `post` (%2, %3), `pad` (%4), `years` (%5), `cond(k)` (%6),
`opt7` (%7: 0 for a cost parameter, 1 for a bound, EPS for DAM_COST), `iebd`
(%8, the default option in place of %DEF_IEBD%), `cache` (%9 names a write
cache) and `arg10` (%10: "" , "+" or "-ABS").

A cost parameter (%7 = 0) is processed only where it has an option above 0
(COEF_OBJ interpolates it later); a bound by default (option 10) moves the
data of years inside a period to the period's milestone when that has none.
Options as in fillparm, and 11-19 also fill the first period from the
first data point and the last from the last (the MIYR_1 rule, L58-62); -13
deletes the data on the target years; below -0.5 the record is left alone.

GAMS: prepparm.gms L20-76, v4.9.7.
"""
function prepparm!(st::InterpState, name, pre, post, pad, years, cond, opt7::GNum;
                   iebd=nothing, cache::Bool=false, arg10::AbstractString="")
    fpre, fpost = ctlsets(st, pre), ctlsets(st, post)
    fs = vcat(fpre, Union{Nothing,Set{String}}[nothing], fpost)
    P = gvalues(st.tm, name, length(fs))
    # L25: IF(G_NOINTERP, INT_DEFAULT('%1')=NO; ELSE ...)
    if st.g_nointerp
        delete!(st.int_default, (String(name),))
    else
        _prepparm!(st, String(name), P, fs, length(fpre) + 1, String.(pad), years, cond, opt7,
                   iebd === nothing ? st.def_iebd : Float64(iebd), cache, arg10)
    end
    # L76: %1(%2,'EMPTY',%3)=0: EMPTY is a $PHANTOM label (initsys.mod L20), never a record
    gput!(st.tm, name, P)
    return st
end

function _prepparm!(st::InterpState, name, P::Dict{NTuple{N,String},Float64}, fs, yi, pad, years, cond, opt7, def_iebd,
                    cache, arg10) where {N}
    ax, yv = st.ax, st.ax.yearval
    dfl = "0"
    yset = Set(years)
    noncost = !(opt7 == GZERO)                                  # L21: $IF NOT %7 == 0 (the literal; EPS is not 0)
    # L26: OPTION CLEAR=UNCD7; CNT = (%DEF_IEBD%+(3-%DEF_IEBD%)$IE_DEFAULT('%1'))$%7
    cnt = iszero(opt7) ? 0.0 : def_iebd + (iszero(gv(st.ie_default, (name,))) ? 0.0 : 3 - def_iebd)
    st.CNT = GNum(cnt)
    opt(row) = gv(P, row)
    rowof(k) = Base.setindex(k, dfl, yi)
    rowset = Set{NTuple{N,String}}()
    if cnt == 0
        # L27: UNCD7(%2%LL%,%3%4)$(%1(%2,'%DFLBL%',%3)>0) = YES
        for k in keys(P)
            (k[yi] == dfl && passes(k, fs) && P[k] > 0) && push!(rowset, k)
        end
    else
        # L28-29: the -13 option deletes the data on the target years
        del = NTuple{N,String}[]
        for k in keys(P)
            (k[yi] in yset && passes(k, fs) && opt(rowof(k)).v == -13) && push!(del, k)   # $= %1: EPS counts (G24)
        end
        foreach(k -> delete!(P, k), del)
        # L30: UNCD7(%2,LL--ORD(LL),%3%4)$((%10(%1(%2,'%DFLBL%',%3))>-.5)$%1(%2,LL,%3))=YES   (LL--ORD(LL) is '0', G31)
        for k in keys(P)
            passes(k, fs) || continue
            o = opt(rowof(k)).v
            (arg10 == "-ABS" ? -abs(o) : o) > -0.5 && push!(rowset, rowof(k))
        end
    end
    rows = gams_sort!(collect(rowset), st.tm.data)
    st.uncd7 = Set{NTuple{7,String}}(NTuple{7,String}(((noncost ? r : (r[1:yi-1]..., r[yi+1:N]...))..., pad...)) for r in rows)
    C = Dict{NTuple{N,String},Float64}()                       # %9, the write cache
    last_arr = nothing
    # L32: LOOP(UNCD7(%2%LL%,%3%4), DFUNC = CNT; DFUNC $= ROUND(%1(%2,'%DFLBL%',%3));
    for row in rows
        r = grnd(opt(row))
        dfunc = iszero(r) ? GNum(cnt) : r
        # L33: MY_ARRAY(DM_YEAR) = %1(%2,DM_YEAR,%3); OPTION CLEAR=MY_FIL2;
        arr = row_array(st, P, row, yi)
        last_arr = arr
        arrd = Dict(arr)
        myarr(y) = (y in st.dm_set) ? get(arrd, y, GZERO) : gv(st.my_array, (y,))   # MY_ARRAY(y) during the row
        my_fil2 = Dict{Tuple{String},Float64}()
        my_f, first_val, last_val = st.MY_F, st.FIRST_VAL, st.LAST_VAL
        F, Z, my_fyear = st.F.v, st.Z.v, st.MY_FYEAR.v
        if dfunc.v != 10
            # L35-49: interpolation between the data years into MY_FIL2
            last_val, F, Z = GZERO, 0.0, 0.0
            for (y, x) in arr
                my_f = x
                Z = yv[y]
                if !iszero(last_val)
                    if dfunc.v > 999 && Z > dfunc.v
                        # L40-43: exponential from the last value at the rate MY_F; MY_FIL2 at the data year too
                        for t in years
                            yt = yv[t]
                            (Z > yt && yt > my_fyear) || continue
                            gassign!(my_fil2, (t,), last_val * gpower(GNum(1.0) + my_f, glead(yt - my_fyear)) + GEPS)
                        end
                        my_f = last_val * gpower(GNum(1.0) + my_f, glead(Z - my_fyear)) + GEPS
                        gassign!(my_fil2, (y,), my_f)
                    else
                        # L45-46: linear
                        for t in years
                            yt = yv[t]
                            (Z > yt && yt > my_fyear) || continue
                            gassign!(my_fil2, (t,), last_val + (my_f - last_val) / gyear(Z - my_fyear) * gyear(yt - my_fyear))
                        end
                    end
                else
                    F, first_val = Z, my_f                      # L48
                end
                last_val, my_fyear = my_f, Z                    # L49
            end
        elseif noncost
            # L50-56: intra-period: a data year inside a period (MY_FIL) moves to the period's milestone
            first_val, my_fyear = GZERO, 0.0
            for ll in st.my_fil
                haskey(arrd, ll) || continue                    # LOOP(MY_FIL(LL)$MY_ARRAY(MY_FIL), ...)
                my_f = arrd[ll]
                Z = yv[ll]
                F = gv(st.fil2, (ll,)).v
                if my_fyear < F
                    # L53: IF(F > MIN(FIRST_VAL,Z), LAST_VAL = MY_F; FIRST_VAL = F)  (FIRST_VAL holds a year here)
                    F > gmin(first_val, gyear(Z)).v && ((last_val, first_val) = (my_f, gyear(F)))
                    # L54: MY_FIL2(%5(LL+(F-YEARVAL(LL))))$(NOT MY_ARRAY(%5)) = LAST_VAL+(MY_F-LAST_VAL)/(Z-MY_FYEAR)*(F-MY_FYEAR)
                    t = lead(ax, ll, glead(F - yv[ll]))
                    if t !== nothing && t in yset && iszero(myarr(t))
                        gassign!(my_fil2, (t,), last_val + (my_f - last_val) / gyear(Z - my_fyear) * gyear(F - my_fyear))
                    end
                end
                last_val, my_fyear = my_f, Z                    # L55
            end
            dfunc = opt7                                        # L56: DFUNC = %7
        end
        # L58-62 (bounds): IF(FLOOR(DFUNC/10)=1, the MIYR_1 rule; DFUNC=DFUNC-10)
        if noncost && floor(dfunc.v / 10) == 1
            for ll in st.miyr_1
                my_fyear = yv[ll]
                # L60: MY_F = FIL2(LL+(F-MY_FYEAR)); IF(MY_F<F$MY_F, MY_FIL2(%5(LL+(MY_F-MY_FYEAR))) = FIRST_VAL)
                l1 = lead(ax, ll, glead(F - my_fyear))
                my_f = l1 === nothing ? GZERO : gv(st.fil2, (l1,))
                if my_f.v < (iszero(my_f) ? 0.0 : F)
                    t = lead(ax, ll, glead(my_f.v - my_fyear))
                    (t !== nothing && t in yset) && gassign!(my_fil2, (t,), first_val)
                end
                # L61: MY_F = FIL2(LL+(Z-MY_FYEAR)); IF(MY_F>Z, MY_FIL2(%5(LL+(MY_F-MY_FYEAR))) = LAST_VAL)
                l2 = lead(ax, ll, glead(Z - my_fyear))
                my_f = l2 === nothing ? GZERO : gv(st.fil2, (l2,))
                if my_f.v > Z
                    t = lead(ax, ll, glead(my_f.v - my_fyear))
                    (t !== nothing && t in yset) && gassign!(my_fil2, (t,), last_val)
                end
            end
            dfunc = dfunc - GNum(10.0)
        end
        # L63-69: IF(DFUNC NE %7, extrapolate, or fill in with EPS)
        if dfunc.v != opt7.v
            # %DATA%$(%6$(NOT %DATA%+MY_ARRAY(%5))) = EPS: NOT (a+b) (G19), and EPS+EPS is EPS (G6)
            fill_eps!() = for t in years
                k = Base.setindex(row, t, yi)
                (cond(k) && iszero(gv(my_fil2, (t,)) + myarr(t))) && gassign!(my_fil2, (t,), GEPS)
            end
            if dfunc.v <= 2
                fill_eps!()                                     # L65
            else
                dfunc.v == 4 ? (Z = Inf) : dfunc.v == 5 && (F = 0.0)   # L66
                # L67: %DATA%$(%6) $= FIRST_VAL$(YEARVAL(%5)<F) + LAST_VAL$(YEARVAL(%5)>Z)
                for t in years
                    cond(Base.setindex(row, t, yi)) || continue
                    x5 = gif(first_val, yv[t] < F) + gif(last_val, yv[t] > Z)
                    iszero(x5) || gassign!(my_fil2, (t,), x5)
                end
                # L68: IF((NOT %7)$LAST_VAL, ... = EPS): NOT EPS is false (G25)
                (iszero(opt7) && !iszero(last_val)) && fill_eps!()
            end
        end
        # L70: %1(%2,%5,%3) $= %DATA%;  L71 (cache): %9(%2,%3,%5)$(%6) $= %DATA%
        for t in years
            haskey(my_fil2, (t,)) || continue
            k = Base.setindex(row, t, yi)
            if cache
                cond(k) && gassign!(C, k, gv(my_fil2, (t,)))
            else
                gassign!(P, k, gv(my_fil2, (t,)))
            end
        end
        st.DFUNC = dfunc
        st.MY_F, st.F, st.Z, st.LAST_VAL, st.FIRST_VAL, st.MY_FYEAR = my_f, gyear(F), gyear(Z), last_val, first_val, gyear(my_fyear)
        st.my_fil2 = my_fil2
    end
    last_arr === nothing || set_my_array!(st, last_arr)
    # L74: $IF NOT %10==+  %1(%2,'0',%3)$(MAX(0,%1(%2,'0',%3)-MAX(%7,%RESET%))$%1(%2,'0',%3)) = %RESET%
    if arg10 != "+"
        m = gmax(opt7, GNum(st.reset))
        for k in collect(keys(P))
            (k[yi] == dfl && passes(k, fs)) || continue
            iszero(gmax(GZERO, gv(P, k) - m)) || gassign!(P, k, GNum(st.reset))
        end
    end
    # L75: %1(%2,%5,%3) $= %9(%2,%3,%5); OPTION KILL=%9
    for (k, v) in C
        P[k] = v
    end
    return P
end

"""
    preshape!(st, name, pre, post, pad, years, ctl, cond; def=10)

preshape.gms with the arguments of one `\$BATINCLUDE preshape` call (M1.3,
change 7a): `name` (%1), the control indices `pre` and `post` (%2, %3), the
padding `pad` (%4, labels), the target years `years` (%5), the control-tuple
set `ctl` (%6: "RXX" or "UNCD7"), the condition `cond(k)` on a target record
(%7) and the default option `def` (%8, 10 unless given).

A shape or multiplier index is carried forward as a step: from each data
year (rounded) to the target years before the next, the first value back and
the last forward. Options (`MOD(ROUND(%1(...,'0',...)),1000)`): 10 (the
default) moves the data of years inside a period to the period's milestone
when that has none; 11-19 extrapolate one period each way, then act as their
last digit; 2-9 extrapolate (4 not forward, 5 not backward; 2 with no data
fills EPS); 1 and below only interpolate.

The control tuples are kept in RXX (`(R,'0',P)`, stored in `tm`) or UNCD7
(`st.uncd7`), as GAMS leaves them.

GAMS: preshape.gms L17-48, v4.9.7.
"""
function preshape!(st::InterpState, name, pre, post, pad, years, ctl::AbstractString, cond; def::Real=10)
    fpre, fpost = ctlsets(st, pre), ctlsets(st, post)
    fs = vcat(fpre, Union{Nothing,Set{String}}[nothing], fpost)
    P = gvalues(st.tm, name, length(fs))
    rows = _preshape!(st, P, fs, length(fpre) + 1, years, cond, Float64(def))
    # L20-21: OPTION CLEAR = %6; %6(%2,LL--ORD(LL)%TAIL%%4) $= %1(%2,LL%TAIL%)
    if ctl == "RXX"
        gput!(st.tm, "RXX", Set{NTuple{3,String}}(NTuple{3,String}(r) for r in rows))
    else
        st.uncd7 = Set{NTuple{7,String}}(NTuple{7,String}((r..., String.(pad)...)) for r in rows)
    end
    gput!(st.tm, name, P)
    return st
end

function _preshape!(st::InterpState, P::Dict{NTuple{N,String},Float64}, fs, yi, years, cond, def) where {N}
    ax, yv = st.ax, st.ax.yearval
    dfl = "0"
    yset = Set(years)
    B, E = gvalues(st.tm, "B", 1), gvalues(st.tm, "E", 1)
    # L21: the control tuples, from a record in any year (EPS included, G41); LL--ORD(LL) is '0' (G31)
    rowset = Set{NTuple{N,String}}()
    for k in keys(P)
        passes(k, fs) && push!(rowset, Base.setindex(k, dfl, yi))
    end
    rows = gams_sort!(collect(rowset), st.tm.data)
    last_arr = nothing
    # L22: LOOP(%6(%2,'%DFLBL%'%TAIL%%4), ...)
    for row in rows
        # L23: DFUNC=%DEF%; DFUNC $= MOD(ROUND(%1(%2,'%DFLBL%'%TAIL%)),1000)   (ROUND(EPS) is 0, G38)
        r = rem(grnd(gv(P, row)).v, 1000)
        dfunc = r == 0 ? def : r
        # L24: MY_ARRAY(DM_YEAR) = %1(%2,DM_YEAR%TAIL%)
        arr = row_array(st, P, row, yi)
        last_arr = arr
        arrd = Dict(arr)
        myarr(y) = (y in st.dm_set) ? get(arrd, y, GZERO) : gv(st.my_array, (y,))
        my_f, first_val, last_val = st.MY_F, st.FIRST_VAL, st.LAST_VAL
        F, Z, my_fyear = st.F.v, st.Z.v, st.MY_FYEAR.v
        if dfunc != 10
            # L25-31: F=0; LAST_VAL=0; the rounded value of each data year carried forward over the target years
            F, last_val = 0.0, GZERO
            for (y, x) in arr
                my_f = x
                Z = yv[y]
                if !iszero(last_val)
                    # L29: %1(%2,%5%TAIL%)$((Z>YEARVAL(%5))$(YEARVAL(%5)>MY_FYEAR)) = LAST_VAL
                    for t in years
                        (Z > yv[t] > my_fyear) && gassign!(P, Base.setindex(row, t, yi), last_val)
                    end
                else
                    F, first_val = Z, my_f                      # L30
                end
                last_val, my_fyear = grnd(my_f), Z              # L31: LAST_VAL = ROUND(MY_F)
            end
        else
            # L32-38: intra-period: a data year inside a period (MY_FIL) moves to the period's milestone
            first_val, my_fyear = GZERO, 0.0
            for ll in st.my_fil
                x = myarr(ll)
                iszero(x) && continue                           # LOOP(MY_FIL(LL)$MY_ARRAY(MY_FIL), ...): EPS counts
                my_f = x
                Z = yv[ll]
                F = gv(st.fil2, (ll,)).v
                if my_fyear < F
                    # L35: IF(F>MIN(FIRST_VAL,Z), LAST_VAL = MY_F; FIRST_VAL = F)
                    F > gmin(first_val, gyear(Z)).v && ((last_val, first_val) = (my_f, gyear(F)))
                    # L36: %1(%2,%5(LL+(F-YEARVAL(LL)))%TAIL%)$(NOT MY_ARRAY(%5)) = LAST_VAL
                    t = lead(ax, ll, glead(F - yv[ll]))
                    (t !== nothing && t in yset && iszero(myarr(t))) && gassign!(P, Base.setindex(row, t, yi), last_val)
                end
                last_val, my_fyear = my_f, Z                    # L37
            end
            dfunc = 0.0                                         # L38
        end
        # L40-42: IF(ROUND(DFUNC-5,-1)=10, one period back and forward; DFUNC=DFUNC-10)
        if round((dfunc - 5) / 10, RoundNearestTiesAway) * 10 == 10
            for t in years
                k = Base.setindex(row, t, yi)
                cond(k) || continue
                x5 = gif(first_val, yv[t] < F && gv(E, (t,)).v >= F) + gif(last_val, yv[t] > Z && gv(B, (t,)).v <= Z)
                iszero(x5) || gassign!(P, k, x5)                # $= (G24)
            end
            dfunc -= 10
        end
        # L43-47: IF(DFUNC GE 2, IF(DFUNC=4, Z=INF; ELSEIF DFUNC=5, F=0; ELSEIF DFUNC=(2-F), LAST_VAL=EPS; Z=0); extrapolate)
        if dfunc >= 2
            if dfunc == 4
                Z = Inf
            elseif dfunc == 5
                F = 0.0
            elseif dfunc == 2 - F
                last_val, Z = GEPS, 0.0
            end
            for t in years
                k = Base.setindex(row, t, yi)
                cond(k) || continue
                x5 = gif(first_val, yv[t] < F) + gif(last_val, yv[t] > Z)
                iszero(x5) || gassign!(P, k, x5)
            end
        end
        st.DFUNC = GNum(dfunc)
        st.MY_F, st.F, st.Z, st.LAST_VAL, st.FIRST_VAL, st.MY_FYEAR = my_f, gyear(F), gyear(Z), last_val, first_val, gyear(my_fyear)
    end
    last_arr === nothing || set_my_array!(st, last_arr)
    return rows
end

"""
    filparam!(st, name, pre, post, pad, src, tgt; back=true, fwd=true, year_in_uncd7=false)

filparam.gms with the arguments of one `\$BATINCLUDE filparam` call:
`name` (%1), the control indices `pre` (%2, which in GAMS ends with a comma)
and `post` (%3), `pad` (%4), the source data years `src` (%5) and the target
years `tgt` (%6); `back` false for %7 'NO\$' (no backward extrapolation,
ppmain.mod L631 MULTI), `fwd` likewise for %8; %9 is empty in every call
translated. `year_in_uncd7` when %10 is given (UC_TIME, "YEAR,"): UNCD7 then
holds '0' at the year position.

Default (no option): linear interpolation between the data years and
constant extrapolation both ways, over the target years. Options: < 0 none;
1 interpolation only; 2 EPS outside the data; 4 no forward, 5 no backward
extrapolation; above 1 by its last digit.

GAMS: filparam.gms L19-42, v4.9.7.
"""
function filparam!(st::InterpState, name, pre, post, pad, src, tgt; back::Bool=true, fwd::Bool=true, year_in_uncd7::Bool=false)
    fpre, fpost = ctlsets(st, pre), ctlsets(st, post)
    fs = vcat(fpre, Union{Nothing,Set{String}}[nothing], fpost)
    P = gvalues(st.tm, name, length(fs))
    _filparam!(st, P, fs, length(fpre) + 1, String.(pad), src, tgt, year_in_uncd7; back, fwd)
    gput!(st.tm, name, P)
    return st
end

function _filparam!(st::InterpState, P::Dict{NTuple{N,String},Float64}, fs, yi, pad, src, tgt, year_in_uncd7;
                    back::Bool=true, fwd::Bool=true) where {N}
    yv = st.ax.yearval
    dfl = "0"
    srcset = Set(src)
    # L21-22: UNCD7 from the tuples with a record in %5 (L21) or in any year (L22, %10 given)
    rowset = Set{NTuple{N,String}}()
    for k in keys(P)
        ((year_in_uncd7 || k[yi] in srcset) && passes(k, fs)) && push!(rowset, Base.setindex(k, dfl, yi))
    end
    rows = gams_sort!(collect(rowset), st.tm.data)
    tail1 = N > yi ? String[] : [""]                           # L20: %3 empty -> TAIL1 is ''
    st.uncd7 = Set{NTuple{7,String}}(NTuple{7,String}((r[1:yi-1]..., (year_in_uncd7 ? (dfl,) : ())..., r[yi+1:N]..., tail1..., pad...))
                                     for r in rows)
    for row in rows
        # L23-25: F=0; Z=INF; MY_FYEAR=9999; DFUNC = ROUND(%SRC%(%2'%DFLBL%'%TAIL2%))
        F, Z, my_fyear = 0.0, Inf, 9999.0
        dfunc = grnd(gv(P, row)).v
        st.DFUNC = GNum(dfunc)
        st.F, st.Z, st.MY_FYEAR = gyear(F), gyear(Z), gyear(my_fyear)
        dfunc >= 0 || continue                                  # L26
        # L27: MY_ARRAY(%5) = %SRC%(%2%5%TAIL2%); MY_ARRAY('%DFLBL%')=0
        for y in src
            k = Base.setindex(row, y, yi)
            haskey(P, k) ? (st.my_array[(y,)] = P[k]) : delete!(st.my_array, (y,))
        end
        delete!(st.my_array, (dfl,))
        my_f, first_val, last_val = st.MY_F, st.FIRST_VAL, st.LAST_VAL
        # L29-35: LOOP(%5$MY_ARRAY(%5), ...)
        for y in src
            haskey(st.my_array, (y,)) || continue
            my_f = gv(st.my_array, (y,))
            Zy = yv[y]
            if Zy > my_fyear + 1
                for t in tgt
                    yt = yv[t]
                    (Zy > yt && yt > my_fyear) || continue
                    gassign!(P, Base.setindex(row, t, yi), last_val + (my_f - last_val) / gyear(Zy - my_fyear) * gyear(yt - my_fyear))
                end
            elseif Zy < my_fyear
                F, first_val = Zy, my_f
            end
            last_val, my_fyear, Z = my_f, Zy, Zy
        end
        # L37-38: IF(DFUNC GT 1, DFUNC=MOD(DFUNC,10); 2: EPS both ways; 4: Z=INF; 5: F=0)
        if dfunc > 1
            dfunc = rem(dfunc, 10)
            if dfunc == 2
                first_val, last_val = GEPS, GEPS
            elseif dfunc == 4
                Z = Inf
            elseif dfunc == 5
                F = 0.0
            end
        end
        # L39-40: IF(DFUNC NE 1, %1(%2%6%TAIL2%) $= FIRST_VAL$(%7(YEARVAL(%6) LT F)) + LAST_VAL$(%8(YEARVAL(%6) GT Z)))
        if dfunc != 1
            for t in tgt
                x5 = gif(first_val, back && yv[t] < F) + gif(last_val, fwd && yv[t] > Z)
                iszero(x5) || gassign!(P, Base.setindex(row, t, yi), x5)
            end
        end
        st.DFUNC = GNum(dfunc)
        st.MY_F, st.F, st.Z, st.LAST_VAL, st.FIRST_VAL, st.MY_FYEAR = my_f, gyear(F), gyear(Z), last_val, first_val, gyear(my_fyear)
    end
    return P
end
