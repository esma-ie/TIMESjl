# M1.3 (15a): ppmain.mod L1101-1179 (docs/m13-plan.md): the user-constraint
# defaults: the year specifications through %DFLBL% (prepxtra.mod UCINT),
# UC_RHSRTS levelled to the UC timeslice levels, UC_R_EACH/UC_R_SUM,
# UC_TS_EACH/UC_TS_SUM and UC_T_EACH/UC_T_SUM/UC_T_SUCC defaults, the
# cumulative and dynamic UCs (UC_ATTR, UC_DYNDIR, UC_TSL), RS_PREV and G_UDS.
#
# GAMS: ppmain.mod L1101-1179, prepxtra.mod L61-77 (UCINT), v4.9.7.
#
# Index sets: R is REG (the UC sets are declared over ALL_R, so the loops
# take the model regions only), UC_N and UCN the UCs, SIDE is LHS/RHS, T is
# MILESTONYR, LL and YEAR are ALLYEAR, S and TS are ALL_TS, TSL and TSLVL the
# timeslice levels, L is LIM, J the indexes '1' to '999'. %DFLBL% is '0'
# (initmty.mod L367). `$x` is true for EPS (G3) and `NOT x` false (G25); a
# numeric comparison takes EPS as 0 (G12); `$=` writes only a nonzero or EPS
# value (G24); a right-hand side that names the symbol being assigned reads
# it as it was before the statement (G11); SMAX and SMIN over nothing are
# -INF and +INF (G31).

"""
    ppmain_uc_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1101-1179 settles that nothing later in the prelv
-> ppm segment changes (for the layer-1 check at the ppm checkpoint):
UC_R_EACH and UC_R_SUM only without UC_DYNBND (equcrtp.vda PPM_EXT L66-70).
Left out: R_UC (L1350), UC_ATTR (L1195), UC_ON (L1207), RXX (L1206) and the
scratch, which the replay checks at L1179.
"""
function ppmain_uc_symbols(tm)
    out = ["UC_T_SUM", "UC_T_SUCC", "UC_T_EACH", "UC_TSL", "UC_DS", "UC_RHSRTS", "UC_TS_EACH", "UC_TS_SUM", "UC_RHS", "UC_RHSR",
           "UC_DYNDIR", "RS_PREV", "G_UDS"]
    isempty(gset_opt(tm.data, "UC_DYNBND", 2).members) && append!(out, ["UC_R_EACH", "UC_R_SUM"])
    return out
end

