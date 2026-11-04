# Run ppmain.mod L616-797 (TIMES v4.9.7: change 9's pp_qafs.mod, SHAPE and
# MULTI, the defaults and the capacity-only flows; then the commodity
# attributes by timeslice (pp_lvlfc.mod), COM_FR, RS_FR and RTCS_FR, the
# elastic demand steps, the availability factors (pp_lvlbr.mod) and the
# peak contributions (pp_lvlpk.mod)) itself with GAMS on the crafted states
# of test/unit/ppmain_tsattr_case.jl, one fixture per case, so the unit test
# checks pp_qafs!, ppmain_dflt! and ppmain_tsattr! on the paths no core
# reference run takes.
#
#   julia --project=test scripts/make_ppmain_tsattr_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint, so only ppmain.mod
# L616-797 runs (scripts/ppmain_replay.jl: the lines unchanged, the control
# variables set as TIMES sets them). Writes
# test/fixtures/ppmain_tsattr_unit_gams/<case>/. scripts/m13_replay.jl runs
# the same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "ppmain_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_dflt_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_tsattr_case.jl"))

"What ppmain.mod L616-797 writes (compared at L797, scratch included)."
const PPMAIN_TSATTR_OUTPUTS = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW))

"""
    ppmain_tsattr_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-797 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_TSATTR_OUTPUTS at L797
(scripts/ppmain_replay.jl).
"""
function ppmain_tsattr_replay(tm, times_dir; kw...)
    occursin("pp_lvlpk.mod", readlines(joinpath(times_dir, "ppmain.mod"))[797]) ||
        error("ppmain.mod L797 is not the pp_lvlpk.mod call: is this TIMES v4.9.7?")
    return ppmain_replay(tm, times_dir, 797; outputs=PPMAIN_TSATTR_OUTPUTS,
                         declared=vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW), kw...)
end

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_tsattr_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_TSATTR_CASES
        tm = ppmain_tsattr_start(fixtures, name)
        work = mktempdir()
        ppmain_tsattr_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-797 on test/unit/ppmain_tsattr_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
