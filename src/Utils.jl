module Utils

using FunctionWrappers: FunctionWrapper
using JSON3: JSON3

using ..API
using ..API: AbstractWebview, AbstractPlatformImpl

# JuliaLang/julia #269
mutable struct DispatchedFunction{T}
    const func::FunctionWrapper{Nothing,Tuple{}}
    const ch::T
end

mutable struct CallbackHandler
    const callbacks::Dict{String,FunctionWrapper{Nothing,Tuple{Int,Vector{Any}}}}
    # func -> seq
    const dispatched::Dict{DispatchedFunction{CallbackHandler}, UInt64}
    CallbackHandler() = new(Dict(), Dict())
end


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

function API.bind_raw(f::Function, ch::CallbackHandler, name::AbstractString, arg=nothing)
    haskey(ch.callbacks, name) && return
    ch.callbacks[name] = FunctionWrapper{Nothing,Tuple{Int,Vector{Any}}}() do seq, args
        f(seq, args, arg)
        nothing
    end
    nothing
end

function API.unbind(ch::CallbackHandler, name::AbstractString)
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
    df = DispatchedFunction{CallbackHandler}(func, ch)
    ch.dispatched[df] = 0
    ptr = pointer_from_objref(df)
end

function call_dispatch(ptr::Ptr{Cvoid})
    df = unsafe_load(Ptr{DispatchedFunction}(ptr))
    df.func()
end

function clear_dispatch(ptr::Ptr{Cvoid})
    dispatched = df.ch.dispatched
    df = unsafe_load(Ptr{DispatchedFunction}(ptr))
    haskey(dispatched, df) || return nothing
    id = dispatched[df]
    delete!(dispatched, df)
    id
end

end
