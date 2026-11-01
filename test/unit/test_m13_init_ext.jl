# M1.3 (1): the init segment, maindrv.mod L55 (v4.9.7): init_ext.dsc,
# init_ext.vda with equcrtp.vda INIT_EXT. Layer 1 on TIMES_Demo demo12
# reduce_off from the input checkpoint to the init checkpoint, on every set
# and parameter of the dump (scripts/m13_probe.jl does the same on the core
# reference runs).

using TIMES: TimesModel, DumpData, layer1, init_ext!, init_ext_unported, gset, gparam, gput!, UnportedError
using TIMES.Reference: ispass
import TOML

@testset "init_ext layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=fx["switches"])
    @test isempty(init_ext_unported(tm))
    init_ext!(tm)
    names = [i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)]
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_init")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) > 800 && all(ispass, r)
    # L57-59: the first milestone and the year before it
    @test gset(tm, "MIYR_1").keys == [("2005",)] && gparam(tm, "MIYR_BOH")[()] == 2004 && gset(tm, "PYR_S").keys == [("2004",)]
    # L92-93: a residual capacity puts PRC_RESID at '0' (EPS when there was none) and NCAP_PASTI at PYR_S
    @test all(k -> haskey(gparam(tm, "NCAP_PASTI"), (k[1], "2004", k[3])), [k for k in gparam(tm, "PRC_RESID").keys if k[2] == "0"])
    # init_ext.dsc (DSCAUTO YES loads it): no discrete data, so %DSC% becomes NO
    @test tm.switches["DSC"] == "NO"
end

@testset "init_ext refusals" begin
    mk(sw) = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=sw)
    @test occursin("L129", only(init_ext_unported(mk(Dict("CLI" => "YES")))))
    @test occursin("GDX_IREBND", only(init_ext_unported(mk(Dict("GDX_IREBND" => "prev")))))
    @test_throws UnportedError init_ext!(mk(Dict("STAGES" => "YES")))
    tm = mk(Dict("DSCAUTO" => "YES"))
    gput!(tm, "NCAP_DISC", Dict(("REG1", "2010", "ELCTNGAS01", "1") => 100.0))
    @test occursin("NCAP_DISC", only(init_ext_unported(tm)))
    @test isempty(init_ext_unported(mk(Dict{String,String}())))   # without DSC the extension is not loaded
end
