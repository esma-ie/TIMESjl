# Run ppmain.mod L616-843 (TIMES v4.9.7: changes 9, 10 and 11a, then
# FLO_FUNC and FLO_SUM levelled (pp_lvlff.mod, pp_lvlfs.mod), FLO_SUM and
# IRE_FLOSUM from PRC_ACTFLO, FLO_SHAR levelled (pp_lvlbr.mod) and the market
# shares (eqflomrk.mod)) itself with GAMS on the crafted states of
# test/unit/ppmain_flofs_case.jl, one fixture per case, so the unit test
# checks pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo! and
# ppmain_flofs! on the paths no core reference run takes.
#
#   julia --project=test scripts/make_ppmain_flo_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint, so only ppmain.mod
# L616-843 runs (scripts/ppmain_replay.jl: the lines unchanged, the control
# variables set as TIMES sets them). Writes
# test/fixtures/ppmain_flofs_unit_gams/<case>/. scripts/m13_replay.jl runs the
# same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "ppmain_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_dflt_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_tsattr_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_flo_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_flofs_case.jl"))

"What ppmain.mod L616-843 writes (compared at L843, scratch included)."
const PPMAIN_FLOFS_OUTPUTS = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW))

"""
    ppmain_flofs_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-843 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_FLOFS_OUTPUTS at L843
(scripts/ppmain_replay.jl).
"""
function ppmain_flofs_replay(tm, times_dir; kw...)
    occursin("RPC_NOFLO(RMKC(RPC))", readlines(joinpath(times_dir, "ppmain.mod"))[843]) ||
        error("ppmain.mod L843 is not RPC_NOFLO(RMKC(RPC)) = NO: is this TIMES v4.9.7?")
    return ppmain_replay(tm, times_dir, 843; outputs=PPMAIN_FLOFS_OUTPUTS,
                         declared=vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW, PPMAIN_FLO_DECLARED_NEW, PPMAIN_FLOFS_DECLARED_NEW), kw...)
end

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_flofs_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_FLOFS_CASES
        tm = ppmain_flofs_start(fixtures, name)
        work = mktempdir()
        ppmain_flofs_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-843 on test/unit/ppmain_flofs_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
