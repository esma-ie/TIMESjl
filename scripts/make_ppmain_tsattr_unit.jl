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
# L616-797 runs, copied unchanged after ppmain.mod L13 (FILE QLOG, which
# pp_qaput.mod writes to) and timslice.mod L39 (the RTS(S) macro, with %RTS%
# S as timslice.mod L31 sets it and %OBMAC% YES as initmty.mod L21 sets it on
# GAMS 23 and later), and $BATINCLUDEd with `mod` (scripts/gams_replay.jl);
# %MX% empty (maindrv.mod L30 outside the stochastic extension), %DFLBL%
# '0' as initmty.mod L367 sets it, %RL%, %PL% and %CL% as setglobs.gms L317
# sets them without G2X6 (L230), the other control variables from the
# case's switches. No SOLVE, so the PyPI demo GAMS will do (on Windows set
# TJL_PYTHON to the harness venv's python.exe). Writes
# test/fixtures/ppmain_tsattr_unit_gams/<case>/. scripts/m13_replay.jl runs
# the same lines on the core models' prelv checkpoints.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_dflt_case.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_tsattr_case.jl"))

"What ppmain.mod L616-797 writes (compared at L797, scratch included)."
const PPMAIN_TSATTR_OUTPUTS = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW))

"""
    ppmain_tsattr_replay(tm, times_dir; workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-797 on the state `tm` (a prelv checkpoint,
possibly modified): the symbols of PPMAIN_TSATTR_OUTPUTS at L797.
"""
function ppmain_tsattr_replay(tm, times_dir; workdir=mktempdir(), kw...)
    ppm = readlines(joinpath(times_dir, "ppmain.mod"))
    tsl = readlines(joinpath(times_dir, "timslice.mod"))
    startswith(strip(ppm[13]), "FILE QLOG") || error("ppmain.mod L13 is not FILE QLOG: is this TIMES v4.9.7?")
    occursin("pp_lvlpk.mod", ppm[797]) || error("ppmain.mod L797 is not the pp_lvlpk.mod call: is this TIMES v4.9.7?")
    occursin("MACRO RTS(S)", tsl[39]) || error("timslice.mod L39 is not the RTS macro: is this TIMES v4.9.7?")
    main_ = joinpath(workdir, "ppm_tsattr.mod")                    # timslice.mod L39, ppmain.mod L13 and L616-797, unchanged
    write(main_, join(vcat(tsl[39:39], ppm[13:13], ppm[616:797]), "\n") * "\n")
    glob = merge(tm.switches, Dict("DFLBL" => "'0'", "RL" => "'R.TL:MAX(12,CARD(R.TL))'", "PL" => "'P.TL:MAX(12,CARD(P.TL))'",
                                   "CL" => "C.TL:MAX(12,CARD(C.TL))", "MX" => "", "RTS" => "S", "OBMAC" => "YES"))
    return gams_replay(tm, [main_ => "mod"], PPMAIN_TSATTR_OUTPUTS; times_dir,
                       also_scan=["pp_qafs.mod", "pp_qaput.mod", "filshape.gms", "filparam.gms", "pp_lvlfc.mod", "pp_lvlbr.mod",
                                  "pp_lvlpk.mod"],
                       skip=Set(vcat(PPMAIN_DFLT_DECLARED, PPMAIN_TSATTR_DECLARED_NEW)), setglobals=glob, workdir, kw...)
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
