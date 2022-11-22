using Test
using HTTP
using Webviews

@testset "Webviews.jl" begin
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
    bind(webview, "run_test") do
        step += 1
        if step == 1
            html!(webview, html)
        elseif step == 2
            eval!(webview, "run_test()")
        elseif step == 3
            # `terminate` does not work on macOS.
            Webviews.WEBVIEW_PLATFORM ≡ Webviews.WEBVIEW_COCOA && return exit(0)
            terminate(webview)
        end
        nothing
    end
    init!(webview, "run_test().catch(console.error)")
    navigate!(webview, "data:text/html,$(HTTP.escapeuri(html))")
    run(webview)
end
