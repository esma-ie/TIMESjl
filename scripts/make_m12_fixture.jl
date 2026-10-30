# Copy one reference run into test/fixtures as an M1.2 (coefficients) fixture:
#
#   <prefix>_ppm/    the dump after preprocessing (maindrv.mod L58): the input
#   <prefix>_coef/   the dump after the coefficients (L73): the reference
#
# Usage, from the repository root:
#   julia --project=test scripts/make_m12_fixture.jl <reference>/<model>/<variant> <prefix>
#
# Manifest source paths are rewritten to "<reference>/..." as in
# make_m11_fixture.jl.

function copy_dump(src, dst, refroot)
    isdir(dst) && rm(dst; recursive=true)
    cp(src, dst)
    mf = joinpath(dst, "manifest.json")
    write(mf, replace(read(mf, String), refroot => "<reference>"))
end

function main(run_dir, prefix)
    run_dir = abspath(run_dir)
    refroot = dirname(dirname(run_dir))
    fixtures = joinpath(@__DIR__, "..", "test", "fixtures")
    for d in ("ppm", "coef")
        copy_dump(joinpath(run_dir, d), joinpath(fixtures, prefix * "_" * d), refroot)
    end
    println("wrote ", prefix, "_ppm and ", prefix, "_coef")
end

main(ARGS...)
