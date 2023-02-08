using Test
using WebIO
using Webviews

@testset "WebIO tests" begin

    w = Webview(;
        title="WebIO Test",
        debug=true
    )
    scope = Scope()
    obs = Observable(scope, "obs", false)
    on(obs) do x
        @test x
        terminate(w)
        close(w)
    end
    scope(dom"button#mybutton"(
        events=Dict(
            "click" => js"() => _webIOScope.setObservableValue('obs', true)"
        )
    ))
    onmount(scope, js"() => run_test()")
    bind(w, "run_test") do _
        @test true
        eval!(w, js"document.querySelector('#mybutton').click()")
        nothing
    end
    html!(w, scope)

    run(w)
    @test Test.get_testset().n_passed == 2
end
