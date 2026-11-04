# M1.3 (9): ppmain.mod L619-682, after pp_qafs.mod (docs/m13-plan.md): the
# SHAPE and MULTI tables filled in (filshape.gms, filparam.gms), the defaults
# of the non-timeslice attributes (economic life, commodity release and
# investment lead times, CHP, storage efficiency) and the commodities
# involved only with capacity (RPC_NOFLO, UC_CAPFLO).
#
# GAMS: ppmain.mod L619-682, filshape.gms L1-26, filparam.gms L19-42 (L631),
# v4.9.7.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG, CG1 and CG2 are
# COM_GRP, T is MILESTONYR, V is MODLYEAR, LL is ALLYEAR, J the shape and
# multiplier indexes '1' to '999', AGE and its alias LIFE the ages '1' to
# '200', S is ALL_TS, IE is IMPEXP, IO is IN_OUT, BD is BND_TYPE, LIM the
# limit types. RTP(R,T,P) and RTP(R,V,P) run over the milestones and the
# model years (G8, G27); RTP alone over every record. A lead rounds (G29);
# `J+n` past '999' selects nothing. SMAX over nothing is -INF (G31). `$x`
# is true for EPS (G12) and `NOT x` false (G25); a numeric comparison takes
# EPS as 0 (G12); `$=` writes only a nonzero or EPS value (G24). The scratch
# Z, F, MY_F, LAST_VAL, MY_FYEAR and AGEFIL is left as GAMS leaves it.

"""
    ppmain_dflt_symbols(tm) -> Vector{String}

The symbols ppmain.mod L619-682 settles that nothing later in the prelv ->
ppm segment changes (for the layer-1 check at the ppm checkpoint). Left out:
UC_CAPFLO (L1189), RPC_NOFLO (L843, ppm_ext.vda L71, L86), RPCS_VAR
(L783), TRACKPC, UNCD7 and the scalars (used again); NCAP_BPME when CHP
has members and NCAP_CHPR when CHP has members or NCAP_CHPR an FX record
(pp_chp.mod L12, L31, L34). Their values at L682 are checked by replay
(test/unit/test_m13_ppmain_dflt.jl, scripts/m13_replay.jl).
"""
function ppmain_dflt_symbols(tm)
    out = ["MAXLIFE", "RTC_SHED", "STARTOFF", "SHAPE", "AGEFIL", "MULTI", "NCAP_ELIFE", "NCAP_DLIFE", "NCAP_DELIF",
           "NCAP_CLED", "STG_EFF"]
    nochp = isempty(gset_opt(tm.data, "CHP", 2).keys)
    nochp && push!(out, "NCAP_BPME")
    (nochp && !any(k -> k[4] == "FX", gparam_opt(tm.data, "NCAP_CHPR", 4).keys)) && push!(out, "NCAP_CHPR")
    return out
end

gscal(tm, n) = gv(gparam_opt(tm.data, n, 0), ())
gput_gnum!(tm, n, x::GNum) = gput!(tm, n, iszero(x) ? Dict{Tuple{},Float64}() : Dict{Tuple{},Float64}(() => x.v))

