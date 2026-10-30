# M1.2 (1): the start of the coefficient stage and the capacity-transfer and
# availability coefficients.
#
# GAMS (v4.9.7): maindrv.mod L70 (DISCSHIFT, a compile-time setting used by
# coef_obj.mod), coefmain.mod L11 (SOW, SW_T), coef_cpt.mod L13-63, and
# pp_shapr.mod L15-46 for its two includes (L48, L59).
#
# Shaped availabilities are not translated: pp_shapr.mod shapes an attribute
# only for (R,V,P) with a shape index >= 1.5 in NCAP_AFX/NCAP_AFSX or
# NCAP_AFM/NCAP_AFSM (L19-20), and NCAP_AFX also drives TRACKP
# (coef_cpt.mod L42-47) and NCAP_AFSX (L56-58). No test model has any of the
# four, so they raise UnportedError (coef_unported); with all four empty,
# pp_shapr reduces to its base assignment (L23, L43-46) and those coef_cpt
# lines to the set algebra written out below. %STAGES% (L11) and %VALIDATE%
# (L23) are refused as in M1.1.

"""
    ctst(tm) -> String

The value of `%CTST%` (initmty.mod L426-430): `'**EPS'` for OBJ ALT or LIN,
`'**0'` when OBLONG is YES (OBJ MOD sets OBLONG, L427), `''` otherwise; the
last applicable line wins, comparisons case-insensitive (`\$IFI`).
"""
function ctst(tm)
    obj = uppercase(gswitch(tm, "OBJ", ""))
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES" || obj == "MOD"
    c = ""
    obj == "ALT" && (c = "**EPS")
    oblong && (c = "**0")
    obj == "LIN" && (c = "**EPS")
    return c
end

"""
    coef_cpt_unported(tm) -> Vector{String}

The coef_cpt.mod / coefmain.mod paths this model would take that are not
translated (see the file header); empty when coef_cpt! can run.
"""
function coef_cpt_unported(tm)
    out = String[]
    yes(n) = uppercase(gswitch(tm, n, "")) == "YES"
    yes("STAGES") && push!(out, "coefmain.mod L11 (STAGES YES)")
    yes("VALIDATE") && push!(out, "coef_cpt.mod L23 (VALIDATE YES)")
    for (p, n) in (("NCAP_AFM", 3), ("NCAP_AFX", 3), ("NCAP_AFSM", 3), ("NCAP_AFSX", 4))
        isempty(gparam_opt(tm.data, p, n)) ||
            push!(out, "coef_cpt.mod L42-58 and pp_shapr.mod L19-40 (shaped availability: $p has data)")
    end
    isempty(gset_opt(tm.data, "RTP_ISHPR", 3)) ||
        push!(out, "pp_shapr.mod L19-40 (RTP_ISHPR not empty on entry)")
    return out
end

