using Libdl

using JSON3: JSON3

using ..Consts
using ..Consts: TIMEOUT_INTERVAL
using ..API
using ..API: AbstractWebview, AbstractPlatformImpl
using ..Utils: CallbackHandler, on_message,
    setup_dispatch, call_dispatch, clear_dispatch,
    set_dispatch_id

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
