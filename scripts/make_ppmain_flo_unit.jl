# Run ppmain.mod L616-821 (TIMES v4.9.7: changes 9 and 10, then the flow
# attributes levelled by pp_lvlfc.mod, the FLO_PKCOI default and pp_chp.mod)
# itself with GAMS on the crafted states of test/unit/ppmain_flo_case.jl,
# one fixture per case, so the unit test checks pp_qafs!, ppmain_dflt!,
# ppmain_tsattr! and ppmain_flo! on the paths no core reference run takes.
#
#   julia --project=test scripts/make_ppmain_flo_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint, so only ppmain.mod
# L616-821 runs (scripts/ppmain_replay.jl: the lines unchanged, the control
# variables set as TIMES sets them). Writes
# test/fixtures/ppmain_flo_unit_gams/<case>/. scripts/m13_replay.jl runs the
# same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "ppmain_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_dflt_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_tsattr_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_flo_case.jl"))

"What ppmain.mod L616-821 writes (compared at L821, scratch included)."
const PPMAIN_FLO_OUTPUTS = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW))

"""
    ppmain_flo_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-821 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_FLO_OUTPUTS at L821
(scripts/ppmain_replay.jl).
"""
function ppmain_flo_replay(tm, times_dir; kw...)
    occursin("pp_chp", readlines(joinpath(times_dir, "ppmain.mod"))[821]) ||
        error("ppmain.mod L821 is not the pp_chp call: is this TIMES v4.9.7?")
    return ppmain_replay(tm, times_dir, 821; outputs=PPMAIN_FLO_OUTPUTS,
                         declared=vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW, PPMAIN_FLO_DECLARED_NEW), kw...)
end

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_flo_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_FLO_CASES
        tm = ppmain_flo_start(fixtures, name)
        work = mktempdir()
        ppmain_flo_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-821 on test/unit/ppmain_flo_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
