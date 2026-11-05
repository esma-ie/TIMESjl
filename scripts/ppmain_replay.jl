# GAMS's own ppmain.mod L616-<last> (TIMES v4.9.7) on a prelv state held by
# a TimesModel (a reference run's prelv checkpoint, or a crafted state), for
# the replay checks of the prelv -> ppm segment (scripts/m13_replay.jl and
# the scripts/make_ppmain_*_unit.jl fixtures).
#
# The lines are copied unchanged after ppmain.mod L13 (FILE QLOG, which
# pp_qaput.mod writes to) and timslice.mod L39 (the RTS(S) macro, with %RTS%
# S as timslice.mod L31 sets it and %OBMAC% YES as initmty.mod L21 sets it on
# GAMS 23 and later), and $BATINCLUDEd with `mod` (scripts/gams_replay.jl);
# %MX% empty (maindrv.mod L30 outside the stochastic extension), %DFLBL% '0'
# as initmty.mod L367 sets it, %RL%, %PL% and %CL% as setglobs.gms L317 sets
# them without G2X6 (L230), the other control variables from the model's
# switches. No SOLVE, so the PyPI demo GAMS will do (on Windows set
# TJL_PYTHON to the harness venv's python.exe).

include(joinpath(@__DIR__, "gams_replay.jl"))

"The files ppmain.mod L616-<last> includes, by the last line that needs them."
const PPMAIN_REPLAY_SCAN = [682 => ["pp_qafs.mod", "pp_qaput.mod", "filshape.gms", "filparam.gms"],
                            797 => ["pp_lvlfc.mod", "pp_lvlbr.mod", "pp_lvlpk.mod"],
                            821 => ["pp_chp.mod"],
                            843 => ["pp_lvlff.mod", "pp_lvlfs.mod", "eqflomrk.mod"]]

"""
    ppmain_replay(tm, times_dir, last; outputs, declared, workdir, kw...) -> DumpData

GAMS's own ppmain.mod L616-`last` on the state `tm`: the symbols `outputs`
at line `last`. `declared` lists the symbols those lines and the files they
include declare themselves (left out of the state written for GAMS).
"""
function ppmain_replay(tm, times_dir, last; outputs, declared, workdir=mktempdir(), kw...)
    ppm = readlines(joinpath(times_dir, "ppmain.mod"))
    tsl = readlines(joinpath(times_dir, "timslice.mod"))
    startswith(strip(ppm[13]), "FILE QLOG") || error("ppmain.mod L13 is not FILE QLOG: is this TIMES v4.9.7?")
    occursin("MACRO RTS(S)", tsl[39]) || error("timslice.mod L39 is not the RTS macro: is this TIMES v4.9.7?")
    main_ = joinpath(workdir, "ppm_replay.mod")
    write(main_, join(vcat(tsl[39:39], ppm[13:13], ppm[616:last]), "\n") * "\n")
    glob = merge(tm.switches, Dict("DFLBL" => "'0'", "RL" => "'R.TL:MAX(12,CARD(R.TL))'", "PL" => "'P.TL:MAX(12,CARD(P.TL))'",
                                   "CL" => "C.TL:MAX(12,CARD(C.TL))", "MX" => "", "RTS" => "S", "OBMAC" => "YES"))
    scan = reduce(vcat, (fs for (l, fs) in PPMAIN_REPLAY_SCAN if l <= last); init=String[])
    return gams_replay(tm, [main_ => "mod"], outputs; times_dir, also_scan=scan, skip=Set(declared), setglobals=glob, workdir, kw...)
end
