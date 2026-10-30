# The flow term of a process/commodity/timeslice inside equations: the
# `$BATINCLUDE %cal_red% ...` that eqptrans.mod, eqcombal.mod and others use.
#
# %cal_red% is chosen in pp_reduce.red: cal_nored.red by default (L13) and
# cal_red.red only when REDUCE is YES (L58-59). With REDUCE NO the
# reduction is skipped (L15), so RPC_EMIS and FS_EMIT stay empty and the
# expression is the flow variable itself; with REDUCE neither YES nor NO the
# emission substitution of cal_nored.red applies to what pp_reduce.red
# computed. cal_red.red (flows replaced by activities under REDUCE YES) is
# not translated yet.

"""
    cal_nored!(expr, tm, coef, r, v, t, p, c, ts; mode="") -> expr

Add `coef` times the flow of commodity `c` in timeslice `ts` of process `p`
(period `t`, vintage `v`) to `expr`, as cal_nored.red expands it:

    ( VAR_FLO(R,%VNT%,%5,%4,%1,%3)\$(NOT RPC_EMIS(R,%4,%1))
      + SUM((FS_EMIT(R,%4,%1,CG3,COM2),ALL_TS)\$(RS_FR(R,%3,ALL_TS)*RTPCS_VARF(R,%5,%4,COM2,ALL_TS)),
            VAR_FLO(R,%VNT%,%5,%4,COM2,ALL_TS) * COEF_PTRAN(R,%VNT%,%4,CG3,COM2,%1,ALL_TS)%SHP3% *
            RS_FR(R,%3,ALL_TS)*(1+RTCS_FR(R,%5,COM2,%3,ALL_TS))
      )\$RPC_EMIS(R,%4,%1) )

with %1 = c, %3 = ts, %4 = p, %5 = t and `mode` = %7:
- `""` (general case): %VNT% = V (here `v`) and %SHP3% =
  `*(1+RTP_FFCX(R,V,T,P,CG3,C)\$PRC_VINT(R,P))` [`*(1+RTP_FFCS(R,V,P,CG3,C))`];
- `"V"`: as above without `\$PRC_VINT(R,P)`;
- `"T"`: %VNT% = %5 (pass `v = t`) and only the RTP_FFCS factor.
The RTP_FFCS factor exists only when RTP_FFCS is DEFINED (L18).
%8/%9 (a SUM over vintages wrapped around the whole term, used only by
cal_fflo.mod) are not supported here.

GAMS: cal_nored.red L15-30, v4.9.7 (macro defaults from setglobs.gms
L348-353: %VAR% -> VAR, %SOW% -> '', %SHFF% -> 1+RTP_FFC).
"""
function cal_nored!(expr::JuMP.AffExpr, tm::TimesModel, coef::GNum,
                    r::String, v::String, t::String, p::String, c::String, ts::String;
                    mode::AbstractString="")
    tm.reduce && throw(UnportedError(
        "cal_red.red (REDUCE YES: flows substituted by activities); only cal_nored.red is translated"))
    mode in ("", "T", "V") || throw(ArgumentError("cal_nored mode (%7) must be '', T or V, got $mode"))
    iszero(coef) && return expr
    vnt = mode == "T" ? t : v

    rpc_emis = gset(tm, "RPC_EMIS")
    if !((r, p, c) in rpc_emis)
        return addterm!(expr, coef, tm, "VAR_FLO", r, vnt, t, p, c, ts)
    end

    # Emission flow = flow variable * emission factor (cal_nored.red L26-28).
    fs_emit_by_rpc = get!(() -> indexby(gset(tm, "FS_EMIT"), (1, 2, 3)), tm.cache, "FS_EMIT/rpc")
    rs_fr = gparam(tm, "RS_FR")
    rs_fr_by_rs = get!(() -> indexby(rs_fr, (1, 2)), tm.cache, "RS_FR/rs")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    coef_ptran = gparam(tm, "COEF_PTRAN")
    rtcs_fr = gparam(tm, "RTCS_FR")
    rtp_ffcx = gparam(tm, "RTP_FFCX")
    rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5)
    prc_vint = gset(tm, "PRC_VINT")
    for (_, _, _, cg3, com2) in get(fs_emit_by_rpc, (r, p, c), NTuple{5,String}[])
        for (_, _, all_ts) in get(rs_fr_by_rs, (r, ts), NTuple{3,String}[])
            # $(RS_FR(R,%3,ALL_TS)*RTPCS_VARF(R,%5,%4,COM2,ALL_TS)): RS_FR present, VARF member.
            (r, t, p, com2, all_ts) in rtpcs_varf || continue
            shp3 = GNum(1.0)
            if mode != "T"
                ffcx = gv(rtp_ffcx, (r, v, t, p, cg3, c))
                shp3 = 1 + (mode == "V" ? ffcx : gif(ffcx, (r, p) in prc_vint))
            end
            shp3 = shp3 * (1 + gv(rtp_ffcs, (r, vnt, p, cg3, c)))
            k = coef * (gv(coef_ptran, (r, vnt, p, cg3, com2, c, all_ts)) * shp3 *
                        gv(rs_fr, (r, ts, all_ts)) * (1 + gv(rtcs_fr, (r, t, com2, ts, all_ts))))
            addterm!(expr, k, tm, "VAR_FLO", r, vnt, t, p, com2, all_ts)
        end
    end
    return expr
end
