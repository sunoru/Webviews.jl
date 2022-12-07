module API

export terminate,
    destroy,
    dispatch,
    window_handle,
    title!,
    navigate!,
    html!,
    init!,
    eval!,
    bind_raw,
    unbind,
    return_raw

using JSON3: JSON3

using ..Consts
using ..Consts: WebviewStatus, WEBVIEW_PENDING, WEBVIEW_RUNNING, WEBVIEW_DESTORYED
abstract type AbstractWebview end
abstract type AbstractPlatformImpl end

macro forward(expr)
    w = expr.args[2]
    s = gensym()
    expr.args[2] = :($w::AbstractWebview)
    return_self = endswith(string(expr.args[1]), '!')
    :($expr = (
        $s = $(expr.args[1])($w.platform, $(expr.args[3:end]...));
        $(return_self ? w : s)
    )) |> esc
end

"""
    terminate(w::Webview)

Stops the main loop. It is safe to call this function from another other background thread.

**Note:** This function is not working on macOS.
"""
@forward terminate(w)

@forward is_shown(w)

"""
    destroy(w::Webview)

Destroys the webview and closes the window along with freeing all internal resources.
"""
function destroy(w::AbstractWebview)
    w.status ≡ WEBVIEW_DESTORYED && return
    for key in keys(w.callback_handler.callbacks)
        unbind(w, key)
    end
    is_shown(w.platform) && terminate(w)
    destroy(w.platform)
    w.status = WEBVIEW_DESTORYED
    nothing
end
destroy(::AbstractPlatformImpl) = nothing

"""
    run(w::Webview)

Runs the webview event loop. Runs the main event loop until it's terminated.
After this function exits, the webview is automatically destroyed.
"""
function Base.run(w::AbstractWebview)
    w.status ≡ WEBVIEW_DESTORYED && error("Webview is already destroyed")
    if w.status ≡ WEBVIEW_RUNNING
        @warn "Webview is already running"
        return
    end
    w.status = WEBVIEW_PENDING
    run(w.platform)
    destroy(w)
end

"""
    dispatch(f::Function, w::Webview, [arg])

Posts a function to be executed on the main thread. You normally do not need
to call this function, unless you want to tweak the native window.

The function `f` will be called with two arguments: the webview and the `arg`.
"""
function dispatch(f::Function, w::AbstractWebview, arg=nothing)
    dispatch(w.platform) do
        f(w, arg)
    end
    nothing
end

"""
    window_handle(w::Webview)

**UNSAFE** An unsafe pointer to the webviews platform specific native window handle.
When using GTK backend the pointer is `GtkWindow` pointer, when using Cocoa
backend the pointer is `NSWindow` pointer, when using Win32 backend the
pointer is `HWND` pointer.
"""
@forward window_handle(w)

"""
    title!(w::Webview, title::AbstractString)

Sets the native window title.
"""
@forward title!(w, title::AbstractString)

"""
    size(w::Webview)

Gets the native window size.
"""
@forward Base.size(w)

"""
    resize!(w::Webview, [size::Tuple{Integer, Integer}]; [hint::WindowSizeHint])

Sets the native window size.
"""
function Base.resize!(
    w::AbstractWebview,
    size::Tuple{Integer, Integer};
    hint::Union{WindowSizeHint, Nothing}=WEBVIEW_HINT_NONE
)
    resize!(w.platform, size, hint=hint)
    w
end

"""
    navigate!(w::Webview, url::AbstractString)

Navigates webview to the given URL. URL may be a data URI, i.e.
`"data:text/html,<html>...</html>"`.
"""
@forward navigate!(w, url::AbstractString)

"""
    html!(w::Webview, html::AbstractString)

Set webview HTML directly.
"""
@forward html!(w, html::AbstractString)

"""
    init(w::Webview, js::AbstractString)

Injects JavaScript code at the initialization of the new page. Every time the webview will open a the new
page - this initialization code will be executed. It is guaranteed that code is executed before `window.onload`.
"""
@forward init!(w, js::AbstractString)

"""
    eval!(w::Webview, js::AbstractString)

Evaluates arbitrary JavaScript code. Evaluation happens asynchronously, also the result of the expression
is ignored. Use `bind` if you want to receive notifications about the results of the evaluation.
"""
@forward eval!(w, js::AbstractString)

"""
    bind_raw(f::Function, w::Webview, name::AbstractString, [arg])

Binds a callback so that it will appear in the webview with the given name
as a global async JavaScript function. Callback receives a seq and req value.
The seq parameter is an identifier for using `Webviews.return_raw` to
return a value while the req parameter is a string of an JSON array representing
the arguments passed from the JavaScript function call.

The callback function must has the method `f(seq::String, req::String, [arg::Any])`.
"""
bind_raw(f::Function, w::AbstractWebview, name::AbstractString, arg=nothing) =
    bind_raw(f, w.platform, name, arg)

"""
    bind(f::Function, w::Webview, name::AbstractString)

Binds a callback so that it will appear in the webview with the given name
as a global async JavaScript function. Callback arguments are automatically
converted from json to as closely as possible match the arguments in the
webview context and the callback automatically converts and returns the
return value to the webview.

The callback function must handle a `Tuple` as its argument.
"""
function Base.bind(f::Function, w::AbstractWebview, name::AbstractString)
    bind_raw(w, name) do seq, args, _
        try
            @show seq, args
            result = f(Tuple(args))
            _return(w, seq, true, result)
        catch err
            _return(w, seq, false, err)
        end
        nothing
    end
end

"""
    unbind(w::Webview, name::AbstractString)

Unbinds a previously bound function freeing its resource and removing it from the webview JavaScript context.
"""
function unbind end

"""
    return_raw(w::Webview, seq::String, success::Bool, result_or_err)

Allows to return a value from the native binding. Original request pointer
must be provided to help internal RPC engine match requests with responses.
"""
function return_raw(w::AbstractWebview, seq::Int, success::Bool, result_or_err::AbstractString)
    dispatch(w, nothing) do w, _
        if success
            eval!(w, "window._rpc[$seq].resolve($result_or_err); delete window._rpc[$seq]");
        else
            eval!(w, "window._rpc[$seq].reject($result_or_err); delete window._rpc[$seq]");
        end
    end
end

function _return(w::AbstractWebview, seq::Int, success::Bool, result)
    s = try
        if success
            JSON3.write(result)
        else
            throw(result)
        end
    catch err
        success = false
        JSON3.write(sprint(showerror, err))
    end
    return_raw(w, seq, success, s)
end

"""
    set_timeout(f::Function, w::Webview, interval::Real; [repeat::Bool=false])

Sets a function to be called after the given interval in webview's event loop.
If `repeat` is `true`, the function will be called repeatedly.
This function returns a `timer_id::Ptr{Cvoid}` which can be used in `clear_timeout(webview, timer_id)`.
"""
set_timeout(f::Function, w::AbstractWebview, interval::Real; repeat::Bool=false) =
    set_timeout(f::Function, w.platform, interval; repeat)

"""
    clear_timeout(timer_id::Ptr{Cvoid})

Clears a previously set timeout.
"""
@forward clear_timeout(w, timer_id::Ptr{Cvoid})

const run = Base.run
const size = Base.size
const resize! = Base.resize!
const bind = Base.bind

end
