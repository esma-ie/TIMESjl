# M1.3 (18a): maindrv.mod L58, the extensions' ppm_ext (docs/m13-plan.md):
# ppm_ext.dsc, which exits at once, then ppm_ext.vda L11-58 with
# pp_actef.vda L9-48 (LVL): the dispatching and partial-load sets, the
# VDA_EMCB emission sums, the flows that may be reduced, and ACT_EFF
# prepared, inherited and levelled.
#
# GAMS: maindrv.mod L58, main_ext.mod L13-24, ppm_ext.dsc L1-16,
# ppm_ext.vda L11-58, pp_actef.vda L9-48, v4.9.7.
#
# main_ext.mod includes ppm_ext.<ext> for each extension in %EXTEND% order;
# ppm_ext.dsc exits at L12 (%DSC% is NO, init_ext.dsc L15-23: discrete
# capacities are refused there), and ppm_ext.vda is included as
# `ppm_ext.vda VDA mod`, so `pp_actef.%1` is pp_actef.vda. Refused
# (UnportedError): GR_VARGEN data (L12, resloadc.vda; refused at prep_ext.vda
# L38 already), discrete capacities (ppm_ext.dsc L16). Index sets: R is REG,
# V MODLYEAR, LL ALLYEAR, T MILESTONYR, S TS SL ALL_TS, C COM COM, CG
# COM_GRP, IO IN_OUT, L LIM, LNX {N, FX}, J 1*999, ITEM the universe, TSL
# TSLVL, STL the ALL_TS labels (initmty.vda L22). `$x` is true for EPS (G3),
# `NOT x` false (G25), `x = 0` true (G12); `NOT a + b` is `NOT (a + b)`
# (G37); `$=` writes nonzero or EPS values (G24, G41); `OPTION a < b` takes
# for each index of `a` the rightmost unmatched index of `b` with the same
# declared domain, `<=` the leftmost (G26, G34, G45); the circular lags
# `LL--ORD(LL)` and `S--ORD(S)` fold onto one element (G31), so VDA_FLOP at
# L28 only marks the (R,P,CG) that RPC_ACE projects; `S+STOA(S)` leads S by
# STOA(S) along ALL_TS (STOA is the lag to ANNUAL, so it is ANNUAL), rounded
# as G29 and dropped past the ends; `SQRT(ABS(EPS))` is EPS (checked 5 Nov
# 2026, GAMS 54.6.1).

"""
    ppm_ext_unported(tm) -> Vector{String}

What ppm_ext.dsc and ppm_ext.vda L11-58 meet that is not translated.
"""
function ppm_ext_unported(tm)
    out = String[]
    append!(out, init_ext_dsc_unported(tm))
    isempty(gparam_opt(tm.data, "GR_VARGEN", 4).keys) || push!(out, "ppm_ext.vda L12 (GR_VARGEN has data: resloadc.vda COEF)")
    return out
end

"""
    ppm_ext_actef_symbols(tm) -> Vector{String}

The symbols ppm_ext.vda L11-58 settles that nothing later in the prelv ->
ppm segment changes. Left out, as ppm_ext.vda L59-169 changes them (18b):
TRACKPG, TRACKPC, TRACKP, KEEP_FLOF, RPG_1ACE, RP_GRP, RPC_EMIS,
RPCC_FFUNC, RPC_FFUNC, RPC_NOFLO, which the replay checks at L58.
"""
ppm_ext_actef_symbols(tm) = ["RP_UPL", "RP_PL", "FS_EMCB", "FSCK", "FLO_SUM", "VDA_EMCB", "CG_GRP", "FS_EMIS", "FS_EMIT", "RXX",
                             "RPG_ACE", "RPG_PACE", "ACT_EFF", "UNCD7", "VDA_FLOP", "RPC_ACE", "MY_TS", "TS_ARRAY", "FSCKS", "FFCKS"]

