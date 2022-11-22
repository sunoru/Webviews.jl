using Test
using HTTP
using Webviews

@testset "Webviews.jl" begin
    is_cocoa = Webviews.WEBVIEW_PLATFORM ≡ Webviews.WEBVIEW_COCOA

    server = HTTP.serve!(8080) do _
        HTTP.Response("<html><body><h1>Hello</h1></body></html>")
    end

    webview = Webview(;
        title="Test",
        debug=true,
        size_hint=WEBVIEW_HINT_MAX
    )
    resize!(webview, (320, 240))
    @test webview.size == (320, 240)
    sizehint!(webview, WEBVIEW_HINT_MAX)
    @test webview.size_hint == WEBVIEW_HINT_MAX
    @test window_handle(webview) != C_NULL
    html = """<html><body><h1>Hello from Julia v$VERSION</h1></body></html>"""
    step = 0
    bind(webview, "run_test") do _
        step += 1
        if step == 1
            html!(webview, html)
        elseif step == 2
            navigate!(webview, "http://localhost:8080")
        elseif step == 3
            eval!(webview, "end_test(document.body.innerHTML)")
        end
        nothing
    end
    bind(webview, "end_test") do (x,)
        @test x == "<h1>Hello</h1>"
        # `terminate` does not work on macOS.
        close(server)
        is_cocoa && return exit(0)
        terminate(webview)
    end
    init!(webview, "run_test().catch(console.error)")
    navigate!(webview, "data:text/html,$(HTTP.escapeuri(html))")
    run(webview)
end
