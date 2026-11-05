# Run ppmain.mod L616-1357 and ppm_ext.vda L11-58 (TIMES v4.9.7: changes 9
# to 17a, then the ACT_EFF preparation of ppm_ext.vda with pp_actef.vda)
# itself with GAMS on the crafted states of test/unit/ppm_ext_case.jl, one
# fixture per case, so the unit test checks the translated steps up to
# ppm_ext_actef! on the paths no core reference run takes.
#
#   julia --project=test scripts/make_ppm_ext_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint (scripts/ppmain_replay.jl:
# the lines unchanged, the control variables set as TIMES sets them). Writes
# test/fixtures/ppm_ext_unit_gams/<case>/. scripts/m13_replay.jl runs the
# same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "make_ppmain_reduce_unit.jl"))
include(joinpath(REPO, "test", "unit", "ppm_ext_case.jl"))
using TIMES: PPM_EXT_ACTEF_OUTPUTS

"What ppmain.mod L616-1357 and ppm_ext.vda L11-58 write (compared at ppm_ext.vda L58, scratch included)."
const PPM_EXT_ACTEF_ALL = unique(vcat(PPMAIN_REDUCE_OUTPUTS, PPM_EXT_ACTEF_OUTPUTS))

"What ppm_ext.vda L11-58 and pp_actef.vda declare themselves: MICRO (pp_actef.vda L11)."
const PPM_EXT_ACTEF_DECLARED_NEW = ["MICRO"]

"""
    ppm_ext_actef_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-1357 and ppm_ext.vda L11-58 on the state `tm` (a
prelv checkpoint, possibly modified): the symbols of PPM_EXT_ACTEF_ALL at
ppm_ext.vda L58 (scripts/ppmain_replay.jl).
"""
function ppm_ext_actef_replay(tm, times_dir; kw...)
    occursin("BATINCLUDE pp_actef.%1 LVL", readlines(joinpath(times_dir, "ppm_ext.vda"))[58]) ||
        error("ppm_ext.vda L58 is not the pp_actef.vda LVL include: is this TIMES v4.9.7?")
    return ppm_ext_replay(tm, times_dir, 58; outputs=PPM_EXT_ACTEF_ALL,
                          declared=vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW, PPMAIN_FLO_DECLARED_NEW, PPMAIN_FLOFS_DECLARED_NEW,
                                        PPMAIN_IRE_DECLARED_NEW, PPMAIN_BND_DECLARED_NEW, PPMAIN_CUM_DECLARED_NEW, PPMAIN_STG_DECLARED_NEW,
                                        PPMAIN_UC_DECLARED_NEW, PPMAIN_UCMAP_DECLARED_NEW, PPMAIN_BLEND_DECLARED_NEW,
                                        PPMAIN_REDUCE_DECLARED_NEW, PPM_EXT_ACTEF_DECLARED_NEW), kw...)
end

function main_ppm_ext(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppm_ext_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPM_EXT_CASES
        tm = ppm_ext_start(fixtures, name)
        work = mktempdir()
        ppm_ext_actef_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-1357, ppm_ext.vda L11-58 on test/unit/ppm_ext_case.jl: $name>"
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_ppm_ext(ARGS...)
end
