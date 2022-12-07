# This file is only loaded on non-Windows platforms.

function API.bind_raw(f::Function, w::AbstractWebview, name::AbstractString)
    bind_raw(f, w.callback_handler, name)
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
