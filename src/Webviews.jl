# Wrappers for https://github.com/webview/webview
"""
    Webviews

Julia wrappers for [webview](https://github.com/webview/webview),
a tiny cross-platform webview library.
"""
module Webviews

using Reexport: @reexport
using JSON3: JSON3

export Webview

include("./Consts.jl")
include("./Utils.jl")
include("./API.jl")

# Platform-specific implementations
@static if Sys.isapple()
    include("./platforms/apple/Impl.jl")
    using .AppleImpl: AppleImpl as PlatformImpl
elseif Sys.iswindows()
    include("./platforms/windows/Impl.jl")
    using .WindowsImpl: WindowsImpl as PlatformImpl
else
    include("./platforms/linux/Impl.jl")
    using .LinuxImpl: LinuxImpl as PlatformImpl
end
@reexport using .Consts
using .Consts: WebviewStatus, WEBVIEW_PENDING, WEBVIEW_RUNNING, WEBVIEW_DESTORYED
@reexport using .API

"""
    Webview(
        size=(1024, 768);
        title="",
        debug=false,
        size_fixed=false,
        unsafe_window_handle=C_NULL,
        enable_webio=true,
        auto_terminate=true
    )
    Webview(width, height; kwargs...)

Create a new webview instance with `size` and `title`.

- If `debug` is true, developer tools will be enabled (if the platform supports them).
- **UNSAFE** `unsafe_window_handle` can be an unsafe pointer to the platforms specific native window handle.
If it's non-null - then child WebView is embedded into the given parent window.
Otherwise a new window is created. Depending on the platform,
a `GtkWindow`, `NSWindow` or `HWND` pointer can be passed here.
- If `enable_webio` is true, then WebIO will be enabled.
- The process will be terminated when all webviews with `auto_terminate=true` are destroyed.
"""
mutable struct Webview <: API.AbstractWebview
    const platform::PlatformImpl.Webview
    const callback_handler::Utils.CallbackHandler
    const webio_enabled::Bool
    const auto_terminate::Bool
    status::Consts.WebviewStatus
    function Webview(
        size::Tuple{Integer,Integer}=(1024, 768);
        title::AbstractString="",
        debug::Bool=false,
        size_fixed::Bool=false,
        unsafe_window_handle::Ptr{Cvoid}=C_NULL,
        enable_webio::Bool=true,
        auto_terminate::Bool=true
    )
        ch = Utils.CallbackHandler()
        platform = PlatformImpl.Webview(ch, debug, unsafe_window_handle)
        window = window_handle(platform)
        window ≡ C_NULL && error("Failed to create webview window")
        w = new(platform, ch, enable_webio, auto_terminate, WEBVIEW_PENDING)
        API.resize!(w, size; hint=size_fixed ? WEBVIEW_HINT_FIXED : WEBVIEW_HINT_NONE)
        title!(w, title)
        if enable_webio
            webio_init!(w)
        end
        if auto_terminate
            lock(ActiveWindowsLock) do
                ActiveWindows[window] = w
            end
        end
        finalizer(destroy, w)
    end
end
Webview(width::Integer, height::Integer; kwargs...) = Webview((width, height); kwargs...)

function Base.show(io::IO, w::Webview)
    status = w.status ≡ Consts.WEBVIEW_PENDING ? "pending" :
        w.status ≡ Consts.WEBVIEW_RUNNING ? "running" :
        w.status ≡ Consts.WEBVIEW_DESTORYED ? "destroyed" :
        "unknown"
    num_bindings = length(w.callback_handler.callbacks)
    if w.webio_enabled && w.status ≢ Consts.WEBVIEW_DESTORYED
        num_bindings -= 1
    end
    print(
        io,
        "Webview ($num_bindings bindings): $(status)"
    )
end

# Window => Webview
const ActiveWindows = Dict{Ptr{Cvoid}, Webview}()
const ActiveWindowsLock = ReentrantLock()

function on_window_destroy(w::Ptr{Cvoid})
    lock(ActiveWindowsLock) do
        haskey(ActiveWindows, w) || return
        webview = pop!(ActiveWindows, w)
        destroy(webview)
        if isempty(ActiveWindows)
            terminate()
        end
    end
end

function __init__()
    if PlatformImpl.check_dependency()
        PlatformImpl.setup_platform()
    end
    nothing
end

include("./webio.jl")

end # module
