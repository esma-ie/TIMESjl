# The M1.3 replay check: GAMS runs TIMES lines itself from a reference
# run's checkpoint state, and TIMES.jl runs its translation of them on the
# same state; every symbol the lines write is compared where they end, at
# 1e-9. It checks, on the core models' own data, symbols that the probe
# (scripts/m13_probe.jl) can only compare at the next checkpoint once the
# lines after them are translated too.
#
#   julia --project=test scripts/m13_replay.jl <reference dir> [--root name=dir ...] <model> ...
#
# Needs the TIMES_model clone (--root times_source=...), GAMS (TJL_GAMS, or
# the PyPI demo GAMS: no SOLVE, so any licence will do) and TJL_PYTHON on
# Windows (the harness venv's python.exe). Both variants are run. The work
# files go to a temporary folder; nothing is written to the reference.
#
# Replays: ppmain.mod L616-682 (change 9: pp_qafs.mod, SHAPE/MULTI, the
# defaults, the capacity-only flows) from the prelv checkpoint.

include(joinpath(@__DIR__, "m11_probe.jl"))      # run_switches, runfile_of, suite_switches, parse_probe_args
include(joinpath(@__DIR__, "make_ppmain_dflt_unit.jl"))
using TIMES: TimesModel, layer1, pp_qafs!, ppmain_dflt!
using TIMES.Reference: ispass
using JSON

function replay13(refdir, model; roots, variant)
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) && isdir(joinpath(dir, "prelv")) || return println("== ", model, "/", variant, ": no prelv dump")
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    times_dir = roots["times_source"]
    tm = TimesModel(joinpath(dir, "prelv"); switches=sw)
    kw = haskey(ENV, "TJL_GAMS") ? (; gams=ENV["TJL_GAMS"]) : (;)
    work = mktempdir()
    tg = @elapsed g = ppmain_dflt_replay(tm, times_dir; workdir=work, kw...)
    tj = @elapsed (pp_qafs!(tm); ppmain_dflt!(tm))
    r = layer1(tm, g, PPMAIN_DFLT_OUTPUTS)
    bad = filter(!ispass, r)
    println("== ", model, "/", variant, " ppmain.mod L616-682 replayed: ", isempty(bad) ? "PASS" : "FAIL", " (", length(r),
            " symbols, ", sum(d -> d.n_ref, r; init=0), " GAMS records; GAMS ", round(tg; digits=1), " s, TIMES.jl ",
            round(tj; digits=1), " s)")
    for d in bad
        println("     ", d)
        foreach(e -> println("        ", e), d.examples)
    end
    # which checks fired, from GAMS's QA log: pp_qaput.mod writes a ' *** <check>' header, then one line per record
    qa = joinpath(work, "QA_CHECK.LOG")
    isfile(qa) || return
    counts, cur = Dict{String,Int}(), nothing
    for l in eachline(qa)
        m = match(r"^ \*\*\* ([^*].*?)\s*$", l)                     # not the banner (L9-11)
        if m !== nothing
            cur = m.captures[1]
            get!(counts, cur, 0)
        elseif cur !== nothing && occursin(r"(SEVERE ERROR|WARNING|ERROR)\s+-", l)
            counts[cur] += 1
        end
    end
    foreach(((h, n),) -> println("     QA: ", h, ": ", n), sort(collect(counts)))
    n = count("(Auto-relaxed)", read(qa, String))
    n > 0 && println("     QA: auto-relaxed: ", n)
end

if abspath(PROGRAM_FILE) == @__FILE__
    refdir, roots, models = parse_probe_args(ARGS)
    for model in models, variant in ("reduce_off", "as_run")
        replay13(refdir, model; roots, variant)
    end
end
