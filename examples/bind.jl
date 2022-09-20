using Webviews

html = """
  <html>
  <body>
    <h1>Hello from Julia v$VERSION</h1>
    <button onclick="press('I was pressed!', 123, new Date()).then(log);">
      Press me!
    </button>
    <button onclick="terminate()">
      Close
    </button>
  </body>
  </html>
"""

webview = Webview(540, 360)

html!(webview, html)

counter = 0
bind!(webview, "press") do a, b, c
    @show a, b, c
    Dict("times" => (global counter += 1))
end
bind!(println, webview, "log")
bind!(webview, "terminate") do
    terminate(webview)
end

run(webview)