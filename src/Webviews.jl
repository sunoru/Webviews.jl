```@meta
DocTestSetup = quote
    using Webviews
end
```
# Wrappers for https://github.com/webview/webview
module Webviews

using Libdl: Libdl
using Downloads: Downloads
using JSON: JSON

export Webview,
    destroy,
    terminate,
    window_handle,
    title!,
    navigate!,
    html!,
    init!,
    eval!,
    unbind

export WindowSizeHint,
    WEBVIEW_HINT_NONE,
    WEBVIEW_HINT_MIN,
    WEBVIEW_HINT_MAX,
    WEBVIEW_HINT_FIXED

const LIBWEBVIEW_VERSION = v"0.7.4"
const HOST_OS_ARCH = let hp = Base.BinaryPlatforms.HostPlatform()
    Base.BinaryPlatforms.os(hp), Base.BinaryPlatforms.arch(hp)
end
const libwebview = joinpath(
    @__DIR__, "..", "libs",
    if HOST_OS_ARCH == ("linux", "x86_64")
        "libwebview.so"
    elseif HOST_OS_ARCH == ("windows", "x86_64")
        "webview.dll"
    elseif HOST_OS_ARCH == ("macos", "x86_64")
        "libwebview.x86_64.dylib"
    elseif HOST_OS_ARCH == ("macos", "aarch64")
        "libwebview.aarch64.dylib"
    else
        error("Unsupported platform: $(HOST_OS_ARCH)")
    end
) |> abspath

function download_libwebview(force=false)
    if !force && isfile(libwebview)
        return libwebview
    end
    dir = dirname(libwebview)
    mkpath(dir)
    dl = (filename) -> begin
        @debug "Downloading $filename"
        Downloads.download(
            "https://github.com/webview/webview_deno/releases/download/$LIBWEBVIEW_VERSION/$filename",
            joinpath(dir, filename)
        )
    end
    if HOST_OS_ARCH[1] == "windows"
        dl("WebView2Loader.dll")
    end
    dl(basename(libwebview))
end

function _check_dependency()
    hdl = nothing
    try
        hdl = Libdl.dlopen(libwebview)
        return true
    catch
        @warn "Failed to load $libwebview"
        return false
    finally
        Libdl.dlclose(hdl)
    end
end

function __init__()
    download_libwebview()
    _check_dependency()
    nothing
end

"""
    WindowSizeHint

Enum to specify the window size hint.
Values:
- `WEBVIEW_HINT_NONE`: Width and height are default size.
- `WEBVIEW_HINT_MIN`: Width and height are minimum bounds.
- `WEBVIEW_HINT_MAX`: Width and height are maximum bounds.
- `WEBVIEW_HINT_FIXED`: Window size can not be changed by a user.
"""
@enum WindowSizeHint begin
    WEBVIEW_HINT_NONE = 0
    WEBVIEW_HINT_MIN = 1
    WEBVIEW_HINT_MAX = 2
    WEBVIEW_HINT_FIXED = 3
end

@enum _WebviewState::UInt8 begin
    _WEBVIEW_RUNNABLE
    _WEBVIEW_TERMINATED
    _WEBVIEW_DESTROYED
end

"""
    Webview(size=(1024, 768); title="", debug=false, size_hint=WEBVIEW_HINT_NONE, unsafe_window_handle=C_NULL)
    Webview(width, height; kwargs...)

Create a new webview instance with `size` and `title`.

- If `debug` is true, developer tools will be enabled (if the platform supports them).
- **UNSAFE** `unsafe_window_handle` can be an unsafe pointer to the platforms specific native window handle.
If it's non-null - then child WebView is embedded into the given parent window.
Otherwise a new window is created. Depending on the platform,
a `GtkWindow`, `NSWindow` or `HWND` pointer can be passed here.
"""
mutable struct Webview
    const handle::Ptr{Cvoid}
    const callbacks::Dict{String,Base.CFunction}
    size::Tuple{Int32, Int32}
    size_hint::WindowSizeHint
    _state::_WebviewState
    function Webview(
        size::Tuple{Integer, Integer}=(1024, 768);
        title::AbstractString="",
        debug::Bool=false,
        size_hint::WindowSizeHint=WEBVIEW_HINT_NONE,
        unsafe_window_handle::Ptr{Cvoid}=C_NULL
    )
        handle = ccall(
            (:webview_create, libwebview),
            Ptr{Cvoid},
            (Cint, Ptr{Cvoid}),
            debug, unsafe_window_handle
        )
        w = new(handle, Dict(), size, size_hint, _WEBVIEW_RUNNABLE)
        resize!(w, size)
        sizehint!(w, size_hint)
        title!(w, title)
        finalizer(destroy, w)
    end
end
Webview(width::Integer, height::Integer; kwargs...) = Webview((width, height); kwargs...)
Base.cconvert(::Type{Ptr{Cvoid}}, w::Webview) = w.handle
"""
    destroy(w::Webview)

Destroys the webview and closes the window along with freeing all internal resources.
"""
function destroy(w::Webview)
    w._state ≡ _WEBVIEW_DESTROYED && return
    for key in keys(w.callbacks)
        unbind(w, key)
    end
    terminate(w)
    ccall((:webview_destroy, libwebview), Cvoid, (Ptr{Cvoid},), w)
    w._state = _WEBVIEW_DESTROYED
    nothing
end

"""
    run(w::Webview)

Run the webview event loop. Runs the main event loop until it's terminated.
After this function exits, the webview is automatically destroyed.
"""
function Base.run(w::Webview)
    if w._state ≢ _WEBVIEW_RUNNABLE
        throw(ArgumentError("Webview is already destroyed"))
    end
    ccall(
        (:webview_run, libwebview),
        Cvoid,
        (Ptr{Cvoid},),
        w
    )
    destroy(w)
