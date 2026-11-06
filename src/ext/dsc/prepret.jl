# M1.3 (6a): prepret.dsc PREP, the preprocessing of early retirements and
# refits, $BATINCLUDEd by preppm.mod L57 as `prepret.dsc PREP PRC_RCAP
# RCAP_BND` when %RETIRE% is set. %PGPRIM% is 'ACT' unless the run sets it,
# and then initmty.mod L454 sets %RETIRE% to YES, so the block is reached in
# every suite run.
#
# GAMS: prepret.dsc L1-41, v4.9.7.
#
# Compile-time parts, decided from the data the DD files give (G35; an empty
# data statement such as `PARAMETER x //` counts, G40):
# - L15: with PRC_REFIT data, `SET PRC_RCAP //; PARAMETER RCAP_BND //;`
#   makes both DEFINED;
# - L17: with PRC_RCAP DEFINED, RCAP_BND gets the 'N' option of the
#   processes in PRC_RCAP (and is DEFINED by that assignment);
# - L18: with %RETIRE% YES the arguments shift: %1 is PRC_RCAP, %2 RCAP_BND;
# - L20: without RCAP_BND DEFINED the file exits here;
# - L28-29: only with NCAP_OLIFE data;
# - L39-41 set %SOLMIP% and define the macro VNRET (used by prep_ext.vda L75
#   and later), no data.
# %RETIRE% values other than YES (NO, MIP) take other compile paths and are
# refused.

"%RETIRE% as initmty.mod L454 leaves it: YES with %PGPRIM% ACT, else as the run sets it."
function retire_switch(tm)
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    return pg == "ACT" ? "YES" : uppercase(strip(gswitch(tm, "RETIRE", ""), ['\'', '"']))
end

hasdata(tm, name, N) = !isempty(gparam_opt(tm.data, name, N).keys)
hasmembers(tm, name, N) = !isempty(gset_opt(tm.data, name, N).keys)

"The prepret.dsc PREP paths this model would take that are not translated."
function prepret_unported(tm)
    r = retire_switch(tm)
    (r == "" || r == "YES") && return String[]
    return ["prepret.dsc L16-18 (RETIRE $r: only YES is translated)"]
end

