using HTTP

using Webviews

server = HTTP.serve!(8080) do _
    HTTP.Response("<html><body><h1>Hello World</h1></body></html>")
end

webview = Webview()
navigate!(webview, "http://localhost:8080")
run(webview)
close(server)
