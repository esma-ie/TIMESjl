# M1.3 (7a): the start of the prep -> prelv segment (docs/m13-plan.md):
# ppmain.mod L249-328, after preppm.mod (the preshape calls, preppm_shape!):
# the timestep control, the horizon (DUR_MAX, EACHYEAR), the commodity groups
# and RC, and the primary and shadow primary groups.
#
# GAMS: ppmain.mod L249-328, v4.9.7.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG is COM_GRP, T is
# MILESTONYR, PYR is PASTYEAR, IO is IN_OUT, IE is IMPEXP, TSL is TSLVL
# (initmty.mod L98). `OPTION a < b` matches positions right to left and `<=`
# left to right, by domain (G26); NOT ranks below + (G19); a LOOP's
# `$`-condition is read before each iteration (G30); `$x` is true for EPS
# (G12); SMAX over nothing is -INF (G31).
#
# Not translated: L249 (%INTEXT_ONLY% YES, refused at preppm.mod L10); L253
# (`SET SUBT(T) / SET.T /`, a data statement, compiled before execution: SUBT
# holds T's members in every dump); the QA log of L273-277 (PUTGRP and the
# message of a commodity group that is also a commodity in the topology),
# m13-plan.md open items. The data effects of L273-277 are translated.

"""
    ppmain_topo_symbols(tm) -> Vector{String}

The symbols ppmain.mod L249-328 settles that nothing later in the prep ->
prelv segment changes (for the layer-1 check at the prelv checkpoint). Left
out: DEM (L417 sets it again), PRC_CG (pp_prelv.vda L33 adds to it), RPC_PG
(ppmain.mod L593, L595), and the scratch TRACKP and Z, used again.
"""
ppmain_topo_symbols(tm) = ["SUBT", "RT_PP", "DUR_MAX", "EOHYEARS", "EACHYEAR", "PERIODYR", "MI_DMAS", "FIN", "RC", "RPC",
                           "COM_GMAP", "NRG_GMAP", "RPC_CAPFLO", "RPC_NOFLO", "RP_PGTYPE", "RP_AIRE", "RP_INOUT", "PRC_SPG",
                           "RPC_SPG"]

