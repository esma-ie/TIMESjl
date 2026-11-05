# M1.3 (15b): ppmain.mod L1181-1226 (docs/m13-plan.md): the UC group maps
# (UC_MAP_FLO, UC_MAP_IRE, UC_QAFLO, UC_GMAP_C, UC_GMAP_P), the dynamic
# COMCON attributes, VAR_CAP for UC capacities (RTP_VARP), VAR_COMNET and
# VAR_COMPRD for UC commodities (RHS_COMBAL, RHS_COMPRD), UC_ACT, UC_FLO,
# UC_IRE and UC_COM levelled to the process and commodity timeslices
# (pp_lvlus.mod), and the balance controls RCS_COMBAL and RCS_COMPRD.
#
# GAMS: ppmain.mod L1181-1226, pp_lvlus.mod L14-40, v4.9.7.
#
# Index sets: R is REG, UC_N and UCN the UCs, T is MILESTONYR, S and TS are
# ALL_TS, TSL the timeslice levels, J the indexes '1' to '999', IO is IN/OUT
# and IPS is IN/N. `$x` is true for EPS (G3) and `NOT x` false (G25); a
# numeric comparison takes EPS as 0 (G12); `$=` writes only a nonzero or EPS
# value (G24); `OPTION a < b` matches each index of `a` to the rightmost
# unmatched index of `b` with the same declared domain (G26, G34, G45); the
# circular lag `T--ORD(T)` is the last milestone year (G31); SMAX over nothing
# is -INF (G31); `MAX(EPS,0)` is EPS (G14).

"""
    ppmain_ucmap_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1181-1226 settles that nothing later in the prelv
-> ppm segment changes (for the layer-1 check at the ppm checkpoint).
Without UC_DYNBND only (equcrtp.vda PPM_EXT L17-70): UC_GMAP_P (L46), UC_ON
(L67), UC_ACT (L25) and UC_COM (L21-36). With %REDUCE% NO only: RHS_COMPRD
(pp_reduce.red L161). Without GR_VARGEN only: RHS_COMBAL and RCS_COMBAL
(resloadc.vda L54-55, included at ppm_ext.vda L12). Left out: the scratch
(TRACKP, RXX, UC_JMAP, UNCD7, TS_ARRAY, Z, F), which the replay checks at
L1226.
"""
function ppmain_ucmap_symbols(tm)
    out = ["UC_MAP_FLO", "UC_MAP_IRE", "UC_QAFLO", "UC_CAPFLO", "UC_GMAP_C", "UC_ATTR", "RTP_VARP", "UC_FLO", "UC_IRE", "RCS_COMPRD"]
    isempty(gset_opt(tm.data, "UC_DYNBND", 2).members) && append!(out, ["UC_GMAP_P", "UC_ON", "UC_ACT", "UC_COM"])
    uppercase(strip(gswitch(tm, "REDUCE", ""))) == "NO" && push!(out, "RHS_COMPRD")
    isempty(gparam_opt(tm.data, "GR_VARGEN", 4).keys) && append!(out, ["RHS_COMBAL", "RCS_COMBAL"])
    return out
end

