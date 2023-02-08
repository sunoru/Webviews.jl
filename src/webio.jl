using Sockets: Sockets
using WebIO: WebIO

struct WebIOWebviewComm{T<:API.AbstractWebview} <: WebIO.AbstractConnection
    webview::T
end

function Sockets.send(comm::WebIOWebviewComm, data)
    @show data
    @show s = JSON3.write(Dict(:type=>"webio", :data=>data))
    API.eval!(
        comm.webview,
        "window.external.webio_send($s)"
    )
    nothing
end
Base.isopen(comm::WebIOWebviewComm) = API.is_shown(comm.webview)

function webio_init!(w::API.AbstractWebview)
    webio_js = read(WebIO.bundlepath, String)
    init!(w, webio_js)
    comm = WebIOWebviewComm(w)
    bind(w, "_webio_send_callback") do (msg,)
        msg = Dict(string(k)=>v for (k, v) in msg)
        WebIO.dispatch(comm, msg)
    end
    js = raw"((function () {
        window.WebIO = new webio.default()
        window.WebIO.setSendCallback(window._webio_send_callback)
        window.external.webio_send = function (msg) {
            window.WebIO.dispatch(msg.data)
        }
    })())"
    init!(w, js)
end

API.init!(w::API.AbstractWebview, js::WebIO.JSString) = init!(w, js.s)
API.eval!(w::API.AbstractWebview, js::WebIO.JSString) = eval!(w, js.s)
