using Test
using HTTP
using Webviews

@testset "Multiple windows" begin
    # Create three windows
    webviews = [Webview() for _ in 1:3]
    for i in 1:3
        w = webviews[i]
        bind(w, "run_test") do _
            @info "Window $i received run_test"
            @test true
            close(w)
        end
        init!(w, "run_test().catch(console.error)")
        html!(w, """<html><body><h1>Window $i</h1></body></html>""")
    end
    run(webviews[1])
    @test Test.get_testset().n_passed == 3
end
