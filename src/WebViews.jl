# Wrappers for https://github.com/webview/webview
module WebViews

export WebView,
    terminate,
    window_handle,
    title!,
    navigate!,
    html!,
    init!,
    eval!,
    bind

export WindowSizeHint,
    WEBVIEW_HINT_NONE,
    WEBVIEW_HINT_MIN,
    WEBVIEW_HINT_MAX,
    WEBVIEW_HINT_FIXED

const libwebview = joinpath(@__DIR__, "..", "build", "libwebview.so")

mutable struct WebView
    const handle::Ptr{Cvoid}
    WebView(; debug=false) =
        finalizer(new(
            ccall(
                (:webview_create, libwebview),
                Ptr{Cvoid},
                (Cint, Ptr{Cvoid}),
                debug, C_NULL
            )
        )) do w
            ccall(
                (:webview_destroy, libwebview),
                Cvoid,
                (Ptr{Cvoid},),
                w
            )
        end
end
Base.cconvert(::Type{Ptr{Cvoid}}, w::WebView) = w.handle

Base.run(w::WebView) = ccall(
    (:webview_run, libwebview),
    Cvoid,
    (Ptr{Cvoid},),
    w
)
terminate(w::WebView) = ccall(
    (:webview_terminate, libwebview),
    Cvoid,
    (Ptr{Cvoid},),
    w
)
# webview_dispatch(w, fn, arg)
window_handle(w::WebView) = ccall(
    (:webview_get_window, libwebview),
    Ptr{Cvoid},
    (Ptr{Cvoid},),
    w
)
title!(w::WebView, title::AbstractString) = ccall(
    (:webview_set_title, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, title
)

@enum WindowSizeHint begin
    WEBVIEW_HINT_NONE = 0 # Width and height are default size
    WEBVIEW_HINT_MIN = 1 # Width and height are minimum bounds
    WEBVIEW_HINT_MAX = 2 # Width and height are maximum bounds
    WEBVIEW_HINT_FIXED = 3 # Window size can not be changed by a user
end

navigate!(w::WebView, url::AbstractString) = ccall(
    (:webview_navigate, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, url
)
html!(w::WebView, html::AbstractString) = ccall(
    (:webview_set_html, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, html
)
init!(w::WebView, js::AbstractString) = ccall(
    (:webview_init, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, js
)
eval!(w::WebView, js::AbstractString) = ccall(
    (:webview_eval, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, js
)

function _raw_bind(@nospecialize(f::Function), w::WebView, name::AbstractString)
    cf = @cfunction $f Cvoid (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid})
    ccall(
        (:webview_bind, libwebview),
        Cvoid,
        (Ptr{Cvoid}, Cstring, Ptr{Cvoid}, Ptr{Cvoid}),
        w, name, cf, C_NULL
    )
end
function bind(@nospecialize(f::Function), w::WebView, name::AbstractString)
    function wrapper(seq_ptr::Ptr{Cvoid}, req_ptr::Ptr{Cvoid}, ::Ptr{Cvoid})
        req = unsafe_string(req_ptr)
        args = JSON.parse(req)
    end
    _raw_bind(wrapper, w, name)
end

end # module
