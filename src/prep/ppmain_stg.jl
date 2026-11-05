# M1.3 (14): ppmain.mod L1058-1099 (docs/m13-plan.md): the storage
# processes: RTPCS_OUT for the genuine storage flows, the demand-sifting
# storages (TRACKPC from STG_SIFT, RPC_SPG, RPC_STGN, RPC_LS, STG_SIFT
# levelled to the sifting level, ACT_TIME), the flexible storages (RPS_STG,
# RP_STS, PRC_TS, PRC_STGTSS, STG_LOSS, RP_STL, NCAP_AF), STG_LOSS and
# STG_SIFT levelled (pp_lvlfc.mod) and STG_LOSS converted to the year
# fractions.
#
# GAMS: ppmain.mod L1058-1099, pp_lvlfc.mod L19-45, v4.9.7.
#
# Index sets: R is REG, P is PRC, C is COM, S and TS are ALL_TS, T is
# MILESTONYR, V is MODLYEAR, TSL and TSLVL are the timeslice levels, J the
# indexes '1' to '999', BD is BND_TYPE (LO, FX, UP), IO is IN_OUT, IPS holds
# IN. RTP(R,T,P) and RTP(R,V,P) run over the milestones and the model years
# (G8, G27); `S(TSL)` is the timeslice ANNUAL only (G44). `$x` is true for
# EPS (G3) and `NOT x` false (G25); `NOT a$b` is `NOT (a$b)` (G46); a numeric
# comparison takes EPS as 0 (G12); `$=` writes only a nonzero or EPS value
# (G24); a right-hand side that names the symbol being assigned reads it as
# it was before the statement (G11); a scalar `$` on a loop domain is read
# again before each member (G30, G46).

"""
    ppmain_stg_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1058-1099 settles that nothing later in the prelv
-> ppm segment changes (for the layer-1 check at the ppm checkpoint): RPC_PKC
only with %REDUCE% NO (pp_reduce.red L184). Left out: RP_STL (ppm_ext.vda
L141), RTPCS_OUT (L1350), RHS_COMPRD (L1209-1226) and the scratch, which
the replay checks at L1099.
"""
function ppmain_stg_symbols(tm)
    out = ["RPC_SPG", "RPC_STGN", "RPC_LS", "STG_SIFT", "ACT_TIME", "RPS_STG", "RP_STS", "RP_STG", "PRC_STGTSS", "STG_LOSS",
           "NCAP_AF", "PRC_TS"]
    strip(gswitch(tm, "REDUCE", "")) == "NO" && push!(out, "RPC_PKC")
    return out
end

