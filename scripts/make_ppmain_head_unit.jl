# Run ppmain.mod L1-137 (TIMES v4.9.7) itself with GAMS on the crafted states
# of test/unit/ppmain_head_case.jl, one fixture per case, so the unit test
# checks ppmain_head! on the paths no core reference run takes (storage
# defaults, guessed primary groups, the spread of past investments).
#
#   julia --project=test scripts/make_ppmain_head_unit.jl <TIMES_model dir> [<gams executable>]
#
# The lines are copied unchanged from <TIMES_model dir>/ppmain.mod into a
# work file and $BATINCLUDEd with `mod` (scripts/gams_replay.jl); no SOLVE,
# so the PyPI demo GAMS will do (on Windows set TJL_PYTHON to the harness
# venv's python.exe). Writes test/fixtures/ppmainhead_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_head_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmainhead_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_HEAD_CASES
        tm = ppmain_head_start(fixtures, name)
        work = mktempdir()
        head = joinpath(work, "ppmain_head.mod")                     # ppmain.mod L1-137, unchanged
        write(head, join(first(readlines(joinpath(times_dir, "ppmain.mod")), 137), "\n") * "\n")
        glob = merge(tm.switches, Dict("DFLBL" => "'0'", "PGPRIM" => "\"'ACT'\"", "DATAGDX" => "NO", "G2X6" => "NO"))
        gams_replay(tm, [head => "mod"], PPMAIN_HEAD_OUTPUTS; times_dir, skip=PPMAIN_HEAD_DECLARED, setglobals=glob,
                    workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L1-137 on test/unit/ppmain_head_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