"""
    ppmain_topo!(tm) -> tm

ppmain.mod L249-328 on the state after `preppm_shape!`: RT_PP; DUR_MAX, the
longest lifetime with its lead and lags; EOHYEARS and EACHYEAR to the end of
the longest lifetime, PERIODYR for the years after the last period; the
commodity groups of single commodities, NRG_GMAP, PRC_CG; aggregated
commodities and capacity-related flows into RC; the primary group
commodities (RPC_PG), their types and sides; the shadow primary groups
(PRC_SPG, guessed for the processes that have none) and their commodities.

GAMS: ppmain.mod L249-328, v4.9.7.
"""
function ppmain_topo!(tm)
    d = tm.data
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    reg = gset(tm, "REG").members
    inreg(r) = (r,) in reg
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tset)
    io_set = [k[1] for k in gset(tm, "IO").keys]
    com = gset(tm, "COM").members

    # --- Timestep control, horizon (L253-266) -------------------------------------------
    # L254: RT_PP(R,T) = YES
    rt_pp = gmembers(tm, "RT_PP", 2)
    for (r,) in gset(tm, "REG").keys, t in tset
        push!(rt_pp, (r, t))
    end
    gput!(tm, "RT_PP", rt_pp)
    # L257: DUR_MAX=MAX(G_TLIFE,SMAX(RVP(R,T,P),NCAP_ILED(RVP)+NCAP_TLIFE(RVP)+NCAP_DLAG(RVP)+NCAP_DLIFE(RVP)+NCAP_DELIF(RVP)))
    life = [gvalues(tm, n, 3) for n in ("NCAP_ILED", "NCAP_TLIFE", "NCAP_DLAG", "NCAP_DLIFE", "NCAP_DELIF")]
    smax = GNum(-Inf)
    for k in gset_opt(d, "RVP", 3).keys
        (inreg(k[1]) && k[2] in tmem) || continue
        x = reduce(+, (gv(p, k) for p in life); init=GZERO)
        smax = gmax(smax, x)
    end
    dur_max = gmax(GNum(gscalar(tm, "G_TLIFE")), smax)
    gput!(tm, "DUR_MAX", gassign!(Dict{Tuple{},Float64}(), (), dur_max))
    minyr, miyr_vl = gscalar(tm, "MINYR"), gscalar(tm, "MIYR_VL")
    # L260: EOHYEARS(PYR)$(YEARVAL(PYR)<MINYR) = YES
    eohyears = gmembers(tm, "EOHYEARS", 1)
    foreach(k -> yv(k[1]) < minyr && push!(eohyears, k), gset(tm, "PASTYEAR").keys)
    gput!(tm, "EOHYEARS", eohyears)
    # L262-263: EACHYEAR(PASTYEAR) = YES; EACHYEAR(ALLYEAR)$((YEARVAL >= MINYR) * (YEARVAL <= (MIYR_VL+DUR_MAX))) = YES
    eachyear = union!(gmembers(tm, "EACHYEAR", 1), gset(tm, "PASTYEAR").members)
    foreach(y -> minyr <= yv(y) <= miyr_vl + dur_max.v && push!(eachyear, (y,)), ax.years)
    gput!(tm, "EACHYEAR", eachyear)
    # L266: PERIODYR(T,EACHYEAR)$((E(T)=MIYR_VL)*(YEARVAL(EACHYEAR) >= MIYR_VL)) = YES
    E = gvalues(tm, "E", 1)
    periodyr = gmembers(tm, "PERIODYR", 2)
    for t in tset
        gv(E, (t,)).v == miyr_vl || continue
        foreach(k -> yv(k[1]) >= miyr_vl && push!(periodyr, (t, k[1])), eachyear)
    end
    gput!(tm, "PERIODYR", periodyr)

    # --- Commodity groups, RC (L272-294) --------------------------------------------------
    rc, rpc = gmembers(tm, "RC", 2), gmembers(tm, "RPC", 3)
    gmap = gmembers(tm, "COM_GMAP", 3)
    # L272: MI_DMAS(COM_GMAP(RC,C)) = YES; MI_DMAS(R,C,C) = NO   (a group whose label is a commodity of RC)
    mi_dmas = Set{NTuple{3,String}}(k for k in gmap if (k[1], k[2]) in rc && k[2] != k[3])
    # L273-277: IF(CARD(MI_DMAS), OPTION DEM<TOP; <QA log>; OPTION DEM<=MI_DMAS; RC(DEM)=NO;
    #   RPC(R,P,C)$DEM(R,C)=NO; OPTION CLEAR=MI_DMAS,CLEAR=DEM)
    if !isempty(mi_dmas)
        dem = project(mi_dmas, (1, 2))
        setdiff!(rc, dem)
        filter!(k -> !((k[1], k[3]) in dem), rpc)
        gput!(tm, "DEM", Set{NTuple{2,String}}())
        gput!(tm, "RPC", rpc)
    end
    # L278: COM_GMAP(RC(R,C),C) = YES
    foreach(((r, c),) -> push!(gmap, (r, c, c)), rc)
    gput!(tm, "COM_GMAP", gmap)
    # L279: NRG_GMAP(R,NRG_GRID(NRG_TYPE),C) $= NRG_TMAP(R,NRG_TYPE,C)
    grid = gset(tm, "NRG_GRID").members
    nrg_gmap = gmembers(tm, "NRG_GMAP", 3)
    for k in gset_opt(d, "NRG_TMAP", 3).keys
        (inreg(k[1]) && (k[2],) in grid && (k[3],) in com) && push!(nrg_gmap, k)
    end
    gput!(tm, "NRG_GMAP", nrg_gmap)
    # L282-283: PRC_CG(RPC) = YES; PRC_CG(RP_PG) = YES
    rp_pg = gset(tm, "RP_PG").members
    prc_cg = union!(gmembers(tm, "PRC_CG", 3), rpc, rp_pg)
    # L286-288: OPTION MI_DMAS<=COM_AGG,FIN<COM_TMAP; LOOP(MI_DMAS(R,COM,C)$(FIN(R,COM)$FIN(R,C)),RC(R,C)=YES);
    #   OPTION CLEAR=FIN,CLEAR=MI_DMAS   (COM_AGG(REG,ALLYEAR,COM,COM): positions 1, 3, 4; COM_TMAP(REG,COM_TYPE,COM): 1, 3)
    tmap = gset(tm, "COM_TMAP")
    fin = project(tmap.keys, (1, 3))
    for (r, cm, c) in project(gparam_opt(d, "COM_AGG", 4).keys, (1, 3, 4))
        (inreg(r) && (r, cm) in fin && (r, c) in fin) && push!(rc, (r, c))
    end
    gput!(tm, "MI_DMAS", Set{NTuple{3,String}}())
    gput!(tm, "FIN", Set{NTuple{2,String}}())
    # L291: RPC_CAPFLO(RTP,C)$(NCAP_ICOM(RTP,C)+NCAP_OCOM(RTP,C)) = YES
    rtp = gset(tm, "RTP").members
    icom, ocom = gvalues(tm, "NCAP_ICOM", 4), gvalues(tm, "NCAP_OCOM", 4)
    capflo = gmembers(tm, "RPC_CAPFLO", 4)
    for k in union(keys(icom), keys(ocom))
        ((k[1], k[2], k[3]) in rtp && !iszero(gv(icom, k) + gv(ocom, k))) && push!(capflo, k)
    end
    # L292: RPC_CAPFLO(RTP,C) $= SUM(IO$NCAP_COM(RTP,C,IO),1)
    for k in gparam_opt(d, "NCAP_COM", 5).keys
        (k[1], k[2], k[3]) in rtp && push!(capflo, (k[1], k[2], k[3], k[4]))
    end
    gput!(tm, "RPC_CAPFLO", capflo)
    # L293: OPTION RPC_NOFLO < RPC_CAPFLO   (RPC_CAPFLO(R,ALLYEAR,P,C): positions 1, 3, 4)
    noflo = project(capflo, (1, 3, 4))
    gput!(tm, "RPC_NOFLO", noflo)
    # L294: LOOP(RPC_NOFLO(R,P,C)$(NOT RC(R,C)),RC(R,C)=YES)
    foreach(k -> push!(rc, (k[1], k[3])), noflo)
    gput!(tm, "RC", rc)

    # --- Primary groups (L300-307) ---------------------------------------------------------
    rp = gset(tm, "RP").members
    pg_by = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(pg_by, (k[1], k[2]), String[]), k[3]), rp_pg)
    # L300: RPC_PG(RPC(R,P,C))$SUM(RP_PG(R,P,CG)$COM_GMAP(R,CG,C),1) = YES
    rpc_pg = gmembers(tm, "RPC_PG", 3)
    for (r, p, c) in rpc
        inreg(r) || continue
        any(cg -> (r, cg, c) in gmap, get(pg_by, (r, p), String[])) && push!(rpc_pg, (r, p, c))
    end
    # L301: RPC_PG(RP_IRE(R,P),C)$(NOT RPC_IRE(R,P,C,'IMP')+RPC_IRE(R,P,C,'EXP')) = NO
    rp_ire, rpc_ire = gset(tm, "RP_IRE").members, gset(tm, "RPC_IRE").members
    filter!(k -> !((k[1], k[2]) in rp_ire && !((k..., "IMP") in rpc_ire || (k..., "EXP") in rpc_ire)), rpc_pg)
    # L303: RPC_PG(PRC_STGTSS(RP,C))$SUM(PRC_TSL(RP,TSL)$(ORD(TSL)>1),1)=YES
    tslord = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "TSLVL").keys))
    finer = Set{NTuple{2,String}}((k[1], k[2]) for k in gset(tm, "PRC_TSL").keys if get(tslord, k[3], 0) > 1)
    for k in gset_opt(d, "PRC_STGTSS", 3).keys
        ((k[1], k[2]) in rp && (k[1], k[2]) in finer) && push!(rpc_pg, k)
    end
    gput!(tm, "RPC_PG", rpc_pg)
    # L304: RP_PGTYPE(RP(R,P),COM_TYPE)$SUM(RPC_PG(R,P,C)$COM_TMAP(R,COM_TYPE,C),1) = YES
    com_type = gset(tm, "COM_TYPE").members
    types_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> (k[2],) in com_type && push!(get!(types_of, (k[1], k[3]), String[]), k[2]), tmap.keys)
    rp_pgtype = gmembers(tm, "RP_PGTYPE", 3)
    for (r, p, c) in rpc_pg
        (r, p) in rp || continue
        foreach(ct -> push!(rp_pgtype, (r, p, ct)), get(types_of, (r, c), String[]))
    end
    gput!(tm, "RP_PGTYPE", rp_pgtype)
    # L305: RP_AIRE(RP_IRE(RP),IE)$SUM(RPC_IRE(RPC_PG(RP,C),IE),1) = YES
    rp_aire = gmembers(tm, "RP_AIRE", 3)
    for (r, p, c, ie) in rpc_ire
        ((r, p) in rp && (r, p) in rp_ire && (r, p, c) in rpc_pg) && push!(rp_aire, (r, p, ie))
    end
    gput!(tm, "RP_AIRE", rp_aire)
    # L307: RP_INOUT(RP,IO)$SUM(TOP(RPC_PG(RP,C),IO),1) = YES
    top = gset(tm, "TOP")
    rp_inout = gmembers(tm, "RP_INOUT", 3)
    for (r, p, c, io) in top.keys
        ((r, p) in rp && (r, p, c) in rpc_pg) && push!(rp_inout, (r, p, io))
    end
    gput!(tm, "RP_INOUT", rp_inout)

    # --- Shadow primary groups (L309-327) ---------------------------------------------------
    top_by = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> push!(get!(top_by, (k[1], k[2], k[4]), String[]), k[3]), top.keys)
    prc_spg = gmembers(tm, "PRC_SPG", 3)
    rp_flo = gset(tm, "RP_FLO").members
    # L309: TRACKP(RP_FLO(RP))$(NOT SUM(PRC_SPG(RP,COM_GRP),1)) = YES
    has_spg = project(prc_spg, (1, 2))
    trackp = Set{NTuple{2,String}}(k for k in rp_flo if k in rp && !(k in has_spg))
    # L317: (SUM(RPC(R,P,C)$COM_TMAP(R,'MAT',C),1)$SUM(PRC_MAP(R,MATPRC,P),1))$RP_PGTYPE(R,P,'DEM')
    matprc = gset(tm, "MATPRC").members
    matmap = Set{NTuple{2,String}}((k[1], k[3]) for k in gset(tm, "PRC_MAP").keys if (k[2],) in matprc)
    has_mat = Set{NTuple{2,String}}((r, p) for (r, p, c) in rpc if (r, "MAT", c) in tmap.members)
    pg_smap = gset(tm, "PG_SMAP").keys                        # (CG,J,COM_TYPE) in GAMS order
    z = nothing
    # L310-323: LOOP((RP_PGTYPE(RP_FLO(R,P),CG),IO)$(NOT RP_INOUT(R,P,IO)), IF(TRACKP(R,P), ...))   in GAMS order
    for (r, p, cg) in gams_sort!([k for k in rp_pgtype if (k[1], k[2]) in rp_flo], d), io in io_set
        ((r, p, io) in rp_inout || !((r, p) in trackp)) && continue
        side = get(top_by, (r, p, io), String[])
        if any(c -> (r, cg, c) in gmap, side)
            # L313: same type as the PG on the other side
            push!(prc_spg, (r, p, cg))
        elseif (r, p) in has_mat && (r, p) in matmap && (r, p, "DEM") in rp_pgtype
            # L317-318: a material process with a demand PG
            push!(prc_spg, (r, p, "MAT"))
        else
            # L319-320: Z=1; LOOP(PG_SMAP(CG,J,COM_TYPE)$Z, IF(SUM(TOP(R,P,C,IO)$COM_TMAP(R,COM_TYPE,C),1), Z=0; PRC_SPG(R,P,COM_TYPE) = YES))
            z = 1.0
            for (g, _, ct) in pg_smap
                (g == cg && z != 0) || continue
                if any(c -> (r, ct, c) in tmap.members, side)
                    z = 0.0
                    push!(prc_spg, (r, p, ct))
                end
            end
        end
    end
    z === nothing || gput_scalar!(tm, "Z", z)
    gput!(tm, "PRC_SPG", prc_spg)
    # L325: LOOP((PRC_SPG(R,P,CG),IO)$(NOT RP_INOUT(R,P,IO)),RPC_SPG(R,P,C)$(TOP(R,P,C,IO)$COM_GMAP(R,CG,C)) = YES)
    rpc_spg = gmembers(tm, "RPC_SPG", 3)
    for (r, p, cg) in prc_spg, io in io_set
        (inreg(r) && !((r, p, io) in rp_inout)) || continue
        foreach(c -> (r, cg, c) in gmap && push!(rpc_spg, (r, p, c)), get(top_by, (r, p, io), String[]))
    end
    gput!(tm, "RPC_SPG", rpc_spg)
    # L326: PRC_CG(PRC_SPG) = YES
    union!(prc_cg, prc_spg)
    gput!(tm, "PRC_CG", prc_cg)
    # L327: OPTION CLEAR=TRACKP
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    return tm
end