"""
    ppmain_ucmap!(tm) -> tm

ppmain.mod L1181-1226 on the state after `ppmain_uc!`.

GAMS: ppmain.mod L1181-1226, v4.9.7.
"""
function ppmain_ucmap!(tm)
    tr = TsTree(tm)
    reg = tr.reg
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tlist)
    member(s) = Set(k[1] for k in gset(tm, s).keys)

    # --- L1183-1193: FLO / IRE ----------------------------------------------------------------------------
    # L1187: OPTION UC_MAP_FLO < UC_FLO  (UC_FLO(UC_N,SIDE,ALL_REG,ALLYEAR,PRC,COM,TS))
    map_flo = project(keys(gparam_opt(tm.data, "UC_FLO", 7).values), (1, 2, 3, 5, 6))
    # L1188: UC_QAFLO('1',UC_MAP_FLO(UCN,SIDE,RP_IRE(R,P),C))=YES
    qaflo = gmembers(tm, "UC_QAFLO", 6)
    rp_ire = gset(tm, "RP_IRE").members
    foreach(k -> (k[3], k[4]) in rp_ire && push!(qaflo, ("1", k...)), map_flo)
    # L1189: UC_CAPFLO(UC_N,SIDE,R,P,C)$(NOT UC_MAP_FLO(UC_N,SIDE,R,P,C)) = NO
    capflo = gmembers(tm, "UC_CAPFLO", 5)
    filter!(k -> !(k[3] in reg && !(k in map_flo)), capflo)
    # L1190: UC_MAP_FLO(UC_N,SIDE,RP_IRE,C) = NO
    filter!(k -> !((k[3], k[4]) in rp_ire), map_flo)
    # L1191: OPTION UC_MAP_IRE < UC_IRE  (UC_IRE(UC_N,SIDE,ALL_REG,ALLYEAR,PRC,COM,TS,IE))
    map_ire = project(keys(gparam_opt(tm.data, "UC_IRE", 8).values), (1, 3, 5, 6, 8))
    # L1192: UC_QAFLO('2',UCN,'LHS',RP_FLO,C)$=SUM(UC_MAP_IRE(UCN,RP_FLO,C,IE),1)
    rp_flo = gset(tm, "RP_FLO").members
    foreach(k -> (k[2], k[3]) in rp_flo && push!(qaflo, ("2", k[1], "LHS", k[2], k[3], k[4])), map_ire)
    # L1193: UC_MAP_IRE(UC_N,R,P,C,IE)$(NOT RPC_IRE(R,P,C,IE)) = NO
    rpc_ire = gset(tm, "RPC_IRE").members
    filter!(k -> !(k[2] in reg && !((k[2], k[3], k[4], k[5]) in rpc_ire)), map_ire)
    # L1194: OPTION UC_GMAP_C < UC_COM  (UC_COM(UC_N,COM_VAR,SIDE,REG,ALLYEAR,COM,S,UC_GRPTYPE) -> UC_GMAP_C(REG,UC_N,COM_VAR,COM,UC_GRPTYPE))
    gmap_c = project(keys(gparam_opt(tm.data, "UC_COM", 8).values), (4, 1, 2, 6, 8))
    # L1195: UC_ATTR(R,UCN,SIDE,UC_GRPTYPE,UC_DYNT)$UC_ATTR(R,UCN,SIDE,'COMCON',UC_DYNT) $=
    #   SUM(UC_GMAP_C(R,UCN,COM_VAR,C,'COMCON')$COV_MAP(COM_VAR,UC_GRPTYPE),1)
    attr = gmembers(tm, "UC_ATTR", 5)
    dynt = member("UC_DYNT")
    cov = gset(tm, "COV_MAP").keys
    gcv = Set((k[1], k[2], k[3]) for k in gmap_c if k[5] == "COMCON")
    for k in collect(attr)
        (k[1] in reg && k[4] == "COMCON" && k[5] in dynt) || continue
        foreach(m -> (k[1], k[2], m[1]) in gcv && push!(attr, (k[1], k[2], k[3], m[2], k[5])), cov)
    end

    # --- L1197-1206: ACT / CAP / NCAP ---------------------------------------------------------------------
    # L1198-1200: UC_JMAP('2'|'3'|'4',UCN,SIDE,R,T--ORD(T),P,'ACT'|'CAP'|'NCAP')$UC_ON(R,UCN) $= ...
    # added to what UC_JMAP holds: with UC_DYNBND, equcrtp.vda INIT_EXT L59 left its J='1' tuples there
    uc_on = gmembers(tm, "UC_ON", 2)
    lastt = last(tlist)
    jmap = gmembers(tm, "UC_JMAP", 7)
    for (j, n, N, g) in (("2", "UC_ACT", 6, "ACT"), ("3", "UC_CAP", 5, "CAP"), ("4", "UC_NCAP", 5, "NCAP"))
        for k in keys(gparam_opt(tm.data, n, N).values)
            (k[3] in reg && k[4] in tmem && (k[3], k[1]) in uc_on) && push!(jmap, (j, k[1], k[2], k[3], lastt, k[5], g))
        end
    end
    # L1201: OPTION UC_GMAP_P < UC_JMAP  (UC_JMAP(J,UC_N,SIDE,REG,T,PRC,UC_GRPTYPE) -> UC_GMAP_P(REG,UC_N,UC_GRPTYPE,PRC))
    gmap_p = project(jmap, (4, 2, 7, 6))
    # L1204: LOOP(UC_GMAP_P(R,UCN,'CAP',P),TRACKP(R,P)=YES); L1205: RTP_VARP(RTP(R,T,P))$TRACKP(R,P) = YES
    trackp = gmembers(tm, "TRACKP", 2)
    foreach(k -> k[3] == "CAP" && push!(trackp, (k[1], k[4])), gmap_p)
    varp = gmembers(tm, "RTP_VARP", 3)
    foreach(k -> (k[2] in tmem && (k[1], k[3]) in trackp) && push!(varp, k), gset(tm, "RTP").keys)
    # L1206: OPTION CLEAR=TRACKP,CLEAR=RXX,CLEAR=UC_JMAP
    # L1207: UC_ON(R,UCN) $= SUM(UC_DYNBND(UCN,L),1)
    dynbnd = Set(k[1] for k in gset_opt(tm.data, "UC_DYNBND", 2).keys)
    foreach(r -> foreach(u -> push!(uc_on, (r, u)), dynbnd), reg)
    # L1208: LOOP(UC_GMAP_C(UC_ON(R,UC_N),COM_VAR,C,UC_GRPTYPE),RXX(R,COM_VAR,C)=YES)
    rxx = Set{NTuple{3,String}}((k[1], k[3], k[4]) for k in gmap_c if (k[1], k[2]) in uc_on)
    # L1209: RHS_COMPRD(RTCS_VARC(R,T,C,S))$RXX(R,'PRD',C) = YES
    varc = gset(tm, "RTCS_VARC").keys
    rhs_prd, rhs_bal = gmembers(tm, "RHS_COMPRD", 4), gmembers(tm, "RHS_COMBAL", 4)
    foreach(k -> (k[1], "PRD", k[3]) in rxx && push!(rhs_prd, k), varc)
    # L1210: RXX(R,'NET',C)$COM_LIM(R,C,'FX')=NO; L1211: RXX(R,'PRD',C)$(NOT COM_LIM(R,C,'LO'))=NO
    com_lim = gset(tm, "COM_LIM").members
    filter!(k -> !(k[1] in reg && ((k[2] == "NET" && (k[1], k[3], "FX") in com_lim) || (k[2] == "PRD" && !((k[1], k[3], "LO") in com_lim)))), rxx)
    # L1212: LOOP(COM_VAR,RHS_COMBAL(RTCS_VARC(R,T,C,S))$RXX(R,COM_VAR,C) = YES)
    comvar = [k[1] for k in gset(tm, "COM_VAR").keys]
    foreach(k -> any(cv -> (k[1], cv, k[3]) in rxx, comvar) && push!(rhs_bal, k), varc)

    # --- L1215-1218: pp_lvlus.mod -------------------------------------------------------------------------
    st = UsState(gscal(tm, "Z"), gscal(tm, "F"), nothing)
    prc_ts, com_ts, rpcs_var = gset(tm, "PRC_TS"), gset(tm, "COM_TS"), gset(tm, "RPCS_VAR")
    pts, cts, rpcs = Dict{NTuple{2,String},Vector{String}}(), Dict{NTuple{2,String},Vector{String}}(), Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> pushat!(pts, (k[1], k[2]), k[3]), prc_ts.keys)
    foreach(k -> pushat!(cts, (k[1], k[2]), k[3]), com_ts.keys)
    foreach(k -> pushat!(rpcs, (k[1], k[2], k[3]), k[4]), rpcs_var.keys)
    tslvl = [k[1] for k in gset(tm, "TSLVL").keys]
    lpos = Dict(l => i for (i, l) in enumerate(tslvl))
    ptsl, ctsl = Dict{NTuple{2,String},Vector{String}}(), Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(ptsl, (k[1], k[2]), k[3]), gset(tm, "PRC_TSL").keys)
    foreach(k -> pushat!(ctsl, (k[1], k[2]), k[3]), gset(tm, "COM_TSL").keys)
    sgl = gvalues(tm, "PRC_SGL", 2)
    # SMAX(%7%8_TSL(R,%7,TSL),MAX(%9+EPS,ORD(TSL)-1))
    smax(tsls, base) = isempty(tsls) ? GNum(-Inf) : reduce(gmax, (gmax(base, GNum(Float64(lpos[l] - 1))) for l in tsls))
    E = String[]
    # %1 UC_ACT, %2 P, %3 PRC_TS, %4 ,'0','0' (UNCD7 padding), %7%8 PRC: UC_ACT(UC_N,SIDE,R,T,P,S)
    pp_lvlus!(tm, tr, st, "UC_ACT", 6, tlist, tmem;
              split=k -> ((k[1], k[2], k[3], k[5]), k[4], k[6]), join=(g, t, s) -> (g[1], g[2], g[3], t, g[4], s),
              region=g -> g[3], targets=g -> get(pts, (g[3], g[4]), E), u7=(g, io) -> (g..., io, "0", "0"),
              fmax=g -> smax(get(ptsl, (g[3], g[4]), E), GEPS))
    # %1 UC_FLO, %2 P,C, %3 RPCS_VAR, %4 ,'0', %9 PRC_SGL(R,P), %10 ,C: UC_FLO(UC_N,SIDE,R,T,P,C,S)
    pp_lvlus!(tm, tr, st, "UC_FLO", 7, tlist, tmem;
              split=k -> ((k[1], k[2], k[3], k[5], k[6]), k[4], k[7]), join=(g, t, s) -> (g[1], g[2], g[3], t, g[4], g[5], s),
              region=g -> g[3], targets=g -> get(rpcs, (g[3], g[4], g[5]), E), u7=(g, io) -> (g..., io, "0"),
              fmax=g -> smax(get(ptsl, (g[3], g[4]), E), gv(sgl, (g[3], g[4])) + GEPS))
    # %1 UC_IRE, %2 P,C, %3 PRC_TS, %5 ,IE: UC_IRE(UC_N,SIDE,R,T,P,C,S,IE)
    pp_lvlus!(tm, tr, st, "UC_IRE", 8, tlist, tmem;
              split=k -> ((k[1], k[2], k[3], k[5], k[6], k[8]), k[4], k[7]), join=(g, t, s) -> (g[1], g[2], g[3], t, g[4], g[5], s, g[6]),
              region=g -> g[3], targets=g -> get(pts, (g[3], g[4]), E), u7=(g, io) -> (g..., io),
              fmax=g -> smax(get(ptsl, (g[3], g[4]), E), GEPS))
    # %1 UC_COM, %2 C, %3 COM_TS, %5 ,UC_GRPTYPE, %6 ,COM_VAR, %7%8 COM: UC_COM(UC_N,COM_VAR,SIDE,R,T,C,S,UC_GRPTYPE)
    pp_lvlus!(tm, tr, st, "UC_COM", 8, tlist, tmem;
              split=k -> ((k[1], k[2], k[3], k[4], k[6], k[8]), k[5], k[7]), join=(g, t, s) -> (g[1], g[2], g[3], g[4], t, g[5], s, g[6]),
              region=g -> g[4], targets=g -> get(cts, (g[4], g[5]), E), u7=(g, io) -> (g..., io),
              fmax=g -> smax(get(ctsl, (g[4], g[5]), E), GEPS))

    # --- L1220-1226: RCS_COMBAL / RCS_COMPRD --------------------------------------------------------------
    # L1223: RCS_COMBAL(RTCS_VARC(R,T,C,S),LIM)$(COM_LIM(R,C,LIM) * (NOT RHS_COMBAL(R,T,C,S))) = YES
    rcs_bal, rcs_prd = gmembers(tm, "RCS_COMBAL", 5), gmembers(tm, "RCS_COMPRD", 5)
    lims = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(lims, (k[1], k[2]), k[3]), gset(tm, "COM_LIM").keys)
    for k in varc
        k in rhs_bal && continue
        foreach(l -> push!(rcs_bal, (k..., l)), get(lims, (k[1], k[3]), E))
    end
    # L1224: RCS_COMBAL(RHS_COMBAL,'FX') = YES
    foreach(k -> push!(rcs_bal, (k..., "FX")), rhs_bal)
    # L1225: $IF '%VALIDATE%'==YES  RHS_COMPRD(RTCS_VARC) = YES
    uppercase(strip(gswitch(tm, "VALIDATE", ""))) == "YES" && union!(rhs_prd, varc)
    # L1226: RCS_COMPRD(RHS_COMPRD,'FX') = YES
    foreach(k -> push!(rcs_prd, (k..., "FX")), rhs_prd)

    for (n, v) in (("UC_MAP_FLO", map_flo), ("UC_MAP_IRE", map_ire), ("UC_QAFLO", qaflo), ("UC_CAPFLO", capflo), ("UC_GMAP_C", gmap_c),
                   ("UC_ATTR", attr), ("UC_GMAP_P", gmap_p), ("RTP_VARP", varp), ("UC_ON", uc_on), ("RXX", rxx),
                   ("RHS_COMPRD", rhs_prd), ("RHS_COMBAL", rhs_bal), ("RCS_COMBAL", rcs_bal), ("RCS_COMPRD", rcs_prd))
        gput!(tm, n, v)
    end
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "UC_JMAP", Set{NTuple{7,String}}())
    gput!(tm, "UNCD7", Set{NTuple{7,String}}())
    st.tsarr === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in st.tsarr))
    gput_gnum!(tm, "Z", st.Z)
    gput_gnum!(tm, "F", st.F)
    return tm
