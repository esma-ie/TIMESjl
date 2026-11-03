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