"""
    prepret_prep!(st) -> st

prepret.dsc PREP (preppm.mod L57) on the state of `st.tm`: the retirement
bounds RCAP_BND (with the 'N' option for PRC_RCAP), RCAP_BLK, RCAP_OCAP and
NCAP_OLIFE interpolated, PRC_RCAP from RCAP_BND, and the refits of
PRC_REFIT (their NCAP_ILED made negative, RTP_VARP).

GAMS: prepret.dsc L13-41, v4.9.7.
"""
function prepret_prep!(st::InterpState)
    tm = st.tm
    retire_switch(tm) == "YES" || return st                       # preppm.mod L57: $IF SET RETIRE
    refit_def = hasdata(tm, "PRC_REFIT", 3)
    rcap_def = refit_def || hasmembers(tm, "PRC_RCAP", 2)          # L15
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    prc = Set(k[1] for k in gset(tm, "PRC").keys)
    rcap_bnd = gvalues(tm, "RCAP_BND", 4)
    prc_rcap = gmembers(tm, "PRC_RCAP", 2)
    if rcap_def
        # L17: RCAP_BND(R,'0',P,'N')$(RCAP_BND(R,'0',P,'N')=0) $= PRC_RCAP(R,P)
        register_uel!(tm.data, "N")
        for (r, p) in prc_rcap
            (r in reg && p in prc) || continue
            k = (r, "0", p, "N")
            gv(rcap_bnd, k).v == 0 && gassign!(rcap_bnd, k, GNum(1.0))
        end
        gput!(tm, "RCAP_BND", rcap_bnd)
    end
    # L20: $IF NOT DEFINED RCAP_BND $EXIT
    (rcap_def || !isempty(rcap_bnd)) || return st
    # L19: PRC_REFIT(RP,P)$0=0 assigns nothing
    # L24: OPTION PRC_RCAP < RCAP_BND: RCAP_BND(REG,ALLYEAR,PRC,LIM) onto PRC_RCAP(REG,PRC)
    prc_rcap = project(keys(rcap_bnd), (1, 3))
    gput!(tm, "PRC_RCAP", prc_rcap)
    rtp = gmembers(tm, "RTP", 3)
    V = [k[1] for k in gset(tm, "MODLYEAR").keys]
    rtpV = k -> (k[1], k[2], k[3]) in rtp
    ge0 = (d, k) -> d >= 0
    # L25: $BATINCLUDE fillparm RCAP_BLK R 'P' ",'','','','',''" V 'RTP(R,V,P)' '>=0'
    fillparm!(st, "RCAP_BLK", "R", "P", pd(",'','','','',''"), V, rtpV, ge0)
    # L26: $BATINCLUDE fillparm RCAP_OCAP R 'P,C' ",'0','0','0','0'" V 'RTP(R,V,P)' '>=0'
    fillparm!(st, "RCAP_OCAP", "R", "P,C", pd(",'0','0','0','0'"), V, rtpV, ge0)
    # L27: $BATINCLUDE prepparm RCAP_BND R 'P,L' ",'','',''" V 'RTP(R,V,P)' 1
    prepparm!(st, "RCAP_BND", "R", "P,L", pd(",'','',''"), V, rtpV, GNum(1.0))
    if hasdata(tm, "NCAP_OLIFE", 3)
        # L28: $IF DEFINED NCAP_OLIFE $BATINCLUDE fillparm NCAP_OLIFE R P ",'','','','',''" V 'RTP(R,V,P)' '>=0'
        fillparm!(st, "NCAP_OLIFE", "R", "P", pd(",'','','','',''"), V, rtpV, ge0)
        # L29: OPTION PRC_CAP < NCAP_ELIFE; NCAP_ELIFE(R,V,P)$(NOT PRC_CAP(R,P)) $= NCAP_OLIFE(R,V,P); PRC_CAP(R,P)=0
        elife = gvalues(tm, "NCAP_ELIFE", 3)
        prc_cap = project(keys(elife), (1, 3))
        Vset = Set(V)
        for (k, x) in gvalues(tm, "NCAP_OLIFE", 3)
            (k[1] in reg && k[2] in Vset && k[3] in prc && !((k[1], k[3]) in prc_cap)) && (elife[k] = x)
        end
        gput!(tm, "NCAP_ELIFE", elife)
        gput!(tm, "PRC_CAP", Set{NTuple{2,String}}())
    end
    # L31-33: LOOP((RP(R,PRC),P)$(RP(R,P)$PRC_REFIT(RP,P)), NCAP_ILED(RTP(R,V,P)) = -ABS(NCAP_ILED(RTP));
    #           PRC_RCAP(RP)=YES; TRACKP(R,P)$(PRC_REFIT(RP,P)<0)=YES)
    rp = gset(tm, "RP").members
    iled = gvalues(tm, "NCAP_ILED", 3)
    trackp = gmembers(tm, "TRACKP", 2)
    refit = gparam_opt(tm.data, "PRC_REFIT", 3)
    byrp = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(byrp, (k[1], k[3]), String[]), k[2]), rtp)
    for k in refit.keys                                           # EPS counts (G3)
        r, host, p = k
        ((r, host) in rp && (r, p) in rp) || continue
        for v in get(byrp, (r, p), String[])
            kk = (r, v, p)
            gassign!(iled, kk, -abs(gv(iled, kk)))
        end
        push!(prc_rcap, (r, host))
        gv(refit, k).v < 0 && push!(trackp, (r, p))
    end
    gput!(tm, "NCAP_ILED", iled)
    # L34: RTP_VARP(RTP(R,T,P)) $= PRC_RCAP(R,P)
    tset = gset(tm, "MILESTONYR").members
    rtp_varp = gmembers(tm, "RTP_VARP", 3)
    foreach(k -> ((k[2],) in tset && (k[1], k[3]) in prc_rcap) && push!(rtp_varp, k), rtp)
    gput!(tm, "RTP_VARP", rtp_varp)
    # L35: PRC_RCAP(TRACKP)=YES; OPTION CLEAR=TRACKP
    union!(prc_rcap, trackp)
    gput!(tm, "PRC_RCAP", prc_rcap)
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    # L37: RCAP_OCAP(RTP(R,V,P),C)$(PRC_RCAP(R,P)->0) = 0
    ocap = gvalues(tm, "RCAP_OCAP", 4)
    filter!(((k, _),) -> !((k[1], k[2], k[3]) in rtp && !((k[1], k[3]) in prc_rcap)), ocap)
    gput!(tm, "RCAP_OCAP", ocap)
    return st