"""
    ppmain_dflt!(tm) -> tm

ppmain.mod L619-682 on the state after `pp_qafs!`: MAXLIFE, RTC_SHED and
STARTOFF; SHAPE interpolated and extrapolated (filshape.gms), with index '1'
at 1 up to STARTOFF and no EPS left; MULTI interpolated, extrapolated
forward (filparam.gms) and back from its first value up to 1, with index '1'
at 1; NCAP_ELIFE, NCAP_DLIFE, NCAP_DELIF, NCAP_CLED, NCAP_BPME, NCAP_CHPR
'UP' and STG_EFF defaulted; UC_CAPFLO, RPCS_VAR and RPC_NOFLO for the
commodities involved only with capacity.

GAMS: ppmain.mod L619-682, v4.9.7.
"""
function ppmain_dflt!(tm)
    rtp = gset(tm, "RTP").members
    tmem = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    rpc = gset(tm, "RPC").members
    tlife = gparam_opt(tm.data, "NCAP_TLIFE", 3)

    # --- L621-634: SHAPE and MULTI --------------------------------------------------------------
    # L623: MAXLIFE = SMAX(RTP,NCAP_TLIFE(RTP))
    maxlife = GNum(-Inf)
    foreach(k -> (maxlife = gmax(maxlife, gv(tlife, k))), rtp)
    gput_gnum!(tm, "MAXLIFE", maxlife)
    # L625: LOOP(SAMEAS(J,'1'),RTC_SHED(R,T,C,BD,J+MAX(0,COM_ELASTX(R,T,C,BD)-1))$COM_ELASTX(R,T,C,BD) = YES)
    jax = OrdAxis(tm, "J")
    shed = gmembers(tm, "RTC_SHED", 5)
    if haskey(jax.pos, "1")
        for (k, x) in gparam_opt(tm.data, "COM_ELASTX", 4).values
            k[2] in tmem || continue
            j = lead(jax, "1", glead(max(0.0, x - 1)))
            j === nothing || push!(shed, (k..., j))
        end
    end
    gput!(tm, "RTC_SHED", shed)
    # L626: STARTOFF = CEIL(MAX(MAXLIFE,SMAX(RTC_SHED(R,T,C,BD,J),COM_VOC(R,T,C,BD))*100))+1
    voc = gparam_opt(tm.data, "COM_VOC", 4)
    svoc = GNum(-Inf)
    foreach(k -> k[2] in tmem && (svoc = gmax(svoc, gv(voc, k[1:4]))), shed)
    startoff = ceil(gmax(maxlife, svoc * GNum(100.0)).v) + 1
    gput_gnum!(tm, "STARTOFF", GNum(startoff))
    # L628: $BATINCLUDE filshape 'STARTOFF'
    shape = gvalues(tm, "SHAPE", 2)
    filshape!(tm, shape, startoff)
    # L629: SHAPE('1',AGE)$(ORD(AGE) LE STARTOFF) = 1.
    ages = [k[1] for k in gset(tm, "AGE").keys]
    for (i, a) in enumerate(ages)
        i <= startoff && (shape[("1", a)] = 1.0)
    end
    # L630: SHAPE(J,AGE)$((SHAPE(J,AGE) EQ 0)$SHAPE(J,AGE)) = 0   (the EPS entries)
    filter!(kv -> kv[2] != 0.0, shape)
    gput!(tm, "SHAPE", shape)
    # L631: $BATINCLUDE filparam MULTI 'J,' '' ",'','','','',''" LL EOHYEARS 'NO$' ''
    register_uel!(tm.data, "")
    st = InterpState(tm)
    ax = st.ax
    eoh = [k[1] for k in gset(tm, "EOHYEARS").keys]
    filparam!(st, "MULTI", "J,", "", pd(",'','','','',''"), ax.years, eoh; back=false)
    put_interp_scratch!(st)
    # L632-633: LOOP(J, Z=1; LOOP(LL$(MULTI(J,LL)*Z), Z=0; F=MIN(1,MULTI(J,LL)));
    #   IF(NOT Z, MULTI(J,EOHYEARS)$(NOT MULTI(J,EOHYEARS)) = F))
    multi = gvalues(tm, "MULTI", 2)
    Z, F = gscal(tm, "Z"), gscal(tm, "F")
    byj = Dict{String,Vector{String}}()
    foreach(k -> pushat!(byj, k[1], k[2]), keys(multi))
    for j in jax.labels
        Z = GNum(1.0)
        ys = get(byj, j, nothing)
        ys === nothing && continue
        for y in ax.years
            haskey(multi, (j, y)) || continue
            Z = GZERO
            F = gmin(GNum(1.0), gv(multi, (j, y)))
            break
        end
        if iszero(Z)
            foreach(y -> haskey(multi, (j, y)) || gassign!(multi, (j, y), F), eoh)
        end
    end
    # L634: MULTI('1',EACHYEAR) = 1
    foreach(k -> (multi[("1", k[1])] = 1.0), gset(tm, "EACHYEAR").keys)
    gput!(tm, "MULTI", multi)
    gput_gnum!(tm, "Z", Z)
    gput_gnum!(tm, "F", F)

    # --- L637-651: defaults ---------------------------------------------------------------------
    # L637: NCAP_ELIFE(RTP)$(NOT NCAP_ELIFE(RTP)) = NCAP_TLIFE(RTP)
    elife = gvalues(tm, "NCAP_ELIFE", 3)
    foreach(k -> haskey(elife, k) || gassign!(elife, k, gv(tlife, k)), rtp)
    gput!(tm, "NCAP_ELIFE", elife)
    rtpT = [k for k in rtp if k[2] in tmem]
    # L639: NCAP_DLIFE(RTP(R,T,P))$((NOT NCAP_DLIFE(RTP))$SUM(RPC(R,P,C)$NCAP_OCOM(RTP,C),1)) = 1
    dlife = gvalues(tm, "NCAP_DLIFE", 3)
    ocom = Set(k[1:3] for k in gparam_opt(tm.data, "NCAP_OCOM", 4).keys if (k[1], k[3], k[4]) in rpc)
    foreach(k -> (!haskey(dlife, k) && k in ocom) && (dlife[k] = 1.0), rtpT)
    gput!(tm, "NCAP_DLIFE", dlife)
    # L640: NCAP_DELIF(RTP(R,T,P))$(NOT NCAP_DELIF(RTP))$= NCAP_DLIFE(RTP)
    delif = gvalues(tm, "NCAP_DELIF", 3)
    foreach(k -> (!haskey(delif, k) && haskey(dlife, k)) && (delif[k] = dlife[k]), rtpT)
    gput!(tm, "NCAP_DELIF", delif)
    # L642: NCAP_CLED(RTP(R,T,P),C)$((NOT NCAP_CLED(RTP,C))$NCAP_ICOM(RTP,C)) = COEF_ILED(RTP)
    cled = gvalues(tm, "NCAP_CLED", 4)
    ciled = gparam_opt(tm.data, "COEF_ILED", 3)
    rtpTset = Set(rtpT)
    for k in gparam_opt(tm.data, "NCAP_ICOM", 4).keys
        (k[1:3] in rtpTset && !haskey(cled, k)) && gassign!(cled, k, gv(ciled, k[1:3]))
    end
    gput!(tm, "NCAP_CLED", cled)
    # L644: NCAP_BPME(RTP(R,V,P))$((NOT NCAP_BPME(RTP))$NCAP_CDME(RTP)$CHP(R,P)) = 1
    chp = gset_opt(tm.data, "CHP", 2).members
    rtpV = [k for k in rtp if k[2] in modl]
    bpme = gvalues(tm, "NCAP_BPME", 3)
    cdme = gparam_opt(tm.data, "NCAP_CDME", 3).values
    foreach(k -> (!haskey(bpme, k) && haskey(cdme, k) && (k[1], k[3]) in chp) && (bpme[k] = 1.0), rtpV)
    gput!(tm, "NCAP_BPME", bpme)
    # L645: NCAP_CHPR(RTP(R,V,P),'UP')$((NOT SUM(LIM$NCAP_CHPR(RTP,LIM),1))$CHP(R,P)) = 1
    chpr = gvalues(tm, "NCAP_CHPR", 4)
    withlim = Set(k[1:3] for k in keys(chpr) if (k[4],) in gset(tm, "LIM").members)
    foreach(k -> ((k[1], k[3]) in chp && !(k in withlim)) && (chpr[(k..., "UP")] = 1.0), rtpV)
    gput!(tm, "NCAP_CHPR", chpr)
    # L647: LOOP(RP_STG(R,P)$(NOT SUM(RTP(R,T,P)$STG_EFF(RTP),1)), STG_EFF(RTP(R,V,P)) = 1)
    seff = gvalues(tm, "STG_EFF", 3)
    rp_stg = gset_opt(tm.data, "RP_STG", 2).members
    haseff = Set((k[1], k[3]) for k in rtpT if haskey(seff, k))
    foreach(k -> ((k[1], k[3]) in rp_stg && !((k[1], k[3]) in haseff)) && (seff[k] = 1.0), rtpV)
    gput!(tm, "STG_EFF", seff)

    # --- L656-678: the commodities involved only with capacity -----------------------------------
    noflo = gmembers(tm, "RPC_NOFLO", 3)
    # L658: UC_CAPFLO(UC_N,SIDE,RPC_NOFLO(R,P,C))$UC_ATTR(R,UC_N,SIDE,'FLO','CAPFLO') = YES
    capflo = Set{NTuple{5,String}}()
    ucr = Dict{String,Vector{NTuple{2,String}}}()
    for k in gset_opt(tm.data, "UC_ATTR", 5).keys
        (k[4] == "FLO" && k[5] == "CAPFLO") && pushat!(ucr, k[1], (k[2], k[3]))
    end
    for (r, p, c) in noflo, (u, s) in get(ucr, r, NTuple{2,String}[])
        push!(capflo, (u, s, r, p, c))
    end
    gput!(tm, "UC_CAPFLO", capflo)
    # L659: RPC_NOFLO(RPC_PG) = NO
    setdiff!(noflo, gset(tm, "RPC_PG").members)
    # L660: RPCS_VAR(RPC_NOFLO(R,P,C),ANNUAL)$(NOT RPC(R,P,C)) = YES
    rpcs = gmembers(tm, "RPCS_VAR", 4)
    for k in noflo, s in gset(tm, "ANNUAL").keys
        k in rpc || push!(rpcs, (k..., s[1]))
    end
    gput!(tm, "RPCS_VAR", rpcs)
    # L661: TRACKPC(RPC_NOFLO) = YES
    trackpc = union(gmembers(tm, "TRACKPC", 3), noflo)
    # L663-677: LOOP(TRACKPC(R,P,C), ... IF(NOT Z, RPC_NOFLO(R,P,C) = NO))
    isempty(trackpc) || (Z = capflo_loop!(tm, trackpc, noflo, tmem, Z))
    gput!(tm, "RPC_NOFLO", noflo)
    # L678: OPTION CLEAR=TRACKPC
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput_gnum!(tm, "Z", Z)
    return tm
