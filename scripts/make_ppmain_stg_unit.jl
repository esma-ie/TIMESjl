# Run ppmain.mod L616-1099 (TIMES v4.9.7: changes 9 to 13b, then the
# storage processes) itself with GAMS on the crafted states of
# test/unit/ppmain_stg_case.jl, one fixture per case, so the unit test
# checks the translated steps up to ppmain_stg! on the paths no core
# reference run takes.
#
#   julia --project=test scripts/make_ppmain_flo_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint, so only ppmain.mod
# L616-1099 runs (scripts/ppmain_replay.jl: the lines unchanged, the control
# variables set as TIMES sets them). Writes
# test/fixtures/ppmain_stg_unit_gams/<case>/. scripts/m13_replay.jl runs the
# same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "ppmain_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_dflt_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_tsattr_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_flo_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_flofs_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_ire_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_bnd_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_cum_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_stg_case.jl"))

"What ppmain.mod L616-1099 writes (compared at L1099, scratch included)."
const PPMAIN_STG_OUTPUTS = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW, PPMAIN_CUM_NEW, PPMAIN_STG_NEW))

"""
    ppmain_stg_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-1099 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_STG_OUTPUTS at L1099
(scripts/ppmain_replay.jl).
"""
function ppmain_stg_replay(tm, times_dir; kw...)
    occursin("OPTION CLEAR=TRACKP,CLEAR=TRACKPC;", readlines(joinpath(times_dir, "ppmain.mod"))[1099]) ||
        error("ppmain.mod L1099 is not the end of the storage block: is this TIMES v4.9.7?")
    return ppmain_replay(tm, times_dir, 1099; outputs=PPMAIN_STG_OUTPUTS,
                         declared=vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW, PPMAIN_FLO_DECLARED_NEW, PPMAIN_FLOFS_DECLARED_NEW, PPMAIN_IRE_DECLARED_NEW, PPMAIN_BND_DECLARED_NEW, PPMAIN_CUM_DECLARED_NEW, PPMAIN_STG_DECLARED_NEW), kw...)
end

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_stg_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_STG_CASES
        tm = ppmain_stg_start(fixtures, name)
        work = mktempdir()
        ppmain_stg_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-1099 on test/unit/ppmain_stg_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