end

"""
    terminate(w::Webview)

Stops the main loop. It is safe to call this function from another other background thread.
"""
function terminate(w::Webview)
    w._state ≢ _WEBVIEW_RUNNABLE && return
    ccall((:webview_terminate, libwebview), Cvoid, (Ptr{Cvoid},), w)
    w._state = _WEBVIEW_TERMINATED
    nothing
end

"""
    window_handle(w::Webview)

**UNSAFE** An unsafe pointer to the webviews platform specific native window handle.
When using GTK backend the pointer is `GtkWindow` pointer, when using Cocoa
backend the pointer is `NSWindow` pointer, when using Win32 backend the
pointer is `HWND` pointer.
"""
window_handle(w::Webview) = ccall(
    (:webview_get_window, libwebview),
    Ptr{Cvoid},
    (Ptr{Cvoid},),
    w
)

"""
    title!(w::Webview, title::AbstractString)

Set the native window title.
"""
title!(w::Webview, title::AbstractString) = ccall(
    (:webview_set_title, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, title
)

"""
    resize!(w::Webview, [size::Tuple{Integer, Integer}]; [hint::WindowSizeHint])

Sets the native window size.
"""
Base.resize!(w::Webview, size::Tuple{Integer, Integer}=w.size; hint::WindowSizeHint=(
    w.size_hint ≡ WEBVIEW_HINT_NONE || w.size_hint ≡ WEBVIEW_HINT_FIXED ? w.size_hint : WEBVIEW_HINT_NONE
)) = let (width, height) = size
    ccall(
        (:webview_set_size, libwebview),
        Cvoid,
        (Ptr{Cvoid}, Cint, Cint, Cint),
        w, width, height, hint
    )
    w.size = size
    w.size_hint = hint
    w
end

"""
    sizehint!(w::Webview, hint::WindowSizeHint)

Sets the native window size hint.
"""
Base.sizehint!(w::Webview, hint::WindowSizeHint) = resize!(w; hint=hint)

"""
    navigate!(w::Webview, url::AbstractString)

Navigates webview to the given URL. URL may be a data URI, i.e.
`"data:text/html,<html>...</html>"`.
"""
navigate!(w::Webview, url::AbstractString) = (ccall(
    (:webview_navigate, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, url
); w)

"""
    html!(w::Webview, html::AbstractString)

Set webview HTML directly.
"""
html!(w::Webview, html::AbstractString) = (ccall(
    (:webview_set_html, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, html
); w)

"""
    init(w::Webview, js::AbstractString)

Injects JavaScript code at the initialization of the new page. Every time the webview will open a the new
page - this initialization code will be executed. It is guaranteed that code is executed before `window.onload`.
"""
init!(w::Webview, js::AbstractString) = (ccall(
    (:webview_init, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, js
); w)

"""
    eval!(w::Webview, js::AbstractString)

Evaluates arbitrary JavaScript code. Evaluation happens asynchronously, also the result of the expression
is ignored. Use `bind` if you want to receive notifications about the results of the evaluation.
"""
eval!(w::Webview, js::AbstractString) = (ccall(
    (:webview_eval, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, js
); w)

function _raw_bind(@nospecialize(f::Function), w::Webview, name::AbstractString)
    cf = @cfunction $f Cvoid (Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid})
    ccall(
        (:webview_bind, libwebview),
        Cvoid,
        (Ptr{Cvoid}, Cstring, Ptr{Cvoid}, Ptr{Cvoid}),
        w, name, cf, C_NULL
    )
    cf
end
function _return(w::Webview, seq_ptr::Ptr{Cchar}, success::Bool, result)
    s = try
        if success
            JSON.json(result)
        else
            throw(result)
        end
    catch err
        JSON.json(sprint(showerror, err))
    end
    ccall(
        (:webview_return, libwebview),
        Cvoid,
        (Ptr{Cvoid}, Ptr{Cchar}, Cint, Cstring),
        w, seq_ptr, !success, s
    )
end
"""
    bind(f::Function, w::Webview, name::AbstractString)

Binds a callback so that it will appear in the webview with the given name
as a global async JavaScript function. Callback arguments are automatically
converted from json to as closely as possible match the arguments in the
webview context and the callback automatically converts and returns the
return value to the webview.

# Example

```jldoctest
julia> webview = Webview();
julia> result = 0;
julia> bind(webview, "add") do a, b
           global result = a + b
           terminate(webview)
       end;
julia> html!(webview, "<script>add(1, 2)</script>");
julia> run(webview);
julia> result
3
```
"""
function Base.bind(f::Function, w::Webview, name::AbstractString)
    function wrapper(seq_ptr::Ptr{Cchar}, req_ptr::Ptr{Cchar}, ::Ptr{Cvoid})
        req = unsafe_string(req_ptr)
        args = JSON.parse(req)
        try
            result = f(args...)
            _return(w, seq_ptr, true, result)
        catch err
            _return(w, seq_ptr, false, err)
        end
    end
    cf = _raw_bind(wrapper, w, name)
    w.callbacks[name] = cf
    w
end

"""
    unbind(w::Webview, name::AbstractString)

Unbinds a previously bound function freeing its resource and removing it from the webview JavaScript context.
"""
function unbind(w::Webview, name::AbstractString)
    ccall(
        (:webview_unbind, libwebview),
        Cvoid,
        (Ptr{Cvoid}, Cstring),
        w, name
    )
    delete!(w.callbacks, name)
    w
end

end # module
