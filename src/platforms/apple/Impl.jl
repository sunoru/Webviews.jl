module AppleImpl
# TODO

include("../common.jl")
include("../common_bind.jl")

include("./objc.jl")

Base.@kwdef mutable struct PlatformSettings
    timer_ptr::Ptr{Cvoid} = 0
end
const PLATFORM = PlatformSettings()
const libWebKit = "/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit"
const ASSOCIATED_KEY = "webview"

check_dependency() = _check_dependency(libWebKit)
function setup_platform()
    # Register the yielder in the shared `NSApplication`.
    app = get_shared_application()
    @ccall class_replaceMethod(
        a"NSApplication"cls::Ptr{Cvoid}, a"webviewsjlYielder:"sel::Ptr{Cvoid},
        @cfunction(_event_loop_timeout, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))::Ptr{Cvoid},
        "v@:@"::Cstring
    )::Ptr{Cvoid}
    PLATFORM.timer_ptr = @msg_send(
        Ptr{Cvoid},
        a"NSTimer"cls,
        a"scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"sel,
        (TIMEOUT_INTERVAL / 1000)::Cdouble,
        app,
        a"webviewsjlYielder:"sel,
        C_NULL,
        true::Bool
    )
    prepare_timeout()
    nothing
end

Base.@kwdef mutable struct Webview <: AbstractPlatformImpl
    const parent_window::Ptr{Cvoid}
    const debug::Bool
    const callback_handler::CallbackHandler
    const main_queue::ID = cglobal(:_dispatch_main_q)
    window::ID = C_NULL
    config::ID = C_NULL
    manager::ID = C_NULL
    webview::ID = C_NULL
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
        ASSOCIATED_KEY::Cstring,
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
# TODO: support multiple windows.
API.terminate(::Webview) =
    let app = get_shared_application()
        # Stop the main event loop instead of terminating the process.
        @msg_send Cvoid app a"stop:"sel C_NULL
    end
function API.close(w::Webview)
    @msg_send Cvoid w.window a"close"sel
    # On macOS, we need to send an event explicitly to let the event loop ends
    resize!(w, (1, 1))
    nothing
end
API.is_shown(w::Webview) = (
    @msg_send Bool w.window a"isVisible"sel
) && @msg_send Bool get_shared_application() a"isRunning"sel
API.run(::Webview) =
    let app = get_shared_application()
        @msg_send Cvoid app a"run"sel
    end

function _dispatch(ptr::Ptr{Cvoid})
    call_dispatch(ptr)
    clear_dispatch(ptr)
    nothing
end

function API.dispatch(f::Function, w::Webview)
    cf = @cfunction(_dispatch, Cvoid, (Ptr{Cvoid},))
    ptr = setup_dispatch(f, w.callback_handler)
    @ccall dispatch_async_f(
        w.main_queue::ID,
        ptr::Ptr{Cvoid},
        cf::Ptr{Cvoid}
    )::Cvoid
end

API.title!(w::Webview, title::AbstractString) = @msg_send(
    Cvoid,
    w.window, a"setTitle:"sel,
    @a_str(title, "str")
)

function API.size(w::Webview)
    frame = @msg_send_stret CGRect w.window a"frame"sel
    size = frame.size
    (round(Int, size.width), round(Int, size.height))
end

function API.resize!(w::Webview, size::Tuple{Integer,Integer}; hint::WindowSizeHint=WEBVIEW_HINT_NONE)
    width, height = size
    style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
    if hint ≢ WEBVIEW_HINT_FIXED
        style |= NSWindowStyleMaskResizable
    end
    @msg_send Cvoid w.window a"setStyleMask:"sel style::UInt
    if hint ≡ WEBVIEW_HINT_MIN
        @msg_send Cvoid w.window a"setContentMinSize:"sel CGSize(width, height)::CGSize
    elseif hint ≡ WEBVIEW_HINT_MAX
        @msg_send Cvoid w.window a"setContentMaxSize:"sel CGSize(width, height)::CGSize
    else
        @msg_send(
            Cvoid,
            w.window,
            a"setFrame:display:animate:"sel,
            CGRect(0, 0, width, height)::CGRect,
            true::Bool,
            false::Bool
        )
    end
    @msg_send Cvoid w.window a"center"sel
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
    @msg_send Cvoid w.manager a"addUserScript:"sel user_script
    w
end
function API.eval!(w::Webview, js::AbstractString)
    @msg_send Cvoid w.webview a"evaluateJavaScript:completionHandler:"sel @a_str(js, "str") C_NULL
    w
end

function _timeout(_1, _2, timer::ID)
    valid = @msg_send Bool timer a"isValid"sel
    valid || return
    user_info = @msg_send ID timer a"userInfo"sel
    fp = @msg_send Ptr{Cvoid} user_info a"pointerValue"sel
    call_dispatch(fp)
    interval = @msg_send Cdouble timer a"timeInterval"sel
    interval > 0 || return
    _clear_timeout(fp)
    nothing
end

function prepare_timeout()
    @ccall class_replaceMethod(
        a"NSApplication"cls::Ptr{Cvoid}, a"webviewsjlTimeout:"sel::Ptr{Cvoid},
        @cfunction(_timeout, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))::Ptr{Cvoid},
        "v@:@"::Cstring
    )::Ptr{Cvoid}
    nothing
end

function API.set_timeout(f::Function, w::Webview, interval::Real; repeat=false)
    fp = setup_dispatch(f, w.callback_handler)
    user_info = @msg_send ID a"NSValue"cls a"valueWithPointer:"sel fp
    app = get_shared_application()
    timer_id = @msg_send(
        ID,
        a"NSTimer"cls,
        a"scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"sel,
        interval::Cdouble,
        app,
        a"webviewsjlTimeout:"sel,
        user_info,
        repeat::Bool
    )
    set_dispatch_id(fp, UInt64(timer_id))
    fp
end

function _clear_timeout(timer_id::Ptr{Cvoid})
    timer = clear_dispatch(timer_id)
    isnothing(timer) && return
    @msg_send Cvoid Ptr{Cvoid}(timer) a"invalidate"sel
    nothing
end
API.clear_timeout(::Webview, timer_id::Ptr{Cvoid}) = _clear_timeout(timer_id)

end
