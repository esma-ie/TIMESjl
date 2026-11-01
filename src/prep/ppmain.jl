# M1.3 (2): the start of preprocessing, the first block of the init -> prep
# segment (docs/m13-plan.md).
#
# GAMS: ppmain.mod L1-137, v4.9.7, run at maindrv.mod L56 after the
# extensions' init_ext (the init checkpoint).
#
# L13-29 declare the QA log file, scalars and sets; their data effects are in
# the dumps, taken after compilation. L35 (`$IF WARNINGS`) writes a header to
# QA_CHECK.LOG when compilation raised warnings; the dump does not record
# that, and TIMES.jl does not write the QA log yet (m13-plan.md, open items),
# so it is not translated. Nothing else in L1-137 needs refusing.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG is COM_GRP, LL is
# ALLYEAR, S is ALL_TS; RPC_IRE, RP_IRE and TOP_IRE run over ALL_REG, so
# external regions stay in them but an index R skips them. `OPTION a < b`
# matches positions right to left and `<=` left to right, by domain (G26); an
# alias of COM at a COM_GRP position runs only over commodities (G27); a
# statement reads the values from before it (G11); `$x` is true for EPS (G12).
# %PGPRIM% is 'ACT' (initmty.mod). PYR is an alias of PASTYEAR
# (setglobs.gms L146).

"""
    ppmain_head_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1-137 settles that nothing later in the init -> prep
segment changes (for the layer-1 check at the prep checkpoint), read on the
state after `ppmain_head!`. Some only on some models: RDCUR unless
G_CUREX/R_CUREX has data (curex.gms), NCAP_PASTI and PHYR unless
INT_DEFAULT('PASTI') (ppmain.mod L200-207), INT_DEFAULT unless G_NOINTERP
(prepparm.gms L25). PASTYEAR is not settled (ppmain.mod L160, L201); PASTSUM,
TRACKP and the scalars F, MY_F, Z are used again.
"""
function ppmain_head_symbols(tm)
    d = tm.data
    out = ["PRC_ACTUNT", "RPC_IRE", "RP_IRE", "TOP", "RPC", "RC", "RP", "RP_FLO", "RP_PG", "COM_GMAP", "RP_STS", "PRC_MAP",
           "PRC_STGIPS", "PRC_STGTSS", "PRC_TSL", "RPC_STGN", "PRC_ACT", "RPG_RED", "RPC_AIRE", "CG_GRP", "TRACKC", "TRACKPC",
           "PRC_CAP"]
    isempty(gparam_opt(d, "G_CUREX", 2)) && isempty(gparam_opt(d, "R_CUREX", 3)) && push!(out, "RDCUR")
    ("PASTI",) in gset_opt(d, "INT_DEFAULT", 1).members || append!(out, ["NCAP_PASTI", "PHYR"])
    iszero(get(gparam_opt(d, "G_NOINTERP", 0).values, (), 0.0)) && push!(out, "INT_DEFAULT")
    return out
end

