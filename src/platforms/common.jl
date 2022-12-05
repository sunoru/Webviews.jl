using Libdl

using ..Consts
using ..Consts: TIMEOUT_INTEVAL,
    WebviewStatus, WEBVIEW_PENDING, WEBVIEW_RUNNING, WEBVIEW_DESTORYED
using ..API
using ..API: AbstractPlatformImpl
using ..Utils: CallbackHandler, on_message, get_cglobal

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