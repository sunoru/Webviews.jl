module LinuxImpl

include("../common.jl")

mutable struct Webview <: AbstractPlatformImpl
    const gtk_window_handle::Ptr{Cvoid}
    const webview_handle::Ptr{Cvoid}
    dispatched::Set{Base.RefValue{Tuple{Webview,Function}}}
    sizehint::WindowSizeHint
    status::WebviewStatus
end

const libwebkit2gtk = "libwebkit2gtk-4.0"

macro gcall(expr)
    if expr.head ≡ :call
        expr = :($expr::Cvoid)
    end
    @assert expr.head ≡ :(::) && expr.args[1].head ≡ :call
    expr.args[1].args[1] = :(libwebkit2gtk.$(expr.args[1].args[1]))
    :(@ccall $expr) |> esc
end

check_dependency() = _check_dependency(libwebkit2gtk)

function setup_platform()
    cb = @cfunction(_event_loop_timeout, Cvoid, (Ptr{Cvoid},))
    PLATFORM.timeout_id = @gcall g_timeout_add(
        TIMEOUT_INTEVAL::Cuint,
        cb::Ptr{Cvoid},
        C_NULL::Ptr{Cvoid},
    )::UInt64
    nothing
end

Base.@kwdef mutable struct PlatformSettings
    timeout_id::Cuint = 0
end
const PLATFORM = PlatformSettings()

macro g_signal_connect(instance, signal, data, cf)
    quote
        ccall(
            (:g_signal_connect_data, libwebkit2gtk),
            Cvoid,
            (Ptr{Cvoid}, Cstring, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Cuint),
            $instance, $signal, $cf, pointer_from_objref($data), C_NULL, 0
        )
    end |> esc
end

# macro g_new(type, size)
#     :(@gcall g_malloc_n($size::Csize_t, $(sizeof(type))::Csize_t)::Ptr{$type}) |> esc
# end

# function get_string_from_js_result(r::Ptr{Cvoid})
#     ctx = @gcall webkit_javascript_result_get_global_context(r::Ptr{Cvoid})::Ptr{Cvoid}
#     value = @gcall webkit_javascript_result_get_value(r::Ptr{Cvoid})::Ptr{Cvoid}
#     js = @gcall JSValueToStringCopy(ctx::Ptr{Cvoid}, value::Ptr{Cvoid}, C_NULL::Ptr{Cvoid})::Ptr{Cvoid}
#     n = @gcall JSStringGetMaximumUTF8CStringSize(js::Ptr{Cvoid})::Csize_t
#     s = @g_new(Cchar, n)
#     @gcall JSStringGetUTF8CString(js::Ptr{Cvoid}, s::Ptr{Cchar}, n::Csize_t)
#     @gcall JSStringRelease(js::Ptr{Cvoid})
#     s
# end
function get_string_from_js_result(r::Ptr{Cvoid})
    value = @gcall webkit_javascript_result_get_js_value(r::Ptr{Cvoid})::Ptr{Cvoid}
    s = @gcall jsc_value_to_string(value::Ptr{Cvoid})::Ptr{Cchar}
    s
end

function Webview(
    callback_handler::CallbackHandler,
    debug::Bool,
    unsafe_window_handle::Ptr{Cvoid}
)
    ret = @gcall gtk_init_check(0::Cint, C_NULL::Ptr{Cvoid})::Bool
    ret || error("Failed to initialize GTK")
    window = if unsafe_window_handle ≡ C_NULL
        # GTK_WINDOW_TOPLEVEL
        @gcall gtk_window_new(0::Cint)::Ptr{Cvoid}
    else
        unsafe_window_handle
    end
    webview = @gcall webkit_web_view_new()::Ptr{Cvoid}
    w = Webview(window, webview, Set(), WEBVIEW_HINT_NONE, WEBVIEW_PENDING)

    @g_signal_connect(
        window, "destroy", w,
        @cfunction(
            (_, w) -> terminate(unsafe_pointer_to_objref(Ptr{Webview}(w))),
            Cvoid, (Ptr{Cvoid}, Ptr{Cvoid})
        )
    )
    manager = @gcall webkit_web_view_get_user_content_manager(webview::Ptr{Cvoid})::Ptr{Cvoid}
    @g_signal_connect(
        manager, "script-message-received::external", callback_handler,
        @cfunction(
            (_, r, data) -> begin
                mh = unsafe_pointer_to_objref(Ptr{CallbackHandler}(data))
                s = get_string_from_js_result(r)
                on_message(mh, s)
                @gcall g_free(s::Ptr{Cvoid})
            end,
            Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid})
        )
    )
    @gcall webkit_user_content_manager_register_script_message_handler(
        manager::Ptr{Cvoid}, "external"::Cstring
    )
    init!(w, "window.external={invoke:function(s){window.webkit.messageHandlers.external.postMessage(s);}}")
    @gcall gtk_container_add(window::Ptr{Cvoid}, webview::Ptr{Cvoid})
    @gcall gtk_widget_grab_focus(webview::Ptr{Cvoid})
    settings = @gcall webkit_web_view_get_settings(webview::Ptr{Cvoid})::Ptr{Cvoid}
    @gcall webkit_settings_set_javascript_can_access_clipboard(settings::Ptr{Cvoid}, true::Bool)
    if debug
        @gcall webkit_settings_set_enable_write_console_messages_to_stdout(
            settings::Ptr{Cvoid}, true::Bool
        )
        @gcall webkit_settings_set_enable_developer_extras(settings::Ptr{Cvoid}, true::Bool)
    end
    @gcall gtk_widget_show_all(window::Ptr{Cvoid})
    w
