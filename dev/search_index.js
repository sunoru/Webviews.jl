var documenterSearchIndex = {"docs":
[{"location":"lib/#Library","page":"Library","title":"Library","text":"","category":"section"},{"location":"lib/#Index","page":"Library","title":"Index","text":"","category":"section"},{"location":"lib/","page":"Library","title":"Library","text":"Pages = [\"lib.md\"]","category":"page"},{"location":"lib/#Public-Interface","page":"Library","title":"Public Interface","text":"","category":"section"},{"location":"lib/","page":"Library","title":"Library","text":"Webviews\r\nWebview\r\nWindowSizeHint\r\nrun(::Webview)\r\nterminate\r\nBase.close(::Webview)\r\ndestroy\r\ndispatch\r\nwindow_handle\r\ntitle!\r\nresize!(::Webview, ::Tuple{Integer, Integer}; hint::WindowSizeHint)\r\nnavigate!\r\nhtml!\r\ninit!\r\neval!\r\nbind_raw\r\nbind(::Function, ::Webview, ::AbstractString)\r\nunbind\r\nreturn_raw\r\nset_timeout\r\nclear_timeout","category":"page"},{"location":"lib/#Webviews","page":"Library","title":"Webviews","text":"Webviews\n\nJulia wrappers for webview, a tiny cross-platform webview library.\n\n\n\n\n\n","category":"module"},{"location":"lib/#Webviews.Webview","page":"Library","title":"Webviews.Webview","text":"Webview(\n    size=(1024, 768);\n    title=\"\",\n    debug=false,\n    size_fixed=false,\n    unsafe_window_handle=C_NULL,\n    enable_webio=true,\n    auto_terminate=true\n)\nWebview(width, height; kwargs...)\n\nCreate a new webview instance with size and title.\n\nIf debug is true, developer tools will be enabled (if the platform supports them).\nUNSAFE unsafe_window_handle can be an unsafe pointer to the platforms specific native window handle.\n\nIf it's non-null - then child WebView is embedded into the given parent window. Otherwise a new window is created. Depending on the platform, a GtkWindow, NSWindow or HWND pointer can be passed here.\n\nIf enable_webio is true, then WebIO will be enabled.\nThe process will be terminated when all webviews with auto_terminate=true are destroyed.\n\n\n\n\n\n","category":"type"},{"location":"lib/#Webviews.Consts.WindowSizeHint","page":"Library","title":"Webviews.Consts.WindowSizeHint","text":"WindowSizeHint\n\nEnum to specify the window size hint. Values:\n\nWEBVIEW_HINT_NONE: Width and height are default size.\nWEBVIEW_HINT_MIN: Width and height are minimum bounds.\nWEBVIEW_HINT_MAX: Width and height are maximum bounds.\nWEBVIEW_HINT_FIXED: Window size can not be changed by a user.\n\n\n\n\n\n","category":"type"},{"location":"lib/#Base.run-Tuple{Webview}","page":"Library","title":"Base.run","text":"run(w::Webview)\n\nRuns the webview event loop. Runs the main event loop until it's terminated. After this function exits, the webview is automatically destroyed.\n\nNote: This function will show all webview windows that were created.\n\n\n\n\n\n","category":"method"},{"location":"lib/#Webviews.API.terminate","page":"Library","title":"Webviews.API.terminate","text":"terminate()\n\nStops the main loop. It is safe to call this function from another other background thread.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Base.close-Tuple{Webview}","page":"Library","title":"Base.close","text":"close(w::Webview)\n\nCloses the webview window.\n\n\n\n\n\n","category":"method"},{"location":"lib/#Webviews.API.destroy","page":"Library","title":"Webviews.API.destroy","text":"destroy(w::Webview)\n\nDestroys the webview and closes the window along with freeing all internal resources.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.dispatch","page":"Library","title":"Webviews.API.dispatch","text":"dispatch(f::Function, w::Webview)\n\nPosts a function to be executed on the main thread. You normally do not need to call this function, unless you want to tweak the native window.\n\nThe function f should be callable without arguments.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.window_handle","page":"Library","title":"Webviews.API.window_handle","text":"window_handle(w::Webview)\n\nUNSAFE An unsafe pointer to the webviews platform specific native window handle. When using GTK backend the pointer is GtkWindow pointer, when using Cocoa backend the pointer is NSWindow pointer, when using Win32 backend the pointer is HWND pointer.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.title!","page":"Library","title":"Webviews.API.title!","text":"title!(w::Webview, title::AbstractString)\n\nSets the native window title.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Base.resize!-Tuple{Webview, Tuple{Integer, Integer}}","page":"Library","title":"Base.resize!","text":"resize!(w::Webview, [size::Tuple{Integer, Integer}]; [hint::WindowSizeHint])\n\nSets the native window size.\n\n\n\n\n\n","category":"method"},{"location":"lib/#Webviews.API.navigate!","page":"Library","title":"Webviews.API.navigate!","text":"navigate!(w::Webview, url::AbstractString)\n\nNavigates webview to the given URL. URL may be a data URI, i.e. \"data:text/html,<html>...</html>\".\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.html!","page":"Library","title":"Webviews.API.html!","text":"html!(w::Webview, html::AbstractString)\nhtml!(w::Webview, body)\n\nSet webview HTML directly. If body is not a string, such as a WebIO.Node, it will be converted to HTML first.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.init!","page":"Library","title":"Webviews.API.init!","text":"init(w::Webview, js::AbstractString)\n\nInjects JavaScript code at the initialization of the new page. Every time the webview will open a the new page - this initialization code will be executed. It is guaranteed that code is executed before window.onload.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.eval!","page":"Library","title":"Webviews.API.eval!","text":"eval!(w::Webview, js::AbstractString)\n\nEvaluates arbitrary JavaScript code. Evaluation happens asynchronously, also the result of the expression is ignored. Use bind if you want to receive notifications about the results of the evaluation.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.bind_raw","page":"Library","title":"Webviews.API.bind_raw","text":"bind_raw(f::Function, w::Webview, name::AbstractString)\n\nBinds a callback so that it will appear in the webview with the given name as a global async JavaScript function. Callback receives a seq and req value. The seq parameter is an identifier for using Webviews.return_raw to return a value while the req parameter is a string of an JSON array representing the arguments passed from the JavaScript function call.\n\nThe callback function must has the method f(seq::String, req::String).\n\n\n\n\n\n","category":"function"},{"location":"lib/#Base.bind-Tuple{Function, Webview, AbstractString}","page":"Library","title":"Base.bind","text":"bind(f::Function, w::Webview, name::AbstractString)\n\nBinds a callback so that it will appear in the webview with the given name as a global async JavaScript function. Callback arguments are automatically converted from json to as closely as possible match the arguments in the webview context and the callback automatically converts and returns the return value to the webview.\n\nThe callback function must handle a Tuple as its argument.\n\n\n\n\n\n","category":"method"},{"location":"lib/#Webviews.API.unbind","page":"Library","title":"Webviews.API.unbind","text":"unbind(w::Webview, name::AbstractString)\n\nUnbinds a previously bound function freeing its resource and removing it from the webview JavaScript context.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.return_raw","page":"Library","title":"Webviews.API.return_raw","text":"return_raw(w::Webview, seq::String, success::Bool, result_or_err)\n\nAllows to return a value from the native binding. Original request pointer must be provided to help internal RPC engine match requests with responses.\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.set_timeout","page":"Library","title":"Webviews.API.set_timeout","text":"set_timeout(f::Function, w::Webview, interval::Real; [repeat::Bool=false])\n\nSets a function to be called after the given interval in webview's event loop. If repeat is true, f will be called repeatedly. The function f should be callable without arguments.\n\nThis function returns a timer_id::Ptr{Cvoid} which can be used in clear_timeout(webview, timer_id).\n\n\n\n\n\n","category":"function"},{"location":"lib/#Webviews.API.clear_timeout","page":"Library","title":"Webviews.API.clear_timeout","text":"clear_timeout(w::Webview, timer_id::Ptr{Cvoid})\n\nClears a previously set timeout.\n\n\n\n\n\n","category":"function"},{"location":"#Webviews.jl","page":"Webviews.jl","title":"Webviews.jl","text":"","category":"section"},{"location":"","page":"Webviews.jl","title":"Webviews.jl","text":"Julia implementation of webview, a tiny cross-platform webview library.","category":"page"},{"location":"#Library-Index","page":"Webviews.jl","title":"Library Index","text":"","category":"section"},{"location":"","page":"Webviews.jl","title":"Webviews.jl","text":"Pages = [\"lib.md\"]","category":"page"}]
}
