using Test
using TIMES

const FIXTURES = joinpath(@__DIR__, "fixtures")

# Only openly licensed test models (CLAUDE.md "Test-model licences",
# docs/test-models.md). The per-family tests on the DemoS models were removed
# on 27 Oct 2026; whole-model parity now runs in test_public_parity.jl on the
# fixtures listed in test/fixtures/public_fixtures.toml.
@testset "TIMES.jl" begin
    @test TIMES.TIMES_GAMS_VERSION == v"4.9.7"
    @test TIMES.TIMES_GAMS_COMMIT == "d9a6a25"
    @testset "Reference: dump reader" begin
        include("unit/test_dump.jl")
    end
    @testset "Reference: layer 1 comparison" begin
        include("unit/test_compare.jl")
    end
    @testset "Reference: layer 2-3 canonical LP" begin
        include("unit/test_lp.jl")
    end
    @testset "Model: mod_vars (M1.1)" begin
        include("unit/test_mod_vars.jl")
    end
    @testset "Model: GAMS EPS arithmetic" begin
        include("unit/test_gnum.jl")
    end
    @testset "Model: run switches (OBJ, OBLONG, CTST)" begin
        include("unit/test_switches.jl")
    end
    @testset "Coefficients: GAMS assignment semantics (M1.2)" begin
        include("unit/test_coef_state.jl")
    end
    @testset "Parity on openly licensed models (layers 1-3)" begin
        include("unit/test_public_parity.jl")
    end
    @testset "Coefficients: coef_ptr.mod (M1.2)" begin
        include("unit/test_coef_ptr.jl")
    end
    @testset "Coefficients: coef_obj.mod (M1.2)" begin
        include("unit/test_coef_obj.jl")
    end
    @testset "Coefficients: coef_alt.lin (M1.2)" begin
        include("unit/test_coef_alt.jl")
    end
    @testset "Coefficients: coef_shp.mod (M1.2)" begin
        include("unit/test_coef_shp.jl")
    end
    @testset "Coefficients: coef_ext.vda (M1.2)" begin
        include("unit/test_coef_ext.jl")
    end
    @testset "Preprocessing: checkpoint fixtures (M1.3)" begin
        include("unit/test_m13_checkpoints.jl")
    end
    @testset "Preprocessing: init_ext (M1.3)" begin
        include("unit/test_m13_init_ext.jl")
    end
    @testset "Preprocessing: ppmain.mod L1-137 (M1.3)" begin
        include("unit/test_m13_ppmain_head.jl")
    end
    @testset "Preprocessing: ppmain.mod L138-191 (M1.3)" begin
        include("unit/test_m13_ppmain_years.jl")
    end
end
