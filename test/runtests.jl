using Test
using HTTP
using Webviews

@testset "Webviews.jl" begin
    # TODO: We have skipped some tests for #5
    is_cocoa = Webviews.WEBVIEW_PLATFORM ≡ Webviews.WEBVIEW_COCOA

    server = is_cocoa ? nothing : HTTP.serve!(8080) do _
        HTTP.Response("<h1>Hello</h1>")
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
        elseif step == 3 || is_cocoa
            eval!(webview, "end_test(document.body.innerHTML)")
        elseif step == 2
            navigate!(webview, "http://localhost:8080")
        end
        nothing
    end
    bind(webview, "end_test") do (x,)
        @test x == "<h1>Hello</h1>"
        # `terminate` does not work on macOS.
        is_cocoa && return exit(0)
        close(server)
        terminate(webview)
    end
    init!(webview, "run_test().catch(console.error)")
    navigate!(webview, "data:text/html,$(HTTP.escapeuri(html))")
    run(webview)
end
