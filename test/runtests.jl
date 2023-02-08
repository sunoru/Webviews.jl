using Test
using Webviews

@testset "Webviews.jl" begin
    include("./basics.jl")

    for testfile in ("webio.jl",)
        @test success(
            `$(Base.julia_cmd()) $(joinpath(@__DIR__, testfile))`
        )
    end
end