end

# M1.3 (20b-2): %RCAPSUB% and %RCAPSBM%, the retired capacity taken off the
# capacity terms of the equations compiled after eqobj.mod L39 (prepret.dsc
# EQOBJ is included there, before every other equation of eqmain.mod).
#
# GAMS: prepret.dsc L87-88, v4.9.7:
#   $SETGLOBAL RCAPSUB -SUM(VNTRT(V,T),%VART%_SCAP(R,V,T,P%SWS%))$PRC_RCAP(R,P)
#   $SETGLOBAL RCAPSBM -SUM(VNTRT(MODLYEAR,T),%VART%_SCAP(R,MODLYEAR,T,P%SWS%))$PRC_RCAP(R,P)
# Without early retirement both are empty (setglobs.gms L351). Where V (or
# MODLYEAR) is already controlled the SUM is a condition on it (G18), the
# single term -VAR_SCAP(R,V,T,P) for VNTRT(V,T) (`rcapsub!`): eqcpt.mod L26,
# eqcapact.mod L37 and L45, eqpeak.mod L24, and eqcaflac.vda L32 and L57,
# whose SUM over RVP_KMAP(R,V,P,MODLYEAR(K)) controls MODLYEAR together with
# K (docs/discrepancies.md G48: checked on the crafted case
# TIMES_Demo-demo12_refit_afc, where reading MODLYEAR as free doubles the
# coefficients). The other users (cal_cap.mod, cal_caps.mod, eqactups.vda,
# eqlducs.vda, resloadc.vda) are refused with their files.

"Early retirement on (VNRET defined), PRC_RCAP and VNTRT, cached."
function rcap_ctx(tm::TimesModel)
    get!(tm.cache, "RCAPSUB") do
        on = Reference.has_symbol(tm.data.dump, "RP_RTF")
        (; on, prc_rcap=on ? gset(tm, "PRC_RCAP") : gset_opt(tm.data, "PRC_RCAP", 2),
           vntrt=on ? gset(tm, "VNTRT") : gset_opt(tm.data, "VNTRT", 2))
    end
end

"""
    rcapsub!(expr, c, tm, r, v, t, p) -> expr

`c * %RCAPSUB%` with V and T controlled: `-c * VAR_SCAP(r,v,t,p)` when early
retirement is on, PRC_RCAP(r,p) and VNTRT(v,t).

GAMS: prepret.dsc L87 (and L88, %RCAPSBM%, with MODLYEAR controlled), v4.9.7.
"""
function rcapsub!(expr::JuMP.AffExpr, c::GNum, tm::TimesModel, r, v, t, p)
    x = rcap_ctx(tm)
    x.on && (r, p) in x.prc_rcap && (v, t) in x.vntrt && addterm!(expr, -c, tm, "VAR_SCAP", r, v, t, p)
    return expr
end

