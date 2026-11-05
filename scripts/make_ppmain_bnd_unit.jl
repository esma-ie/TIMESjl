# Run ppmain.mod L616-1001 (TIMES v4.9.7: changes 9 to 12, then the
# commodity subsets and COM_LIM defaults, the trade conversions, the bounds
# aggregated by pp_lvlbd.mod and FLO_BND and ACT_BND from FLO_BDLVL) itself
# with GAMS on the crafted states of test/unit/ppmain_bnd_case.jl, one
# fixture per case, so the unit test checks the translated steps up to
# ppmain_bnd! on the paths no core reference run takes.
#
#   julia --project=test scripts/make_ppmain_bnd_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint, so only ppmain.mod
# L616-1001 runs (scripts/ppmain_replay.jl: the lines unchanged, the control
# variables set as TIMES sets them). Writes
# test/fixtures/ppmain_bnd_unit_gams/<case>/. scripts/m13_replay.jl runs the
# same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "ppmain_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_dflt_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_tsattr_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_flo_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_flofs_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_ire_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_bnd_case.jl"))

"What ppmain.mod L616-1001 writes (compared at L1001, scratch included)."
const PPMAIN_BND_OUTPUTS = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW))

"""
    ppmain_bnd_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-1001 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_BND_OUTPUTS at L1001
(scripts/ppmain_replay.jl).
"""
function ppmain_bnd_replay(tm, times_dir; kw...)
    occursin("FLO_BDLVL(RTP,%PGPRIM%,S,BD)*G_YRFR(R,S)*8760", readlines(joinpath(times_dir, "ppmain.mod"))[1001]) ||
        error("ppmain.mod L1001 is not the ACT_BND from FLO_BDLVL: is this TIMES v4.9.7?")
    return ppmain_replay(tm, times_dir, 1001; outputs=PPMAIN_BND_OUTPUTS,
                         declared=vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW, PPMAIN_FLO_DECLARED_NEW, PPMAIN_FLOFS_DECLARED_NEW, PPMAIN_IRE_DECLARED_NEW, PPMAIN_BND_DECLARED_NEW), kw...)
end

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_bnd_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_BND_CASES
        tm = ppmain_bnd_start(fixtures, name)
        work = mktempdir()
        ppmain_bnd_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-1001 on test/unit/ppmain_bnd_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
