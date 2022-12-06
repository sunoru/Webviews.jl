using Test
using HTTP
using Webviews

@testset "Webviews.jl" begin
    server = HTTP.serve!(8080) do _
        HTTP.Response("<html><body><h1>Hello</h1></body></html>")
    end

    webview = Webview(;
        title="Test",
        debug=true
    )
    resize!(webview, (320, 240))
    @test size(webview) == (320, 240)
    resize!(webview, (500, 500); hint=WEBVIEW_HINT_MAX)
    @test size(webview) == (320, 240)
    @test window_handle(webview) != C_NULL
    html = """<html><body><h1>Hello from Julia v$VERSION</h1></body></html>"""
    step = 0
    bind(webview, "run_test") do _
        step += 1
        if step == 1
            html!(webview, html)
        elseif step == 2
            dispatch(webview, true) do w, _
                @test w == webview
            end
            navigate!(webview, "http://localhost:8080")
        elseif step == 3
            eval!(webview, "end_test(document.body.innerHTML)")
        end
        nothing
    end
    bind(webview, "end_test") do (x,)
        @test x == "<h1>Hello</h1>"
        close(server)
        terminate(webview)
        # On macOS, we need to send an event explicitly to let the event loop ends
        if WEBVIEW_PLATFORM == WEBVIEW_COCOA
            # # Wait for the window to show.
            # Webviews.PlatformImpl.sleep(1)
            resize!(webview, (200, 200))
        end
    end
    init!(webview, "run_test().catch(console.error)")
    navigate!(webview, "data:text/html,$(HTTP.escapeuri(html))")
    run(webview)
end