# M1.3 (20b-1): the retirement and refit equations of the EQOBJ label,
# generated at the SOLVE (mod_equa.mod L212, `$IF DEFINED VNRET`) from the
# data as it stands then (the pre-solve dump: after the DECL label, L44-84,
# and the EQOBJ label's own clean-up, L121-131).
#
# GAMS: prepret.dsc L89-117, v4.9.7, included from eqobj.mod L39 as
# `$IF DECLARED VNRET $BATINCLUDE prepret.dsc EQOBJ`.
#
#   EQ_CUMRET(R,VNTRT(V,K(T-(1-1$RP_RTF(R,P)))),P)$(RTP_CPTYR(R,V,T,P)$PRC_RCAP(R,P))..
#     SUM(RTP_CPTYR(R,V,K,P), VAR_SCAP(R,V,T,P) - VAR_RCAP(R,V,T,P)) -
#     SUM(RTP_CPTYR(R,V,MODLYEAR(Y(T-1)),P)$VNTRT(V,Y), VAR_SCAP(R,V,Y,P))  =E= 0;
#
#   EQL_SCAP(RTP(R,V(LL),P),IPS)$(((OBJ_SUMS(RTP)+(NOT PRC_VINT(R,P))$T(V))$RVPRL(RTP)$L(IPS)
#                                  OR NCAP_OLIFE(RTP)$IO(IPS))$PRC_RCAP(R,P))..
#     SUM(IO(IPS), SUM((RTP_CPTYR(R,V,TT,P),PRC_TS(R,P,S)), VAR_ACT(R,V,TT,P,S)*FPD(TT))/PRC_CAPACT(R,P)/NCAP_OLIFE(RTP)) +
#     SUM(VNTRT(V,T(LL+RVPRL(RTP))), VAR_SCAP(R,V,T,P))$LIM(IPS)
#     =L= VAR_NCAP(R,V,P)$T(V) + NCAP_PASTI(R,V,P) - VAR_SCAP(R,V,'0',P)$RVPRL(RTP);
#
#   EQL_REFIT(RTP_TT(R,TT,T,PRC),LNX(L))$((BD(L)+VNT(T,TT)$(RP_RTF(R,PRC)=3))$RT_PP(R,T))..
#     SUM((V(TT),P)$((VNT(T,V) OR PRC_REFIT(R,PRC,P)<0)$PRC_REFIT(R,PRC,P)),
#         COEF_CPT(R,V,T,P)*(VAR_NCAP(R,V,P) - SUM(VNTRT(V,T),VAR_SCAP(R,V,T,P))$PRC_RCAP(R,P)))
#     + VAR_RCAP(R,T,TT,PRC)$(RP_RTF(R,PRC)$VNT(T,TT)$BD(L)<3)
#     =E=
#     SUM(VNRET(V,TT,PRC), COEF_CPT(R,V,T,PRC) * (VAR_RCAP(R,V,TT,PRC) -
#         SUM(MODLYEAR(K(TT-1))$VNT(V,K), MIN(INF$MOD(RP_RTF(R,PRC),2), RTFORC(R,V,TT,PRC)-RTFORC(R,V,K,PRC))))) +
#     SUM(K(TT-1)$RTP_TT(R,K,T,PRC), VAR_RCAP(R,T,K,PRC))$(RP_RTF(R,PRC)$BD(L)>0);
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VARV%/%VART%/%VARTT%/%VARM% -> VAR,
# %SOW%/%SWS%/%SWT% -> '' (setglobs.gms L348); %R_V_T% -> R,V,T
# (maindrv.mod L39); %RCAPSUB% in EQL_REFIT is L87's
# `-SUM(VNTRT(V,T),VAR_SCAP(R,V,T,P))$PRC_RCAP(R,P)`; VNRET(V,T,P) is the
# L41 macro RTP_CPTYR(R,VNTRT(V,T),P). Sets: IPS = {IN, N}, LNX = {N, FX}
# (setglobs.gms L154); L is LIM = {LO, FX, UP, N} and BD is BND_TYPE =
# {LO, FX, UP} (initsys.mod L70-73), so EQL_SCAP's N rows are the LIM ones
# and its IN rows the IO ones; EQL_REFIT has FX rows wherever RT_PP holds and
# N rows only for VNT(T,TT) with RP_RTF = 3. Despite its name EQL_REFIT is
# =E=. Leads and lags on milestone aliases (T-1, TT-1) move along the
# milestones (G38); `LL+RVPRL` along ALLYEAR, by RVPRL rounded (G29, G34).
# EPS is true in a `$`-condition (G3) and 0 in a comparison (G12); `$` binds
# before the comparisons (as before `-` and `**`, G13, G38), so
# `RP_RTF$VNT$BD<3` reads `(RP_RTF$VNT$BD) < 3`. `MOD(x,2)` keeps the sign
# of x (G43), so a negative odd RP_RTF gives INF.
#
# Not translated yet; data that reaches them raises UnportedError:
# - EQ_DSCRET (L92-95), rows only with RCAP_BLK, which L122 clears unless
#   %MIP% (RCAP_BLK is refused: init_ext.jl);
# - the IN rows of EQL_SCAP (NCAP_OLIFE, prepret.dsc L28-29), which no
#   suite model reaches.