"The symbols ppm_ext.vda L11-58 writes, for the replay at L58."
const PPM_EXT_ACTEF_OUTPUTS = ["RP_UPL", "RP_PL", "FS_EMCB", "FSCK", "FLO_SUM", "VDA_EMCB", "CG_GRP", "TRACKPG", "FS_EMIS", "FS_EMIT",
                               "TRACKPC", "RXX", "RPG_ACE", "TRACKP", "RPG_PACE", "ACT_EFF", "UNCD7", "KEEP_FLOF", "RPG_1ACE",
                               "RP_GRP", "VDA_FLOP", "RPC_ACE", "MY_TS", "TS_ARRAY", "FSCKS", "FFCKS"]

# S+n along ALL_TS: the label n places on (n rounded as G29), nothing past the ends
function ts_lead(pos::Dict{String,Int}, all_ts::Vector{String}, s, n::Float64)
    j = pos[s] + Int(round(n, RoundNearestTiesAway))
    return 1 <= j <= length(all_ts) ? all_ts[j] : nothing
end

"""
    ppm_ext_actef!(tm) -> tm

maindrv.mod L58 up to ppm_ext.vda L58, on the state after `ppmain_reduce!`:
ppm_ext.dsc (exits), then ppm_ext.vda L11-58 with pp_actef.vda LVL.

GAMS: ppm_ext.dsc L12, ppm_ext.vda L11-58, pp_actef.vda L9-48, v4.9.7.
"""
function ppm_ext_actef!(tm)
    u = ppm_ext_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    # ppm_ext.dsc L12: $IFI NOT %DSC%==YES $EXIT
    d = tm.data
    S2 = Dict{NTuple{2,String},Vector{String}}
    S3 = Dict{NTuple{3,String},Vector{String}}
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    comset = Set(k[1] for k in gset(tm, "COM").keys)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    iolab = [k[1] for k in gset(tm, "IN_OUT").keys]
    annual = gset(tm, "ANNUAL").keys[1][1]
    pgu = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    ispg(cg) = uppercase(cg) == pgu
    rp, rp_std, rp_ire = gset(tm, "RP").members, gset(tm, "RP_STD").members, gset(tm, "RP_IRE").members
    rp_flo, rp_pgact, prc_cap = gset(tm, "RP_FLO").members, gset(tm, "RP_PGACT").members, gset(tm, "PRC_CAP").members
    rpc, rpc_pg, rpc_spg = gset(tm, "RPC").members, gset(tm, "RPC_PG").members, gset(tm, "RPC_SPG").members
    rpc_ffunc, rpc_emis = gset(tm, "RPC_FFUNC").members, gset(tm, "RPC_EMIS").members
    rp_inout, gmap = gset(tm, "RP_INOUT").members, gset(tm, "COM_GMAP").members
    top = gset(tm, "TOP").members
    top_of = S3()                                   # (R,P,IO) => C, TOP order
    foreach(k -> pushat!(top_of, (k[1], k[2], k[4]), k[3]), gset(tm, "TOP").keys)
    vs_of = S2()                                    # (R,P) => V of RTP(R,V,P), GAMS order
    foreach(k -> pushat!(vs_of, (k[1], k[3]), k[2]), gset(tm, "RTP").keys)
    vs(r, p) = get(vs_of, (r, p), String[])
    rpcs_of = S3()                                  # (R,P,C) => S of RPCS_VAR
    foreach(k -> pushat!(rpcs_of, (k[1], k[2], k[3]), k[4]), gset(tm, "RPCS_VAR").keys)
    gmap_of = S2()                                  # (R,CG) => C of COM_GMAP
    foreach(k -> pushat!(gmap_of, (k[1], k[2]), k[3]), gset(tm, "COM_GMAP").keys)
    ingrp(r, p, cg, io) = [c for c in get(top_of, (r, p, io), String[]) if (r, cg, c) in gmap]

    # --- ppm_ext.vda L12-15: dispatching and partial loads -----------------------------------------------
    # L12: $IF DEFINED GR_VARGEN $BATINCLUDE resloadc.vda COEF   (no data: ppm_ext_unported)
    # L13: OPTION RP_UPL < ACT_UPS  (ACT_UPS(R,ALLYEAR,P,S,L) -> RP_UPL(R,P,L))
    rp_upl = project(keys(gvalues(tm, "ACT_UPS", 5)), (1, 3, 5))
    # L14: RP_UPL(RP,L)$(NOT PRC_CAP(RP)*RP_STD(RP)) = NO
    filter!(k -> !((k[1], k[2]) in rp && !((k[1], k[2]) in prc_cap && (k[1], k[2]) in rp_std)), rp_upl)
    # L15: RP_PL(R,P,LNX) $= SUM(V$ACT_LOSPL(R,V,P,'FX'),1)
    rp_pl = gmembers(tm, "RP_PL", 3)
    lnx = [k[1] for k in gset(tm, "LNX").keys]
    for k in keys(gvalues(tm, "ACT_LOSPL", 4))
        (k[1] in reg && k[2] in modl && uppercase(k[4]) == "FX") && foreach(l -> push!(rp_pl, (k[1], k[3], l)), lnx)
    end

    # --- L18-21: FLO_SUMs for the VDA_EMCB emissions ---------------------------------------------------
    # L18: FS_EMCB(RP_IRE(R,P),COM,C) = NO
    fs_emcb = gmembers(tm, "FS_EMCB", 4)
    filter!(k -> !((k[1], k[2]) in rp_ire), fs_emcb)
    # L19: OPTION FSCK <= FLO_SUM  (FLO_SUM(REG,ALLYEAR,PRC,CG,C,CG,TS) -> FSCK(REG,PRC,CG,C,CG))
    flo_sum = gvalues(tm, "FLO_SUM", 7)
    fsck = project(keys(flo_sum), (1, 3, 4, 5, 6))
    # L20: FLO_SUM(RTP(R,V,P),COM,C,COM,S)$((NOT FLO_SUM(RTP,COM,C,COM,S))$RPCS_VAR(R,P,C,S)$FS_EMCB(R,P,COM,C)) = VDA_EMCB(R,V,C,COM)
    emcb = gvalues(tm, "VDA_EMCB", 4)
    for (r, p, cm, c) in fs_emcb, v in vs(r, p)
        x = get(emcb, (r, v, c, cm), nothing)
        x === nothing && continue                   # = 0: no record where FLO_SUM has none
        for s in get(rpcs_of, (r, p, c), String[])
            k = (r, v, p, cm, c, cm, s)
            haskey(flo_sum, k) || (flo_sum[k] = x)
        end
    end
    # L21: VDA_EMCB(R,ALLYEAR,C,COM) = 0
    empty!(emcb)

    # --- L24-32: auxiliary flows replaced by source flow x coefficient -----------------------------------
    # L24: CG_GRP(R,P,C,COM)$FSCK(R,P,C,COM,C) = YES   (C and COM run over COM: G27)
    cg_grp = gmembers(tm, "CG_GRP", 4)
    foreach(k -> (k[3] == k[5] && k[3] in comset && k[4] in comset) && push!(cg_grp, k[1:4]), fsck)
    # L25: CG_GRP(FS_EMCB) = YES
    union!(cg_grp, fs_emcb)
    iscc(k) = k[3] in comset && k[4] in comset      # CG_GRP(R,P,C,COM)
    # L26: TRACKPG(RPC(RP_FLO,C)) $= SUM(CG_GRP(RPC,COM),1)
    trackpg = gmembers(tm, "TRACKPG", 3)
    has_cg = Set(k[1:3] for k in cg_grp if iscc(k))
    foreach(k -> ((k[1], k[2]) in rp_flo && k in has_cg) && push!(trackpg, k), rpc)
    # L27: TRACKPG(RPC_PG) = NO; TRACKPG(RPC_FFUNC) = NO; TRACKPG(RPC_EMIS) = NO
    setdiff!(trackpg, rpc_pg); setdiff!(trackpg, rpc_ffunc); setdiff!(trackpg, rpc_emis)
    # L28: LOOP(CG_GRP(R,P,C,COM)$RPC_EMIS(R,P,COM),TRACKPG(R,P,C)=NO)
    foreach(k -> (iscc(k) && (k[1], k[2], k[4]) in rpc_emis) && delete!(trackpg, k[1:3]), cg_grp)
    # L29: FS_EMIS(CG_GRP(TRACKPG(R,P,C),COM),C) = YES
    fs_emis = gmembers(tm, "FS_EMIS", 5)
    foreach(k -> (iscc(k) && k[1:3] in trackpg) && push!(fs_emis, (k..., k[3])), cg_grp)
    # L31: OPTION FS_EMIT < FS_EMIS, TRACKPC < FS_EMIS   (FS_EMIS(R,P,COM_GRP,C,COM) -> FS_EMIT(R,P,COM,COM_GRP,C), TRACKPC(R,P,C))
    fs_emit = project(fs_emis, (1, 2, 5, 3, 4))
    trackpc = project(fs_emis, (1, 2, 4))
    #      TRACKPG(TRACKPC) = NO
    setdiff!(trackpg, trackpc)
    # L32: OPTION CLEAR=CG_GRP, CLEAR=TRACKPC, CLEAR=FS_EMIS, CLEAR=FS_EMCB, CLEAR=FSCK
    empty!(cg_grp); empty!(trackpc); empty!(fs_emis); empty!(fs_emcb); empty!(fsck)

    # --- L35-56: ACT_EFF preparation, inheritance and aggregation -----------------------------------------
    rpc_ace = gmembers(tm, "RPC_ACE", 3)
    # L35: TRACKPC(RPC_ACE(RPC)) = YES
    foreach(k -> k in rpc && push!(trackpc, k), rpc_ace)
    # L36: TRACKPC(RPC_SPG(RP,C))$RPC_ACE(RP,%PGPRIM%) = YES
    ace_pg = Set((k[1], k[2]) for k in rpc_ace if ispg(k[3]))
    foreach(k -> (k[1], k[2]) in ace_pg && push!(trackpc, k), rpc_spg)
    # L37: OPTION CLEAR=RXX; RXX(RPC_ACE) = YES; RXX(TRACKPC) = NO
    rxx = Set(k for k in rpc_ace if !(k in trackpc))
    # L38: RPG_ACE(RXX(R,P,CG),IO)$(SUM(TOP(R,P,C,IO)$COM_GMAP(R,CG,C),1)$(NOT RP_INOUT(R,P,IO))) = YES
    rpg_ace = gmembers(tm, "RPG_ACE", 4)
    for (r, p, cg) in rxx, io in iolab
        (r, p, io) in rp_inout || isempty(ingrp(r, p, cg, io)) || push!(rpg_ace, (r, p, cg, io))
    end
    # L39: OPTION CLEAR=RXX
    empty!(rxx)
    # L41: LOOP(TRACKPC(RPC_PG(R,P,C)), TRACKP(R,P) = YES)
    trackp = gmembers(tm, "TRACKP", 2)
    foreach(k -> k in rpc_pg && push!(trackp, (k[1], k[2])), trackpc)
    # L42: LOOP(RPG_ACE(TRACKP(R,P),CG,IO)$(NOT SUM(TOP(R,P,C,IO)$(COM_GMAP(R,CG,C)*(NOT RPC_SPG(R,P,C))),1)),RPG_PACE(R,P,CG) = YES)
    rpg_pace = gmembers(tm, "RPG_PACE", 3)
    for (r, p, cg, io) in rpg_ace
        (r, p) in trackp || continue
        any(c -> !((r, p, c) in rpc_spg), ingrp(r, p, cg, io)) || push!(rpg_pace, (r, p, cg))
    end
    # L43: LOOP(RPG_PACE(R,P,CG), TRACKP(R,P) = NO)
    foreach(k -> delete!(trackp, (k[1], k[2])), rpg_pace)
    # L45: LOOP(RPG_ACE(R,P,CG,IO),TRACKPC(R,P,C)$COM_GMAP(R,CG,C) = NO)
    foreach(k -> foreach(c -> delete!(trackpc, (k[1], k[2], c)), get(gmap_of, (k[1], k[3]), String[])), rpg_ace)
    # L46: RXX(PRC_SPG(R,P,CG))$(TRACKP(R,P)+SUM(TRACKPC(RPC_SPG(R,P,C)),YES)) = YES
    spg_tpc = Set((k[1], k[2]) for k in trackpc if k in rpc_spg)
    foreach(k -> ((k[1], k[2]) in trackp || (k[1], k[2]) in spg_tpc) && push!(rxx, k), gset(tm, "PRC_SPG").keys)
    # L47: RPG_PACE(RXX(TRACKP,CG)) = YES
    foreach(k -> (k[1], k[2]) in trackp && push!(rpg_pace, k), rxx)
    # L48: TRACKPC(RPC_SPG) = NO
    setdiff!(trackpc, rpc_spg)
    # L50: ACT_EFF(RTP(R,V,P),CG,S)$RXX(R,P,CG) $= ACT_EFF(RTP,%PGPRIM%,S)
    act_eff = gvalues(tm, "ACT_EFF", 5)
    rtp = gset(tm, "RTP").members
    rxx_of = S2()
    foreach(k -> pushat!(rxx_of, (k[1], k[2]), k[3]), rxx)
    for (k, x) in collect(act_eff)
        (ispg(k[4]) && (k[1], k[2], k[3]) in rtp) || continue
        foreach(cg -> act_eff[(k[1], k[2], k[3], cg, k[5])] = x, get(rxx_of, (k[1], k[3]), String[]))
    end
    # L51: ACT_EFF(R,LL,P,%PGPRIM%,S) = 0
    filter!(((k, _),) -> !ispg(k[4]), act_eff)
    # L53: LOOP((TOP(TRACKPC(R,P,C),IO),COM_TMAP(R,COM_TYPE,C))$(NOT RP_INOUT(R,P,IO)),RXX(R,P,COM_TYPE) = YES)
    tmap_of = S2()                                  # (R,C) => COM_TYPE
    foreach(k -> pushat!(tmap_of, (k[1], k[3]), k[2]), gset(tm, "COM_TMAP").keys)
    for (r, p, c) in trackpc, io in iolab
        ((r, p, c, io) in top && !((r, p, io) in rp_inout)) || continue
        foreach(ct -> push!(rxx, (r, p, ct)), get(tmap_of, (r, c), String[]))
    end
    # L54: RPG_ACE(RXX(R,P,CG),IO--1)$RP_INOUT(R,P,IO) = YES   (IO--1: the other of IN, OUT)
    for (r, p, cg) in rxx, (i, io) in enumerate(iolab)
        (r, p, io) in rp_inout && push!(rpg_ace, (r, p, cg, iolab[mod1(i - 1, length(iolab))]))
    end
    # L56: LOOP(IO,ACT_EFF(RTP(R,V,P),CG,ANNUAL)$((ACT_EFF(RTP,CG,ANNUAL)=0)$RPG_ACE(R,P,CG,IO)) = 1)
    for (r, p, cg, _) in rpg_ace, v in vs(r, p)
        get(act_eff, (r, v, p, cg, annual), 0.0) == 0.0 && (act_eff[(r, v, p, cg, annual)] = 1.0)
    end

    # --- pp_actef.vda L11-48 (LVL) -----------------------------------------------------------------------
    # L11: SCALAR MICRO / 1E-6 /  (compile-time data); L12: OPTION CLEAR=UNCD7
    uncd7 = Set{NTuple{7,String}}()
    # L15: CG_GRP(RPC_ACE(RPC(R,P,C)),C) = YES
    foreach(k -> k in rpc && push!(cg_grp, (k..., k[3])), rpc_ace)
    # L16: OPTION KEEP_FLOF<RPG_1ACE, CLEAR=RPG_1ACE   (RPG_1ACE(R,P,CG,C) -> KEEP_FLOF(R,P,C))
    rpg_1ace = gmembers(tm, "RPG_1ACE", 4)
    keep_flof = project(rpg_1ace, (1, 2, 4))
    empty!(rpg_1ace)
    # L18-19: LOOP(RPG_ACE(RP_PGACT(R,P),CG,IO)$(SUM(TOP(R,P,C,IO)$COM_GMAP(R,CG,C),1) LE 1),
    #           IF(NOT RPG_PACE(R,P,CG)+RP_PL(R,P,'FX'),RP_GRP(R,P,CG)=YES; RPG_1ACE(RP_GRP(R,P,CG),C)$(TOP(R,P,C,IO)$COM_GMAP(R,CG,C)) = YES))
    rp_grp = gmembers(tm, "RP_GRP", 3)
    fx = [l for l in lnx if uppercase(l) == "FX"]
    for (r, p, cg, io) in rpg_ace
        (r, p) in rp_pgact || continue
        cs = ingrp(r, p, cg, io)
        length(cs) <= 1 || continue
        ((r, p, cg) in rpg_pace || any(l -> (r, p, l) in rp_pl, fx)) && continue
        push!(rp_grp, (r, p, cg))
        foreach(c -> push!(rpg_1ace, (r, p, cg, c)), cs)
    end
    # L21: ACT_EFF(R,LL,P,C,S)$((RPC_PG(R,P,C)+KEEP_FLOF(R,P,C))$(ACT_EFF(R,LL,P,C,S)=0)$ACT_EFF(R,LL,P,C,S)) = 0   (EPS dropped)
    filter!(((k, x),) -> !(x == 0.0 && k[4] in comset && ((k[1], k[3], k[4]) in rpc_pg || (k[1], k[3], k[4]) in keep_flof)), act_eff)
    # L22: LOOP(RPG_ACE(RPC_SPG(R,P,C),IO),ACT_EFF(RTP(R,V,P),C,S)$ACT_EFF(RTP,C,S)=SQRT(ABS(ACT_EFF(RTP,C,S))))
    #      (once for each IO the group has; SQRT(ABS(EPS)) is EPS)
    nsq = Dict{NTuple{3,String},Int}()
    foreach(k -> k[1:3] in rpc_spg && (nsq[k[1:3]] = get(nsq, k[1:3], 0) + 1), rpg_ace)
    if !isempty(nsq)
        for (k, x) in collect(act_eff)
            n = get(nsq, (k[1], k[3], k[4]), 0)
            (n > 0 && x != 0.0 && (k[1], k[2], k[3]) in rtp) || continue
            for _ in 1:n
                x = sqrt(abs(x))
            end
            act_eff[k] = x
        end
    end
    # L24: CG_GRP(RPG_1ACE) = YES; L25: RPG_ACE(RP_GRP,IO) = NO
    union!(cg_grp, rpg_1ace)
    filter!(k -> !(k[1:3] in rp_grp), rpg_ace)
    # L28: VDA_FLOP(R,LL--ORD(LL),P,CG,S--ORD(S))$STOAL(R,S) $= ACT_EFF(R,LL,P,CG,S); OPTION RPC_ACE<VDA_FLOP, CLEAR=VDA_FLOP
    stoal = gvalues(tm, "STOAL", 2)
    rpc_ace = project(keys(gvalues(tm, "VDA_FLOP", 5)), (1, 3, 4))
    foreach(k -> (k[1] in reg && haskey(stoal, (k[1], k[5]))) && push!(rpc_ace, (k[1], k[3], k[4])), keys(act_eff))
    # L29: UNCD7('1',CG_GRP(RPC_ACE(R,P,CG),C),TSL,S+STOA(S))$TS_GROUP(R,TSL,S) $= RPCS_VAR(R,P,C,S)
    tr = TsTree(tm)
    all_ts = tr.all_ts
    tspos = Dict(s => i for (i, s) in enumerate(all_ts))
    stoa = gvalues(tm, "STOA", 1)
    tsl_of = S2()                                   # (R,S) => TSL of TS_GROUP(R,TSL,S)
    foreach(k -> pushat!(tsl_of, (k[1], k[3]), k[2]), gset(tm, "TS_GROUP").keys)
    toann(s) = ts_lead(tspos, all_ts, s, get(stoa, (s,), 0.0))
    for (r, p, cg, c) in cg_grp
        ((r, p, cg) in rpc_ace && c in comset) || continue
        for s in get(rpcs_of, (r, p, c), String[]), tsl in get(tsl_of, (r, s), String[])
            a = toann(s)
            a === nothing || push!(uncd7, ("1", r, p, cg, c, tsl, a))
        end
    end
    # L30: UNCD7('2',RPG_ACE(RPC_ACE(R,P,CG),IO),TSL,S+STOA(S))$TS_GROUP(R,TSL,S) $= RPS_S1(R,P,S)
    s1_of = S2()
    foreach(k -> pushat!(s1_of, (k[1], k[2]), k[3]), gset(tm, "RPS_S1").keys)
    for (r, p, cg, io) in rpg_ace
        (r, p, cg) in rpc_ace || continue
        for s in get(s1_of, (r, p), String[]), tsl in get(tsl_of, (r, s), String[])
            a = toann(s)
            a === nothing || push!(uncd7, ("2", r, p, cg, io, tsl, a))
        end
    end
    #      CG_GRP(RPC_ACE,C) = NO
    filter!(k -> !(k[1:3] in rpc_ace && k[4] in comset), cg_grp)
    # L31: IF(CARD(NORTS),LOOP((MIYR_1(T),UNCD7(J,R,P,CG,ITEM,TS,TS)),ACT_EFF(RTP(R,V,P),CG,S)$(NORTS(R,V,S)+NORTS(R,T,S)$PASTMILE(V))=0))
    norts = Set(keys(gvalues(tm, "NORTS", 3)))
    if !isempty(norts)
        miyr1 = [k[1] for k in gset(tm, "MIYR_1").keys]
        pastmile = Set(k[1] for k in gset(tm, "PASTMILE").keys)
        rows = Set((u[2], u[3], u[4]) for u in uncd7 if u[6] == u[7])
        isempty(miyr1) && empty!(rows)
        filter!(((k, _),) -> !((k[1], k[3], k[4]) in rows && (k[1], k[2], k[3]) in rtp &&
                                ((k[1], k[2], k[5]) in norts || (k[2] in pastmile && any(t -> (k[1], t, k[5]) in norts, miyr1)))), act_eff)
    end
    # L32: OPTION CLEAR=RPC_ACE; L33: LOOP(RPG_ACE(R,P,CG,IO),RPC_ACE(R,P,C)$(TOP(R,P,C,IO)$COM_GMAP(R,CG,C)) = YES)
    empty!(rpc_ace)
    foreach(k -> foreach(c -> push!(rpc_ace, (k[1], k[2], c)), ingrp(k[1], k[2], k[3], k[4])), rpg_ace)
    # L34: RPC_ACE(KEEP_FLOF) = NO
    setdiff!(rpc_ace, keep_flof)

    # L37-42: LOOP(UNCD7(J,R,P,CG,ITEM,TSL,STL), MY_TS(S) = TS_GROUP(R,TSL,S);
    #          LOOP(RTP(R,V,P), TS_ARRAY(S) = ACT_EFF(R,V,P,CG,S);
    #           ACT_EFF(R,V,P,CG,MY_TS)$(NOT TS_ARRAY(MY_TS)) = (pp_lvlbr.mod's levelling: level_br)))
    sl = Dict{NTuple{4,String},Dict{String,Float64}}()   # ACT_EFF by (R,V,P,CG) => S => value
    for (k, x) in act_eff
        get!(() -> Dict{String,Float64}(), sl, (k[1], k[2], k[3], k[4]))[k[5]] = x
    end
    slice(r, v, p, cg) = get!(() -> Dict{String,Float64}(), sl, (r, v, p, cg))
    order = collect(uncd7)
    gams_sort!(order, d)
    my_ts, ts_array = nothing, nothing
    for (_, r, p, cg, _, tsl, _) in order
        my_ts = get(tr.group, (r, tsl), String[])
        for v in vs(r, p)
            arr = slice(r, v, p, cg)
            ts_array = copy(arr)
            for ts in my_ts
                haskey(ts_array, ts) && continue
                x = level_br(tr, ts_array, r, ts)
                iszero(x) ? delete!(arr, ts) : (arr[ts] = x.eps ? 0.0 : x.v)
            end
        end
    end
    # L44: FSCKS(CG_GRP(R,P,CG,C),CG,S)$RPCS_VAR(R,P,C,S) = YES; OPTION FFCKS <= FSCKS
    fscks = gmembers(tm, "FSCKS", 6)
    for (r, p, cg, c) in cg_grp
        c in comset && foreach(s -> push!(fscks, (r, p, cg, c, cg, s)), get(rpcs_of, (r, p, c), String[]))
    end
    ffcks = project(fscks, (1, 2, 3, 5, 6))
    # L45: ACT_EFF(RTP(R,V,P),CG,S+STOA(S))$(RPS_S1(R,P,S)$STOA(S)$ACT_EFF(RTP,CG,S)) = 0
    rps_s1 = gset(tm, "RPS_S1").members
    for ((r, v, p, cg), arr) in sl
        (r, v, p) in rtp || continue
        drop = String[]
        for s in keys(arr)
            (haskey(stoa, (s,)) && (r, p, s) in rps_s1) || continue
            a = toann(s)
            a === nothing || push!(drop, a)
        end
        foreach(a -> delete!(arr, a), drop)
    end
    # L46: ACT_EFF(RTP(R,V,P),CG,S)$(NOT ACT_EFF(RTP,CG,S)) $= SUM(FFCKS(R,P,CG,CG,S),ACT_EFF(R,V,P,CG,'ANNUAL'))
    for (r, p, cg, cg2, s) in ffcks
        cg == cg2 || continue
        for v in vs(r, p)
            arr = get(sl, (r, v, p, cg), nothing)
            (arr === nothing || haskey(arr, s)) && continue
            x = get(arr, annual, nothing)
            x === nothing || (arr[s] = x)
        end
    end
    # L47: OPTION CLEAR=FFCKS,CLEAR=FSCKS,CLEAR=CG_GRP
    empty!(ffcks); empty!(fscks); empty!(cg_grp)

    act_eff = Dict{NTuple{5,String},Float64}((k..., s) => x for (k, arr) in sl for (s, x) in arr)
    gput!(tm, "ACT_EFF", act_eff)
    for (n, x) in (("RP_UPL", rp_upl), ("RP_PL", rp_pl), ("FS_EMCB", fs_emcb), ("FSCK", fsck), ("CG_GRP", cg_grp),
                   ("TRACKPG", trackpg), ("FS_EMIS", fs_emis), ("FS_EMIT", fs_emit), ("TRACKPC", trackpc), ("RXX", rxx),
                   ("RPG_ACE", rpg_ace), ("TRACKP", trackp), ("RPG_PACE", rpg_pace), ("UNCD7", uncd7), ("KEEP_FLOF", keep_flof),
                   ("RPG_1ACE", rpg_1ace), ("RP_GRP", rp_grp), ("RPC_ACE", rpc_ace), ("FSCKS", fscks), ("FFCKS", ffcks))
        gput!(tm, n, x)
    end
    gput!(tm, "FLO_SUM", flo_sum)
    gput!(tm, "VDA_EMCB", emcb)
    gput!(tm, "VDA_FLOP", Dict{NTuple{5,String},Float64}())
    my_ts === nothing || gput!(tm, "MY_TS", Set{Tuple{String}}((s,) for s in my_ts))
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => x for (s, x) in ts_array))
    return tm
end
