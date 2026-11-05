# M1.3 gate in CI (docs/m13-plan.md "Gate"): TIMES_Demo demo12 reduce_off from
# the input dump through the whole preprocessing chain, TIMES.jl's own state
# carried from one segment to the next (scripts/m13_gate.jl does the same on
# the core reference runs, both variants), compared with GAMS at every
# checkpoint on every set and parameter; then on through the coefficient
# stage (coefmain.mod and coef_ext.vda), compared with the coef dump on the
# fixture's coef_symbols. The model itself is checked from the pre-solve dump
# with REDUCE off and on (test_public_parity.jl: demo12_off, demo12_red).

using TIMES: TimesModel, DumpData, layer1, init_ext!, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!,
             preppm_shape!, ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!, pp_qafs!, ppmain_dflt!, ppmain_tsattr!,
             ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_ucmap!,
             ppmain_blend!, ppmain_reduce!, ppm_ext_actef!, ppm_ext!, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!,
             coef_shp!, coef_ext!
using TIMES.Reference: ispass
import TOML

"The preprocessing steps by segment: (start checkpoint, next checkpoint, steps), maindrv.mod L55-58 order."
const M13_CHAIN = [
    ("input", "init", (init_ext!,)),
    ("init", "prep", (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!)),
    ("prep", "prelv", (preppm_shape!, ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!)),
    ("prelv", "ppm", (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!,
                      ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!, ppmain_reduce!, ppm_ext_actef!, ppm_ext!)),
]

"Carry `tm`'s state (every symbol read or written, and the switches) into a TimesModel of `dir` (scripts/m13_gate.jl)."
function carry_state(tm, dir)
    nt = TimesModel(dir; switches=tm.switches)
    merge!(nt.switches, tm.switches)
    merge!(nt.data.sets, tm.data.sets)
    merge!(nt.data.params, tm.data.params)
    return nt
end

chain_symbols(d) = sort([i.name for i in values(d.dump.symbols) if i.kind in (:set, :parameter) && !(i.name in ("PUTOUT", "PUTGRP", "ERRLEV"))])

@testset "M1.3 chain: input dump -> ppm -> coefficients, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=fx["switches"])
    for (a, b, steps) in M13_CHAIN
        names = chain_symbols(tm.data)
        foreach(f -> f(tm), steps)
        ref = DumpData(joinpath(FIXTURES, "demo12_off_" * b))
        r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n), names))
        foreach(d -> ispass(d) || println("input -> ", b, ": ", d, " ", d.examples), r)
        @test length(r) > 800 && all(ispass, r)
        tm = carry_state(tm, joinpath(FIXTURES, "demo12_off_" * b))
    end
    # coefmain.mod order, then coef_ext.vda (test_public_parity.jl, check_layer1_coef)
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm); coef_ext!(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_coef")), fx["coef_symbols"])
    foreach(d -> ispass(d) || println("coefficients: ", d, " ", d.examples), r)
    @test all(ispass, r)
end
