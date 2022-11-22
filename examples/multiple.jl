using Webviews

webview1 = Webview()
navigate!(webview1, "https://julialang.org/")

webview2 = Webview()
navigate!(webview2, "https://google.com/")

run(webview1)
run(webview2)