"""
    eq_ret!(tm::TimesModel) -> Int

Generate every EQ_CUMRET, EQL_SCAP and EQL_REFIT row (mod_equa.mod L212)
from `tm.data`: nothing unless early retirement is on (RP_RTF declared, the
test `untranslated_families` uses for `\$IF DEFINED VNRET`). Returns the
number of rows generated.

GAMS: prepret.dsc L89-117, v4.9.7.
"""
function eq_ret!(tm::TimesModel)
    d = tm.data
    Reference.has_symbol(d.dump, "RP_RTF") || return 0
    isempty(gparam_opt(d, "RCAP_BLK", 3).keys) ||
        throw(UnportedError("EQ_DSCRET: retirements in blocks (RCAP_BLK, prepret.dsc L92-95)"))
    prc_rcap, rp_rtf = gset(tm, "PRC_RCAP"), gparam(tm, "RP_RTF")
    ncap_olife = gparam_opt(d, "NCAP_OLIFE", 3)
    any(k -> (k[1], k[3]) in prc_rcap, ncap_olife.keys) &&
        throw(UnportedError("EQL_SCAP IN rows: salvage limited by activity (NCAP_OLIFE, prepret.dsc L105-107)"))
    one = GNum(1.0)
    t_set = gset(tm, "MILESTONYR")
    t_list = [k[1] for k in t_set.keys]
    t_prev = Dict(t_list[i] => t_list[i-1] for i in 2:length(t_list))   # T-1 on the milestones (G38)
    allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
    ord = Dict(y => i for (i, y) in enumerate(allyear))
    rtp_cptyr, vntrt, vnt = gset(tm, "RTP_CPTYR"), gset(tm, "VNTRT"), gset(tm, "VNT")
    modlyear = gset(tm, "MODLYEAR")
    n = 0

    # EQ_CUMRET (L98-102)
    for (r, v, t, p) in rtp_cptyr
        ((r, p) in prc_rcap && (t,) in t_set) || continue
        k = haskey(rp_rtf.values, (r, p)) ? t : get(t_prev, t, nothing)  # K(T-(1-1$RP_RTF))
        (k !== nothing && (v, k) in vntrt) || continue
        lhs = JuMP.AffExpr(0.0)
        if (r, v, k, p) in rtp_cptyr
            addterm!(lhs, one, tm, "VAR_SCAP", r, v, t, p)
            addterm!(lhs, -one, tm, "VAR_RCAP", r, v, t, p)
        end
        y = get(t_prev, t, nothing)                                     # Y(T-1)
        y !== nothing && (y,) in modlyear && (r, v, y, p) in rtp_cptyr && (v, y) in vntrt &&
            addterm!(lhs, -one, tm, "VAR_SCAP", r, v, y, p)
        gconstraint!(tm, "EQ_CUMRET", (r, v, k, p), "E", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    end

    # EQL_SCAP, the N rows (L105-111)
    rvprl, obj_sums, prc_vint = gparam(tm, "RVPRL"), gset(tm, "OBJ_SUMS"), gset(tm, "PRC_VINT")
    ncap_pasti = gparam(tm, "NCAP_PASTI")
    for (r, v, p) in gset(tm, "RTP")
        (r, p) in prc_rcap || continue
        haskey(rvprl.values, (r, v, p)) || continue                      # $RVPRL(RTP)
        ((r, v, p) in obj_sums || (!((r, p) in prc_vint) && (v,) in t_set)) || continue
        lhs = JuMP.AffExpr(0.0)
        i = ord[v] + glead(gv(rvprl, (r, v, p)).v)                     # T(LL+RVPRL(RTP))
        if 1 <= i <= length(allyear)
            tl = allyear[i]
            (tl,) in t_set && (v, tl) in vntrt && addterm!(lhs, one, tm, "VAR_SCAP", r, v, tl, p)
        end
        rhs = JuMP.AffExpr(0.0)
        (v,) in t_set && addterm!(rhs, one, tm, "VAR_NCAP", r, v, p)
        addconst!(rhs, gv(ncap_pasti, (r, v, p)))
        addterm!(rhs, -one, tm, "VAR_SCAP", r, v, "0", p)
        gconstraint!(tm, "EQL_SCAP", (r, v, p, "N"), "L", lhs, rhs) === nothing || (n += 1)
    end

    # EQL_REFIT (L113-117)
    rt_pp, coef_cpt, rtforc = gset(tm, "RT_PP"), gparam(tm, "COEF_CPT"), gparam(tm, "RTFORC")
    rtp_tt, prc_refit = gset(tm, "RTP_TT"), gparam(tm, "PRC_REFIT")
    refit_of = indexby(prc_refit, (1, 2))                               # (r,prc) -> PRC_REFIT(r,prc,p)
    vret_of = Dict{NTuple{3,String},Vector{String}}()                   # (r,tt,prc) -> V with VNRET(V,TT,PRC)
    for (r, v, t, p) in rtp_cptyr
        (v, t) in vntrt && push!(get!(vret_of, (r, t, p), String[]), v)
    end
    for (r, tt, t, prc) in rtp_tt, l in ("N", "FX")                    # RTP_TT(R,TT,T,PRC), LNX(L)
        (r, t) in rt_pp || continue
        rtf = gv(rp_rtf, (r, prc))
        bdl = l == "FX"                                                 # BD(L)
        vtt = (t, tt) in vnt                                            # VNT(T,TT)
        (bdl || (vtt && rtf.v == 3)) || continue
        lhs = JuMP.AffExpr(0.0)
        for (_, _, p) in get(refit_of, (r, prc), NTuple{3,String}[])
            (vtt || gv(prc_refit, (r, prc, p)).v < 0) || continue
            c = gv(coef_cpt, (r, tt, t, p))
            addterm!(lhs, c, tm, "VAR_NCAP", r, tt, p)
            (r, p) in prc_rcap && (tt, t) in vntrt && addterm!(lhs, -c, tm, "VAR_SCAP", r, tt, t, p)   # %RCAPSUB%
        end
        ((vtt && bdl) ? rtf.v : 0.0) < 3 && addterm!(lhs, one, tm, "VAR_RCAP", r, t, tt, prc)
        rhs = JuMP.AffExpr(0.0)
        k = get(t_prev, tt, nothing)                                    # K(TT-1)
        odd = rtf.v != 0 && rem(rtf.v, 2) != 0                          # MOD(RP_RTF,2) (G43)
        for v in get(vret_of, (r, tt, prc), String[])
            c = gv(coef_cpt, (r, v, t, prc))
            addterm!(rhs, c, tm, "VAR_RCAP", r, v, tt, prc)
            if k !== nothing && (k,) in modlyear && (v, k) in vnt
                m = gmin(odd ? GNum(Inf) : GZERO, gv(rtforc, (r, v, tt, prc)) - gv(rtforc, (r, v, k, prc)))
                addconst!(rhs, -(c * m))
            end
        end
        if (bdl ? rtf.v : 0.0) > 0 && k !== nothing && (r, k, t, prc) in rtp_tt
            addterm!(rhs, one, tm, "VAR_RCAP", r, t, k, prc)
        end
        gconstraint!(tm, "EQL_REFIT", (r, tt, t, prc, l), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
