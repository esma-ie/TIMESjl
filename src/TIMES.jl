"""
    TIMES

Julia/JuMP translation of the IEA-ETSAP TIMES model generator.

Phase 1 translates TIMES v4.9.7 (`etsap-TIMES/TIMES_model` @ `d9a6a25`) with
exact numerical parity. The `TIMES.Reference` submodule reads GAMS reference
dumps and compares them with TIMES.jl output; the model itself is added
milestone by milestone from M1.1.
"""
module TIMES

"TIMES GAMS version this code is translated from."
const TIMES_GAMS_VERSION = v"4.9.7"

"Commit of `etsap-TIMES/TIMES_model` this code is translated from."
const TIMES_GAMS_COMMIT = "d9a6a25"

import JuMP

include("reference/Reference.jl")
include("model/gams_data.jl")
include("model/mod_vars.jl")
include("model/equations.jl")
include("model/eqactflo.jl")
include("model/eqactbnd.jl")
include("model/eqcapact.jl")
include("model/eqcpt.jl")
include("model/cal_red.jl")
include("model/eqptrans.jl")
include("model/eqfloshr.jl")
include("model/eqcumflo.jl")
include("model/eqcumcom.jl")
include("model/eqcombal.jl")
include("model/eqire.jl")
include("model/eqpeak.jl")
include("model/eqstgtss.jl")
include("model/eqstgaux.jl")
include("model/eqstgflo.jl")
include("model/equserco.jl")
include("model/eqobj.jl")
include("model/bndmain.jl")
include("ext/vda/pp_actef.jl")
include("ext/vda/eqashar.jl")
include("ext/vda/eqcaflac.jl")
include("coef/state.jl")
include("coef/coef_cpt.jl")
include("coef/coef_nio.jl")
include("coef/coef_ptr.jl")
include("coef/coef_obj.jl")
include("coef/coef_alt.jl")
include("coef/coef_shp.jl")
include("coef/coef_ext.jl")
include("coef/later.jl")
include("ext/dsc/init_ext.jl")
include("ext/vda/equcrtp.jl")
include("ext/vda/init_ext.jl")
include("prep/ppmain.jl")
include("model/generate.jl")

end # module TIMES
