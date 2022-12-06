module Utils

using JSON3: JSON3

using ..API

mutable struct CallbackHandler
    const callbacks::Dict{String,Base.RefValue{Tuple{Function,Any}}}
    CallbackHandler() = new(Dict())
end

function on_message(ch::CallbackHandler, s::Ptr{Cchar})
    try
        msg = JSON3.read(unsafe_string(s))
        name = msg.method
        haskey(ch.callbacks, name) || return
        seq = msg.id
        args = msg.params
        f, arg = ch.callbacks[name][]
        f(seq, copy(args), arg)
    catch e
        @debug "Error occured while handling message: $e"
    end
    nothing
end

function API.bind_raw(f::Function, ch::CallbackHandler, name::AbstractString, arg=nothing)
    haskey(ch.callbacks, name) && return
    ch.callbacks[name] = Ref{Tuple{Function,Any}}((f, arg))
    nothing
end

function API.unbind(ch::CallbackHandler, name::AbstractString)
    delete!(ch.callbacks, name)
    nothing
end

end
