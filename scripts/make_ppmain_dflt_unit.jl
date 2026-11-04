# Run ppmain.mod L616-682 (TIMES v4.9.7: pp_qafs.mod, SHAPE and MULTI with
# filshape.gms and filparam.gms, the defaults, the capacity-only flows)
# itself with GAMS on the crafted states of test/unit/ppmain_dflt_case.jl,
# one fixture per case, so the unit test checks pp_qafs! and ppmain_dflt! on
# the paths no core reference run takes.
#
#   julia --project=test scripts/make_ppmain_dflt_unit.jl <TIMES_model dir> [<gams executable>]
#
# The states start from the demo12 prelv checkpoint, so only ppmain.mod
# L616-682 runs, copied unchanged after ppmain.mod L13 (FILE QLOG, which
# pp_qaput.mod writes to) and $BATINCLUDEd with `mod`
# (scripts/gams_replay.jl); %DFLBL% '0' as initmty.mod L367 sets it, %RL%,
# %PL% and %CL% as setglobs.gms L317 sets them without G2X6 (L230), the
# other control variables from the case's switches. No SOLVE, so the PyPI demo GAMS will do (on Windows set
# TJL_PYTHON to the harness venv's python.exe). Writes
# test/fixtures/ppmain_dflt_unit_gams/<case>/. scripts/m13_replay.jl runs
# the same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_dflt_case.jl"))

"""
    ppmain_dflt_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-682 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_DFLT_OUTPUTS at L682.
"""
function ppmain_dflt_replay(tm, times_dir; workdir=mktempdir(), kw...)
    ppm = readlines(joinpath(times_dir, "ppmain.mod"))
    startswith(strip(ppm[13]), "FILE QLOG") || error("ppmain.mod L13 is not FILE QLOG: is this TIMES v4.9.7?")
    main_ = joinpath(workdir, "ppm_dflt.mod")                      # ppmain.mod L13 and L616-682, unchanged
    write(main_, join(vcat(ppm[13:13], ppm[616:682]), "\n") * "\n")
    # %DFLBL% as initmty.mod L367 sets it (filparam.gms L24 reads the option there)
    glob = merge(tm.switches, Dict("DFLBL" => "'0'", "RL" => "'R.TL:MAX(12,CARD(R.TL))'", "PL" => "'P.TL:MAX(12,CARD(P.TL))'",
                                   "CL" => "C.TL:MAX(12,CARD(C.TL))"))
    return gams_replay(tm, [main_ => "mod"], PPMAIN_DFLT_OUTPUTS; times_dir,
                       also_scan=["pp_qafs.mod", "pp_qaput.mod", "filshape.gms", "filparam.gms"],
                       skip=Set(PPMAIN_DFLT_DECLARED), setglobals=glob, workdir, kw...)
end

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_dflt_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_DFLT_CASES
        tm = ppmain_dflt_start(fixtures, name)
        work = mktempdir()
        ppmain_dflt_replay(tm, times_dir; workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L616-682 on test/unit/ppmain_dflt_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS...)
end
