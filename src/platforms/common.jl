using Libdl

using FunctionWrappers: FunctionWrapper
using JSON3: JSON3

using ..Consts
using ..Consts: TIMEOUT_INTERVAL
using ..API
using ..API: AbstractWebview, AbstractPlatformImpl
using ..Utils: CallbackHandler, on_message,
    setup_dispatch, call_dispatch, clear_dispatch

_event_loop_timeout(_...) = (yield(); nothing)

function _check_dependency(lib)
    hdl = nothing
    try
        hdl = Libdl.dlopen(lib)
        return true
    catch
        @warn "Failed to load $lib"
        return false
    finally
        Libdl.dlclose(hdl)
    end
end

@static if !Sys.iswindows()

# Since we are using a workaround on Windows, the following is only defined otherwise.
function API.bind_raw(f::Function, w::AbstractPlatformImpl, name::AbstractString, arg=nothing)
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

API.unbind(w::AbstractWebview, name::AbstractString) = unbind(w.callback_handler, name)

end
