# Run ppmain.mod L1-247, preppm.mod L1-212 and prep_ext.vda (TIMES v4.9.7)
# themselves with GAMS on the crafted states of test/unit/prep_ext_case.jl,
# one fixture per case, so the unit test checks prep_ext! on the paths no
# core reference run takes (PRC_RESID options, NCAP_AFAC/NCAP_AFCS, ACT_FLO,
# the unit-commitment parameters, COM_LIM 'FX', FLO_ASHAR, cost-neutral
# ILEDs, dynamic process bounds).
#
#   julia --project=test scripts/make_prep_ext_unit.jl <TIMES_model dir> [<gams executable>]
#
# The lines are copied unchanged from <TIMES_model dir>/ppmain.mod (L1-247)
# and preppm.mod (L1-212) into one work file, followed by
# `$BATINCLUDE prep_ext.vda mod` as main_ext.mod includes it for the VDA
# extension at preppm.mod L215 (prep_ext.dsc exits: %DSC% is not YES), and
# $BATINCLUDEd with `mod` (scripts/gams_replay.jl). %DATAGDX% is NO and
# %RETIRE% YES as in make_preppm_unit.jl. No SOLVE, so the PyPI demo GAMS will
# do (on Windows set TJL_PYTHON to the harness venv's python.exe). Writes
# test/fixtures/prep_ext_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_head_case.jl"))     # PPMAIN_HEAD_DECLARED
include(joinpath(REPO, "test", "unit", "timslice_case.jl"))        # TIMSLICE_DECLARED
include(joinpath(REPO, "test", "unit", "preppm_case.jl"))          # PREPPM_BARE, PREPPM_OUTPUTS
include(joinpath(REPO, "test", "unit", "prep_ext_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "prep_ext_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    pre = readlines(joinpath(times_dir, "preppm.mod"))[1:212]
    vda = readlines(joinpath(times_dir, "prep_ext.vda"))
    # what preppm.mod declares itself: L47-48 and the write caches of fillparm/prepparm (prep_ext.vda's too)
    declared = union(["OBJ_VFLO", "RPC_CUR", "RP_RTF"], [m.match for l in vcat(pre, vda) for m in eachmatch(r"\bX_[A-Z]+\b", l)])
    for name in PREP_EXT_CASES
        tm = prep_ext_start(fixtures, name)
        work = mktempdir()
        head = joinpath(work, "prep_ext_head.mod")                   # ppmain.mod L1-247, preppm.mod L1-212, unchanged; then prep_ext.vda
        write(head, join(vcat(first(readlines(joinpath(times_dir, "ppmain.mod")), 247), pre, ["\$BATINCLUDE prep_ext.vda mod"]), "\n") * "\n")
        # %OBMAC% is YES on any GAMS from 23.0 (initmty.mod L21); %RL% as setglobs.gms L317 sets it without G2X6 (L230)
        glob = merge(tm.switches, Dict("DFLBL" => "'0'", "PGPRIM" => "\"'ACT'\"", "DATAGDX" => "NO", "G2X6" => "NO", "OBMAC" => "YES",
                                       "RL" => "'R.TL:MAX(12,CARD(R.TL))'", "RETIRE" => "'YES'"))
        gams_replay(tm, [head => "mod"], PREP_EXT_OUTPUTS; times_dir,
                    also_scan=["filparam.gms", "timslice.mod", "pp_off.mod", "pp_qaput.mod", "prepret.dsc", "fillvint.gms", "prepparm.gms",
                               "fillparm.gms", "prep_ext.vda", "equcrtp.vda"],
                    skip=union(PPMAIN_HEAD_DECLARED, ["MINYR"], TIMSLICE_DECLARED, declared), setglobals=glob, workdir=work, onmulti=true,
                    bare=Set(PREP_EXT_BARE), kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L1-247, preppm.mod L1-212, prep_ext.vda on test/unit/prep_ext_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
