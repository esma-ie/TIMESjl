# M1.3 layer 1: the translated preprocessing steps on the checkpoint dumps of
# reference runs (harness 0.3.0; docs/m13-plan.md).
#
#   julia --project=test scripts/m13_probe.jl <reference dir> [--root name=path ...] [<model> ...]
#
# Each segment starts from GAMS's own state at its first checkpoint and is
# checked at the next one, so a segment can be translated and checked on its
# own (the whole chain is tested at the M1.3 gate):
#
#   input -> init   maindrv.mod L55 (init_ext.dsc, init_ext.vda)
#   init  -> prep   ppmain.mod L1-248, preppm.mod L1-217 (with prep_ext.vda)
#   prep  -> prelv  preppm.mod L218-253, ppmain.mod L249-615 (with pp_prelv.vda)
#   prelv -> ppm    ppmain.mod L616-1357, maindrv.mod L58 (ppm_ext.dsc, ppm_ext.vda)
#
# A step is compared on the symbols it settles that nothing later in its
# segment changes (`symbols`, plus `extra(tm)` for those that depend on the
# model's switches or data). A step that ends its segment is compared on
# every set and parameter of the dump (`all_symbols`), so a side effect on a
# symbol it should leave alone shows too. Both variants (reduce_off, as_run)
# are probed.

include(joinpath(@__DIR__, "m11_probe.jl"))      # run_switches, runfile_of, suite_switches, parse_probe_args
using TIMES: DumpData, layer1, init_ext!, ppmain_head!, ppmain_head_symbols, ppmain_years!, ppmain_years_symbols,
             timslice!, timslice_symbols, ppmain_rtp!, ppmain_rtp_symbols, preppm!, preppm_symbols,
             prep_ext!, prep_ext_symbols, preppm_shape!, preppm_shape_symbols, ppmain_topo!, ppmain_topo_symbols,
             ppmain_tslvl!, ppmain_tslvl_symbols, ppmain_life!, ppmain_life_symbols,
             pp_prelv!, pp_prelv_symbols, pp_qafs!, pp_qafs_symbols, ppmain_dflt!, ppmain_dflt_symbols,
             ppmain_tsattr!, ppmain_tsattr_symbols, ppmain_flo!, ppmain_flo_symbols
using TIMES.Reference: ispass

"The four segments: (first checkpoint, next checkpoint)."
const M13_SEGMENTS = [("input", "init"), ("init", "prep"), ("prep", "prelv"), ("prelv", "ppm")]

"Every set and parameter of the dump `tm` started from."
all_symbols(tm) = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])

"Translated steps in execution order: (segment start, name, function, symbols, symbols by model)."
const M13_STEPS = Tuple{String,String,Function,Vector{String},Function}[
    ("input", "init_ext", init_ext!, String[], all_symbols),          # maindrv.mod L55: the whole input -> init segment
    ("init", "ppmain_head", ppmain_head!, String[], ppmain_head_symbols),   # ppmain.mod L1-137
    ("init", "ppmain_years", ppmain_years!, String[], ppmain_years_symbols),   # ppmain.mod L138-191
    ("init", "timslice", timslice!, String[], timslice_symbols),       # ppmain.mod L196: timslice.mod with pp_off.mod
    ("init", "ppmain_rtp", ppmain_rtp!, String[], ppmain_rtp_symbols),   # ppmain.mod L199-247
    ("init", "preppm", preppm!, String[], preppm_symbols),            # ppmain.mod L248: preppm.mod L1-212
    ("init", "prep_ext", prep_ext!, String[], prep_ext_symbols),      # preppm.mod L213-217: the whole init -> prep segment
    ("prep", "preppm_shape", preppm_shape!, String[], preppm_shape_symbols),   # preppm.mod L218-252: preshape.gms
    ("prep", "ppmain_topo", ppmain_topo!, String[], ppmain_topo_symbols),     # ppmain.mod L249-328
    ("prep", "ppmain_tslvl", ppmain_tslvl!, String[], ppmain_tslvl_symbols),   # ppmain.mod L329-460
    ("prep", "ppmain_life", ppmain_life!, String[], ppmain_life_symbols),     # ppmain.mod L461-611
    ("prep", "pp_prelv", pp_prelv!, String[], pp_prelv_symbols),            # ppmain.mod L615: pp_prelv.vda, the whole prep -> prelv segment
    ("prelv", "pp_qafs", pp_qafs!, String[], pp_qafs_symbols),               # ppmain.mod L617: pp_qafs.mod
    ("prelv", "ppmain_dflt", ppmain_dflt!, String[], ppmain_dflt_symbols),   # ppmain.mod L619-682
    ("prelv", "ppmain_tsattr", ppmain_tsattr!, String[], ppmain_tsattr_symbols),   # ppmain.mod L683-797
    ("prelv", "ppmain_flo", ppmain_flo!, String[], ppmain_flo_symbols),   # ppmain.mod L800-821
]

function probe13(refdir, model; roots=Dict{String,String}(), variant="reduce_off", steps=M13_STEPS)
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) || return println("== ", model, ": no reference")
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    missing_cp = filter(c -> !isdir(joinpath(dir, c)), ["input", "init", "prep", "prelv", "ppm"])
    isempty(missing_cp) || return println("== ", model, ": no checkpoint dump ", join(missing_cp, ", "),
                                          " (make_reference.py --only presolve, harness 0.3.0)")
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    model = string(model, "/", variant)
    for (a, b) in M13_SEGMENTS
        seg = filter(s -> s[1] == a, steps)
        if isempty(seg)
            println("== ", model, " ", a, " -> ", b, ": nothing translated yet")
            continue
        end
        tm = TimesModel(joinpath(dir, a); switches=sw)
        ref = DumpData(joinpath(dir, b))
        for (_, name, f, syms, extra) in seg
            try
                t = @elapsed f(tm)
                r = layer1(tm, ref, vcat(syms, extra(tm)))
                bad = filter(!ispass, r)
                println("== ", model, " ", name, ": ", isempty(bad) ? "PASS" : "FAIL", " (", length(r), " symbols, ",
                        sum(d -> d.n_ref, r; init=0), " GAMS records at ", b, ", ", round(t; digits=2), " s)")
                for d in bad
                    println("     ", d)
                    foreach(e -> println("        ", e), d.examples)
                end
            catch e
                e isa TIMES.UnportedError || rethrow()
                println("== ", model, " ", name, ": not translated: ", sprint(showerror, e))
                break
            end
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    refdir, roots, models = parse_probe_args(ARGS)
    for model in models, variant in ("reduce_off", "as_run")
        probe13(refdir, model; roots, variant)
    end
end