end

"""
    filshape!(tm, shape, limit) -> shape

filshape.gms with %1 = `limit` (STARTOFF): for each J in GAMS order, the
SHAPE values at the ages between two data ages interpolated linearly, 1
before the first data age, the last value after the last one up to age
`limit`. The scratch Z, F, MY_F, LAST_VAL, MY_FYEAR and AGEFIL (the last
J's data ages) is stored as GAMS leaves it.

GAMS: filshape.gms L11-25, v4.9.7.
"""
function filshape!(tm, shape, limit)
    ages = [k[1] for k in gset(tm, "AGE").keys]
    Z, F, my_f, last_val, my_fyear = gscal(tm, "Z"), gscal(tm, "F"), gscal(tm, "MY_F"), gscal(tm, "LAST_VAL"), gscal(tm, "MY_FYEAR")
    agefil = gmembers(tm, "AGEFIL", 1)
    byj = Dict{String,Vector{String}}()
    foreach(k -> pushat!(byj, k[1], k[2]), keys(shape))
    pos = Dict(a => i for (i, a) in enumerate(ages))
    for j in (k[1] for k in gset(tm, "J").keys)
        z, mfy = 0.0, 9999.0                                                    # L12: Z = 0; MY_FYEAR = 9999
        has = Set(get(byj, j, String[]))
        agefil = Set{Tuple{String}}((a,) for a in ages if a in has)            # L14: AGEFIL(AGE) = YES$SHAPE(J,AGE)
        for (i, a) in enumerate(ages)                                            # L15-21
            a in has || continue
            my_f = gv(shape, (j, a)); z = Float64(i)
            if z > mfy + 1
                for l in (Int(mfy) + 1):(i - 1)
                    gassign!(shape, (j, ages[l]), last_val + (my_f - last_val) / GNum(z - mfy) * GNum(l - mfy))
                end
            elseif z < mfy
                F = GNum(z)
            end
            last_val, mfy = my_f, z
        end
        if z != 0                                                               # L23-24
            for (l, a) in enumerate(ages)
                l < F.v && (shape[(j, a)] = 1.0)
                (l > z && l <= limit) && gassign!(shape, (j, a), last_val)
            end
        end
        Z, my_fyear = GNum(z), GNum(mfy)
    end
    gput!(tm, "AGEFIL", agefil)
    for (n, x) in (("Z", Z), ("F", F), ("MY_F", my_f), ("LAST_VAL", last_val), ("MY_FYEAR", my_fyear))
        gput_gnum!(tm, n, x)
    end
    return shape
