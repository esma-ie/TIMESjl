# M1.3 (16): ppmain.mod L1228-1333 (docs/m13-plan.md): the blending block
# (BLE_* control sets, REFUNIT, BL_UNIT, PEAKDA_BL, BLE_BAL, RU_CVT, RU_FEQ).
# Blending is refused (UnportedError) unless a model needs it: no suite
# model has blending data (BL_TYPE, OPR). Without BL_TYPE and OPR every
# statement of the block but one acts on an empty set: BLE_SPE (L1246)
# comes from BL_TYPE, and BLE_TP, BL_UNIT, BLE_SPEOPR, BLE_SPEINP, BLE_OPR,
# BLE_ENV, BLE_BAL and RU_CVT all follow from it; BLE_INP is only declared
# (its assignments are comments), so PEAKDA_BL (L1297) is never written;
# RU_FEQ (L1311-1333) runs over OPR. The one that acts is the REFUNIT
# default (L1251), translated here.
#
# GAMS: ppmain.mod L1228-1333, v4.9.7.

"""
    ppmain_blend_unported(tm) -> Vector{String}

What ppmain.mod L1228-1333 meets that is not translated: blending data.
"""
function ppmain_blend_unported(tm)
    out = String[]
    isempty(gparam_opt(tm.data, "BL_TYPE", 3).values) || push!(out, "ppmain.mod L1246-1333 (blending: BL_TYPE has data)")
    isempty(gset_opt(tm.data, "OPR", 1).keys) || push!(out, "ppmain.mod L1311-1333 (blending: OPR has members, RU_FEQ)")
    return out
end

"""
    ppmain_blend_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1228-1333 settles (nothing later in the prelv ->
ppm segment writes them).
"""
ppmain_blend_symbols(tm) = ["REFUNIT", "BLE_SPE", "BLE_TP", "BLE_SPEOPR", "BLE_OPR", "BLE_INP", "BLE_SPEINP", "BLE_ENV", "BLE_BAL",
                            "BL_UNIT", "PEAKDA_BL", "RU_CVT", "RU_FEQ"]

"""
    ppmain_blend!(tm) -> tm

ppmain.mod L1228-1333 on the state after `ppmain_ucmap!`, without blending
data (`ppmain_blend_unported`).

GAMS: ppmain.mod L1228-1333, v4.9.7.
"""
function ppmain_blend!(tm)
    u = ppmain_blend_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    # L1236-1243: SET BLE_SPE(R,COM,SPE), BLE_TP(R,ALLYEAR,*), BLE_SPEOPR(R,COM,SPE,OPR), BLE_OPR(R,COM,COM),
    #   BLE_INP(R,COM,COM), BLE_SPEINP(R,COM,SPE,COM), BLE_ENV(R,COM,COM,OPR) //; PARAMETER BLE_BAL(R,YEAR,C,C) //;
    #   declared empty, and without BL_TYPE and OPR the block leaves them so
    for (n, N) in (("BLE_SPE", 3), ("BLE_TP", 3), ("BLE_SPEOPR", 4), ("BLE_OPR", 3), ("BLE_INP", 3), ("BLE_SPEINP", 4), ("BLE_ENV", 4))
        gput!(tm, n, Set{NTuple{N,String}}())
    end
    gput!(tm, "BLE_BAL", Dict{NTuple{4,String},Float64}())
    # L1251: REFUNIT(R)$(NOT REFUNIT(R)) = 1  (an EPS REFUNIT is kept, G25)
    ru = gvalues(tm, "REFUNIT", 1)
    for k in gset(tm, "REG").keys
        haskey(ru, k) || (ru[k] = 1.0)
    end
    gput!(tm, "REFUNIT", ru)
    return tm
end