"""
    ppmain_head!(tm) -> tm

ppmain.mod L1-137 on the GAMS state in `tm` (the init checkpoint): the
discounted currencies, the trade, process and commodity control sets, the
primary groups, the storage defaults and the spread of past investments.

GAMS: ppmain.mod L1-137, v4.9.7.
"""
function ppmain_head!(tm)
    reg = gset(tm, "REG")
    com = gset(tm, "COM")
    io_set = [k[1] for k in gset(tm, "IO").keys]
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    dflbl = "0"                                                       # %DFLBL% (initmty.mod L367)
    # labels the block writes that a dump holds only when some record uses them (G36)
    foreach(l -> register_uel!(tm.data, l), ("IMP", "EXP", "IN", "OUT", "STG", "STK", "STS", "NST", "ANNUAL", "PASTI", pg))

    # --- Discounted currencies (L38) --------------------------------------------
    # L38: LOOP((R,LL(BOHYEAR),CUR)$G_DRATE(R,LL,CUR), RDCUR(R,CUR) = YES)
    boh = gset(tm, "BOHYEAR")
    rdcur = gmembers(tm, "RDCUR", 2)
    for k in keys(gparam_opt(tm.data, "G_DRATE", 3).values)          # EPS counts (G12)
        ((k[1],) in reg && (k[2],) in boh) && push!(rdcur, (k[1], k[3]))
    end
    gput!(tm, "RDCUR", rdcur)

    # --- Trade, process and commodity sets (L43-55) -------------------------------
    # L43: PRC_ACTUNT(R,P,%PGPRIM%,UNITS_ACT) = NO
    actunt = filter(k -> !(k[3] == pg && (k[1],) in reg), gmembers(tm, "PRC_ACTUNT", 4))
    gput!(tm, "PRC_ACTUNT", actunt)
    # L44-45: OPTION RPC_AIRE < TOP_IRE; RPC_IRE(RPC_AIRE,'IMP') = YES; OPTION RPC_AIRE <= TOP_IRE; RPC_IRE(RPC_AIRE,'EXP') = YES
    #   TOP_IRE(ALL_REG,COM,ALL_REG,COM,PRC) onto RPC_AIRE(ALL_REG,PRC,COM): `<` takes positions 3, 5, 4, `<=` 1, 5, 2
    top_ire = gset_opt(tm.data, "TOP_IRE", 5).keys
    rpc_ire = gmembers(tm, "RPC_IRE", 4)
    foreach(k -> push!(rpc_ire, (k..., "IMP")), project(top_ire, (3, 5, 4)))
    foreach(k -> push!(rpc_ire, (k..., "EXP")), project(top_ire, (1, 5, 2)))
    gput!(tm, "RPC_IRE", rpc_ire)
    # L46: OPTION CLEAR=RPC_AIRE, PRC_ACT < PRC_ACTUNT
    gput!(tm, "RPC_AIRE", Set{NTuple{3,String}}())
    prc_act = project(actunt, (1, 2))
    # L47: RP_IRE(ALL_R,P)$SUM(RPC_IRE(ALL_R,P,C,IE),1) = YES
    rp_ire = union!(gmembers(tm, "RP_IRE", 2), project(rpc_ire, (1, 2)))
    gput!(tm, "RP_IRE", rp_ire)
    # L48-49: TOP(RP_IRE(R,P),C,'IN')$RPC_IRE(R,P,C,'EXP') = NO; TOP(RP_IRE(R,P),C,'OUT')$RPC_IRE(R,P,C,'IMP') = NO
    top = gmembers(tm, "TOP", 4)
    filter!(k -> !((k[1],) in reg && (k[4] == "IN" ? (k[1], k[2], k[3], "EXP") in rpc_ire :
                                      k[4] == "OUT" && (k[1], k[2], k[3], "IMP") in rpc_ire)), top)
    # L50: TOP(RPG_RED(PRC_ACT(R,P),C,IO))$(COM_TMAP(R,'ENV',C)+RP_IRE(R,P)) = YES
    tmap = gset(tm, "COM_TMAP")
    for (r, p, c, io) in gset_opt(tm.data, "RPG_RED", 4).keys
        ((r, p) in prc_act && (c,) in com) || continue                 # C at the CG position: commodities only (G27)
        ((r, "ENV", c) in tmap || (r, p) in rp_ire) && push!(top, (r, p, c, io))
    end
    # L52: RPC(R,P,C)$(SUM(TOP(R,P,C,IO),1) + SUM(RPC_IRE(R,P,C,IE),1)) = YES
    rpc = gmembers(tm, "RPC", 3)
    foreach(k -> push!(rpc, (k[1], k[2], k[3])), top)
    for k in rpc_ire
        (k[1],) in reg && push!(rpc, (k[1], k[2], k[3]))
    end
    gput!(tm, "RPC", rpc)
    # L53-55: RC(R,C), RP(R,P) from RPC; RP_FLO(RP)$(NOT RP_IRE(RP)) = YES
    gput!(tm, "RC", union!(gmembers(tm, "RC", 2), project(rpc, (1, 3))))
    rp = union!(gmembers(tm, "RP", 2), project(rpc, (1, 2)))
    gput!(tm, "RP", rp)
    gput!(tm, "RP_FLO", union!(gmembers(tm, "RP_FLO", 2), filter(k -> !(k in rp_ire), rp)))

    # --- Primary groups (L58-65) --------------------------------------------------
    # L58: OPTION RP_PG < PRC_ACTUNT, CLEAR=RPG_RED, CLEAR=PRC_ACT
    rp_pg = project(actunt, (1, 2, 3))
    gput!(tm, "RPG_RED", Set{NTuple{4,String}}())
    # L59: PRC_ACT(RP)$(NOT SUM(RP_PG(RP,CG),1)) = YES
    has_pg = project(rp_pg, (1, 2))
    prc_act = Set{NTuple{2,String}}(k for k in rp if !(k in has_pg))
    # L60-63: IF(CARD(PRC_ACT),
    #   TRACKPC(PRC_ACT(R,P),C)$((NOT COM_TMAP(R,'ENV',C)+COM_TMAP(R,'FIN',C))$TOP(R,P,C,'OUT')) = YES;
    #   PRC_ACT(RP)$(SUM(TRACKPC(RP,C),1) NE 1) = NO; RP_PG(TRACKPC(PRC_ACT,C)) = YES; OPTION CLEAR=PRC_ACT,CLEAR=TRACKPC)
    #   NOT ranks below +: NOT (ENV + FIN)
    trackpc = gmembers(tm, "TRACKPC", 3)
    for (r, p, c, io) in top
        (io == "OUT" && (r, p) in prc_act) || continue
        ((r, "ENV", c) in tmap || (r, "FIN", c) in tmap) || push!(trackpc, (r, p, c))
    end
    npc = Dict{NTuple{2,String},Int}()
    foreach(k -> (npc[(k[1], k[2])] = get(npc, (k[1], k[2]), 0) + 1), trackpc)
    filter!(k -> get(npc, k, 0) == 1, prc_act)
    for k in trackpc
        (k[1], k[2]) in prc_act && push!(rp_pg, k)
    end
    gput!(tm, "RP_PG", rp_pg)
    gput!(tm, "PRC_ACT", Set{NTuple{2,String}}())
    empty!(trackpc)
    # L65: COM_GMAP(COM_TMAP) = YES
    gmap = union!(gmembers(tm, "COM_GMAP", 3), tmap.keys)
    gput!(tm, "COM_GMAP", gmap)

    # --- Storage defaults (L71-117) -----------------------------------------------
    # L72-73: TRACKC(R,C)$COM_LIM(R,C,'N') = YES; TRACKC(R,%PGPRIM%) = YES
    trackc = gmembers(tm, "TRACKC", 2)
    for k in gset_opt(tm.data, "COM_LIM", 3).keys
        (k[3] == "N" && (k[1],) in reg) && push!(trackc, (k[1], k[2]))
    end
    foreach(((r,),) -> push!(trackc, (r, pg)), reg.keys)
    # L76: RP_STS(R,P)$PRC_MAP(R,'STS',P) = YES
    prc_map = gmembers(tm, "PRC_MAP", 3)
    rp_sts = gmembers(tm, "RP_STS", 2)
    for (r, g, p) in prc_map
        (g == "STS" && (r,) in reg) && push!(rp_sts, (r, p))
    end
    gput!(tm, "RP_STS", rp_sts)
    # L77-79: TRACKP(R,P)$(PRC_MAP(R,'STG',P)+PRC_MAP(R,'STK',P)+RP_STS(R,P)) = YES;
    #         TRACKP(R,P)$SUM(PRC_STGTSS(R,P,C),1) = NO; TRACKP(R,P)$SUM(PRC_NSTTS(R,P,S),1) = NO
    trackp = gmembers(tm, "TRACKP", 2)
    for (r, g, p) in prc_map
        (g in ("STG", "STK") && (r,) in reg) && push!(trackp, (r, p))
    end
    union!(trackp, rp_sts)
    stgtss = gmembers(tm, "PRC_STGTSS", 3)
    nstts = gset_opt(tm.data, "PRC_NSTTS", 3).keys
    setdiff!(trackp, project(stgtss, (1, 2)))
    setdiff!(trackp, project(nstts, (1, 2)))
    # L80: TRACKPC(TRACKP(R,P),C)$SUM((TOP(R,P,C,IO),RP_PG(R,P,CG))$COM_GMAP(R,CG,C),1) = YES
    pg_by = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(pg_by, (k[1], k[2]), String[]), k[3]), rp_pg)
    for (r, p, c, _) in top
        (r, p) in trackp || continue
        any(cg -> (r, cg, c) in gmap, get(pg_by, (r, p), String[])) && push!(trackpc, (r, p, c))
    end
    # L81: TRACKPC(TRACKP(R,P),C)$SUM(RP_PG(R,P,C)$(NOT TRACKC(R,C)),1) = YES
    for (r, p, c) in rp_pg
        ((r, p) in trackp && (c,) in com && !((r, c) in trackc)) && push!(trackpc, (r, p, c))
    end
    # L83: RPC_STGN(TOP(TRACKP(R,P),C,IO))$SUM((COM_GMAP(R,COM_TYPE(CG),C),TRACKPC(R,P,COM))$COM_GMAP(R,CG,COM),1) = YES
    com_type = gset(tm, "COM_TYPE")
    tracked = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(tracked, (k[1], k[2]), String[]), k[3]), trackpc)
    rpc_stgn = gmembers(tm, "RPC_STGN", 4)
    for (r, p, c, io) in top
        (r, p) in trackp || continue
        coms = get(tracked, (r, p), String[])
        any(((cg,),) -> (r, cg, c) in gmap && any(cm -> (r, cg, cm) in gmap, coms), com_type.keys) && push!(rpc_stgn, (r, p, c, io))
    end
    # L84: OPTION CG_GRP < FLO_FUNC; RPC_STGN(RP,C,IO)$SUM(RPC_STGN(TRACKPC(RP,COM),IO),1) = NO   (G11: the old RPC_STGN)
    cg_grp = project(gparam_opt(tm.data, "FLO_FUNC", 6).keys, (1, 3, 4, 5))
    stored_io = Set{NTuple{3,String}}((r, p, io) for (r, p, c, io) in rpc_stgn if (r, p, c) in trackpc)
    filter!(k -> !((k[1], k[2]) in rp && (k[1], k[2], k[4]) in stored_io), rpc_stgn)
    # L85: LOOP(CG_GRP(TRACKP(RP),C,COM), IF(TRACKPC(RP,C), RPC_STGN(RP,COM,IO)=NO ELSEIF TRACKPC(RP,COM), RPC_STGN(RP,C,IO)=NO))
    for (r, p, c, cm) in cg_grp
        ((r, p) in trackp && (r, p) in rp && (c,) in com && (cm,) in com) || continue
        drop = (r, p, c) in trackpc ? cm : (r, p, cm) in trackpc ? c : nothing
        drop === nothing || foreach(io -> delete!(rpc_stgn, (r, p, drop, io)), io_set)
    end
    # L86: TRACKPC(RPC) $= SUM(RPC_STGN(RPC,IO),1)
    for (r, p, c, _) in rpc_stgn
        (r, p, c) in rpc && push!(trackpc, (r, p, c))
    end
    # L89-93: LOOP(PRC_NSTTS(R,P,S), PRC_MAP(R,'STG',P) = YES; PRC_MAP(R,'NST',P) = YES; PRC_MAP(R,'STK',P) = NO)
    for (r, p, _) in nstts
        push!(prc_map, (r, "STG", p), (r, "NST", p))
        delete!(prc_map, (r, "STK", p))
    end
    # L95: PRC_STGIPS(TRACKPC(R,P,C))$PRC_MAP(R,'STK',P) = YES
    stgips = gmembers(tm, "PRC_STGIPS", 3)
    foreach(k -> (k[1], "STK", k[2]) in prc_map && push!(stgips, k), trackpc)
    # L96-102: LOOP(PRC_STGIPS(R,P,C), PRC_MAP(R,'STG',P) = YES; PRC_MAP(R,'STK',P) = YES; PRC_MAP(R,'NST',P) = NO;
    #   IF(NOT SUM(TOP(R,P,C,IO),1),TOP(R,P,C,IO)=YES); IF(NOT RP_STS(R,P),PRC_TSL(R,P,TSLVL) = SAMEAS(TSLVL,'ANNUAL')))
    prc_tsl = gmembers(tm, "PRC_TSL", 3)
    no_top(r, p, c) = !any(io -> (r, p, c, io) in top, io_set)
    for (r, p, c) in stgips
        push!(prc_map, (r, "STG", p), (r, "STK", p))
        delete!(prc_map, (r, "NST", p))
        no_top(r, p, c) && foreach(io -> push!(top, (r, p, c, io)), io_set)
        if !((r, p) in rp_sts)
            filter!(k -> !(k[1] == r && k[2] == p), prc_tsl)
            push!(prc_tsl, (r, p, "ANNUAL"))
        end
    end
    # L104: PRC_STGTSS(TRACKPC(R,P,C))$(NOT PRC_MAP(R,'STK',P)) = YES
    foreach(k -> (k[1], "STK", k[2]) in prc_map || push!(stgtss, k), trackpc)
    # L105-111: LOOP(PRC_STGTSS(R,P,C), PRC_MAP(R,'STG',P) = YES; PRC_MAP(R,'STS',P) = YES; PRC_MAP(R,'NST',P) = NO;
    #   PRC_MAP(R,'STK',P) = NO; IF(NOT SUM(TOP(R,P,C,IO),1),TOP(R,P,C,IO)=YES))
    for (r, p, c) in stgtss
        push!(prc_map, (r, "STG", p), (r, "STS", p))
        delete!(prc_map, (r, "NST", p))
        delete!(prc_map, (r, "STK", p))
        no_top(r, p, c) && foreach(io -> push!(top, (r, p, c, io)), io_set)
    end
    gput!(tm, "PRC_MAP", prc_map)
    gput!(tm, "PRC_STGIPS", stgips)
    gput!(tm, "PRC_STGTSS", stgtss)
    gput!(tm, "PRC_TSL", prc_tsl)
    # L113: OPTION CLEAR=TRACKC,CLEAR=TRACKP,CLEAR=TRACKPC,CLEAR=CG_GRP,CLEAR=RPC_STGN
    gput!(tm, "TRACKC", Set{NTuple{2,String}}())
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "CG_GRP", Set{NTuple{4,String}}())
    # L115-116: RPC_STGN(PRC_STGTSS(R,P,C),IO)$(NOT SUM(TOP(R,P,COM,IO)$PRC_STGTSS(R,P,COM),1)) = YES; the same for PRC_STGIPS
    rpc_stgn = Set{NTuple{4,String}}()
    for stg in (stgtss, stgips)
        stored = Dict{NTuple{2,String},Vector{String}}()
        foreach(k -> push!(get!(stored, (k[1], k[2]), String[]), k[3]), stg)
        for (r, p, c) in stg, io in io_set
            any(cm -> (r, p, cm, io) in top, stored[(r, p)]) || push!(rpc_stgn, (r, p, c, io))
        end
    end
    gput!(tm, "RPC_STGN", rpc_stgn)
    # L117: TOP(RPC_STGN) = YES
    union!(top, rpc_stgn)
    gput!(tm, "TOP", top)

    # --- Spread of past investments (L122-136) --------------------------------------
    # L124: OPTION PRC_CAP < NCAP_PASTY
    pasty = gparam_opt(tm.data, "NCAP_PASTY", 3)
    prc_cap = project(pasty.keys, (1, 3))
    # L125-130: LOOP((PRC_CAP(RP(R,P)),PASTYEAR(LL))$(NCAP_PASTY(R,PASTYEAR,P) > 1),
    #   F = NCAP_PASTY(R,LL,P); MY_F = NCAP_PASTI(R,LL,P) / F;
    #   FOR(Z = F-1 DOWNTO 0, PASTSUM(R,ALLYEAR(LL-Z),P) = PASTSUM(R,ALLYEAR,P) + MY_F);
    #   NCAP_PASTI(R,LL,P) = 0)
    # In GAMS loop order (R, P, then LL); a lag by a non-integer Z is rounded (G29); a lag before the first year selects nothing.
    allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
    pos = Dict(y => i for (i, y) in enumerate(allyear))
    pastyear = [k[1] for k in gset(tm, "PASTYEAR").keys]
    pasti = gvalues(tm, "NCAP_PASTI", 3)
    pastsum = Dict{NTuple{3,String},Float64}()
    loop_rp = gams_sort!([k for k in prc_cap if k in rp], tm.data)
    for (r, p) in loop_rp, ll in pastyear
        f = get(pasty.values, (r, ll, p), 0.0)
        f > 1 || continue
        my_f = gv(pasti, (r, ll, p)) / GNum(f)
        z = f - 1
        while z >= 0
            j = pos[ll] - glead(z)
            j >= 1 && gassign!(pastsum, (r, allyear[j], p), gv(pastsum, (r, allyear[j], p)) + my_f)
            z -= 1
        end
        delete!(pasti, (r, ll, p))
    end
    # L132: NCAP_PASTI(R,LL,P)$PASTSUM(R,LL,P) = NCAP_PASTI(R,LL,P) + PASTSUM(R,LL,P)
    for k in keys(pastsum)
        gassign!(pasti, k, gv(pasti, k) + gv(pastsum, k))
    end
    gput!(tm, "NCAP_PASTI", pasti)
    # L134-135: OPTION PASTYEAR < NCAP_PASTI; INT_DEFAULT('PASTI')$PYR('0')=1; PYR('0')=NO
    pyr = project(keys(pasti), (2,))
    if (dflbl,) in pyr
        intd = gmembers(tm, "INT_DEFAULT", 1)
        push!(intd, ("PASTI",))
        gput!(tm, "INT_DEFAULT", intd)
        delete!(pyr, (dflbl,))
    end
    gput!(tm, "PASTYEAR", pyr)
    # L136: OPTION CLEAR=PRC_CAP, CLEAR=PASTSUM
    gput!(tm, "PRC_CAP", Set{NTuple{2,String}}())
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    return tm
end
