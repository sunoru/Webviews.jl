# Wrappers for https://github.com/webview/webview
module Webviews

using Libdl: Libdl
using Downloads: Downloads
using JSON: JSON

export Webview,
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

@enum WindowSizeHint begin
    WEBVIEW_HINT_NONE = 0 # Width and height are default size
    WEBVIEW_HINT_MIN = 1 # Width and height are minimum bounds
    WEBVIEW_HINT_MAX = 2 # Width and height are maximum bounds
    WEBVIEW_HINT_FIXED = 3 # Window size can not be changed by a user
end

mutable struct Webview
    const handle::Ptr{Cvoid}
    const callbacks::Dict{String,Base.CFunction}
    size::Tuple{Int32, Int32}
    size_hint::WindowSizeHint
    function Webview(
        size::Tuple{Integer, Integer}=(1024, 768);
        title::AbstractString="",
        debug::Bool=false,
        size_hint::WindowSizeHint=WEBVIEW_HINT_NONE,
        window_handle::Ptr{Cvoid}=C_NULL
    )
        handle = ccall(
            (:webview_create, libwebview),
            Ptr{Cvoid},
            (Cint, Ptr{Cvoid}),
            debug, window_handle
        )
        w = new(handle, Dict(), size, size_hint)
        resize!(w, size)
        sizehint!(w, size_hint)
        title!(w, title)
        finalizer(_destroy, w)
    end
end
Webview(width::Integer, height::Integer; kwargs...) = Webview((width, height); kwargs...)
Base.cconvert(::Type{Ptr{Cvoid}}, w::Webview) = w.handle
function _destroy(w::Webview)
    for key in keys(w.callbacks)
        unbind(w, key)
    end
    ccall((:webview_destroy, libwebview), Cvoid, (Ptr{Cvoid},), w)
end

Base.run(w::Webview) = ccall(
    (:webview_run, libwebview),
    Cvoid,
    (Ptr{Cvoid},),
    w
)
terminate(w::Webview) = ccall(
    (:webview_terminate, libwebview),
    Cvoid,
    (Ptr{Cvoid},),
    w
)
# webview_dispatch(w, fn, arg)
window_handle(w::Webview) = ccall(
    (:webview_get_window, libwebview),
    Ptr{Cvoid},
    (Ptr{Cvoid},),
    w
)
title!(w::Webview, title::AbstractString) = ccall(
    (:webview_set_title, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, title
)
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
Base.sizehint!(w::Webview, hint::WindowSizeHint) = resize!(w; hint=hint)

navigate!(w::Webview, url::AbstractString) = (ccall(
    (:webview_navigate, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, url
); w)
html!(w::Webview, html::AbstractString) = (ccall(
    (:webview_set_html, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, html
); w)
init!(w::Webview, js::AbstractString) = (ccall(
    (:webview_init, libwebview),
    Cvoid,
    (Ptr{Cvoid}, Cstring),
    w, js
); w)
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
