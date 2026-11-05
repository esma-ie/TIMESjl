# M1.3 (13b): ppmain.mod L1003-1056 (docs/m13-plan.md): the cumulative
# bounds moved from the BOH and EOH labels to the first and last years
# (UC_CUMFLO, FLO_CUM, UC_CUMCOM, COM_CUM) with their control sets
# (RPC_CUMFLO, RC_CUMCOM), and the commodities whose VAR_COMNET or VAR_COMPRD
# goes on the right-hand side of the balance (RC_AGP, RHS_COMBAL,
# RHS_COMPRD, RTC_NET, RTC_PRD, the COM_CSTNET and COM_CSTPRD flags).
#
# GAMS: ppmain.mod L1003-1056, v4.9.7.
#
# Index sets: R is REG, P is PRC, C and COM are COM, UC_N the user
# constraints, BOHYEAR the label BOH and the years 1960-2200, EOHYEAR those
# and EOH, YEAR and LL are ALLYEAR, S and TS are ALL_TS, T is MILESTONYR, BD
# is BND_TYPE (LO, FX, UP), L is LIM, COM_VAR the labels NET and PRD.
# `BOHYEAR+BEOH(BOHYEAR)` leads along BOHYEAR by BEOH (1 for BOH, -1 for EOH,
# 0 otherwise), so BOH becomes the first year and EOH the last. `$x` is true
# for EPS (G3) and `NOT x` false (G25); a numeric comparison takes EPS as 0
# (G12); `$=` writes only a nonzero or EPS value (G24); a right-hand side
# that names the symbol being assigned reads it as it was before the
# statement (G11).

"""
    ppmain_cum_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1003-1056 settles that nothing later in the prelv
-> ppm segment changes (for the layer-1 check at the ppm checkpoint).
"""
ppmain_cum_symbols(tm) = ["UC_CUMFLO", "UC_CUMACT", "FLO_CUM", "ACT_CUM", "RPC_CUMFLO", "UC_CUMCOM", "RC_CUMCOM", "COM_CUM",
                          "COM_CUMNET", "COM_CUMPRD", "RC_AGP", "RTC_NET", "RTC_PRD", "COM_CSTNET", "COM_CSTPRD"]

