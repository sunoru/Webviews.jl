module Utils

using FunctionWrappers: FunctionWrapper
using JSON3: JSON3

const MessageCallback = FunctionWrapper{Nothing,Tuple{Int,Vector{Any}}}

# JuliaLang/julia #269
mutable struct _DispatchCallback{T}
    const func::FunctionWrapper{Nothing,Tuple{}}
    const ch::T
end

mutable struct CallbackHandler
    const callbacks::Dict{String,MessageCallback}
    # func -> seq
    const dispatched::Dict{_DispatchCallback{CallbackHandler}, UInt64}

    CallbackHandler() = new(Dict(), Dict())
end
const DispatchCallback = _DispatchCallback{CallbackHandler}

function on_message(ch::CallbackHandler, s::Ptr{Cchar})
    try
        msg = JSON3.read(unsafe_string(s))
        name = msg.method
        haskey(ch.callbacks, name) || return
        seq = msg.id
        args = msg.params
        f = ch.callbacks[name]
        f(seq, copy(args))
    catch e
        @debug "Error occured while handling message: $e"
    end
    nothing
end

function bind_raw(f::Function, ch::CallbackHandler, name::AbstractString)
    haskey(ch.callbacks, name) && return
    ch.callbacks[name] = MessageCallback() do seq, args
        f(seq, args)
        nothing
    end
    nothing
end

function unbind(ch::CallbackHandler, name::AbstractString)
    delete!(ch.callbacks, name)
    nothing
end

# Returns a pointer to the function wrapper as the ID.
function setup_dispatch(f::Function, ch::CallbackHandler)
    func = FunctionWrapper{Nothing,Tuple{}}() do
        try
            f()
        catch e
            @debug "Error occured while dispatching: $e"
        end
        nothing
    end
    dcb = DispatchCallback(func, ch)
    ch.dispatched[dcb] = 0
    ptr = pointer_from_objref(dcb)
end

function set_dispatch_id(ptr::Ptr{Cvoid}, id::Integer)
    dcb = unsafe_pointer_to_objref(ptr)::DispatchCallback
    dcb.ch.dispatched[dcb] = UInt64(id)
    nothing
end

function call_dispatch(ptr::Ptr{Cvoid})
    dcb = unsafe_pointer_to_objref(ptr)::DispatchCallback
    dcb.func()
end

function clear_dispatch(ptr::Ptr{Cvoid})
    dcb = unsafe_pointer_to_objref(ptr)::DispatchCallback
    dispatched = dcb.ch.dispatched
    haskey(dispatched, dcb) || return nothing
    id = dispatched[dcb]
    delete!(dispatched, dcb)
    id
end

end