end

API.terminate(::Webview) = @gcall gtk_main_quit()
function API.is_destroyed(w::Webview)
    w.status ≡ WEBVIEW_DESTORYED && return true
    w.status ≡ WEBVIEW_PENDING && return false
    destroyed = 0 == @gcall gtk_main_level()::Cuint;
    if destroyed
        w.status = WEBVIEW_DESTORYED
    end
    destroyed
end
function API.run(w::Webview)
    w.status = WEBVIEW_RUNNING
    @gcall gtk_main()
end

function _dispatched(p::Ptr{Cvoid})
    cd = unsafe_pointer_to_objref(Ptr{Base.RefValue{Tuple{Webview,Function}}}(p))
    w, f = cd[]
    try
        f()
    finally
        delete!(w.dispatched, cd)
    end
    Cint(false)
end

function API.dispatch(f::Function, w::Webview)
    cf = @cfunction(_dispatched, Cint, (Ptr{Cvoid},))
    ref = Ref{Tuple{Webview,Function}}((w, f))
    push!(w.dispatched, ref)
    ptr = pointer_from_objref(ref)
    @gcall g_idle_add_full(
        100::Cint,  # G_PRIORITY_HIGH_IDLE
        cf::Ptr{Cvoid},
        ptr::Ptr{Cvoid},
        C_NULL::Ptr{Cvoid}
    )
end

API.window_handle(w::Webview) = w.gtk_window_handle
API.title!(w::Webview, title::AbstractString) = @gcall gtk_window_set_title(
    w.gtk_window_handle::Ptr{Cvoid},
    title::Cstring
)::Ptr{Cchar}

function API.size(w::Webview)
    width = Ref{Cint}()
    height = Ref{Cint}()
    @gcall gtk_window_get_size(
        w.gtk_window_handle::Ptr{Cvoid},
        width::Ptr{Cint},
        height::Ptr{Cint}
    )
    (width[], height[])
end

Base.@kwdef struct GdkGeometry
    min_width::Cint = 0
    min_height::Cint = 0
    max_width::Cint = 0
    max_height::Cint = 0
    base_width::Cint = 0
    base_height::Cint = 0
    width_inc::Cint = 0
    height_inc::Cint = 0
    min_aspect::Float64 = 0
    max_aspect::Float64 = 0
    win_gravity::Cint = 1  # GDK_GRAVITY_NORTH_WEST
end

function API.resize!(w::Webview, size::Tuple{Integer,Integer}; hint::WindowSizeHint)
    window = w.gtk_window_handle
    width, height = size
    @gcall gtk_window_set_resizable(window::Ptr{Cvoid}, (hint ≢ WEBVIEW_HINT_FIXED)::Bool)
    if hint ≡ WEBVIEW_HINT_NONE
        @gcall gtk_window_resize(window::Ptr{Cvoid}, width::Cint, height::Cint)
    elseif hint ≡ WEBVIEW_HINT_FIXED
        @gcall gtk_widget_set_size_request(window::Ptr{Cvoid}, width::Cint, height::Cint)
    else
        g = Ref(GdkGeometry(
            min_width=width,
            max_width=width,
            min_height=height,
            max_height=height
        ))
        h = if hint ≡ WEBVIEW_HINT_MIN
            1 << 1  # GDK_HINT_MIN_SIZE
        else
            1 << 2  # GDK_HINT_MAX_SIZE
        end
        @gcall gtk_window_set_geometry_hints(
            window::Ptr{Cvoid},
            C_NULL::Ptr{Cvoid},
            g::Ptr{GdkGeometry},
            h::Cint
        )
    end
    w.sizehint = hint
    w
end
API.sizehint(w::Webview) = w.sizehint

API.navigate!(w::Webview, url::AbstractString) = (@gcall webkit_web_view_load_uri(
    w.webview_handle::Ptr{Cvoid},
    url::Cstring
)::Cvoid; w)

API.html!(w::Webview, html::AbstractString) = (@gcall webkit_web_view_load_html(
    w.webview_handle::Ptr{Cvoid},
    html::Cstring,
    C_NULL::Ptr{Cchar}
)::Cvoid; w)

function API.init!(w::Webview, js::AbstractString)
    manager = @gcall webkit_web_view_get_user_content_manager(w.webview_handle::Ptr{Cvoid})::Ptr{Cvoid}
    script = @gcall webkit_user_script_new(
        js::Cstring,
        1::Cint,  # WEBKIT_USER_CONTENT_INJECT_TOP_FRAME
        0::Cint,  # WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START
        C_NULL::Ptr{Cvoid},
        C_NULL::Ptr{Cvoid}
    )::Ptr{Cvoid}
    @gcall webkit_user_content_manager_add_script(
        manager::Ptr{Cvoid},
        script::Ptr{Cvoid}
    )
    w
end

API.eval!(w::Webview, js::AbstractString) = (@gcall webkit_web_view_run_javascript(
    w.webview_handle::Ptr{Cvoid},
    js::Cstring,
    C_NULL::Ptr{Cvoid},
    C_NULL::Ptr{Cvoid},
    C_NULL::Ptr{Cvoid}
)::Cvoid; w)

end