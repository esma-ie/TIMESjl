# Run ppmain.mod L1-196 (TIMES v4.9.7) itself with GAMS on the crafted states
# of test/unit/timslice_case.jl, one fixture per case, so the unit test checks
# timslice! on the paths no core reference run takes (TS_OFF, dynamic
# timeslices, unit commitment, normalisation, zero fractions, TS_CYCLE).
#
#   julia --project=test scripts/make_timslice_unit.jl <TIMES_model dir> [<gams executable>]
#
# The lines are copied unchanged from <TIMES_model dir>/ppmain.mod into a
# work file and $BATINCLUDEd with `mod` (scripts/gams_replay.jl); L196
# includes timslice.mod, which includes pp_off.mod and pp_qaput.mod, and L189
# filparam.gms, all from <TIMES_model dir>. No SOLVE, so the PyPI demo GAMS
# will do (on Windows set TJL_PYTHON to the harness venv's python.exe). Only
# what timslice.mod writes is unloaded. Writes test/fixtures/timslice_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_head_case.jl"))     # PPMAIN_HEAD_DECLARED
include(joinpath(REPO, "test", "unit", "timslice_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "timslice_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in TIMSLICE_CASES
        tm = timslice_start(fixtures, name)
        work = mktempdir()
        head = joinpath(work, "ppmain_timslice.mod")                  # ppmain.mod L1-196, unchanged
        write(head, join(first(readlines(joinpath(times_dir, "ppmain.mod")), 196), "\n") * "\n")
        # %OBMAC% is YES on any GAMS from 23.0 (initmty.mod L21)
        glob = merge(tm.switches, Dict("DFLBL" => "'0'", "PGPRIM" => "\"'ACT'\"", "DATAGDX" => "NO", "G2X6" => "NO", "OBMAC" => "YES"))
        gams_replay(tm, [head => "mod"], TIMSLICE_OUTPUTS; times_dir, also_scan=["filparam.gms", "timslice.mod", "pp_off.mod", "pp_qaput.mod"],
                    skip=union(PPMAIN_HEAD_DECLARED, ["MINYR"], TIMSLICE_DECLARED), setglobals=glob, workdir=work, onmulti=true, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L1-196 on test/unit/timslice_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
