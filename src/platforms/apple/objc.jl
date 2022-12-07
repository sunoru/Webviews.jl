const ID = Ptr{Cvoid}
const SEL = Ptr{Cvoid}
const UnsafeRawPointer = Ptr{Cvoid}

function _msg_send(args...; is_stret)
    rettype, args = args[1], collect(Any, args[2:end])
    for i in eachindex(args)
        argi = args[i]
        if argi isa Expr && argi.head ≡ :(::)
            args[i] = :($(esc(argi.args[1]))::$(esc(argi.args[2])))
        else
            args[i] = :($(esc(argi))::Ptr{Cvoid})
        end
    end
    if is_stret
        :(let result = Ref{$rettype}()
            @ccall objc_msgSend_stret(result::Ptr{$rettype}, $(args...))::Cvoid
            result[]::$rettype
        end)
    else
        :(@ccall objc_msgSend($(args...))::$rettype)
    end
end

macro msg_send(args...)
    _msg_send(args...; is_stret=false)
end
macro msg_send_stret(args...)
    _msg_send(args...; is_stret=true)
end

macro a_str(s, ss)
    s = esc(s)
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
struct CGPoint
    x::CGFloat
    y::CGFloat
end
struct CGSize
    width::CGFloat
    height::CGFloat
end
struct CGRect
    origin::CGPoint
    size::CGSize
end
CGRect(x, y, width, height) = CGRect(CGPoint(x, y), CGSize(width, height))

# @enum NSWindowStyleMask::UInt
const NSWindowStyleMaskTitled = UInt(1)
const NSWindowStyleMaskClosable = UInt(2)
const NSWindowStyleMaskMiniaturizable = UInt(4)
const NSWindowStyleMaskResizable = UInt(8)
