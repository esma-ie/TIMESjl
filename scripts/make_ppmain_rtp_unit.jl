# Run ppmain.mod L1-247 (TIMES v4.9.7) itself with GAMS on the crafted states
# of test/unit/ppmain_rtp_case.jl, one fixture per case, so the unit test
# checks ppmain_rtp! on the paths no core reference run takes (past
# investments moved off the milestones, user PRC_NOFF ranges, NCAP_START out
# of the year range or not an integer, G_OFFTHD thresholds).
#
#   julia --project=test scripts/make_ppmain_rtp_unit.jl <TIMES_model dir> [<gams executable>]
#
# The lines are copied unchanged from <TIMES_model dir>/ppmain.mod into a
# work file and $BATINCLUDEd with `mod` (scripts/gams_replay.jl); L189
# includes filparam.gms, L196 timslice.mod (with pp_off.mod and pp_qaput.mod),
# L229 pp_qaput.mod and L237 pp_off.mod, all from <TIMES_model dir>. No SOLVE,
# so the PyPI demo GAMS will do (on Windows set TJL_PYTHON to the harness
# venv's python.exe). Only what L199-247 writes is unloaded. Writes
# test/fixtures/ppmain_rtp_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_head_case.jl"))     # PPMAIN_HEAD_DECLARED
include(joinpath(REPO, "test", "unit", "timslice_case.jl"))        # TIMSLICE_DECLARED
include(joinpath(REPO, "test", "unit", "ppmain_rtp_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "ppmain_rtp_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in PPMAIN_RTP_CASES
        tm = ppmain_rtp_start(fixtures, name)
        work = mktempdir()
        head = joinpath(work, "ppmain_rtp.mod")                       # ppmain.mod L1-247, unchanged
        write(head, join(first(readlines(joinpath(times_dir, "ppmain.mod")), 247), "\n") * "\n")
        # %OBMAC% is YES on any GAMS from 23.0 (initmty.mod L21); %RL% as setglobs.gms L317 sets it without G2X6 (L230)
        glob = merge(tm.switches, Dict("DFLBL" => "'0'", "PGPRIM" => "\"'ACT'\"", "DATAGDX" => "NO", "G2X6" => "NO", "OBMAC" => "YES",
                                       "RL" => "'R.TL:MAX(12,CARD(R.TL))'"))
        gams_replay(tm, [head => "mod"], PPMAIN_RTP_OUTPUTS; times_dir, also_scan=["filparam.gms", "timslice.mod", "pp_off.mod", "pp_qaput.mod"],
                    skip=union(PPMAIN_HEAD_DECLARED, ["MINYR"], TIMSLICE_DECLARED), setglobals=glob, workdir=work, onmulti=true, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L1-247 on test/unit/ppmain_rtp_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
