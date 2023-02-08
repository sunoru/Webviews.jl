using Test
using Webviews

@testset "Webviews.jl" begin
    include("./basics.jl")
    if WEBVIEW_PLATFORM ≡ WEBVIEW_COCOA
        @test success(
            `$(Base.julia_cmd()) $(joinpath(@__DIR__, "webio.jl"))`
        )
    else
        include("./webio.jl")
    end
end
