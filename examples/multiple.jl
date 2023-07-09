using Webviews

webview1 = Webview()
navigate!(webview1, "https://julialang.org/")

webview2 = Webview()
navigate!(webview2, "https://google.com/")

# This will show both windows.
run(webview1)
