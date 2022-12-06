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
include("./API.jl")
include("./Utils.jl")

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
    Webview(size=(1024, 768); title="", debug=false, size_hint=WEBVIEW_HINT_NONE, unsafe_window_handle=C_NULL)
    Webview(width, height; kwargs...)

Create a new webview instance with `size` and `title`.

- If `debug` is true, developer tools will be enabled (if the platform supports them).
- **UNSAFE** `unsafe_window_handle` can be an unsafe pointer to the platforms specific native window handle.
If it's non-null - then child WebView is embedded into the given parent window.
Otherwise a new window is created. Depending on the platform,
a `GtkWindow`, `NSWindow` or `HWND` pointer can be passed here.
"""
mutable struct Webview <: API.AbstractWebview
    const platform::PlatformImpl.Webview
    const callback_handler::Utils.CallbackHandler
    status::Consts.WebviewStatus
    function Webview(
        size::Tuple{Integer,Integer}=(1024, 768);
        title::AbstractString="",
        debug::Bool=false,
        size_hint::WindowSizeHint=WEBVIEW_HINT_NONE,
        unsafe_window_handle::Ptr{Cvoid}=C_NULL
    )
        ch = Utils.CallbackHandler()
        platform = PlatformImpl.Webview(ch, debug, unsafe_window_handle)
        window_handle(platform) ≡ C_NULL && error("Failed to create webview window")
        w = new(platform, ch, WEBVIEW_PENDING)
        API.resize!(w, size; hint=size_hint)
        title!(w, title)
        finalizer(destroy, w)
    end
end
Webview(width::Integer, height::Integer; kwargs...) = Webview((width, height); kwargs...)

function __init__()
    if PlatformImpl.check_dependency()
        PlatformImpl.setup_platform()
    end
    nothing
end

end # module
