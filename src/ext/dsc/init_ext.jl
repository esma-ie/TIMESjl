# M1.3 (1): the discrete-capacity extension's initial preprocessing.
#
# GAMS: init_ext.dsc L11-23, v4.9.7, run at maindrv.mod L55 (main_ext.mod
# init_ext, before init_ext.vda: DSC precedes VDA in %EXTEND%, initmty.mod
# L467-468). The extension is loaded when %DSC% is YES, which %DSCAUTO% YES
# sets (initmty.mod L453).
#
# The file decides the compile-time switch %DSC% (L15-18, L23): YES only
# when PRC_DSCNCAP is DEFINED, which with %DSCAUTO% YES it is as soon as
# NCAP_DISC is (L17, `OPTION PRC_DSCNCAP < NCAP_DISC`; G1). Its execution
# statements (L12-14, L17) act only on discrete and semi-continuous data
# (PRC_DSCNCAP, NCAP_DISC, NCAP_SEMI, PRC_SEMI). `$IF DEFINED` is read from
# the dump: a symbol is DEFINED when it has records (G35); a DD data
# statement without records would be DEFINED in GAMS but cannot be told
# apart here.
#
# Translated for models without such data, the case of every core model:
# then no statement changes anything and %DSC% becomes NO. Models with the
# data raise UnportedError until crafted cases check these statements
# against GAMS (M1.3 change 1b). %SOLMIP% (L19-20) is left as the run set
# it: it turns YES only through RCAP_BLK or %DSC% YES, both refused here.

const DSC_INIT_DATA = (("PRC_DSCNCAP", 2, :set), ("NCAP_DISC", 4, :param), ("NCAP_SEMI", 3, :param),
                       ("PRC_SEMI", 2, :param), ("RCAP_BLK", 3, :param))

"The init_ext.dsc paths this model would take that are not translated; empty when init_ext_dsc! can run."
function init_ext_dsc_unported(tm)
    out = String[]
    for (name, N, kind) in DSC_INIT_DATA
        n = kind == :set ? length(gset_opt(tm.data, name, N)) : length(gparam_opt(tm.data, name, N))
        n > 0 && push!(out, "init_ext.dsc L12-20 ($name has data: discrete/semi-continuous capacity, M1.3 change 1b)")
    end
    return out
end

"""
    init_ext_dsc!(tm) -> tm

init_ext.dsc on the GAMS state in `tm`, for a model without discrete or
semi-continuous capacity data: L13 leaves PRC_SEMI empty, no other statement
applies, and %DSC% becomes NO (L15, L23), as `\$SETGLOBAL` makes it for the
code compiled after it.

GAMS: init_ext.dsc L11-23, v4.9.7.
"""
function init_ext_dsc!(tm)
    u = init_ext_dsc_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    # L12: $IF DEFINED PRC_DSCNCAP ...                       (not DEFINED)
    # L13: OPTION PRC_SEMI<NCAP_SEMI; NCAP_SEMI(R,'0',P)$(...$PRC_SEMI(R,P)) = 10   (both empty)
    # L14: $IFE CARD(NCAP_SEMI) ...                           (CARD 0)
    # L15-18: $SET DSC NO; $IFI %DSCAUTO%==YES $IF DEFINED NCAP_DISC OPTION PRC_DSCNCAP < NCAP_DISC   (not DEFINED)
    # L23: $SETGLOBAL DSC %DSC%
    tm.switches["DSC"] = "NO"
    return tm
end

"True when the run loads the DSC extension (initmty.mod L453, L467: `\$IF %DSCAUTO%==YES` is case-sensitive)."
dsc_loaded(tm) = uppercase(gswitch(tm, "DSC", "")) == "YES" || gswitch(tm, "DSCAUTO", "") == "YES"
