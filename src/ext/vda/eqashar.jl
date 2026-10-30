# EQE_ASHAR / EQL_ASHAR / EQG_ASHAR (VDA extension): ANNUAL-level ("advanced")
# share constraints. The flows of a commodity group CG are bounded by a share
# of the flows of a reference group CG2 (or of the activity, CG2 = 'ACT').
#
# GAMS: eqashar.vda L38-78 (the EQDEF label), v4.9.7, included from
# equ_ext.vda L94-96 as
#   $BATINCLUDE eqashar.mod E FX
#   $BATINCLUDE eqashar.mod L LO
#   $BATINCLUDE eqashar.mod G UP
# (%1 = equation type, %2 = bound type); declared equ_ext.vda L25-27
# (R,ALLYEAR,ALLYEAR,P,CG,COM_GRP,S); in the model through mod_ext.vda
# L29-31. The share multiplies the reference group, which is on the left, so
# EQL_ASHAR is the LO bound (share*CG2 =L= CG) and EQG_ASHAR the UP bound.
# The preprocessing part (L13-34: RPCG_ASHAR, RP_PGFLO additions, levelling
# FLO_ASHAR) is M1.3; its results are read from the pre-solve dump.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_V_T% -> 'R,V,T' (maindrv.mod L39); RTS(S) -> S; %cal_red% is
# cal_nored.red (cal_red.jl) with mode ''. V = MODLYEAR, T = MILESTONYR.
# ACTCG = {'ACT'} (initmty.mod L140, %PGPRIM% = ACT).
#
# Not translated; data that needs them raises UnportedError:
# - the IRE branch L56-65 (rows of exchange processes, RP_IRE);
# - the storage terms (RP_STG processes: the STG_LOSS factor of L51 and the
#   VAR_SOUT term L75-76), until storage is translated.

const ASHAR_VARIANTS = (("E", "FX"), ("L", "LO"), ("G", "UP"))

