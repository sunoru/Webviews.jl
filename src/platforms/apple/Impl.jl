module AppleImpl
# TODO

include("../common.jl")

include("./objc.jl")

Base.@kwdef mutable struct PlatformSettings
    timer_ptr::Ptr{Cvoid} = 0
end
const PLATFORM = PlatformSettings()

check_dependency() = true
function setup_platform()
    # Register the yielder in the shared `NSApplication`.
    app = get_shared_application()
    @ccall class_replaceMethod(
        a"NSApplication"cls::Ptr{Cvoid}, a"webviewsjlTick:"sel::Ptr{Cvoid},
        @cfunction(_event_loop_timeout, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))::Ptr{Cvoid},
        "v@:@"::Cstring
    )::Ptr{Cvoid}
    PLATFORM.timer_ptr = @msg_send(
        Ptr{Cvoid},
        a"NSTimer"cls,
        a"scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"sel,
        (TIMEOUT_INTERVAL / 1000)::Cdouble,
        app,
        a"webviewsjlTick:"sel,
        C_NULL,
        true::Bool
    )
end

Base.@kwdef mutable struct Webview <: AbstractPlatformImpl
    const parent_window::Ptr{Cvoid}
    const debug::Bool
    const callback_handler::CallbackHandler
    const main_queue::ID = cglobal(:_dispatch_main_q)
    const dispatched::Set{Base.RefValue{Tuple{Webview,Function}}} = Set()
    window::ID = C_NULL
    config::ID = C_NULL
    manager::ID = C_NULL
    webview::ID = C_NULL
    sizehint::WindowSizeHint = WEBVIEW_HINT_NONE
end

include("./utils.jl")

function Webview(
    callback_handler::CallbackHandler,
    debug::Bool,
    unsafe_window_handle::Ptr{Cvoid}
)
    w = Webview(;
        parent_window=unsafe_window_handle,
        debug,
        callback_handler
    )
    this_ptr = pointer_from_objref(w)
    app = get_shared_application()
    delegate = create_app_delegate(w)
    @ccall objc_setAssociatedObject(
        delegate::ID,
        "webview"::Cstring,
        this_ptr::ID,
        0::UInt  # OBJC_ASSOCIATION_ASSIGN
    )::ID
    @msg_send Cvoid app a"setDelegate:"sel delegate
    if unsafe_window_handle ≡ C_NULL
        @msg_send Cvoid app a"run"sel
    else
        on_application_did_finish_launching(w, delegate, app)
    end
    w
end

API.window_handle(w::Webview) = w.window
API.terminate(::Webview) =
    let app = get_shared_application()
        @msg_send Cvoid app a"terminate"sel C_NULL
    end
API.is_shown(w::Webview) = @msg_send Bool w.window a"isVisible"sel
API.run(::Webview) =
    let app = get_shared_application()
        @msg_send Cvoid app a"run"sel
    end
function API.dispatch(f::Function, w::Webview)
    ref = Ref{Tuple{Webview,Function}}((w, f))
    push!(w.dispatched, ref)
    ptr = pointer_from_objref(ref)
    @ccall dispatch_async_f(
        w.main_queue::ID,
        ptr::Ptr{Cvoid},
        @cfunction(_dispatch, Cvoid, (Ptr{Cvoid},))::Ptr{Cvoid}
    )::Cvoid
end

API.title!(w::Webview, title::AbstractString) = @msg_send(
    Cvoid,
    w.window, a"setTitle:"sel,
    @a_str(title, "str")
)

function API.size(w::Webview)
    frame = @msg_send ID w.window a"frame"sel
    width = @msg_send CGFloat frame a"width"sel
    height = @msg_send CGFloat frame a"height"sel
    (round(Int, width), round(Int, height))
end

function API.resize!(w::Webview, size::Tuple{Integer,Integer}; hint::WindowSizeHint)
    width, height = size
    style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
    if hint ≢ WEBVIEW_HINT_FIXED
        style |= NSWindowStyleMaskResizable
    end
    @msg_send Cvoid w.window a"setStyleMask:"sel style
    if hint ≡ WEBVIEW_HINT_MIN
        @msg_send Cvoid w.window a"setContentMinSize:"sel @ccall(CGSizeMake(width::CGFloat, height::CGFloat)::ID)
    elseif hint ≡ WEBVIEW_HINT_MAX
        @msg_send Cvoid w.window a"setContentMaxSize:"sel @ccall(CGSizeMake(width::CGFloat, height::CGFloat)::ID)
    else
        @msg_send(
            Cvoid,
            w.window,
            a"setFrame:display:animate:"sel,
            (@ccall CGRectMake(0::CGFloat, 0::CGFloat, width::CGFloat, height::CGFloat)::ID),
            true::Bool,
            false::Bool
        )
    end
    @msg_send Cvoid w.window a"center"sel
    w.sizehint = hint
    w
end

function API.navigate!(w::Webview, url::AbstractString)
    nsurl = @msg_send ID a"NSURL"cls a"URLWithString:"sel @a_str(url, "str")
    @msg_send Cvoid w.webview a"loadRequest:"sel @msg_send ID a"NSURLRequest"cls a"requestWithURL:"sel nsurl
    w
end
function API.html!(w::Webview, html::AbstractString)
    @msg_send Cvoid w.webview a"loadHTMLString:baseURL:"sel @a_str(html, "str") C_NULL
    w
end
function API.init!(w::Webview, js::AbstractString)
    user_script = @msg_send(
        ID,
        (@msg_send ID a"WKUserScript"cls a"alloc"sel),
        a"initWithSource:injectionTime:forMainFrameOnly:"sel,
        @a_str(js, "str"),
        0::Int,  # WKUserScriptInjectionTimeAtDocumentStart
        true::Bool
    )
    @msg_send Cvoid w.webview a"addUserScript:"sel user_script
    w
end
function API.eval!(w::Webview, js::AbstractString)
    @msg_send Cvoid w.webview a"evaluateJavaScript:completionHandler:"sel @a_str(js, "str") C_NULL
    w
end

end
