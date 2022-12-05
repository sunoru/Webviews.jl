module WindowsImpl

include("../common.jl")
include("./win_types.jl")

check_dependency() = _check_dependency(libwebview2loader) && is_webview2_available()
setup_platform() = nothing

mutable struct ComInit
    initialized::Bool
    function ComInit()
        ret = @wcall CoInitializeEx(C_NULL::Ptr{Cvoid}, COINIT_APARTMENTTHREADED::Culong)::HRESULT
        ci_new = new(ret == S_OK || ret == S_FALSE)
        finalizer(ci_new) do ci
            ci.initialized || return
            @wcall CoUninitialize()
            ci.initialized = false;
        end
    end
end

mutable struct Webview <: AbstractPlatformImpl
    const window::HWND
    com_init::ComInit
    max_size::POINT
    min_size::POINT
    function Webview(
        callback_handler::CallbackHandler,
        debug::Bool,
        unsafe_window_handle::Ptr{Cvoid}
    )
        com_init = ComInit()
        com_init.initialized || error("Failed to initialize COM")
        enable_dpi_awareness()
        w = new()
        w.com_init = com_init
        w.max_size = POINT()
        w.min_size = POINT()
        window = if unsafe_window_handle ≡ C_NULL
            create_window(w)
        else
            unsafe_window_handle
        end
        w.window = window
        @wcall "user32" ShowWindow(window::HWND, SW_SHOW::Cint)::Bool
        @wcall "user32" UpdateWindow(window::HWND)::Bool
        @wcall "user32" SetFocus(window::HWND)
        embed(window, debug, callback_handler)
        _resize(w, window)

    # m_controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    end

end

include("./utils.jl")

end
