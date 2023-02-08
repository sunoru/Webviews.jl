using Test
using HTTP
using Webviews

@testset "Basic tests" begin
    server = HTTP.serve!(8080) do _
        HTTP.Response("<html><body><h1>Hello</h1></body></html>")
    end

    w = Webview(;
        title="Test",
        debug=true,
        enable_webio=false,
    )
    window = window_handle(w)
    @test window != C_NULL
    @test string(w) == "Webview (0 bindings): pending"
    resize!(w, (320, 240))
    html = """<html><body><h1>Hello from Julia v$VERSION</h1></body></html>"""
    step = 0
    bind(w, "run_test") do _
        step += 1
        if step == 1
            @test string(w) == "Webview (2 bindings): running"
            @test size(w) == (320, 240)
            resize!(w, (240, 240))
            resize!(w, (500, 500); hint=WEBVIEW_HINT_MAX)
            timer = set_timeout(w, 0.5, repeat=true) do
                @test true
                clear_timeout(w, timer)
                html!(w, html)
            end
            @test timer ≢ C_NULL
        elseif step == 2
            @test size(w) == (240, 240)
            dispatch(w) do
                @test true
            end
            navigate!(w, "http://localhost:8080")
        elseif step == 3
            eval!(w, "end_test(document.body.innerHTML)")
        end
        nothing
    end
    bind(w, "end_test") do (x,)
        @test x == "<h1>Hello</h1>"
        close(server)
        terminate(w)
        close(w)
    end
    init!(w, "run_test().catch(console.error)")
    navigate!(w, "data:text/html,$(HTTP.escapeuri(html))")
    run(w)
    @test string(w) == "Webview (0 bindings): destroyed"
    @test Test.get_testset().n_passed == 10
end
