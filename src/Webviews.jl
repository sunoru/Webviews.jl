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
using SHA: SHA

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
const libwebview, LIBWEBVIEW_SHA256SUM = let
    (f, s) = if HOST_OS_ARCH == ("linux", "x86_64")
        "libwebview.so", "43b18a86c19db14838c3ef1338daeb2551b0547f8d17026d1c132ee12759ac3e"
    elseif HOST_OS_ARCH == ("windows", "x86_64")
        "webview.dll", "2523d5dcac6aed37f8d8d45782322112bea8ccb08ecde644d90a74ce038d7ff9"
    elseif HOST_OS_ARCH == ("macos", "x86_64")
        "libwebview.x86_64.dylib", "d345593ea6ea97c4877866efdf407355ef6b17b2ebad4271e85804389a0e62e4"
    elseif HOST_OS_ARCH == ("macos", "aarch64")
        "libwebview.aarch64.dylib", "467b302988aef9acc665fac81c057a46aa6aec107afedd02c0e1fcefee10f91b"
    else
        error("Unsupported platform: $(HOST_OS_ARCH)")
    end
    abspath(joinpath(@__DIR__, "..", "libs", f)), s
end

function download_libwebview(force=false)
    if !force && isfile(libwebview)
        return libwebview
    end
    dir = dirname(libwebview)
    mkpath(dir)
    dl = (filename, chksum) -> begin
        @debug "Downloading $filename"
        output = Downloads.download(
            "https://github.com/webview/webview_deno/releases/download/$LIBWEBVIEW_VERSION/$filename",
        )
        @assert SHA.sha256(open(output)) |> bytes2hex == chksum "Downloaded file $output does not match checksum"
        mv(output, joinpath(dir, filename), force=true)
    end
    if HOST_OS_ARCH[1] == "windows"
        dl("WebView2Loader.dll", "184574b9c36b044888644fc1f2b19176e0e76ccc3ddd2f0a5f0d618c88661f86")
    end
    dl(basename(libwebview), LIBWEBVIEW_SHA256SUM)
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
    const callbacks::Dict{String, Base.RefValue{Tuple{Webview, Function}}}
    size::Tuple{Int32, Int32}
    size_hint::WindowSizeHint
    _destroyed::Bool
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
        w = new(handle, Dict(), size, size_hint, false)
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
    w._destroyed && return
    for key in keys(w.callbacks)
        unbind(w, key)
    end
    terminate(w)
    ccall((:webview_destroy, libwebview), Cvoid, (Ptr{Cvoid},), w)
    w._destroyed = true
    nothing
end

"""
    run(w::Webview)

Run the webview event loop. Runs the main event loop until it's terminated.
After this function exits, the webview is automatically destroyed.
"""
function Base.run(w::Webview)
    w._destroyed && error("Webview is already destroyed")
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
terminate(w::Webview) = ccall((:webview_terminate, libwebview), Cvoid, (Ptr{Cvoid},), w)

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

function _raw_bind(f::Function, w::Webview, name::AbstractString)
    cf = @cfunction $f Cvoid (Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid})
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

function _bind_wrapper(seq_ptr::Ptr{Cchar}, req_ptr::Ptr{Cchar}, p::Ptr{Cvoid})
    cd = unsafe_pointer_to_objref(Ptr{Base.RefValue{Tuple{Webview, Function}}}(p))
    w, f = cd[]
    req = unsafe_string(req_ptr)
    args = JSON.parse(req)
    try
        result = f(args...)
        _return(w, seq_ptr, true, result)
    catch err
        _return(w, seq_ptr, false, err)
    end
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
    cf = @cfunction _bind_wrapper Cvoid (Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid})
    cd = Ref{Tuple{Webview, Function}}((w, f))
    ccall(
        (:webview_bind, libwebview),
        Cvoid,
        (Ptr{Cvoid}, Cstring, Ptr{Cvoid}, Ptr{Cvoid}),
        w, name, cf, pointer_from_objref(cd)
    )
    w.callbacks[name] = cd
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
