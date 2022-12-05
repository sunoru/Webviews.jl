module API

export terminate,
    destroy,
    dispatch,
    window_handle,
    title!,
    sizehint,
    navigate!,
    html!,
    init!,
    eval!,
    bind_raw,
    return_raw,
    unbind

using JSON3: JSON3

using ..Consts
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

@forward is_destroyed(w)

"""
    destroy(w::Webview)

Destroys the webview and closes the window along with freeing all internal resources.
"""
function destroy(w::AbstractWebview)
    is_destroyed(w) && return
    for key in keys(w.callback_handler.callbacks)
        unbind(w, key)
    end
    terminate(w)
    destroy(w.platform)
    nothing
end
destroy(::AbstractPlatformImpl) = nothing

"""
    run(w::Webview)

Runs the webview event loop. Runs the main event loop until it's terminated.
After this function exits, the webview is automatically destroyed.
"""
function Base.run(w::AbstractWebview)
    is_destroyed(w) && error("Webview is already destroyed")
    run(w.platform)
    destroy(w)
end

"""
    dispatch(f::Function, w, arg)

Posts a function to be executed on the main thread. You normally do not need
to call this function, unless you want to tweak the native window.
"""
function dispatch(f::Function, w::AbstractWebview, arg)
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
    size::Tuple{Integer, Integer}=size(w);
    hint::Union{WindowSizeHint, Nothing}=nothing
)
    if isnothing(hint)
        hint = sizehint(w)
        if hint ≡ WEBVIEW_HINT_MIN || hint ≡ WEBVIEW_HINT_MAX
            hint = WEBVIEW_HINT_NONE
        end
    end
    resize!(w.platform, size, hint=hint)
    w
end

"""
    sizehint(w::Webview)

Gets the native window size hint.
"""
@forward sizehint(w)

"""
    sizehint!(w::Webview, hint::WindowSizeHint)

Sets the native window size hint.
"""
Base.sizehint!(w, hint::WindowSizeHint) = resize!(w; hint)

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
function bind_raw(f::Function, w::AbstractWebview, name::AbstractString, arg=nothing)
    bind_raw(f, w.callback_handler, name, arg)
    js = "((function() { var name = '$name';
      var RPC = window._rpc = (window._rpc || {nextSeq: 1});
      window[name] = function() {
        var seq = RPC.nextSeq++;
        var promise = new Promise(function(resolve, reject) {
          RPC[seq] = {
            resolve: resolve,
            reject: reject,
          };
        });
        window.external.invoke(JSON.stringify({
          id: seq,
          method: name,
          params: Array.prototype.slice.call(arguments),
        }));
        return promise;
      }
    })())"
    init!(w, js)
    eval!(w, js)
    nothing
end

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
            result = f(Tuple(args))
            _return(w, seq, true, result)
        catch err
            _return(w, seq, false, err)
        end
    end
end

"""
    unbind(w::Webview, name::AbstractString)

Unbinds a previously bound function freeing its resource and removing it from the webview JavaScript context.
"""
unbind(w, name::AbstractString) = unbind(w.callback_handler, name)

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

const run = Base.run
const size = Base.size
const resize! = Base.resize!
const sizehint! = Base.sizehint!
const bind = Base.bind

end
