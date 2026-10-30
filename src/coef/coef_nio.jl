# M1.2 (2): commodity flows tied to new capacity and to decommissioning.
#
# GAMS (v4.9.7): coef_nio.mod L13-71.
#
# Capacity-related commodity flows (NCAP_ICOM, NCAP_OCOM, RCAP_OCAP, the
# RPC_CAPFLO control set, NCAP_COM, NCAP_CLED) are not translated in Phase 1
# yet: no test model has any (M1.1 refuses their equation terms, cal_cap.mod,
# likewise). With all of them empty the loops (L17-33, L38-56) and the
# assignments L15, L35, L58, L64-67 and L70-71 change nothing, and the file
# reduces to its two work-set assignments, L16 and L36, and the CLEAR of CNT
# (L59); other data raise UnportedError.

"The coef_nio.mod paths this model would take that are not translated; empty when coef_nio! can run."
function coef_nio_unported(tm)
    out = String[]
    for (s, n, kind) in (("RPC_CAPFLO", 4, :set), ("NCAP_ICOM", 4, :param), ("NCAP_OCOM", 4, :param),
                         ("RCAP_OCAP", 4, :param), ("NCAP_COM", 5, :param), ("NCAP_CLED", 4, :param))
        empty = kind == :set ? isempty(gset_opt(tm.data, s, n)) : isempty(gparam_opt(tm.data, s, n))
        empty || push!(out, "coef_nio.mod L15-71 (capacity-related commodity flows: $s has data)")
    end
    return out
end

"""
    coef_nio!(tm) -> tm

coef_nio.mod on the GAMS state in `tm`, for a model without capacity-related
commodity flows (see the file header): FIL(V) = YEARVAL(V) GE MIYR_V1 (L16),
FIL2(T) = E(T)+(1+MAX(1,D(T+1))-B(T)-E(T))/2 (L36; T+1 is the next
milestone year, none after the last, whose D is then 0) and CNT cleared
(L59).

GAMS: coef_nio.mod L13-71, v4.9.7.
"""
function coef_nio!(tm)
    u = coef_nio_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    # L16: FIL(V) over MODLYEAR (V's domain); members outside V are kept
    yearval = gparam(tm, "YEARVAL")
    miyr_v1 = gv(gparam(tm, "MIYR_V1"), ())
    fil = Set(k for k in gmembers(tm, "FIL", 1) if !(k in gset(tm, "MODLYEAR")))
    for (v,) in gset(tm, "MODLYEAR").keys
        Float64(gv(yearval, (v,))) >= Float64(miyr_v1) && push!(fil, (v,))
    end
    gput!(tm, "FIL", fil)
    # L36
    B, E, D = gparam(tm, "B"), gparam(tm, "E"), gparam(tm, "D")
    t = [k[1] for k in gset(tm, "MILESTONYR").keys]
    fil2 = gvalues(tm, "FIL2", 1)
    for (i, ti) in enumerate(t)
        dnext = i < length(t) ? gv(D, (t[i+1],)) : GZERO
        gassign!(fil2, (ti,), gv(E, (ti,)) + (1 + gmax(GNum(1), dnext) - gv(B, (ti,)) - gv(E, (ti,))) / 2)
    end
    gput!(tm, "FIL2", fil2)
    # L59: OPTION CLEAR=CNT
    gput!(tm, "CNT", Dict{Tuple{},Float64}())
    return tm
end
