const ID = Ptr{Cvoid}
const SEL = Ptr{Cvoid}

macro msg_send(args...)
    rettype, args = args[1], collect(args[2:end])
    for i in eachindex(args)
        if args[i].head ≡ :(::)
            args[i] = :($(esc(args[i].args[1]))::$(esc(args[i].args[2])))
        else
            args[i] = :($(esc(args[i]))::Ptr{Cvoid})
        end
    end
    quote
        @ccall objc_msgSend($(args...))::$rettype
    end
end

macro a_str(s, ss)
    func = if ss == "sel"
        :sel_registerName
    elseif ss == "cls"
        :objc_getClass
    elseif ss == "str"
        return :(@msg_send ID a"NSString"cls a"stringWithUTF8String:"sel $s::Cstring)
    else
        error("Unknown selector type: $ss")
    end |> QuoteNode
    quote
        ccall($func, Ptr{Cvoid}, (Cstring,), $s)
    end
end

const CGFloat = @static Sys.WORD_SIZE == 64 ? Float64 : Float32

@enum NSWindowStyleMask::UInt begin
    NSWindowStyleMaskTitled = 1,
    NSWindowStyleMaskClosable = 2,
    NSWindowStyleMaskMiniaturizable = 4,
    NSWindowStyleMaskResizable = 8
end