"""
    ppmain_uc!(tm) -> tm

ppmain.mod L1101-1179 on the state after `ppmain_stg!`.

GAMS: ppmain.mod L1101-1179, v4.9.7.
"""
function ppmain_uc!(tm)
    tr = TsTree(tm)
    reg = tr.reg
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tlist)
    allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
    ypos = Dict(y => i for (i, y) in enumerate(allyear))
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    ucnset, sides, lim = member("UC_N"), [k[1] for k in gset(tm, "SIDE").keys], member("LIM")
    tslvl = [k[1] for k in gset(tm, "TSLVL").keys]
    lpos = Dict(l => i for (i, l) in enumerate(tslvl))
    annual = tr.annual
    Z, F = gscal(tm, "Z"), gscal(tm, "F")
    tsum, tsucc, teach = gmembers(tm, "UC_T_SUM", 3), gmembers(tm, "UC_T_SUCC", 3), gmembers(tm, "UC_T_EACH", 3)
    ru(k) = k[1] in reg && k[2] in ucnset
    dfl = "0"

    # --- prepxtra.mod L61-76: UCINT ------------------------------------------------------------------------
    # L64: UC_DT(R,UC_N)$UC_T_SUM(R,UC_N,'%DFLBL%') = YES; UC_T_SUM(UC_DT,'%DFLBL%') = NO
    uc_dt = gmembers(tm, "UC_DT", 2)
    foreach(k -> (ru(k) && k[3] == dfl) && push!(uc_dt, (k[1], k[2])), tsum)
    filter!(k -> !((k[1], k[2]) in uc_dt && k[3] == dfl), tsum)
    # L65-68: LOOP(UC_DT, Z=SMAX(UC_T_SUM(UC_DT,LL),ORD(LL)); IF(Z > 0, F=SMIN(UC_T_SUM(UC_DT,LL),ORD(LL)); ELSE F=Z);
    #   IF(Z NE F,UC_T_SUM(UC_DT,T(LL))$((ORD(LL) GT F)$(ORD(LL) LT Z)) = YES; ELSE UC_T_SUM(UC_DT,T) = YES))
    for d in gams_sort!(collect(uc_dt), tm.data)
        os = [ypos[k[3]] for k in tsum if (k[1], k[2]) == d && haskey(ypos, k[3])]
        Z = isempty(os) ? GNum(-Inf) : GNum(Float64(maximum(os)))
        F = Z.v > 0 ? GNum(Float64(minimum(os))) : Z
        if Z.v != F.v
            foreach(t -> (ypos[t] > F.v && ypos[t] < Z.v) && push!(tsum, (d..., t)), tlist)
        else
            foreach(t -> push!(tsum, (d..., t)), tlist)
        end
    end
    # L69: OPTION CLEAR=UC_DT; L70-71: UC_T_SUCC|UC_T_EACH(R,UC_N,T)$UC_T_SUCC|EACH(R,UC_N,'%DFLBL%') = YES
    for s in (tsucc, teach)
        for k in collect(s)
            (ru(k) && k[3] == dfl) && foreach(t -> push!(s, (k[1], k[2], t)), tlist)
        end
    end
    # L72-76: LOOP(T(YEAR), UC_T_xxx(R,UC_N,LL+(ORD(YEAR)-ORD(LL)))$(EOHYEARS(LL)$PERIODYR(T,LL)$UC_T_xxx(R,UC_N,LL)) = YES)
    eoh = member("EOHYEARS")
    pyr = Dict{String,Vector{String}}()
    foreach(k -> pushat!(pyr, k[1], k[2]), gset(tm, "PERIODYR").keys)
    for t in tlist, s in (teach, tsucc, tsum)
        add = [(k[1], k[2], t) for k in s if ru(k) && k[3] in eoh && k[3] in get(pyr, t, String[])]
        union!(s, add)
    end

    # --- L1107-1114: UC_RHSRTS levelled -------------------------------------------------------------------
    # L1108: LOOP(T,UC_TSL(R,UC_N,SIDE,TSL)$UC_T_SUCC(R,UC_N,T)=NO)
    uc_tsl = gmembers(tm, "UC_TSL", 4)
    succ_ru = Set((k[1], k[2]) for k in tsucc if ru(k) && k[3] in tmem)
    filter!(k -> !(ru(k) && (k[1], k[2]) in succ_ru), uc_tsl)
    # L1109: OPTION UC_DS < UC_TSL, R_UC < UC_DS, MREG < R_UC
    uc_ds = project(uc_tsl, (1, 2, 4))
    r_uc = project(uc_ds, (1, 2))
    mreg = Set(k[1] for k in r_uc)
    # L1110: UC_TSL(R_UC,'LHS',TSL) $= UC_DS(R_UC,TSL)
    foreach(k -> push!(uc_tsl, (k[1], k[2], "LHS", k[3])), uc_ds)
    # L1111-1112: LOOP((RJLVL(J,R(MREG),TSLVL),TSL)$(ORD(TSL)>ORD(TSLVL)), LOOP(TS_GROUP(R,TSLVL,TS),
    #   UC_RHSRTS(R_UC(R,UCN),T,S,L)$((NOT UC_RHSRTS(R_UC,T,S,L))$UC_DS(R_UC,TSL)) $= UC_RHSRTS(R_UC,T,TS,L)$RS_BELOW(R,TS,S)$TS_GROUP(R,TSL,S)))
    rts = gvalues(tm, "UC_RHSRTS", 5)
    tsg = gset(tm, "TS_GROUP").members
    rucs = gams_sort!(collect(r_uc), tm.data)
    for (j, r, lv) in gset(tm, "RJLVL").keys
        (r in reg && r in mreg) || continue
        for tsl in tslvl
            lpos[tsl] > lpos[lv] || continue
            for ts in get(tr.group, (r, lv), String[])
                put = Pair{NTuple{5,String},Float64}[]
                for (r2, u) in rucs
                    (r2 == r && (r, u, tsl) in uc_ds) || continue
                    for t in tlist, l in lim
                        y = get(rts, (r, u, t, ts, l), nothing)
                        y === nothing && continue
                        for s in get(tr.below, (r, ts), String[])
                            ((r, tsl, s) in tsg && !haskey(rts, (r, u, t, s, l))) && push!(put, (r, u, t, s, l) => y)
                        end
                    end
                end
                foreach(((k, y),) -> (rts[k] = y), put)
            end
        end
    end
    # L1113: LOOP(UC_DS(R_UC(R,UCN),TSL)$SUM(UC_TS_EACH(R_UC,S),1),UC_RHSRTS(R_UC,T,S,L)$((NOT UC_TS_EACH(R_UC,S))$TS_GROUP(R,TSL,S))=0)
    tseach, tssum = gmembers(tm, "UC_TS_EACH", 3), gmembers(tm, "UC_TS_SUM", 3)
    each_ru = Set((k[1], k[2]) for k in tseach)
    for (r, u, tsl) in uc_ds
        ((r, u) in r_uc && (r, u) in each_ru && r in reg) || continue
        filter!(((k, _),) -> !(k[1] == r && k[2] == u && k[3] in tmem && k[5] in lim && !((r, u, k[4]) in tseach) && (r, tsl, k[4]) in tsg), rts)
    end
    # L1114: UC_TS_EACH(R_UC,S) = NO; UC_ATTR(R_UC,SIDE,UC_GRPTYPE,UC_NAME(TSL)) = NO
    filter!(k -> !((k[1], k[2]) in r_uc), tseach)
    attr = gmembers(tm, "UC_ATTR", 5)
    tslset = Set(tslvl)
    filter!(k -> !((k[1], k[2]) in r_uc && k[5] in tslset), attr)
    # L1116-1117: UC_RHS(UC_N,L)$(NOT UC_RHS(UC_N,L)) $= UC_RHSS(UC_N,'ANNUAL',L); UC_RHSR the same from UC_RHSRS
    rhs, rhsr = gvalues(tm, "UC_RHS", 2), gvalues(tm, "UC_RHSR", 3)
    for (k, y) in gparam_opt(tm.data, "UC_RHSS", 3).values
        (k[2] == "ANNUAL" && k[1] in ucnset && k[3] in lim && !haskey(rhs, (k[1], k[3]))) && (rhs[(k[1], k[3])] = y)
    end
    for (k, y) in gparam_opt(tm.data, "UC_RHSRS", 4).values
        (k[3] == "ANNUAL" && k[1] in reg && k[2] in ucnset && k[4] in lim && !haskey(rhsr, (k[1], k[2], k[4]))) && (rhsr[(k[1], k[2], k[4])] = y)
    end
    gput!(tm, "UC_RHS", rhs)
    gput!(tm, "UC_RHSR", rhsr)

    # --- L1118-1129: UC_R_EACH / UC_R_SUM -----------------------------------------------------------------
    reach, rsum = gmembers(tm, "UC_R_EACH", 2), gmembers(tm, "UC_R_SUM", 2)
    rhsrt, rhst, rhsts = gparam_opt(tm.data, "UC_RHSRT", 4).keys, gparam_opt(tm.data, "UC_RHST", 3).keys, gparam_opt(tm.data, "UC_RHSTS", 4).keys
    # L1119: UNCD1(UCN)$(NOT SUM(UC_R_EACH(ALL_R,UCN),1)) = YES
    uncd1 = Set(u for u in ucnset if !any(k -> k[2] == u, reach))
    # L1120-1122: UC_ON(R,UCN) from UC_RHSR, UC_RHSRT (T), UC_RHSRTS (T)
    uc_on = gmembers(tm, "UC_ON", 2)
    foreach(k -> (k[1] in reg && k[2] in ucnset && k[3] in lim) && push!(uc_on, (k[1], k[2])), keys(rhsr))
    foreach(k -> (k[1] in reg && k[2] in ucnset && k[3] in tmem && k[4] in lim) && push!(uc_on, (k[1], k[2])), rhsrt)
    foreach(k -> (k[1] in reg && k[2] in ucnset && k[3] in tmem && k[5] in lim) && push!(uc_on, (k[1], k[2])), keys(rts))
    # L1123: UC_R_EACH(R,UCN)$(NOT UC_ON(R,UCN))=NO; UC_R_EACH(UC_ON(R,UCN))$=UNCD1(UCN)
    filter!(k -> !(k[1] in reg && k[2] in ucnset && !(k in uc_on)), reach)
    foreach(k -> k[2] in uncd1 && push!(reach, k), uc_on)
    # L1124: UNCD1(UCN)$(NOT SUM(UC_R_SUM(ALL_R,UCN),1)) = YES
    uncd1 = Set(u for u in ucnset if !any(k -> k[2] == u, rsum))
    # L1125-1127: UC_DT(R,UCN) from UC_RHS, UC_RHST (T), UC_RHSTS (T)
    uc_dt = Set{NTuple{2,String}}()
    hasu = Set{String}()
    foreach(k -> (k[1] in ucnset && k[2] in lim) && push!(hasu, k[1]), keys(rhs))
    foreach(k -> (k[1] in ucnset && k[2] in tmem && k[3] in lim) && push!(hasu, k[1]), rhst)
    foreach(k -> (k[1] in ucnset && k[2] in tmem && k[4] in lim) && push!(hasu, k[1]), rhsts)
    foreach(r -> foreach(u -> push!(uc_dt, (r, u)), hasu), reg)
    # L1128: UC_R_SUM(R,UCN)$(NOT UC_DT(R,UCN))=NO; UC_R_SUM(UC_DT(R,UCN))$=UNCD1(UCN)
    filter!(k -> !(k[1] in reg && k[2] in ucnset && !(k in uc_dt)), rsum)
    foreach(k -> k[2] in uncd1 && push!(rsum, k), uc_dt)
    # L1129: OPTION CLEAR=UC_DT,UC_ON<UC_R_EACH; UC_ON(UC_R_SUM)=YES
    uc_on = union(Set{NTuple{2,String}}(reach), rsum)

    # --- L1130-1139: UC_TS_EACH / UC_TS_SUM ---------------------------------------------------------------
    hasts(k) = any(x -> x[1] == k[1] && x[2] == k[2], tssum) || any(x -> x[1] == k[1] && x[2] == k[2], tseach)
    # L1131: UC_DT(UC_R_SUM(R,UC_N))$((NOT SUM(UC_TS_SUM(R,UC_N,S),1))$(NOT SUM(UC_TS_EACH(R,UC_N,S),1))) = YES
    uc_dt = Set{NTuple{2,String}}(k for k in rsum if ru(k) && !hasts(k))
    # L1132-1134
    rhs_u, rhst_u = Set(k[1] for k in keys(rhs) if k[2] in lim), Set(k[1] for k in rhst if k[2] in tmem && k[3] in lim)
    for (r, u) in uc_dt
        u in rhs_u && foreach(a -> push!(tseach, (r, u, a)), annual)
        foreach(k -> (k[1] == u && k[2] in tmem && k[4] in lim) && push!(tseach, (r, u, k[3])), rhsts)
        u in rhst_u && foreach(a -> push!(tssum, (r, u, a)), annual)
    end
    # L1135: UC_DT(UC_R_SUM)$(NOT UC_R_EACH(UC_R_SUM)) = NO
    filter!(k -> !(k in rsum && !(k in reach)), uc_dt)
    # L1136: UC_DT(UC_R_EACH(R,UC_N))$((NOT SUM(UC_TS_SUM(R,UC_N,S),1))$(NOT SUM(UC_TS_EACH(R,UC_N,S),1))) = YES
    foreach(k -> (ru(k) && !hasts(k)) && push!(uc_dt, k), collect(reach))
    # L1137-1139: UC_TS_SUM(UC_DT,ANNUAL)$SUM((T,L)$UC_RHSRT(UC_DT,T,L),1); UC_TS_EACH(UC_DT,ANNUAL)$SUM(L$UC_RHSR(UC_DT,L),1);
    #   UC_DT(R_UC) = NO; UC_TS_EACH(UC_DT,S)$SUM((T,L)$UC_RHSRTS(UC_DT,T,S,L),1)
    rt_ru = Set((k[1], k[2]) for k in rhsrt if k[3] in tmem && k[4] in lim)
    rr_ru = Set((k[1], k[2]) for k in keys(rhsr) if k[3] in lim)
    for k in uc_dt
        k in rt_ru && foreach(a -> push!(tssum, (k..., a)), annual)
        k in rr_ru && foreach(a -> push!(tseach, (k..., a)), annual)
    end
    setdiff!(uc_dt, r_uc)
    for k in keys(rts)
        ((k[1], k[2]) in uc_dt && k[3] in tmem && k[5] in lim) && push!(tseach, (k[1], k[2], k[4]))
    end

    # --- L1140-1147: UC_T_EACH / UC_T_SUM -----------------------------------------------------------------
    # L1143: UC_T_EACH(UC_T_SUCC) = YES; OPTION UC_DT < UC_ON
    union!(teach, tsucc)
    uc_dt = Set{NTuple{2,String}}(uc_on)
    # L1144: UC_DT(UC_DT)$SUM(UC_T_EACH(UC_DT,T),1) = NO; UC_DT(UC_DT)$SUM(UC_T_SUM(UC_DT,T),1) = NO
    filter!(k -> !any(x -> (x[1], x[2]) == k && x[3] in tmem, teach) && !any(x -> (x[1], x[2]) == k && x[3] in tmem, tsum), uc_dt)
    # L1145: UC_T_SUM(UC_R_SUM(UC_DT(R,UC_N)),T)$SUM(L$UC_RHS(UC_N,L),1) = YES; L1146: UC_T_SUM(UC_R_EACH(UC_DT),T)$SUM(L$UC_RHSR(UC_DT,L),1) = YES
    for k in uc_dt
        ((k in rsum && k[2] in rhs_u) || (k in reach && k in rr_ru)) && foreach(t -> push!(tsum, (k..., t)), tlist)
    end
    # L1147: UC_T_EACH(UC_DT,T)$(NOT UC_T_SUM(UC_DT,T)) = YES
    foreach(k -> foreach(t -> (k..., t) in tsum || push!(teach, (k..., t)), tlist), uc_dt)

    # --- L1149-1154: cumulative UCs -----------------------------------------------------------------------
    # L1150: OPTION CLEAR=MREG,CLEAR=UC_DT; L1151: LOOP(T,UC_DT(R,UC_N)$(UC_TS_EACH(R,UC_N,'ANNUAL')$UC_T_SUM(R,UC_N,T)) = YES)
    uc_dt = Set{NTuple{2,String}}((k[1], k[2]) for k in tsum if ru(k) && k[3] in tmem && (k[1], k[2], "ANNUAL") in tseach)
    # L1152: UC_TS_SUM(UC_DT,ANNUAL) = YES; UC_TS_EACH(UC_TS_SUM(R,UC_N,ANNUAL)) = NO
    foreach(k -> foreach(a -> push!(tssum, (k..., a)), annual), uc_dt)
    filter!(k -> !(k[3] in annual && k in tssum && ru(k)), tseach)
    # L1153: UC_DT(R_UC)$UC_DS(R_UC,'ANNUAL') = NO
    filter!(k -> !(k in r_uc && (k..., "ANNUAL") in uc_ds), uc_dt)
    # L1154: UC_ATTR(UC_DT,SIDE,UC_GRPTYPE,'PERIOD')$(NOT SAMEAS(UC_GRPTYPE,'NCAP')) = NO
    filter!(k -> !((k[1], k[2]) in uc_dt && k[5] == "PERIOD" && k[4] != "NCAP"), attr)
    # L1156: UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,UC_COST) $= SUM(UC_MAPCOST(UC_COST,UC_NAME),UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,UC_NAME))
    mapc = gset(tm, "UC_MAPCOST").keys
    add = [(k[1:4]..., m[1]) for k in attr for m in mapc if m[2] == k[5] && ru(k)]
    union!(attr, add)
    # L1158: LOOP(UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,'GROWTH'),UC_DYNDIR(R,UC_N,SIDE) = YES)
    dyndir = gmembers(tm, "UC_DYNDIR", 3)
    foreach(k -> (k[5] == "GROWTH" && ru(k)) && push!(dyndir, k[1:3]), attr)
    # L1160: UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,'PERIOD')$UC_ATTR(...,'CUMSUM') = NOT UC_ATTR(...,'ANNUL')
    for k in collect(attr)
        (k[5] == "CUMSUM" && ru(k)) || continue
        (k[1:4]..., "ANNUL") in attr ? delete!(attr, (k[1:4]..., "PERIOD")) : push!(attr, (k[1:4]..., "PERIOD"))
    end
    # L1161: UC_ATTR(R,UC_N,SIDE,'NCAP','CUMSUM')$UC_ATTR(R,UC_N,SIDE,'NCAP','ANNUL') = YES
    foreach(k -> (k[4] == "NCAP" && k[5] == "ANNUL" && ru(k)) && push!(attr, (k[1:4]..., "CUMSUM")), collect(attr))
    # L1162-1163: 'CUM+' for RHS SYNC with CUMSUM, then CUMSUM dropped
    for k in collect(attr)
        (k[3] == "RHS" && k[5] == "SYNC" && ru(k) && (k[1:4]..., "CUMSUM") in attr) && push!(attr, (k[1:4]..., "CUM+"))
    end
    filter!(k -> !(k[3] == "RHS" && k[5] == "CUMSUM" && ru(k) && (k[1:4]..., "CUM+") in attr), attr)
    # L1165-1166: OPTION CLEAR=RXX; LOOP(UC_ATTR(R,UC_N,'RHS',UC_GRPTYPE,UC_NAME),RXX(R,UC_N,'RHS') = YES);
    #   LOOP(T,RXX(R,UC_N,'RHS')$UC_T_SUCC(R,UC_N,T) = NO); UC_DYNDIR(RXX(R,UC_N,'RHS')) = YES
    rxx = Set{NTuple{3,String}}((k[1], k[2], "RHS") for k in attr if k[3] == "RHS" && ru(k))
    succ_ru = Set((k[1], k[2]) for k in tsucc if ru(k) && k[3] in tmem)
    filter!(k -> !((k[1], k[2]) in succ_ru), rxx)
    union!(dyndir, rxx)
    gput!(tm, "RXX", rxx)
    # L1167: LOOP(UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,UC_DYNT),UC_DYNDIR(R,UC_N,'RHS') = YES)
    dynt = member("UC_DYNT")
    foreach(k -> (k[5] in dynt && ru(k)) && push!(dyndir, (k[1], k[2], "RHS")), attr)
    # L1168: UC_ATTR(R,UC_N,'RHS',UC_GRPTYPE,'N')$UC_ATTR(R,UC_N,'RHS',UC_GRPTYPE,'SYNC') = YES
    foreach(k -> (k[3] == "RHS" && k[5] == "SYNC" && ru(k)) && push!(attr, (k[1:4]..., "N")), collect(attr))
    gput!(tm, "UC_ATTR", attr)
    # L1170: UC_DYNDIR(R,UC_N,'RHS')$UC_DYNDIR(R,UC_N,'LHS') = NO
    filter!(k -> !(k[3] == "RHS" && ru(k) && (k[1], k[2], "LHS") in dyndir), dyndir)
    # L1171: UC_TSL(UC_DYNDIR(R_UC,'RHS'),TSL)$UC_DS(R_UC,TSL)=YES; UC_DYNDIR(R_UC,SIDE)=NO
    foreach(k -> ((k[1], k[2]) in r_uc && (k[1], k[2], "RHS") in dyndir) && push!(uc_tsl, (k[1], k[2], "RHS", k[3])), uc_ds)
    filter!(k -> !((k[1], k[2]) in r_uc), dyndir)
    # L1173: UC_T_SUCC(UC_T_EACH(R,UCN,T)) $= SUM(UC_DYNDIR(R,UCN,SIDE),1)
    dyn_ru = Set((k[1], k[2]) for k in dyndir if k[3] in Set(sides))
    foreach(k -> (ru(k) && k[3] in tmem && (k[1], k[2]) in dyn_ru) && push!(tsucc, k), teach)
    # L1174: UC_T_SUCC(UC_T_EACH(R,UCN,T))$UC_R_SUM(R,UCN) $= SUM(UC_T_SUCC(UC_R_SUM(REG,UCN),T),1)
    old = copy(tsucc)
    for k in teach
        (ru(k) && k[3] in tmem && (k[1], k[2]) in rsum) || continue
        any(x -> x[2] == k[2] && x[3] == k[3] && x[1] in reg && (x[1], x[2]) in rsum, old) && push!(tsucc, k)
    end
    # L1175: UC_T_EACH(UC_T_SUCC) = NO
    setdiff!(teach, tsucc)
    # L1177: UC_T_SUCC(UC_T_SUCC(R,UC_N,T))$(ORD(T) = CARD(T)) = UC_DYNDIR(R,UC_N,'RHS')
    lastt = last(tlist)
    filter!(k -> !(k[3] == lastt && ru(k) && !((k[1], k[2], "RHS") in dyndir)), tsucc)
    # L1178: RS_PREV(R,S,S--RS_STG(R,S)) $= RS_TSLVL(R,S); G_UDS(S,'LHS',S) = YES
    rs_prev = gmembers(tm, "RS_PREV", 3)
    rs_stg, rs_tslvl = gvalues(tm, "RS_STG", 2), gvalues(tm, "RS_TSLVL", 2)
    n = length(tr.all_ts)
    tspos = Dict(s => i for (i, s) in enumerate(tr.all_ts))
    for (k, y) in rs_tslvl
        (k[1] in reg) || continue
        i = mod(tspos[k[2]] - glead(Float64(gv(rs_stg, k).v)) - 1, n) + 1      # the circular lag S--RS_STG(R,S)
        push!(rs_prev, (k[1], k[2], tr.all_ts[i]))
    end
    gput!(tm, "RS_PREV", rs_prev)
    g_uds = gmembers(tm, "G_UDS", 3)
    foreach(s -> push!(g_uds, (s, "LHS", s)), tr.all_ts)
    # L1179: LOOP(R$SUM(UC_TSL(R,UCN,'RHS',TSL),1),G_UDS(S,'RHS',TS)$RS_PREV(R,S,TS)=YES)
    for r in reg
        any(k -> k[1] == r && k[3] == "RHS", uc_tsl) || continue
        foreach(k -> k[1] == r && push!(g_uds, (k[2], "RHS", k[3])), rs_prev)
    end
    gput!(tm, "G_UDS", g_uds)

    for (n2, v) in (("UC_T_SUM", tsum), ("UC_T_SUCC", tsucc), ("UC_T_EACH", teach), ("UC_TSL", uc_tsl), ("UC_DS", uc_ds), ("R_UC", r_uc),
                    ("UC_TS_EACH", tseach), ("UC_TS_SUM", tssum), ("UC_R_EACH", reach), ("UC_R_SUM", rsum), ("UC_ON", uc_on),
                    ("UC_DYNDIR", dyndir))
        gput!(tm, n2, v)
    end
    gput!(tm, "UC_RHSRTS", rts)
    gput!(tm, "UC_DT", Set{NTuple{2,String}}(uc_dt))
    gput!(tm, "MREG", Set{Tuple{String}}())
    gput!(tm, "UNCD1", Set{Tuple{String}}((u,) for u in uncd1))
    gput_gnum!(tm, "Z", Z)
    gput_gnum!(tm, "F", F)
    return tm
end