"""
    eq_ashar!(tm::TimesModel) -> Int

Generate every EQE/EQL/EQG_ASHAR row. Returns the number of rows.

    EQ%1_ASHAR(RTP_VINTYR(R,V,T,P),CG,CG2,S)\$(SUM(RS_TREE(R,S,TS)\$FLO_ASHAR(R,V,P,CG,CG2,TS,'%2'),1)\$RPCG_ASHAR(R,P,CG,CG2,S)) ..
      SUM(RPS_S2(RP_FLO(R,P),SL)\$TS_MAP(R,S,SL),
          SUM(TS_ANN(SL,TS),FLO_ASHAR(R,V,P,CG,CG2,TS,'%2')) *
          (SUM((RTPCS_VARF(R,T,P,COM,TS),RS_TREE(R,SL,TS))\$COM_GMAP(R,CG2,COM),
               [cal_red COM COM1 TS P T] *
               MAX(RPCG_ASHAR(R,P,CG,CG2,S),1\$SUM(TOP(R,P,C(CG),IO),TOP(R,P,COM,IO))\$COM_TYPE(CG2)) *
               RS_FR(R,SL,TS)*(1+RTCS_FR(R,T,COM,SL,TS))) +
           SUM((PRC_TS(R,P,TS),RTP_VARA(R,T,P))\$RS_FR(R,SL,TS),
               RS_FR(R,SL,TS)*(VAR_ACT(R,V,T,P,TS)*EXP((-ABS(STG_LOSS(R,V,P,TS))/2)\$RP_STG(R,P)))\$(NOT RP_PGFLO(R,P)) +
               SUM(RPC_PG(RP_STD(R,P),COM),(VAR_ACT(R,V,T,P,TS)\$RP_PGACT(R,P)+(VAR_FLO(R,V,T,P,COM,TS)/PRC_ACTFLO(R,V,P,COM))\$(NOT RP_PGACT(R,P))) *
                   RS_FR(R,SL,TS)*(1+RTCS_FR(R,T,COM,SL,TS)))\$RP_PGFLO(R,P))\$ACTCG(CG2)))
      + [IRE branch, refused]
      =%1=
      SUM((RTPCS_VARF(R,T,P,COM,TS),COM_GMAP(R,CG,COM))\$TS_MAP(R,S,TS), [cal_red COM COM1 TS P T])\$RP_FLO(R,P) +
      SUM(PRC_TS(R,P,TS)\$TS_MAP(R,S,TS),VAR_ACT(R,V,T,P,TS)\$(NOT NO_ACT(R,P))+
          SUM(RPC_PG(NO_ACT(R,P),C),VAR_FLO(R,V,T,P,C,TS)/PRC_ACTFLO(R,V,P,C)))\$ACTCG(CG)
      + [VAR_SOUT storage term, refused];

In the activity part `RS_FR(R,SL,TS)` multiplies only the non-RP_PGFLO term
(`*` binds tighter than `+`); the RP_PGFLO term carries its own. The
right-hand side's VAR_ACT has no RTP_VARA condition.

GAMS: eqashar.vda L38-78 with equ_ext.vda L94-96, v4.9.7.
"""
function eq_ashar!(tm::TimesModel)
    d = tm.data
    flo_ashar = gparam_opt(d, "FLO_ASHAR", 7)                     # init_ext.vda L44
    rpcg_ashar = gparam_opt(d, "RPCG_ASHAR", 5)
    (isempty(flo_ashar) || isempty(rpcg_ashar)) && return 0
    modlyear, milestonyr = gset(tm, "MODLYEAR"), gset(tm, "MILESTONYR")
    rp_flo, rp_ire, rp_stg = gset(tm, "RP_FLO"), gset(tm, "RP_IRE"), gset(tm, "RP_STG")
    rp_pgflo, rp_pgact, rp_std = gset(tm, "RP_PGFLO"), gset(tm, "RP_PGACT"), gset(tm, "RP_STD")
    no_act = gset(tm, "NO_ACT")
    rtp_vara, ts_map, com_gmap = gset(tm, "RTP_VARA"), gset(tm, "TS_MAP"), gset(tm, "COM_GMAP")
    com_type, top = gset(tm, "COM_TYPE"), gset(tm, "TOP")
    rs_fr, rtcs_fr, prc_actflo = gparam(tm, "RS_FR"), gparam(tm, "RTCS_FR"), gparam(tm, "PRC_ACTFLO")
    tree_of_rts = indexby(gset(tm, "RS_TREE"), (1, 3))          # (r,ts) -> RS_TREE(r,s,ts)
    rs_tree = gset(tm, "RS_TREE")
    vt_of_rvp = indexby(gset(tm, "RTP_VINTYR"), (1, 2, 4))     # (r,v,p) -> RTP_VINTYR(r,v,t,p)
    s2_of_rp = indexby(gset(tm, "RPS_S2"), (1, 2))              # (r,p) -> RPS_S2(r,p,sl)
    tsann_of_s = indexby(gset(tm, "TS_ANN"), (1,))              # sl -> TS_ANN(sl,ts)
    varf_of_rtp = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3))   # (r,t,p) -> RTPCS_VARF(r,t,p,c,ts)
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))              # (r,p) -> PRC_TS(r,p,ts)
    pg_of_rp = indexby(gset(tm, "RPC_PG"), (1, 2))              # (r,p) -> RPC_PG(r,p,c)
    io_of_rpc = indexby(top, (1, 2, 3))                         # (r,p,c) -> TOP(r,p,c,io)
    no3, no4, no5 = NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]
    rpcg_on(k) = haskey(rpcg_ashar.values, k)                  # $RPCG_ASHAR: present (EPS counts)

    n = 0
    for (eqtype, bd) in ASHAR_VARIANTS
        name = "EQ$(eqtype)_ASHAR"
        rows = Set{NTuple{7,String}}()
        for (r, v, p, cg, cg2, ts, b) in flo_ashar.keys
            b == bd || continue
            (v,) in modlyear || continue
            for (_, s, _) in get(tree_of_rts, (r, ts), no3)      # SUM(RS_TREE(R,S,TS)$FLO_ASHAR(...,TS,'%2'),1)
                rpcg_on((r, p, cg, cg2, s)) || continue
                for (_, _, t, _) in get(vt_of_rvp, (r, v, p), no4)
                    (t,) in milestonyr && push!(rows, (r, v, t, p, cg, cg2, s))
                end
            end
        end
        rows = collect(rows)
        gams_sort!(rows, d)
        for (r, v, t, p, cg, cg2, s) in rows
            (r, p) in rp_ire && throw(UnportedError("eqashar.vda L56-65: ASHAR share of an exchange process ($r, $p)"))
            (r, p) in rp_stg && throw(UnportedError("eqashar.vda L51, L75-76: ASHAR share of a storage process ($r, $p)"))
            rpcg = gv(rpcg_ashar, (r, p, cg, cg2, s))
            lhs = JuMP.AffExpr(0.0)
            if (r, p) in rp_flo
                for (_, _, sl) in get(s2_of_rp, (r, p), no3)
                    (r, s, sl) in ts_map || continue
                    share = GZERO
                    for (_, ts) in get(tsann_of_s, (sl,), Tuple{String,String}[])
                        share += gv(flo_ashar, (r, v, p, cg, cg2, ts, bd))
                    end
                    # Reference-group flows.
                    for (_, _, _, com, ts) in get(varf_of_rtp, (r, t, p), no5)
                        ((r, sl, ts) in rs_tree && (r, cg2, com) in com_gmap) || continue
                        same_side = any(k -> (r, p, com, k[4]) in top, get(io_of_rpc, (r, p, cg), no4))
                        f = gmax(rpcg, gif(gif(1, same_side), (cg2,) in com_type))
                        k = share * f * gv(rs_fr, (r, sl, ts)) * (1 + gv(rtcs_fr, (r, t, com, sl, ts)))
                        cal_nored!(lhs, tm, k, r, v, t, p, com, ts)
                    end
                    # Activity as the reference (ACTCG(CG2)).
                    cg2 == "ACT" || continue
                    (r, t, p) in rtp_vara || continue
                    for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                        haskey(rs_fr, (r, sl, ts)) || continue
                        if !((r, p) in rp_pgflo)
                            # EXP((-ABS(STG_LOSS)/2)$RP_STG) = 1: storage refused above.
                            addterm!(lhs, share * gv(rs_fr, (r, sl, ts)), tm, "VAR_ACT", r, v, t, p, ts)
                        elseif (r, p) in rp_std
                            for (_, _, com) in get(pg_of_rp, (r, p), no3)
                                w = share * gv(rs_fr, (r, sl, ts)) * (1 + gv(rtcs_fr, (r, t, com, sl, ts)))
                                if (r, p) in rp_pgact
                                    addterm!(lhs, w, tm, "VAR_ACT", r, v, t, p, ts)
                                else
                                    addterm!(lhs, w / gv(prc_actflo, (r, v, p, com)), tm, "VAR_FLO", r, v, t, p, com, ts)
                                end
                            end
                        end
                    end
                end
            end
            rhs = JuMP.AffExpr(0.0)
            if (r, p) in rp_flo
                for (_, _, _, com, ts) in get(varf_of_rtp, (r, t, p), no5)
                    ((r, cg, com) in com_gmap && (r, s, ts) in ts_map) || continue
                    cal_nored!(rhs, tm, GNum(1.0), r, v, t, p, com, ts)
                end
            end
            if cg == "ACT"
                for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                    (r, s, ts) in ts_map || continue
                    if !((r, p) in no_act)
                        addterm!(rhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, ts)
                    else
                        for (_, _, c) in get(pg_of_rp, (r, p), no3)
                            addterm!(rhs, GNum(1.0) / gv(prc_actflo, (r, v, p, c)), tm, "VAR_FLO", r, v, t, p, c, ts)
                        end
                    end
                end
            end
            gconstraint!(tm, name, (r, v, t, p, cg, cg2, s), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