"""
    ppmain_cum!(tm) -> tm

ppmain.mod L1003-1056 on the state after `ppmain_bnd!`.

GAMS: ppmain.mod L1003-1056, v4.9.7.
"""
function ppmain_cum!(tm)
    tr = TsTree(tm)
    reg = tr.reg
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tlist)
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    com, allyear, lim, bdset, ucn, comvar = member("COM"), member("ALLYEAR"), member("LIM"), member("BD"), member("UC_N"), member("COM_VAR")
    rp, rc = gset(tm, "RP").members, gset(tm, "RC").members
    bohs, eohs = [k[1] for k in gset(tm, "BOHYEAR").keys], [k[1] for k in gset(tm, "EOHYEAR").keys]
    bohset, eohset = Set(bohs), Set(eohs)
    beoh = gvalues(tm, "BEOH", 1)
    bax, eax = OrdAxis(bohs), OrdAxis(eohs)
    # BOHYEAR+BEOH(BOHYEAR), EOHYEAR+BEOH(EOHYEAR): nothing when the lead leaves the set
    sb(y) = lead(bax, y, glead(Float64(gv(beoh, (y,)))))
    se(y) = lead(eax, y, glead(Float64(gv(beoh, (y,)))))
    pg = strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"'])
    gnum(x) = x == 0.0 ? GEPS : GNum(x)
    # shift!(x, bp, ok): X(..,BOHYEAR+BEOH(BOHYEAR),EOHYEAR+BEOH(EOHYEAR),..) $= X(..,BOHYEAR,EOHYEAR,..) for the records `ok`
    # admits, the BOH/EOH pair at positions bp and bp+1; `to` gives the target record's other indexes (G11: from before)
    function shift!(dst, src, bp, ok; to=k -> k, yearok=(b, e) -> true)
        put = Pair{Any,Float64}[]
        for (k, x) in src
            (ok(k) && k[bp] in bohset && k[bp+1] in eohset) || continue
            b, e = sb(k[bp]), se(k[bp+1])
            (b === nothing || e === nothing || !yearok(b, e)) && continue
            push!(put, to((k[1:bp-1]..., b, e, k[bp+2:end]...)) => x)
        end
        foreach(((k, x),) -> (dst[k] = x), put)
        return dst
    end
    notyears(k, bp) = k[bp] in bohset && k[bp+1] in eohset && !(k[bp] in allyear && k[bp+1] in allyear)

    # --- L1006-1016: process flows -----------------------------------------------------------------------
    ucf = gvalues(tm, "UC_CUMFLO", 6)                                      # (UC_N,R,P,C,BOH,EOH)
    okf(k) = k[1] in ucn && k[2] in reg && k[4] in com
    # L1007: UC_CUMFLO(UC_N,R,P,C,BOHYEAR+BEOH(BOHYEAR),EOHYEAR+BEOH(EOHYEAR)) $= UC_CUMFLO(UC_N,R,P,C,BOHYEAR,EOHYEAR)
    shift!(ucf, copy(ucf), 5, okf)
    # L1008: UC_CUMFLO(UC_N,R,P,C,BOHYEAR,EOHYEAR)$(NOT LL(BOHYEAR)*LL(EOHYEAR)) = 0
    filter!(((k, _),) -> !(okf(k) && notyears(k, 5)), ucf)
    # L1009: UC_CUMFLO(UC_N,R,P,%PGPRIM%,BOHYEAR+BEOH(BOHYEAR),EOHYEAR+BEOH(EOHYEAR)) $= UC_CUMACT(UC_N,R,P,BOHYEAR,EOHYEAR)
    shift!(ucf, gvalues(tm, "UC_CUMACT", 5), 4, k -> k[1] in ucn && k[2] in reg; to=k -> (k[1], k[2], k[3], pg, k[4], k[5]))
    gput!(tm, "UC_CUMFLO", ucf)
    # L1010: LOOP((UC_N,RP,C,YEAR,LL)$UC_CUMFLO(UC_N,RP,C,YEAR,LL),RPC_CUMFLO(RP,C,YEAR,LL)=YES)
    cumflo = gmembers(tm, "RPC_CUMFLO", 5)
    for k in keys(ucf)
        (k[1] in ucn && (k[2], k[3]) in rp && k[4] in com && k[5] in allyear && k[6] in allyear) && push!(cumflo, k[2:6])
    end
    # L1012-1014: FLO_CUM the same, ACT_CUM as the flow of %PGPRIM%
    fcum = gvalues(tm, "FLO_CUM", 6)                                       # (R,P,C,BOH,EOH,L)
    okc(k) = k[1] in reg && k[3] in com && k[6] in lim
    shift!(fcum, copy(fcum), 4, okc)
    filter!(((k, _),) -> !(okc(k) && notyears(k, 4)), fcum)
    shift!(fcum, gvalues(tm, "ACT_CUM", 5), 3, k -> k[1] in reg && k[5] in lim; to=k -> (k[1], k[2], pg, k[3], k[4], k[5]))
    gput!(tm, "FLO_CUM", fcum)
    # L1015: RPC_CUMFLO(RP,C,YEAR,LL) $= SUM(L$FLO_CUM(RP,C,YEAR,LL,L),YES)
    for k in keys(fcum)
        ((k[1], k[2]) in rp && k[3] in com && k[4] in allyear && k[5] in allyear && k[6] in lim) && push!(cumflo, k[1:5])
    end
    gput!(tm, "RPC_CUMFLO", cumflo)
    # L1016: OPTION CLEAR=UC_CUMACT,CLEAR=ACT_CUM
    gput!(tm, "UC_CUMACT", Dict{NTuple{5,String},Float64}())
    gput!(tm, "ACT_CUM", Dict{NTuple{5,String},Float64}())

    # --- L1017-1025: commodities -------------------------------------------------------------------------
    ucc = gvalues(tm, "UC_CUMCOM", 6)                                      # (UC_N,R,COM_VAR,C,BOH,EOH)
    okm(k) = k[1] in ucn && k[2] in reg && k[3] in comvar && k[4] in com
    shift!(ucc, copy(ucc), 5, okm)                                         # L1018
    # L1019: UC_CUMCOM(UC_N,R,COM_VAR,C,BOHYEAR,EOHYEAR)$(NOT LL(BOHYEAR)*LL(EOHYEAR)*RC(R,C)) = 0
    filter!(((k, _),) -> !(okm(k) && k[5] in bohset && k[6] in eohset && !(k[5] in allyear && k[6] in allyear && (k[2], k[4]) in rc)), ucc)
    gput!(tm, "UC_CUMCOM", ucc)
    # L1020: LOOP((UC_N,R,COM_VAR,C,YEAR,LL)$UC_CUMCOM(...),RC_CUMCOM(R,COM_VAR,YEAR,LL,C)=YES)
    rccum = gmembers(tm, "RC_CUMCOM", 5)
    foreach(k -> (okm(k) && k[5] in allyear && k[6] in allyear) && push!(rccum, (k[2], k[3], k[5], k[6], k[4])), keys(ucc))
    # L1022-1023: COM_CUM(R,'NET'|'PRD',YEAR(BOHYEAR+BEOH(BOHYEAR)),LL(EOHYEAR+BEOH(EOHYEAR)),C,L) $= COM_CUMNET|PRD(R,BOHYEAR,EOHYEAR,C,L)
    ccum = gvalues(tm, "COM_CUM", 6)
    for (v, n) in (("NET", "COM_CUMNET"), ("PRD", "COM_CUMPRD"))
        shift!(ccum, gvalues(tm, n, 5), 2, k -> k[1] in reg && k[4] in com && k[5] in lim;
               to=k -> (k[1], v, k[2], k[3], k[4], k[5]), yearok=(b, e) -> b in allyear && e in allyear)
        gput!(tm, n, Dict{NTuple{5,String},Float64}())                     # L1024
    end
    gput!(tm, "COM_CUM", ccum)
    # L1025: RC_CUMCOM(R,COM_VAR,YEAR,LL(EOHYEAR),C) $= SUM(L$COM_CUM(R,COM_VAR,YEAR,LL,C,L),YES)
    for k in keys(ccum)
        (k[1] in reg && k[2] in comvar && k[3] in allyear && k[4] in allyear && k[4] in eohset && k[5] in com && k[6] in lim) &&
            push!(rccum, (k[1], k[2], k[3], k[4], k[5]))
    end
    gput!(tm, "RC_CUMCOM", rccum)

    # --- L1030-1056: VAR_COMxxx on the RHS of the balance --------------------------------------------------
    rcvar = gset(tm, "RTCS_VARC").keys
    by_rc = Dict{NTuple{2,String},Vector{NTuple{4,String}}}()
    foreach(k -> k[2] in tmem && pushat!(by_rc, (k[1], k[3]), k), rcvar)
    comlim = gset(tm, "COM_LIM").members
    # L1031: LOOP((R,T,C,COM)$COM_AGG(R,T,C,COM),RC_AGP(COM_LIM(R,C,LIM)) = YES)
    agp = gmembers(tm, "RC_AGP", 3)
    for k in gparam_opt(tm.data, "COM_AGG", 4).keys
        (k[1] in reg && k[2] in tmem && k[3] in com && k[4] in com) || continue
        foreach(l -> (k[1], k[3], l) in comlim && push!(agp, (k[1], k[3], l)), lim)
    end
    # L1032: RC_AGP(R,C,BD)$(COM_TMAP(R,'DEM',C)$RC_AGP(R,C,'LO')) = NOT BDNEQ(BD)
    tmap = gset(tm, "COM_TMAP").members
    bdneq = member("BDNEQ")
    for (r, c, l) in collect(agp)
        (l == "LO" && (r, "DEM", c) in tmap) || continue
        foreach(b -> b in bdneq ? delete!(agp, (r, c, b)) : push!(agp, (r, c, b)), bdset)
    end
    # L1033: RC_AGP(RC,'FX')$RC_AGP(RC,'N') = YES
    foreach(k -> (k[3] == "N" && (k[1], k[2]) in rc) && push!(agp, (k[1], k[2], "FX")), collect(agp))
    gput!(tm, "RC_AGP", agp)
    rhsb, rhsp = gmembers(tm, "RHS_COMBAL", 4), gmembers(tm, "RHS_COMPRD", 4)
    # L1034-1035: RHS_COMBAL|RHS_COMPRD(RTCS_VARC(R,T,C,S))$RC_AGP(R,C,'LO'|'FX') = YES
    for (r, c, l) in agp
        l == "LO" && union!(rhsb, get(by_rc, (r, c), NTuple{4,String}[]))
        l == "FX" && union!(rhsp, get(by_rc, (r, c), NTuple{4,String}[]))
    end
    # L1037: $IF DEFINED DAM_ELAST RHS_COMPRD(RTCS_VARC(R,T,C,S))$DAM_ELAST(R,C,'N') = YES   (DEFINED: has data, G35)
    for k in gparam_opt(tm.data, "DAM_ELAST", 3).keys
        k[3] == "N" && union!(rhsp, get(by_rc, (k[1], k[2]), NTuple{4,String}[]))
    end
    # L1039-1046: LOOP(RC_CUMCOM(R,'NET'|'PRD',ALLYEAR,LL,C), RTC_NET|RTC_PRD(R,T,C)$((E(T) >= YEARVAL(ALLYEAR)) * (B(T) <= YEARVAL(LL))) = YES;
    #   $IFI %OBJ%==LIN RTC_xxx(R,T,C)$((M(T)+LAGT(T) > YEARVAL(ALLYEAR)) * (M(T)-LEAD(T) < YEARVAL(LL))) = YES)
    yv = gvalues(tm, "YEARVAL", 1)
    B, E, M, LAGT, LEAD = (gvalues(tm, n, 1) for n in ("B", "E", "M", "LAGT", "LEAD"))
    lin = uppercase(gswitch(tm, "OBJ", "")) == "LIN"
    f1(d, t) = gv(d, (t,)).v
    rtcn, rtcp = gmembers(tm, "RTC_NET", 3), gmembers(tm, "RTC_PRD", 3)
    for (r, v, a, l, c) in rccum
        (r in reg && a in allyear && l in allyear && c in com && v in ("NET", "PRD")) || continue
        dst = v == "NET" ? rtcn : rtcp
        ya, yl = f1(yv, a), f1(yv, l)
        for t in tlist
            (f1(E, t) >= ya && f1(B, t) <= yl) && push!(dst, (r, t, c))
            (lin && f1(M, t) + f1(LAGT, t) > ya && f1(M, t) - f1(LEAD, t) < yl) && push!(dst, (r, t, c))
        end
    end
    gput!(tm, "RTC_NET", rtcn)
    gput!(tm, "RTC_PRD", rtcp)
    # L1048: RHS_COMBAL(RTCS_VARC(RTC_NET,S)) = YES
    foreach(k -> k[2] in tmem && (k[1], k[2], k[3]) in rtcn && push!(rhsb, k), rcvar)
    lastll, lasts = last(gset(tm, "ALLYEAR").keys)[1], last(tr.all_ts)
    rdcur = gset(tm, "RDCUR").members
    function flags!(cst, a, b)
        # COM_CSTxxx(R,LL--ORD(LL),C,S--ORD(S),CUR)$(COM_CSTxxx(R,LL,C,S,CUR)+COM_SUBxxx(...)+COM_TAXxxx(...)) = EPS
        x = gvalues(tm, cst, 5)
        ps = (gparam_opt(tm.data, cst, 5).values, gparam_opt(tm.data, a, 5).values, gparam_opt(tm.data, b, 5).values)
        for k in union(Set(keys(ps[1])), keys(ps[2]), keys(ps[3]))
            (k[1] in reg && k[3] in com) || continue
            iszero(reduce(+, (gnum(p[k]) for p in ps if haskey(p, k)); init=GZERO)) && continue
            x[(k[1], lastll, k[3], lasts, k[5])] = 0.0
        end
        gput!(tm, cst, x)
        return x
    end
    # L1049-1050 (NET), L1053-1054 (PRD): the flags, then LOOP((R,C,S,RDCUR(R,CUR))$COM_CSTxxx(R,'0',C,S,CUR), RHS_xxx(RTCS_VARC(R,T,C,TS)) = YES)
    for (cst, a, b, dst) in (("COM_CSTNET", "COM_SUBNET", "COM_TAXNET", rhsb), ("COM_CSTPRD", "COM_SUBPRD", "COM_TAXPRD", rhsp))
        x = flags!(cst, a, b)
        for k in keys(x)
            (k[2] == "0" && k[1] in reg && k[3] in com && (k[1], k[5]) in rdcur) && union!(dst, get(by_rc, (k[1], k[3]), NTuple{4,String}[]))
        end
    end
    # L1051: RHS_COMBAL(RTCS_VARC(R,T,C,S))$SUM((TS_MAP(R,TS,S),BD)$COM_BNDNET(R,T,C,TS,BD),ABS(COM_BNDNET(R,T,C,TS,BD)) NE INF$BDUPX(BD)) = YES
    # L1055-1056: RHS_COMPRD(...)$SUM((TS_MAP(R,TS,S),BD)$COM_BNDPRD(R,T,C,TS,BD),
    #   (ABS(COM_BNDPRD(R,T,C,TS,BD)) NE INF) AND (COM_BNDPRD(R,T,C,TS,BD) NE NA$BDUPX(BD))) = YES
    bdupx = member("BDUPX")
    above = Dict{NTuple{2,String},Vector{String}}()                       # (R,S) => TS with TS_MAP(R,TS,S)
    foreach(k -> pushat!(above, (k[1], k[3]), k[2]), gset(tm, "TS_MAP").keys)
    for (n, dst, prd) in (("COM_BNDNET", rhsb, false), ("COM_BNDPRD", rhsp, true))
        bnd = gparam_opt(tm.data, n, 5).values
        isempty(bnd) && continue
        for k in rcvar
            k[2] in tmem || continue
            (r, t, c, s) = k
            hit = false
            for ts in get(above, (r, s), String[]), b in bdset
                y = get(bnd, (r, t, c, ts, b), nothing)
                y === nothing && continue
                u = b in bdupx
                ok = prd ? (abs(y) != Inf && !(u ? isnan(y) : y == 0.0)) : (u ? abs(y) != Inf : abs(y) != 0.0)
                ok && (hit = true; break)
            end
            hit && push!(dst, k)
        end
    end
    # L1052: RHS_COMPRD(RTCS_VARC(RTC_PRD,S)) = YES
    foreach(k -> k[2] in tmem && (k[1], k[2], k[3]) in rtcp && push!(rhsp, k), rcvar)
    gput!(tm, "RHS_COMBAL", rhsb)
    gput!(tm, "RHS_COMPRD", rhsp)
    return tm
end
