# Run init_ext.vda (TIMES v4.9.7, with equcrtp.vda INIT_EXT) itself with GAMS
# on the crafted states of test/unit/init_ext_case.jl, one fixture per case,
# so the unit test checks init_ext! on the paths no core reference run takes
# (peaking and storage flags, partial loads, the FLO_COST clean-up, VDA_CEH,
# FLO_EFF, IRE_FLOSUM, COM_AGG, SHELL ANSWER, WAVER, updatable OFF-ranges,
# UC_ACTBET).
#
#   julia --project=test scripts/make_init_ext_unit.jl <TIMES_model dir> [<gams executable>]
#
# Uses scripts/gams_replay.jl; no SOLVE, so the PyPI demo GAMS will do (on
# Windows set TJL_PYTHON to the harness venv's python.exe).
# Writes test/fixtures/initext_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "init_ext_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "initext_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in sort(collect(keys(INIT_EXT_CASES)))
        tm = init_ext_start(fixtures, name)
        work = mktempdir()
        glob = merge(tm.switches, Dict("DFLBL" => "'0'", "EOTIME" => "2200", "OBMAC" => "YES", "PGPRIM" => "\"'ACT'\""))
        gams_replay(tm, ["init_ext.vda" => "mod"], INIT_EXT_OUTPUTS; times_dir, also_scan=["equcrtp.vda"],
                    skip=INIT_EXT_DECLARED, setglobals=glob, workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<init_ext.vda on test/unit/init_ext_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
