# Run coef_shp.mod (TIMES v4.9.7) itself with GAMS on the crafted states of
# test/unit/coef_shp_case.jl, one fixture per case, so the unit test checks
# coef_shp! on the shaping paths no reference run takes (FLO_FUNCX, NCAP_CPX,
# repeated investments, lead-time rounding).
#
#   julia --project=test scripts/make_coef_shp_unit.jl <TIMES_model dir> [<gams executable>]
#
# Uses scripts/gams_replay.jl; no SOLVE, so the PyPI demo GAMS will do.
# Writes test/fixtures/coefshp_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "coef_shp_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    outroot = joinpath(REPO, "test", "fixtures", "coefshp_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in COEF_SHP_CASES
        tm = coef_shp_start(joinpath(REPO, "test", "fixtures", "demo12_off_ppm"), name)
        work = mktempdir()
        gams_replay(tm, ["coef_shp.mod" => ""], COEF_SHP_OUTPUTS; times_dir, skip=COEF_SHP_DECLARED, workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        write(mf, replace(read(mf, String), joinpath(work, "out.gdx") => "<coef_shp.mod on test/unit/coef_shp_case.jl: $name>"))
        println("wrote ", out)
    end
end

main(ARGS...)
