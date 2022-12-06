module WindowsImpl

using Downloads: Downloads
using SHA: SHA

include("../common.jl")
include("./win_types.jl")

const LIBWEBVIEW_VERSION = v"0.7.4"
const LIBWEBVIEW2LOADER_SHA256SUM = "184574b9c36b044888644fc1f2b19176e0e76ccc3ddd2f0a5f0d618c88661f86"
const LIBWEBVIEW_SHA256SUM = "2523d5dcac6aed37f8d8d45782322112bea8ccb08ecde644d90a74ce038d7ff9"
const libwebview2loader = joinpath(@__DIR__, "../../../libs/WebView2Loader.dll") |> abspath
const libwebview = joinpath(@__DIR__, "../../../libs/webview.dll") |> abspath

function _download_dlls(force=false)
    dl(file, chksum) = begin
        !force && isfile(file) && return
        dir, filename = splitdir(file)
        @debug "Downloading $filename"
        output = Downloads.download(
            "https://github.com/webview/webview_deno/releases/download/$LIBWEBVIEW_VERSION/$filename",
        )
        open(output) do io
            @assert SHA.sha256(io) |> bytes2hex == chksum "Downloaded file $output does not match checksum"
        end
        isdir(dir) || mkpath(dir)
        mv(output, file, force=true)
    end
    dl(libwebview2loader, LIBWEBVIEW2LOADER_SHA256SUM)
    dl(libwebview, LIBWEBVIEW_SHA256SUM)
    nothing
end

function check_dependency()
    _download_dlls()
    _check_dependency(libwebview2loader)
end
setup_platform() = nothing

mutable struct Webview <: AbstractPlatformImpl
    const ptr::Ptr{Cvoid}
    const timer_id::Cuint
    const main_thread::DWORD
    const dispatched::Set{Base.RefValue{Tuple{Webview,Function}}}
    sizehint::WindowSizeHint
end

function Webview(
    _callback_handler::CallbackHandler,
    debug::Bool,
    unsafe_window_handle::Ptr{Cvoid}
)
    ptr = @ccall libwebview.webview_create(
        debug::Cint,
        unsafe_window_handle::Ptr{Cvoid},
    )::Ptr{Cvoid}
    window = @ccall libwebview.webview_get_window(ptr::Ptr{Cvoid})::Ptr{Cvoid}
    timer_id = @ccall "user32".SetTimer(
        window::Ptr{Cvoid}, 0::UInt, TIMEOUT_INTERVAL::Cuint,
        @cfunction(_event_loop_timeout, Cvoid, (Ptr{Cvoid}, Cuint, UInt, UInt32))::Ptr{Cvoid}::Ptr{Cvoid}
    )::UInt
    main_thread = @ccall GetCurrentThreadId()::DWORD
    Webview(ptr, timer_id, main_thread, Set(), WEBVIEW_HINT_NONE)
end
Base.cconvert(::Type{Ptr{Cvoid}}, w::Webview) = w.ptr

API.window_handle(w::Webview) = @ccall libwebview.webview_get_window(w::Ptr{Cvoid})::Ptr{Cvoid}
API.terminate(w::Webview) = @ccall libwebview.webview_terminate(w::Ptr{Cvoid})::Cvoid
API.destroy(w::Webview) = @ccall libwebview.webview_destroy(w::Ptr{Cvoid})::Cvoid
API.is_shown(w::Webview) = @ccall "user32".IsWindow(window_handle(w)::Ptr{Cvoid})::Bool

function API.run(::Webview)
    # @ccall libwebview.webview_run(w::Ptr{Cvoid})::Cvoid
    ref = Ref{MSG}()
    while (
        res = @ccall "user32".GetMessageW(ref::Ptr{MSG}, C_NULL::Ptr{Cvoid}, 0::Cuint, 0::Cuint)::Cint
    ) ≠ -1
        msg = ref[]
        if msg.hwnd ≢ C_NULL
            @ccall "user32".TranslateMessage(ref::Ptr{MSG})::Bool
            @ccall "user32".DispatchMessageW(ref::Ptr{MSG})::Clong
            continue
        end
        if msg.message == WM_APP
            ptr = Ptr{Cvoid}(msg.lParam);
            _dispatched(ptr)
        elseif msg.message == WM_QUIT
            return
        end
    end
end

function API.dispatch(f::Function, w::Webview)
    cf = @cfunction(_dispatched, Cint, (Ptr{Cvoid},))
    ref = Ref{Tuple{Webview,Function}}((w, f))
    push!(w.dispatched, ref)
    ptr = pointer_from_objref(ref)
    ret = @ccall "user32".PostThreadMessageW(
        w.main_thread::DWORD,
        WM_APP::Cuint,
        0::WPARAM,
        LPARAM(ptr)::LPARAM
    )::Bool
    if !ret
        pop!(w.dispatched, ref)
        @warn "Failed to dispatch function"
    end
end

API.title!(w::Webview, title::AbstractString) = @ccall libwebview.webview_set_title(
    w::Ptr{Cvoid}, title::Cstring
)::Cvoid


function API.size(w::Webview)
    rect = Ref{RECT}()
    @ccall "user32".GetClientRect(window_handle(w)::Ptr{Cvoid}, rect::Ptr{RECT})::Bool
    (rect[].right - rect[].left, rect[].bottom - rect[].top)
end

function API.resize!(w::Webview, size::Tuple{Integer,Integer}; hint::WindowSizeHint)
    width, height = size
    @ccall libwebview.webview_set_size(
        w::Ptr{Cvoid},
        width::Cint,
        height::Cint,
        hint::Cint
    )::Cvoid
    w.sizehint = hint
    w
end
API.sizehint(w::Webview) = w.sizehint

API.navigate!(w::Webview, url::AbstractString) =
    @ccall libwebview.webview_navigate(w::Ptr{Cvoid}, url::Cstring)::Cvoid
API.html!(w::Webview, html::AbstractString) =
    @ccall libwebview.webview_set_html(w::Ptr{Cvoid}, html::Cstring)::Cvoid
API.init!(w::Webview, js::AbstractString) =
    @ccall libwebview.webview_init(w::Ptr{Cvoid}, js::Cstring)::Cvoid
API.eval!(w::Webview, js::AbstractString) =
    @ccall libwebview.webview_eval(w::Ptr{Cvoid}, js::Cstring)::Cvoid

_binding_wrapper(seq::Ptr{Cchar}, req::Ptr{Cchar}, ref::Ptr{Cvoid}) = begin
    try
        cd = unsafe_pointer_to_objref(Ptr{Tuple{Function,Any}}(ref))
        f, arg = cd
        seq_id = JSON3.read(unsafe_string(seq))
        args = JSON3.read(unsafe_string(req))
        f(seq_id, copy(args), arg)
    catch e
        @debug e
    end
    nothing
end

function API.bind_raw(f::Function, w::API.AbstractWebview, name::AbstractString, arg=nothing)
    API.bind_raw(f, w.callback_handler, name, arg)
    ref = w.callback_handler.callbacks[name]
    @ccall libwebview.webview_bind(
        w.platform::Ptr{Cvoid}, name::Cstring,
        @cfunction(_binding_wrapper, Cvoid, (Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid}))::Ptr{Cvoid},
        ref::Ptr{Cvoid}
    )::Cvoid
    nothing
end

function API.unbind(w::API.AbstractWebview, name::AbstractString)
    @ccall libwebview.webview_unbind(w.platform::Ptr{Cvoid}, name::Cstring)::Cvoid
    unbind(w.callback_handler, name)
end

end