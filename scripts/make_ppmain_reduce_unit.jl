# Run ppmain.mod L616-1350 (TIMES v4.9.7: changes 9 to 16, then
# pp_reduce.red and RTPCS_VARF/RTP_VINTYR) itself with GAMS on the crafted
# states of test/unit/ppmain_reduce_case.jl, one fixture per case, so the
# unit test checks the translated steps up to ppmain_reduce! on the paths
# no core reference run takes.
#
#   julia --project=test scripts/make_ppmain_reduce_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint, so only ppmain.mod
# L616-1350 runs (scripts/ppmain_replay.jl: the lines unchanged, the control
# variables set as TIMES sets them). Writes
# test/fixtures/ppmain_reduce_unit_gams/<case>/. scripts/m13_replay.jl runs the
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
include(joinpath(REPO, "test", "unit", "ppmain_uc_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_ucmap_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_blend_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_reduce_case.jl"))

"What ppmain.mod L616-1350 writes (compared at L1350, scratch included)."
const PPMAIN_REDUCE_OUTPUTS = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW, PPMAIN_CUM_NEW, PPMAIN_STG_NEW, PPMAIN_UC_NEW, PPMAIN_UCMAP_NEW, PPMAIN_BLEND_NEW, PPMAIN_REDUCE_NEW))

"""
    ppmain_reduce_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-1350 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_REDUCE_OUTPUTS at L1350
(scripts/ppmain_replay.jl).
"""
function ppmain_reduce_replay(tm, times_dir; kw...)
    occursin("OPTION CLEAR=R_UC,CLEAR=RVP,CLEAR=RTPCS_OUT", readlines(joinpath(times_dir, "ppmain.mod"))[1350]) ||
        error("ppmain.mod L1350 is not the CLEAR of R_UC, RVP, RTPCS_OUT: is this TIMES v4.9.7?")
    return ppmain_replay(tm, times_dir, 1350; outputs=PPMAIN_REDUCE_OUTPUTS,
                         declared=vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW, PPMAIN_FLO_DECLARED_NEW, PPMAIN_FLOFS_DECLARED_NEW, PPMAIN_IRE_DECLARED_NEW, PPMAIN_BND_DECLARED_NEW, PPMAIN_CUM_DECLARED_NEW, PPMAIN_STG_DECLARED_NEW, PPMAIN_UC_DECLARED_NEW, PPMAIN_UCMAP_DECLARED_NEW, PPMAIN_BLEND_DECLARED_NEW, PPMAIN_REDUCE_DECLARED_NEW), kw...)
end

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_reduce_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_REDUCE_CASES
        tm = ppmain_reduce_start(fixtures, name)
        work = mktempdir()
        ppmain_reduce_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-1350 on test/unit/ppmain_reduce_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
