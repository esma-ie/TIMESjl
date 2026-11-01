# M1.3 (1): dynamic process bounds, the INIT_EXT part. User constraints
# listed in UC_DYNBND become annual bounds on a process's development:
# their UC_CAP/UC_NCAP/UC_ACT coefficients move to PRC_DYNUC, their
# UC_COMNET/UC_COMPRD ones to UC_COM at ANNUAL, and missing LHS/RHS
# defaults are filled in.
#
# GAMS: equcrtp.vda L15-38 (the INIT_EXT label), v4.9.7, included from
# init_ext.vda L128 as `$BATINCLUDE equcrtp.vda INIT_EXT`. The PREP_EXT,
# PPM_EXT and EQU_EXT labels (L40-121) are later changes (PREP_EXT calls
# prepparm.gms, M1.3 change 6).
#
# Index sets: UCN is UC_N, R is REG (UC_CAP etc. are over ALL_REG, so R
# filters), C is COM, '0' is LL--ORD(LL), the last ALLYEAR element (G31).
# Every statement reads the values from before it (G11).

"""
    equcrtp_init_ext!(tm) -> tm

equcrtp.vda INIT_EXT on the GAMS state in `tm`: nothing unless UC_DYNBND has
members (L17).

GAMS: equcrtp.vda L15-38, v4.9.7.
"""
function equcrtp_init_ext!(tm)
    dyn = gset_opt(tm.data, "UC_DYNBND", 2)
    isempty(dyn) && return tm                                          # L17: IF(CARD(UC_DYNBND), ...)
    reg = gset(tm, "REG")
    inR(r) = (r,) in reg
    t0 = last(gset(tm, "ALLYEAR").keys)[1]                             # LL--ORD(LL) (G31)
    # L17: OPTION CLEAR=UNCD1; LOOP(UC_DYNBND(UCN,BD),UNCD1(UCN)=YES)
    uncd1 = Set{NTuple{1,String}}((k[1],) for k in dyn.keys)
    gput!(tm, "UNCD1", uncd1)
    bds = Dict{String,Vector{String}}()
    for (u, bd) in dyn.keys
        push!(get!(bds, u, String[]), bd)
    end
    inU(u) = (u,) in uncd1

    # L18-20: PRC_DYNUC(UC_N,SIDE,R,LL,P,'CAP'|'NCAP'|'ACT',BD)$UC_DYNBND(UC_N,BD) $= UC_CAP|UC_NCAP|UC_ACT(...,'ANNUAL')
    dynuc = gvalues(tm, "PRC_DYNUC", 7)
    for (name, gt) in (("UC_CAP", "CAP"), ("UC_NCAP", "NCAP"))
        p = gparam_opt(tm.data, name, 5)
        for (k, _) in p.values
            (u, side, r, y, prc) = k
            inR(r) || continue
            for bd in get(bds, u, String[])
                gassign!(dynuc, (u, side, r, y, prc, gt, bd), gv(p, k))
            end
        end
    end
    uc_act = gparam_opt(tm.data, "UC_ACT", 6)
    for (k, _) in uc_act.values
        (u, side, r, y, prc, s) = k
        (s == "ANNUAL" && inR(r)) || continue
        for bd in get(bds, u, String[])
            gassign!(dynuc, (u, side, r, y, prc, "ACT", bd), gv(uc_act, k))
        end
    end
    gput!(tm, "PRC_DYNUC", dynuc)

    # L21-22: UC_COM(UC_N(UNCD1),'NET'|'PRD',SIDE,R,LL,C,ANNUAL(S),'UCN') $= UC_COMNET|UC_COMPRD(UC_N,SIDE,R,LL,C,S)
    annual = gset(tm, "ANNUAL")
    uccom = gvalues(tm, "UC_COM", 8)
    for (name, cv) in (("UC_COMNET", "NET"), ("UC_COMPRD", "PRD"))
        p = gparam_opt(tm.data, name, 6)
        for (k, _) in p.values
            (u, side, r, y, c, s) = k
            (inU(u) && inR(r) && (s,) in annual) || continue
            gassign!(uccom, (u, cv, side, r, y, c, s, "UCN"), gv(p, k))
        end
    end

    # L23-27: UC_CAP/UC_NCAP/UC_ACT/UC_COMPRD/UC_COMNET(UC_N(UNCD1),SIDE,R,...) = 0
    for (name, N) in (("UC_CAP", 5), ("UC_NCAP", 5), ("UC_ACT", 6), ("UC_COMPRD", 6), ("UC_COMNET", 6))
        p = gparam_opt(tm.data, name, N)
        isempty(p) && continue
        gput!(tm, name, Dict{NTuple{N,String},Float64}(k => v for (k, v) in p.values if !(inU(k[1]) && inR(k[3]))))
    end

    lhs0(k) = (k[1], k[2], "LHS", k[4], t0, k[6], k[7], k[8])
    rhs0(k) = (k[1], k[2], "RHS", k[4], t0, k[6], k[7], k[8])
    ucn(k) = k[8] == "UCN" && inR(k[4])
    lastll = gset(tm, "LASTLL")
    miyr_1 = gset(tm, "MIYR_1")
    # L29: UC_COM(UCN(UNCD1),COM_VAR,'LHS',R,LL--ORD(LL),C,S,'UCN')$((NOT UC_COM(..'LHS',R,'0',..))$UC_COM(..'LHS',R,LL,..)) = 5
    old = copy(uccom)
    for k in keys(old)
        (inU(k[1]) && k[3] == "LHS" && ucn(k) && !haskey(old, lhs0(k))) && gassign!(uccom, lhs0(k), 5.0)
    end
    # L30-31: UC_COM(UCN(UNCD1),COM_VAR,'RHS',R,LL--ORD(LL),C,S,'UCN')$((NOT UC_COM(..'RHS',R,'0',..))$UC_COM(..'RHS',R,LL,..)) =
    #           UC_COM(..'LHS',R,'0',..)+10$(NOT UC_COM(..'LHS',R,'0',..))
    old = copy(uccom)
    for k in keys(old)
        (inU(k[1]) && k[3] == "RHS" && ucn(k) && !haskey(old, rhs0(k))) || continue
        gassign!(uccom, rhs0(k), gv(old, lhs0(k)) + gif(10, !haskey(old, lhs0(k))))
    end
    # L33-34: UC_COM(UCN,COM_VAR,'RHS',R,LL,C,S,'UCN')$((NOT UC_COM(..'RHS',R,'0',..))$UC_COM(..'LHS',R,LL,..)) =
    #           EPS$(NOT MIYR_1(LL))+UC_COM(..'LHS',R,LL,..)$LASTLL(LL)        (every UCN, not only UNCD1)
    old = copy(uccom)
    for k in keys(old)
        (k[3] == "LHS" && ucn(k) && !haskey(old, rhs0(k))) || continue
        y = k[5]
        gassign!(uccom, (k[1], k[2], "RHS", k[4], y, k[6], k[7], k[8]),
                 gif(GEPS, !((y,) in miyr_1)) + gif(gv(old, k), (y,) in lastll))
    end
    # L35-36: UC_COM(UCN,COM_VAR,'LHS',R,LL,C,S,'UCN')$((NOT UC_COM(..'LHS',R,'0',..))$UC_COM(..'RHS',R,LL,..)) =
    #           (1+(UC_COM(..'RHS',R,LL,..)-1)$LASTLL(LL))
    old = copy(uccom)
    one = GNum(1)
    for k in keys(old)
        (k[3] == "RHS" && ucn(k) && !haskey(old, lhs0(k))) || continue
        y = k[5]
        gassign!(uccom, (k[1], k[2], "LHS", k[4], y, k[6], k[7], k[8]), one + gif(gv(old, k) - one, (y,) in lastll))
    end
    gput!(tm, "UC_COM", uccom)
    return tm
end