"""
    coef_cpt!(tm) -> tm

Run maindrv.mod L70, coefmain.mod L11 and coef_cpt.mod L13-63 (with
pp_shapr.mod for L48 and L59) on the GAMS state in `tm` (the ppm dump),
storing every set and parameter they assign: SOW, SW_T, B, E, M, D, FIL,
PASTSUM, COEF_CPT, MY_TS, NCAP_AF, NCAP_AFS, TRACKP, NCAP_AFBX, FIL2,
RTP_ISHPR, COEF_AF, RP_PRC and RTPS_BD.

GAMS: coefmain.mod L11; coef_cpt.mod L13-63; pp_shapr.mod L15-46, v4.9.7.
"""
function coef_cpt!(tm)
    u = coef_cpt_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    S1(name) = gset(tm, name)
    milestonyr, modlyear = S1("MILESTONYR"), S1("MODLYEAR")
    inT(t) = (t,) in milestonyr
    inV(v) = (v,) in modlyear

    # coefmain.mod L11: SOW(ALLSOW)=DIAG(ALLSOW,'1'); SW_T(T,ALLSOW)=SOW(ALLSOW)
    allsow = S1("ALLSOW")
    sow = Set{NTuple{1,String}}(k for k in allsow.keys if k[1] == "1")
    gput!(tm, "SOW", sow)
    sw_t = Set(k for k in gmembers(tm, "SW_T", 2) if !inT(k[1]))
    for (t,) in milestonyr.keys, (w,) in sow
        push!(sw_t, (t, w))
    end
    gput!(tm, "SW_T", sw_t)

    # L13-16: copy the period values into the years within the period
    B, E, M, D = (gvalues(tm, n, 1) for n in ("B", "E", "M", "D"))
    phyr, vnt = S1("PHYR"), S1("VNT")
    for (t, v) in S1("PERIODYR").keys
        (inT(t) && inV(v)) || continue
        (!((v,) in phyr) && (v, t) in vnt) || continue
        for P in (B, E, M, D)
            x = get(P, (t,), nothing)
            x === nothing ? delete!(P, (v,)) : (P[(v,)] = x)
        end
    end
    for (n, P) in zip(("B", "E", "M", "D"), (B, E, M, D))
        gput!(tm, n, P)
    end
    gvB(y) = gv(gparam(tm, "B"), (y,))
    gvE(y) = gv(gparam(tm, "E"), (y,))
    gvD(y) = gv(gparam(tm, "D"), (y,))

    # L18-24: capacity transfer, only when %CTST% is '' (G23: 0**0 = 0**EPS = 1)
    fil = ctst(tm) == "" ? Set{NTuple{1,String}}(modlyear.keys) : Set{NTuple{1,String}}()
    gput!(tm, "FIL", fil)
    pastsum = gvalues(tm, "PASTSUM", 3)
    coef_cpt = gvalues(tm, "COEF_CPT", 4)
    if !isempty(fil)
        prc_cap = S1("PRC_CAP")
        iled, rpti, tlife = gparam(tm, "NCAP_ILED"), gparam(tm, "COEF_RPTI"), gparam(tm, "NCAP_TLIFE")
        for (r, v, p) in S1("RTP").keys                                   # L19
            ((v,) in fil && (r, p) in prc_cap) || continue
            gassign!(pastsum, (r, v, p), gvB(v) + gv(iled, (r, v, p)) + gv(rpti, (r, v, p)) * gv(tlife, (r, v, p)))
        end
        for (r, v, t, p) in S1("RTP_CPTYR").keys                          # L20-21
            ((v,) in fil && inT(t) && haskey(pastsum, (r, v, p))) || continue
            ps = gv(pastsum, (r, v, p))
            x = gmax(GZERO, (gmin(gvE(t) + 1, ps) - gmax(gvB(v) + gv(iled, (r, v, p)), gvB(t))) / gvD(t))
            gassign!(coef_cpt, (r, v, t, p), x)
        end
    end
    gput!(tm, "COEF_CPT", coef_cpt)
    gput!(tm, "PASTSUM", empty!(pastsum))                                  # L24

    # L28-32: NCAP_AF as the minimum of NCAP_AF and NCAP_AFS at the same timeslice
    annual = S1("ANNUAL")
    my_ts = Set{NTuple{1,String}}(k for k in S1("ALL_TS").keys if !(k in annual))
    gput!(tm, "MY_TS", my_ts)
    rtp, prc_ts, rps_prcts = S1("RTP"), S1("PRC_TS"), S1("RPS_PRCTS")
    af, afs = gvalues(tm, "NCAP_AF", 5), gvalues(tm, "NCAP_AFS", 5)
    afs_p = gparam(tm, "NCAP_AFS")
    for k in afs_p.keys                                                    # L29
        (r, v, p, s, bd) = k
        ((r, v, p) in rtp && inV(v) && (s,) in my_ts && (r, p, s) in prc_ts) || continue
        a = gv(af, k)
        gassign!(af, k, gmin(a + gif(Inf, iszero(a)), gv(afs_p, k)))      # NOT a: a is 0, not EPS (G25)
    end
    for (r, v, p, s, bd) in afs_p.keys                                     # L30
        (bd == "FX" && (r, v, p) in rtp && inV(v) && (r, p, s) in prc_ts) || continue
        delete!(af, (r, v, p, s, "LO")); delete!(af, (r, v, p, s, "UP"))
    end
    for (r, v, p, s, bd) in afs_p.keys                                     # L32
        ((r, v, p) in rtp && inV(v) && (s,) in my_ts) || continue
        ((r, p, s) in prc_ts || !((r, p, s) in rps_prcts)) && delete!(afs, (r, v, p, s, bd))
    end
    gput!(tm, "NCAP_AF", af)
    gput!(tm, "NCAP_AFS", afs)

    # L42-47 with NCAP_AFM and NCAP_AFX empty: TRACKP = PRC_CAP(PRC_VINT) (L43-46),
    # NCAP_AFBX unchanged (L47).
    prc_cap, prc_vint = S1("PRC_CAP"), S1("PRC_VINT")
    trackp = Set{NTuple{2,String}}(k for k in prc_vint.keys if k in prc_cap)
    gput!(tm, "TRACKP", trackp)

    # L48: pp_shapr.mod NCAP_AF (R,V,P,S,BD) "TRACKP*RP_AFB*PRC_TS" COEF_AF(...) NCAP_AFM B
    coef_af = gvalues(tm, "COEF_AF", 6)
    rtp_cptyr = [k for k in S1("RTP_CPTYR").keys if inV(k[2]) && inT(k[3])]
    cpt_of_rvp = Dict{NTuple{3,String},Vector{String}}()                  # (r,v,p) -> T of RTP_CPTYR
    for (r, v, t, p) in rtp_cptyr
        push!(get!(() -> String[], cpt_of_rvp, (r, v, p)), t)
    end
    ts_of_rp = indexby(prc_ts, (1, 2))
    afb = gparam(tm, "RP_AFB")
    bd_of_rp = indexby(afb, (1, 2))
    af_p = gparam(tm, "NCAP_AF")
    pp_shapr_base!(tm)
    for (r, v, t, p) in rtp_cptyr                                          # pp_shapr.mod L43-44
        ((r, v, p) in rtp && (r, p) in trackp) || continue
        for (_, _, s) in get(ts_of_rp, (r, p), NTuple{3,String}[]), (_, _, bd) in get(bd_of_rp, (r, p), NTuple{3,String}[])
            gassign!(coef_af, (r, v, t, p, s, bd), gv(af_p, (r, v, p, s, bd)))
        end
    end

    # L50-52: non-vintaged processes take the period's NCAP_AF; NCAP_AFA at ANNUAL
    trackp = Set{NTuple{2,String}}(k for k in prc_cap.keys if !(k in trackp))   # TRACKP ⊆ PRC_CAP here
    gput!(tm, "TRACKP", trackp)
    af_of_rtp = indexby(af_p, (1, 2, 3))
    afa = gparam(tm, "NCAP_AFA")
    afa_of_rtp = indexby(afa, (1, 2, 3))
    for (r, v, t, p) in rtp_cptyr
        if (r, p) in trackp                                                # L51
            for k in get(af_of_rtp, (r, t, p), NTuple{5,String}[])
                (r, p, k[4]) in prc_ts || continue
                gassign!(coef_af, (r, v, t, p, k[4], k[5]), gv(af_p, k))
            end
        end
        if (r, p) in prc_cap                                               # L52
            for k in get(afa_of_rtp, (r, t, p), NTuple{4,String}[]), (a,) in annual.keys
                gassign!(coef_af, (r, v, t, p, a, k[4]), gv(afa, k))
            end
        end
    end

    # L55-58 with NCAP_AFM, NCAP_AFSM, NCAP_AFX and NCAP_AFSX empty
    gput!(tm, "RP_PRC", Set{NTuple{2,String}}())
    afs_p = gparam(tm, "NCAP_AFS")
    rtps_bd = gmembers(tm, "RTPS_BD", 5)
    for k in afs_p.keys                                                    # L57
        (r, v, p, s, bd) = k
        ((r, v, p) in rtp && inV(v)) || continue
        ((r, p) in prc_vint || (s,) in annual) && push!(rtps_bd, k)
    end

    # L59: pp_shapr.mod NCAP_AFS (R,V,P,S,BD) "RTPS_BD(R,V,P,S,BD)" COEF_AF(...) NCAP_AFSM
    pp_shapr_base!(tm)
    for k in sort!(collect(rtps_bd))                                      # pp_shapr.mod L43-44
        (r, v, p, s, bd) = k
        (r, v, p) in rtp || continue
        for t in get(cpt_of_rvp, (r, v, p), String[])
            gassign!(coef_af, (r, v, t, p, s, bd), gv(afs_p, k))
        end
    end

    # L61-62
    afs_of_rtp = indexby(afs_p, (1, 2, 3))
    for (r, v, t, p) in rtp_cptyr
        if (r, p) in prc_cap                                               # L61
            for k in get(afs_of_rtp, (r, t, p), NTuple{5,String}[])
                (r, v, p, k[4], k[5]) in rtps_bd && continue
                gassign!(coef_af, (r, v, t, p, k[4], k[5]), gv(afs_p, k))
            end
        end
        if haskey(afa, (r, t, p, "FX"))                                    # L62
            for (a,) in annual.keys
                delete!(coef_af, (r, v, t, p, a, "LO")); delete!(coef_af, (r, v, t, p, a, "UP"))
            end
        end
    end
    gput!(tm, "COEF_AF", coef_af)

    # L63: OPTION CLEAR=TRACKP,CLEAR=RTPS_BD,CLEAR=NCAP_AFBX
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "RTPS_BD", Set{NTuple{5,String}}())
    gput!(tm, "NCAP_AFBX", Dict{NTuple{4,String},Float64}())
    return tm
end

"""
    pp_shapr_base!(tm)

pp_shapr.mod with no shape index (RTP_ISHPR empty after L19-20, which
coef_cpt_unported guarantees): FIL2(V) = B(V)-YEARVAL(V) (L23); the
assignment of the base value (L43-44) is done by the caller, which knows
%3 and %4; RTP_ISHPR, RTP_SHAPI and PASTSUM end cleared (L46).

GAMS: pp_shapr.mod L15-46, v4.9.7.
"""
function pp_shapr_base!(tm)
    B, yearval = gparam(tm, "B"), gparam(tm, "YEARVAL")
    fil2 = Dict{NTuple{1,String},Float64}()
    for (v,) in gset(tm, "MODLYEAR").keys
        gassign!(fil2, (v,), gv(B, (v,)) - gv(yearval, (v,)))
    end
    gput!(tm, "FIL2", fil2)
    gput!(tm, "RTP_ISHPR", Set{NTuple{3,String}}())
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    return tm
end