"""
    ppmain_stg!(tm) -> tm

ppmain.mod L1058-1099 on the state after `ppmain_cum!`.

GAMS: ppmain.mod L1058-1099, v4.9.7.
"""
function ppmain_stg!(tm)
    tr = TsTree(tm)
    reg = tr.reg
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tlist)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    actcg, bdset, bdupx = member("ACTCG"), member("BD"), member("BDUPX")
    rp, rtp = gset(tm, "RP").members, gset(tm, "RTP").members
    by(itr, f, g) = (d = Dict{Any,Vector{Any}}(); foreach(k -> pushat!(d, f(k), g(k)), itr); d)
    none = Any[]
    rpc_stg = gset_opt(tm.data, "RPC_STG", 3).members
    top = gset(tm, "TOP").members
    rp_stg = gmembers(tm, "RP_STG", 2)
    rp_sts = gmembers(tm, "RP_STS", 2)
    Z, F = gscal(tm, "Z"), gscal(tm, "F")

    # L1062: RTPCS_OUT(RTP(R,T,P),C,S)$(RPCS_VAR(R,P,C,S)$RPC_STG(R,P,C)) = YES
    rtpcs_out = gmembers(tm, "RTPCS_OUT", 5)
    ts_of_rp = by([k for k in rtp if k[2] in tmem], k -> (k[1], k[3]), k -> k[2])
    for (r, p, c, s) in gset(tm, "RPCS_VAR").keys
        (r, p, c) in rpc_stg && foreach(t -> push!(rtpcs_out, (r, t, p, c, s)), get(ts_of_rp, (r, p), none))
    end
    gput!(tm, "RTPCS_OUT", rtpcs_out)

    # --- L1064-1078: demand-sifting storages -------------------------------------------------------------
    sift = gvalues(tm, "STG_SIFT", 5)                                     # (R,T,P,C,S)
    # L1065: OPTION TRACKPC < STG_SIFT; TRACKPC(RP,C)$(NOT (TOP(RP,C,'OUT')$RPC_STG(RP,C)+ACTCG(C))$RP_STG(RP))=NO
    trackpc = project(keys(sift), (1, 3, 4))
    keep(k) = (k[1], k[2]) in rp_stg && (((k..., "OUT") in top && k in rpc_stg) || k[3] in actcg)
    filter!(k -> !((k[1], k[2]) in rp) || keep(k), trackpc)
    # L1066: TRACKPC(RP,C)$PRC_NSTTS(RP,'ANNUAL')=NO
    nstts = gset_opt(tm.data, "PRC_NSTTS", 3).members
    filter!(k -> !((k[1], k[2]) in rp && (k[1], k[2], "ANNUAL") in nstts), trackpc)
    # L1067: LOOP(TRACKPC(R,P,C),TRACKP(R,P)=YES; RPC_PKC(R,P,C)=NO; RHS_COMPRD(RTCS_VARC(R,T,C,S))=YES)
    trackp = gmembers(tm, "TRACKP", 2)
    pkc = gmembers(tm, "RPC_PKC", 3)
    rhsp = gmembers(tm, "RHS_COMPRD", 4)
    varc_of = by([k for k in gset(tm, "RTCS_VARC").keys if k[2] in tmem], k -> (k[1], k[3]), k -> k)
    for k in trackpc
        push!(trackp, (k[1], k[2]))
        delete!(pkc, k)
        union!(rhsp, get(varc_of, (k[1], k[3]), none))
    end
    gput!(tm, "RPC_PKC", pkc)
    gput!(tm, "RHS_COMPRD", rhsp)
    # L1068: RPC_SPG(RPC_STG(TRACKP,C))=YES; RPC_STGN(TOP(RPC_STG(RPC_SPG(RP,C)),IO))$TOP(RP,C,'IN') = (TRACKPC(RP,C) EQV IPS(IO))
    spg = gmembers(tm, "RPC_SPG", 3)
    foreach(k -> (k[1], k[2]) in trackp && push!(spg, k), rpc_stg)
    gput!(tm, "RPC_SPG", spg)
    stgn = gmembers(tm, "RPC_STGN", 4)
    ips = member("IPS")
    for (r, p, c, io) in top
        ((r, p, c) in rpc_stg && (r, p, c) in spg && (r, p) in rp && (r, p, c, "IN") in top) || continue
        ((r, p, c) in trackpc) == (io in ips) ? push!(stgn, (r, p, c, io)) : delete!(stgn, (r, p, c, io))
    end
    gput!(tm, "RPC_STGN", stgn)
    # L1069-1077: LOOP(PRC_TSL(TRACKP(RP(R,P)),TSLVL), ...)
    rpc_ls = gmembers(tm, "RPC_LS", 3)
    act_time = gvalues(tm, "ACT_TIME", 4)
    tslvl = [k[1] for k in gset(tm, "TSLVL").keys]
    lpos = Dict(l => i for (i, l) in enumerate(tslvl))
    rlup = gset(tm, "RLUP").members
    rjlvl = gset(tm, "RJLVL").keys
    stoal = gvalues(tm, "STOAL", 2)
    annual = Set(tr.annual)
    rpcsv_ann = Set((k[1], k[2], k[3]) for k in gset(tm, "RPCS_VAR").keys if k[4] in annual)
    in_of = by(gams_sort!([k for k in top if k[4] == "IN" && (k[1], k[2], k[3]) in rpc_stg], tm.data), k -> (k[1], k[2]), k -> k[3])
    tpc_of = by(trackpc, k -> (k[1], k[2]), k -> k[3])
    for (r, p, lv) in gams_sort!([k for k in gset(tm, "PRC_TSL").keys if (k[1], k[2]) in trackp && (k[1], k[2]) in rp], tm.data)
        delete!(rp_sts, (r, p)); delete!(rp_stg, (r, p))
        # Z=1-SUM(RPCS_VAR(RP,C,ANNUAL),2); LOOP(TOP(RPC_STG(RP,C),'IN'),IF(Z>0,RPC_LS(RP,C)=YES);Z=Z-1); RPC_LS(RP,C(ACTCG))$Z=YES
        Z = GNum(1.0 - 2.0 * count(k -> k[1] == r && k[2] == p, rpcsv_ann))
        for c in get(in_of, (r, p), none)
            Z.v > 0 && push!(rpc_ls, (r, p, c))
            Z = Z - GNum(1.0)
        end
        iszero(Z) || foreach(a -> push!(rpc_ls, (r, p, a)), actcg)
        # LOOP(TRACKPC(RP,C(ACTCG)), F=SUM(RLUP(R,TSLVL,TSL),ORD(TSL)-1); IF(F=0,F=Z); ...)
        for c in gams_sort!(NTuple{1,String}[(String(c),) for c in get(tpc_of, (r, p), none) if c in actcg], tm.data)
            c = c[1]
            F = GNum(reduce(+, (Float64(lpos[l] - 1) for l in tslvl if (r, lv, l) in rlup); init=0.0))
            F.v == 0 && (F = Z)
            # LOOP(RJLVL(J,R,TSL)$(F>=ORD(TSL)), LOOP(TS_GROUP(R,TSL,TS), STG_SIFT(R,T,P,C,S)$(NOT STG_SIFT(R,T,P,C,S)) $=
            #   STG_SIFT(R,T,P,C,TS)$(STOAL(R,S)=F)$RS_BELOW(R,TS,S)))
            for (j, r2, tsl) in rjlvl
                (r2 == r && F.v >= lpos[tsl]) || continue
                for ts in get(tr.group, (r, tsl), String[])
                    put = Pair{NTuple{5,String},Float64}[]
                    for t in tlist, s in get(tr.below, (r, ts), String[])
                        (gv(stoal, (r, s)).v == F.v && !haskey(sift, (r, t, p, c, s))) || continue
                        y = get(sift, (r, t, p, c, ts), nothing)
                        y === nothing || push!(put, (r, t, p, c, s) => y)
                    end
                    foreach(((k, y),) -> (sift[k] = y), put)
                end
            end
            # STG_SIFT(R,T,P,C,S)$(STOAL(R,S) NE F)=0
            filter!(((k, _),) -> !(k[1] == r && k[2] in tmem && k[3] == p && k[4] == c && gv(stoal, (r, k[5])).v != F.v), sift)
        end
        # ACT_TIME(RTP(R,T,P),'LO')$(ACT_TIME(RTP,'UP')=0)=0; ACT_TIME(RTP(R,T,P),BD)$ACT_TIME(RTP,'FX')=ACT_TIME(RTP,'FX')$BDUPX(BD)
        for t in get(ts_of_rp, (r, p), none)
            gv(act_time, (r, t, p, "UP")).v == 0 && delete!(act_time, (r, t, p, "LO"))
            fx = get(act_time, (r, t, p, "FX"), nothing)
            fx === nothing && continue
            foreach(b -> b in bdupx ? (act_time[(r, t, p, b)] = fx) : delete!(act_time, (r, t, p, b)), bdset)
        end
    end
    gput!(tm, "ACT_TIME", act_time)
    # L1078: RPC_LS(RPC(RP,C))$RPC_LS(RP,%PGPRIM%)=NO
    pg = strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"'])
    rpc = gset(tm, "RPC").members
    ls_pg = Set((k[1], k[2]) for k in rpc_ls if k[3] == pg)
    filter!(k -> !(k in rpc && (k[1], k[2]) in rp && (k[1], k[2]) in ls_pg), rpc_ls)
    gput!(tm, "RPC_LS", rpc_ls)

    # --- L1080-1090: flexible general storage --------------------------------------------------------------
    prc_ts = gmembers(tm, "PRC_TS", 3)
    pmap = gset(tm, "PRC_MAP").members
    # L1081: RPS_STG(PRC_TS(RP_STG,TS)) = YES; L1082: RPS_STG(R,P,ANNUAL)$PRC_MAP(R,'STK',P) = NO
    rps_stg = gmembers(tm, "RPS_STG", 3)
    foreach(k -> (k[1], k[2]) in rp_stg && push!(rps_stg, k), prc_ts)
    filter!(k -> !(k[3] in annual && (k[1], "STK", k[2]) in pmap), rps_stg)
    gput!(tm, "RPS_STG", rps_stg)
    # L1083: RP_STS(R,P)$PRC_TSL(R,P,'ANNUAL') = NO
    filter!(k -> !((k..., "ANNUAL") in gset(tm, "PRC_TSL").members), rp_sts)
    # L1084-1088: LOOP(RP_STS(R,P), PRC_TS(RPS_PRCTS(R,P,S))$STOA(S) = YES; PRC_TS(R,P,ANNUAL)$PRC_MAP(R,'STK',P) = YES;
    #   PRC_STGTSS(PRC_STGIPS(R,P,C)) = YES; STG_LOSS(R,V,P,S)$STG_LOSS(R,V,P,S) = -ABS(STG_LOSS(R,V,P,S)))
    stoa = gvalues(tm, "STOA", 1)
    stgtss = gmembers(tm, "PRC_STGTSS", 3)
    loss = gvalues(tm, "STG_LOSS", 4)
    prcts_of = by(gset(tm, "RPS_PRCTS").keys, k -> (k[1], k[2]), k -> k[3])
    ips_of = by(gset_opt(tm.data, "PRC_STGIPS", 3).keys, k -> (k[1], k[2]), k -> k[3])
    for (r, p) in rp_sts
        foreach(s -> iszero(gv(stoa, (s,))) || push!(prc_ts, (r, p, s)), get(prcts_of, (r, p), none))
        (r, "STK", p) in pmap && foreach(a -> push!(prc_ts, (r, p, a)), tr.annual)
        foreach(c -> push!(stgtss, (r, p, c)), get(ips_of, (r, p), none))
        for (k, y) in collect(loss)
            (k[1] == r && k[2] in modl && k[3] == p) && gassign!(loss, k, -abs(y == 0.0 ? GEPS : GNum(y)))
        end
    end
    gput!(tm, "PRC_STGTSS", stgtss)
    # L1089: RP_STL(RP_STS(RP),TSL+1,'N')$(PRC_SGL(RP)>=ORD(TSL)) = YES
    rp_stl = gmembers(tm, "RP_STL", 4)
    sgl = gvalues(tm, "PRC_SGL", 2)
    for (r, p) in rp_sts, (i, l) in enumerate(tslvl)
        (gv(sgl, (r, p)).v >= i && i < length(tslvl)) && push!(rp_stl, (r, p, tslvl[i+1], "N"))
    end
    gput!(tm, "RP_STL", rp_stl)
    # L1090: NCAP_AF(RTP(R,V,P),S,BD)$((NOT RPS_STG(R,P,S))$RP_STS(R,P)) = NCAP_AFS(RTP,S,BD)
    naf = gvalues(tm, "NCAP_AF", 5)
    afs = gparam_opt(tm.data, "NCAP_AFS", 5).values
    if !isempty(rp_sts)
        for k in collect(keys(naf))
            ((k[1], k[3]) in rp_sts && k[2] in modl && (k[1], k[2], k[3]) in rtp && k[5] in bdset && !((k[1], k[3], k[4]) in rps_stg)) || continue
            gassign!(naf, k, gv(afs, k))
        end
        for (k, y) in afs
            ((k[1], k[3]) in rp_sts && k[2] in modl && (k[1], k[2], k[3]) in rtp && k[5] in bdset && !((k[1], k[3], k[4]) in rps_stg)) || continue
            gassign!(naf, k, y == 0.0 ? GEPS : GNum(y))
        end
    end
    gput!(tm, "NCAP_AF", naf)
    gput!(tm, "RP_STS", rp_sts)
    gput!(tm, "RP_STG", rp_stg)

    # --- L1092-1099: STG_LOSS and STG_SIFT levelled and converted ----------------------------------------
    # L1093: TRACKP(RP_STG)$(NOT RP_STS(RP_STG)) = YES
    foreach(k -> k in rp_sts || push!(trackp, k), rp_stg)
    gput!(tm, "PRC_TS", prc_ts)
    gput!(tm, "STG_LOSS", loss)
    gput!(tm, "STG_SIFT", sift)
    pts_of = by(prc_ts, k -> (k[1], k[2]), k -> k[3])
    rpcs_of = by(gset(tm, "RPCS_VAR").keys, k -> (k[1], k[2], k[3]), k -> k[4])
    ts_array = nothing
    # L1094: $BATINCLUDE pp_lvlfc.mod STG_LOSS P PRC_TS '' ",'0','0','0','0'" S2 V 'RTP(R,V,P)$(NOT RPS_STG(R,P,S)$TRACKP(R,P))'
    u7, a = pp_lvlfc!(tm, tr, "STG_LOSS", 4; sp=4, years=modl, keyok=k -> true, targets=k -> get(pts_of, (k[1], k[3]), none),
                      qual=k -> (k[1], k[2], k[3]) in rtp && !((k[1], k[3], k[4]) in rps_stg && (k[1], k[3]) in trackp), s2=true)
    a === nothing || (ts_array = a)
    # L1095: $BATINCLUDE pp_lvlfc.mod STG_SIFT 'P,C' RPCS_VAR '' ",'0','0','0'" ALL_TS T RTP(R,T,P)
    com = member("COM")
    u7, a = pp_lvlfc!(tm, tr, "STG_SIFT", 5; sp=5, years=tmem, keyok=k -> k[4] in com, targets=k -> get(rpcs_of, (k[1], k[3], k[4]), none),
                      qual=k -> (k[1], k[2], k[3]) in rtp)
    a === nothing || (ts_array = a)
    # L1097: STG_LOSS(RTP(R,V,P),S(TSL))$((ABS(STG_LOSS(RTP,S)*2-1)>=1)$PRC_MAP(R,'STK',P)) = 1-EXP(-ABS(STG_LOSS(RTP,S)))
    loss = gvalues(tm, "STG_LOSS", 4)
    sts = [s for s in tr.annual if s in Set(tslvl)]
    for (r, v, p) in rtp
        (v in modl && (r, "STK", p) in pmap) || continue
        for s in sts
            x = gv(loss, (r, v, p, s))
            abs(x.v * 2 - 1) >= 1 && gassign!(loss, (r, v, p, s), GNum(1.0) - gexp(-abs(x)))
        end
    end
    # L1098: STG_LOSS(RTP(R,V,P),S)$(STOA(S)$STG_LOSS(RTP,S)) = LOG(EXP(STG_LOSS(RTP,S)*G_YRFR(R,S)/RS_STGPRD(R,S)))
    prd = gvalues(tm, "RS_STGPRD", 2)
    for (k, y) in collect(loss)
        ((k[1], k[2], k[3]) in rtp && k[2] in modl && !iszero(gv(stoa, (k[4],)))) || continue
        e = gexp((y == 0.0 ? GEPS : GNum(y)) * yrfr_at(tr, k[1], k[4]) / gv(prd, (k[1], k[4])))
        gassign!(loss, k, GNum(log(e.v)))
    end
    gput!(tm, "STG_LOSS", loss)
    # L1099: OPTION CLEAR=TRACKP,CLEAR=TRACKPC
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "UNCD7", u7)
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    gput_gnum!(tm, "Z", Z)
    gput_gnum!(tm, "F", F)
    return tm
end
