# Copy the M1.3 checkpoint dumps of one reference run into test/fixtures, for
# CI (test/unit/test_m13_checkpoints.jl). Only for models with
# redistribute = "public" in reference/suite.toml.
#
#   julia --project=test scripts/make_m13_fixture.jl <reference>/<model>/<variant> <prefix>
#
# Writes test/fixtures/<prefix>_input, _init, _prep, _prelv (the ppm, coef,
# presolve and matrix fixtures come from make_m11_fixture.jl and
# make_m12_fixture.jl). The reference needs harness 0.3.0 checkpoints:
# make_reference.py --only presolve.

import TOML, JSON

const REPO = dirname(@__DIR__)
const CHECKPOINTS = ["input", "init", "prep", "prelv"]

function main(refrun, prefix)
    mf = JSON.parsefile(joinpath(refrun, "manifest.json"))
    model = mf["model"]
    suite = Dict(m["name"] => m for m in TOML.parsefile(joinpath(REPO, "reference", "suite.toml"))["model"])
    get(get(suite, model, Dict()), "redistribute", "?") == "public" ||
        error("$model is not redistribute = \"public\" in reference/suite.toml: no fixture")
    run = get(mf["runs"], "presolve", Dict())
    gams = get(run, "gams_version", "?")
    for c in CHECKPOINTS
        src = joinpath(refrun, c)
        isdir(src) || error("$src missing: make it with make_reference.py --only presolve (harness 0.3.0)")
        dst = joinpath(REPO, "test", "fixtures", "$(prefix)_$c")
        isdir(dst) && rm(dst; recursive=true)
        cp(src, dst)
        m = JSON.parsefile(joinpath(dst, "manifest.json"))
        m["source"] = "<$model $(mf["variant"]) pre-solve run, checkpoint $c; $(strip(first(split(gams, "  "))))>"
        write(joinpath(dst, "manifest.json"), JSON.json(m, 1))
        println("wrote ", dst)
    end
end

main(ARGS...)