end

# ppmain.mod L663-677: Z for each TRACKPC member in GAMS order; RPC_NOFLO
# loses the commodities that have a flow. Returns the last Z.
function capflo_loop!(tm, trackpc, noflo, tmem, Z)
    rp_ire = gset_opt(tm.data, "RP_IRE", 2).members
    rpc_ire = gset_opt(tm.data, "RPC_IRE", 4).members
    rtpc = gset_opt(tm.data, "RTPC", 4).members
    gmap = gset(tm, "COM_GMAP").members
    ireq = Set(k[1:3] for k in rpc_ire)                                         # RPC_IRE(R,P,C,IE) by (R,P,C)
    rp_of(itr, f) = (d = Dict{NTuple{2,String},Vector{Any}}(); foreach(k -> f(k) && pushat!(d, (k[1], k[3]), k), itr); d)
    ifs = rp_of(gparam_opt(tm.data, "IRE_FLOSUM", 8).keys, k -> k[2] in tmem && (k[1], k[2], k[3], k[4]) in rtpc)
    acf = Set(k for k in gparam_opt(tm.data, "PRC_ACTFLO", 4).keys if k[2] in tmem && k in rtpc)
    acfc = Set((k[1], k[3], k[4]) for k in acf)
    ff = rp_of(gparam_opt(tm.data, "FLO_FUNC", 6).keys, k -> k[2] in tmem)
    fsum = rp_of(gparam_opt(tm.data, "FLO_SUM", 7).keys, k -> k[2] in tmem)
    fshar = Set((k[1], k[3], k[4]) for k in gparam_opt(tm.data, "FLO_SHAR", 7).keys if k[2] in tmem)
    for (r, p, c) in gordered(tm, trackpc)
        if (r, p) in rp_ire
            # L666-667: Z = NOT SUM(RPC_IRE(R,P,C,IE),1); Z$Z = NOT SUM((RTPC(R,T,P,COM),S,IE,IO)$IRE_FLOSUM(R,T,P,COM,S,IE,C,IO),RPC_IRE(R,P,COM,IE))
            z = !((r, p, c) in ireq)
            z && (z = !any(k -> k[7] == c && (r, p, k[4], k[6]) in rpc_ire, get(ifs, (r, p), Any[])))
        else
            z = !((r, p, c) in acfc)                                            # L669
            z && (z = !any(k -> (r, k[4], c) in gmap || (r, k[5], c) in gmap, get(ff, (r, p), Any[])))      # L671
            z && (z = !any(k -> (r, k[5], c) in gmap || (r, k[6], c) in gmap, get(fsum, (r, p), Any[])))    # L672
            z && (z = !((r, p, c) in fshar))                                    # L673
        end
        Z = GNum(z ? 1.0 : 0.0)
        z || delete!(noflo, (r, p, c))                                          # L675
    end
    return Z
end
