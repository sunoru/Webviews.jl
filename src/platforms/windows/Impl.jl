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
    const callback_handler::CallbackHandler
end

function Webview(
    callback_handler::CallbackHandler,
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
        @cfunction(_event_loop_timeout, Cvoid, (Ptr{Cvoid}, Cuint, UInt, UInt32))::Ptr{Cvoid}
    )::UInt
    main_thread = @ccall GetCurrentThreadId()::DWORD
    Webview(ptr, timer_id, main_thread, callback_handler)
end
Base.cconvert(::Type{Ptr{Cvoid}}, w::Webview) = w.ptr

API.window_handle(w::Webview) = @ccall libwebview.webview_get_window(w::Ptr{Cvoid})::Ptr{Cvoid}
terminate() = @ccall "user32".PostQuitMessage(0::Cint)::Cvoid
API.close(w::Webview) = @ccall "user32".DestroyWindow(window_handle(w)::Ptr{Cvoid})::Bool
API.destroy(w::Webview) = @ccall libwebview.webview_destroy(w::Ptr{Cvoid})::Cvoid
API.is_shown(w::Webview) = @ccall "user32".IsWindow(window_handle(w)::Ptr{Cvoid})::Bool

function API.run(::Webview)
    ref = Ref{MSG}()
    while (
        res = @ccall "user32".GetMessageW(ref::Ptr{MSG}, C_NULL::Ptr{Cvoid}, 0::Cuint, 0::Cuint)::Cint
    ) ≠ -1
        msg = ref[]
        if msg.hwnd ≢ C_NULL || msg.message == WM_TIMER
            @ccall "user32".TranslateMessage(ref::Ptr{MSG})::Bool
            @ccall "user32".DispatchMessageW(ref::Ptr{MSG})::Clong
            continue
        end
        if msg.message == WM_DESTROY
            on_window_destroy(msg.hwnd)
        elseif msg.message == WM_APP
            ptr = Ptr{Cvoid}(msg.lParam)
            call_dispatch(ptr)
        elseif msg.message == WM_QUIT
            return
        end
    end
end

function API.dispatch(f::Function, w::Webview)
    ptr = setup_dispatch(f, w.callback_handler)
    ret = @ccall "user32".PostThreadMessageW(
        w.main_thread::DWORD,
        WM_APP::Cuint,
        0::WPARAM,
        LPARAM(ptr)::LPARAM
    )::Bool
    if !ret
        clear_dispatch(ptr)
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

function API.resize!(w::Webview, size::Tuple{Integer,Integer}; hint::WindowSizeHint=WEBVIEW_HINT_NONE)
    width, height = size
    @ccall libwebview.webview_set_size(
        w::Ptr{Cvoid},
        width::Cint,
        height::Cint,
        hint::Cint
    )::Cvoid
    w
end

API.navigate!(w::Webview, url::AbstractString) = (
    (@ccall libwebview.webview_navigate(w::Ptr{Cvoid}, url::Cstring)::Cvoid); w)
API.html!(w::Webview, html::AbstractString) = (
    (@ccall libwebview.webview_set_html(w::Ptr{Cvoid}, html::Cstring)::Cvoid); w)
API.init!(w::Webview, js::AbstractString) = (
    (@ccall libwebview.webview_init(w::Ptr{Cvoid}, js::Cstring)::Cvoid); w)
API.eval!(w::Webview, js::AbstractString) = (
    (@ccall libwebview.webview_eval(w::Ptr{Cvoid}, js::Cstring)::Cvoid); w)

function _binding_wrapper(seq::Ptr{Cchar}, req::Ptr{Cchar}, ptr::Ptr{Cvoid})
    try
        f = unsafe_pointer_to_objref(ptr)::MessageCallback
        seq_id = JSON3.read(unsafe_string(seq))
        args = JSON3.read(unsafe_string(req))
        f(seq_id, copy(args))
    catch e
        @debug e
    end
    nothing
end

function API.bind_raw(f::Function, w::AbstractWebview, name::AbstractString)
    API.bind_raw(f, w.callback_handler, name)
    ref = w.callback_handler.callbacks[name]
    @ccall libwebview.webview_bind(
        w.platform::Ptr{Cvoid}, name::Cstring,
        @cfunction(_binding_wrapper, Cvoid, (Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid}))::Ptr{Cvoid},
        pointer_from_objref(ref)::Ptr{Cvoid}
    )::Cvoid
    nothing
end

function API.unbind(w::AbstractWebview, name::AbstractString)
    @ccall libwebview.webview_unbind(w.platform::Ptr{Cvoid}, name::Cstring)::Cvoid
    unbind(w.callback_handler, name)
end

const GlobalTimers = Dict{UInt,Ptr{Cvoid}}()

function _clear_timeout(ptr::Ptr{Cvoid})
    id = clear_dispatch(ptr)
    isnothing(id) && return
    @ccall "user32".KillTimer(C_NULL::Ptr{Cvoid}, id::UInt)::Bool
    delete!(GlobalTimers, id)
    nothing
end

function _timeout(_1, _2, timer_id, _4)
    haskey(GlobalTimers, timer_id) || return
    ptr = GlobalTimers[timer_id]
    _clear_timeout(ptr)
    call_dispatch(ptr)
    nothing
end
function _timeout_repeat(_1, _2, timer_id, _4)
    haskey(GlobalTimers, timer_id) || return
    call_dispatch(GlobalTimers[timer_id])
    nothing
end

function API.set_timeout(f::Function, w::Webview, interval::Real; repeat=false)
    fp = setup_dispatch(f, w.callback_handler)
    timer_id = @ccall "user32".SetTimer(
        C_NULL::Ptr{Cvoid}, 0::UInt, round(Cuint, interval * 1000)::Cuint,
        if repeat
            @cfunction(_timeout_repeat, Cvoid, (Ptr{Cvoid}, Cuint, UInt, UInt32))
        else
            @cfunction(_timeout, Cvoid, (Ptr{Cvoid}, Cuint, UInt, UInt32))
        end::Ptr{Cvoid}
    )::UInt
    if timer_id == 0
        clear_dispatch(fp)
        @warn "Failed to set timer"
        return 0
    end
    set_dispatch_id(fp, timer_id)
    GlobalTimers[timer_id] = fp
    fp
end

API.clear_timeout(::Webview, timer_id::Ptr{Cvoid}) = _clear_timeout(timer_id)

end