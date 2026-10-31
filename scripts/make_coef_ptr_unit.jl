# Run coef_ptr.mod (TIMES v4.9.7) itself with GAMS on the crafted states of
# test/unit/coef_ptr_case.jl, one fixture per case, so the unit test checks
# coef_ptr! on the FLO_FUNC and FLO_SUM paths no public reference run takes
# (forward and reverse FLO_FUNC, both directions, EPS FLO_SUM, a FLO_SUM
# outside the model years, L51).
#
#   julia --project=test scripts/make_coef_ptr_unit.jl <TIMES_model dir> [<gams executable>]
#
# Uses scripts/gams_replay.jl; no SOLVE, so the PyPI demo GAMS will do.
# Writes test/fixtures/coefptr_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "coef_ptr_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    outroot = joinpath(REPO, "test", "fixtures", "coefptr_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in COEF_PTR_CASES
        tm = coef_ptr_start(joinpath(REPO, "test", "fixtures", "demo12_off_ppm"), name)
        work = mktempdir()
        gams_replay(tm, ["coef_ptr.mod" => ""], COEF_PTR_OUTPUTS; times_dir, skip=COEF_PTR_DECLARED, workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<coef_ptr.mod on test/unit/coef_ptr_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
