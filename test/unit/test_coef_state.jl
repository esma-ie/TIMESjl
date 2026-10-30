# M1.2 infrastructure (src/coef/state.jl): GAMS assignment semantics.
# The gput! and layer-1 tests ran on DemoS dumps and were removed
# on 27 Oct 2026 with the DemoS models (docs/test-models.md); layer 1 of the
# coefficient files now runs in test_public_parity.jl on openly licensed
# fixtures.

using TIMES: GNum, GEPS, gassign!

@testset "gassign!: GAMS stores no zero, keeps EPS" begin
    d = Dict{NTuple{2,String},Float64}(("a", "b") => 3.0)
    gassign!(d, ("a", "b"), GNum(0.0))
    @test !haskey(d, ("a", "b"))                       # an exact zero removes the entry
    gassign!(d, ("a", "c"), GEPS)
    @test d[("a", "c")] === 0.0                         # EPS is an entry with value 0.0
    gassign!(d, ("a", "d"), 1.5)
    @test d[("a", "d")] == 1.5
end