end

"The scalars pp_lvlus.mod carries from one call to the next: Z, F and the last TS_ARRAY."
mutable struct UsState
    Z::GNum
    F::GNum
    tsarr::Union{Nothing,Dict{String,Float64}}
end

"""
    pp_lvlus!(tm, tr, st, name, N, tlist, tmem; split, join, region, targets, u7, fmax)

pp_lvlus.mod: the UC attribute `name` (UC_ACT, UC_FLO, UC_IRE or UC_COM)
given at timeslices outside its target set levelled to the target set:
by aggregation where the attribute's level is finer than the finest
target level (or, after an earlier pass marked the group OUT, finer than
F), by inheritance from above otherwise; then ANNUAL values copied to the
target timeslices without a value. `split(k)` gives a record's group (the
indexes other than T and S), year and timeslice, `join` the reverse;
`targets(g)` the target timeslices (%3), `u7(g, io)` the UNCD7 tuple and
`fmax(g)` the F of L18. The scalar F is carried across groups and calls
exactly as in GAMS: L17 compares with the F the previous record left.

GAMS: pp_lvlus.mod L14-40, v4.9.7.
"""
function pp_lvlus!(tm, tr::TsTree, st::UsState, name, N, tlist, tmem; split, join, region, targets, u7, fmax)
    x = gvalues(tm, name, N)
    stoa, stoal = gvalues(tm, "STOA", 1), gvalues(tm, "STOAL", 2)
    ios = [k[1] for k in gset(tm, "IO").keys]
    ips = Set(k[1] for k in gset(tm, "IPS").keys)
    # L14: OPTION CLEAR=UNCD7; L15-19: LOOP((UC_N%6,SIDE,R,T,%2,S%5)$%1(...),
    #   IF((NOT %3(R,%7%10,S))$STOA(S),Z=STOAL(R,S);
    #     IF(UNCD7(...,'OUT'%4), IF(Z>F, F=9; UNCD7(...,'IN'%4)=YES);
    #     ELSE F=SMAX(%7%8_TSL(R,%7,TSL),MAX(%9+EPS,ORD(TSL)-1));
    #       IF(Z>F, F=9; UNCD7(...,IO%4)=YES; ELSE UNCD7(...,'OUT'%4)=YES))))
    uncd7 = Set{NTuple{7,String}}()
    gof = Dict{NTuple{7,String},Tuple{Any,String}}()            # the group and IO of each UNCD7 tuple
    add!(g, io) = (u = u7(g, io); push!(uncd7, u); gof[u] = (g, io))
    for k in gams_sort!([k for k in keys(x) if region(split(k)[1]) in tr.reg && split(k)[2] in tmem], tm.data)
        g, _, s = split(k)
        (!(s in targets(g)) && !iszero(gv(stoa, (s,)))) || continue
        st.Z = gv(stoal, (region(g), s))
        if u7(g, "OUT") in uncd7
            st.Z.v > st.F.v && (st.F = GNum(9.0); add!(g, "IN"))
        else
            st.F = fmax(g)
            if st.Z.v > st.F.v
                st.F = GNum(9.0)
                foreach(io -> add!(g, io), ios)
            else
                add!(g, "OUT")
            end
        end
    end
    # L23-37: LOOP(UNCD7(UC_N%6,SIDE,R,%2%5,IO%4), IF(IPS(IO), F=0; <aggregate>; ELSEIF F, <inherit>; ELSE F=1))
    for u in gams_sort!(collect(uncd7), tm.data)
        g, io = gof[u]
        r = region(g)
        if io in ips
            # L24-30: F=0; LOOP(T, TS_ARRAY(S) = %1(...,T,...,S); %1(...,TS)$((NOT TS_ARRAY(TS))$%3(R,..,TS)) $=
            #   SUM(RS_TREE(FINEST(R,S),TS), G_YRFR(R,S)*(TS_ARRAY(S)+<nearest values above>))/G_YRFR(R,TS))
            st.F = GZERO
            for t in tlist
                arr = Dict{String,Float64}(s => x[join(g, t, s)] for s in tr.all_ts if haskey(x, join(g, t, s)))
                foreach(ts -> haskey(arr, ts) || gassign!(x, join(g, t, ts), level_br(tr, arr, r, ts)), targets(g))
                st.tsarr = arr
            end
        elseif !iszero(st.F)
            # L31-36: LOOP(T, TS_ARRAY(S) = %1(...); LOOP(RJLVL(J,R,TSL)$(ORD(TSL)<4), LOOP(TS_GROUP(R,TSL,TS),
            #   TS_ARRAY(S)$(NOT TS_ARRAY(S)) $= TS_ARRAY(TS)$RS_BELOW(R,TS,S))); %1(...,S)$%3(R,..,S) $= TS_ARRAY(S))
            tsl_pos = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "TSLVL").keys))
            for t in tlist
                arr = Dict{String,Float64}(s => x[join(g, t, s)] for s in tr.all_ts if haskey(x, join(g, t, s)))
                for (_, r2, tsl) in gset(tm, "RJLVL").keys
                    (r2 == r && tsl_pos[tsl] < 4) || continue
                    for ts in get(tr.group, (r, tsl), String[])
                        a = get(arr, ts, nothing)
                        a === nothing && continue
                        foreach(s -> haskey(arr, s) || (arr[s] = a), get(tr.below, (r, ts), String[]))
                    end
                end
                tg = targets(g)
                foreach(((s, a),) -> s in tg && (x[join(g, t, s)] = a), arr)
                st.tsarr = arr
            end
        else
            st.F = GNum(1.0)
        end
    end
    # L39: %1(UC_N%6,SIDE,R,T,%2,S%5)$(%3(R,%7%10,S)$(NOT %1(...,S))) $= %1(UC_N%6,SIDE,R,T,%2,'ANNUAL'%5)
    put = Pair{NTuple{N,String},Float64}[]
    for (k, a) in x
        g, t, s = split(k)
        (s == "ANNUAL" && t in tmem && region(g) in tr.reg) || continue
        foreach(ts -> haskey(x, join(g, t, ts)) || push!(put, join(g, t, ts) => a), targets(g))
    end
    foreach(((k, a),) -> (x[k] = a), put)
    gput!(tm, name, x)
    # L40: OPTION CLEAR=UNCD7
    return st
end
