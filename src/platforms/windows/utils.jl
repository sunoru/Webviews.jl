using Libc: Libc
using Pkg.Artifacts: @artifact_str

const libwebview2loader = joinpath(artifact"webview2_loader", "WebView2Loader.dll")

macro wcall(library, expr)
    if expr.head ≡ :call
        expr = :($expr::Cvoid)
    end
    @assert expr.head ≡ :(::) && expr.args[1].head ≡ :call
    expr.args[1].args[1] = :($library.$(expr.args[1].args[1]))
    :(@ccall $expr) |> esc
end
macro wcall(expr)
    :(@wcall(libwebview2loader, $expr)) |> esc
end

get_cglobal((symbol, library), type=Cvoid) = try
    Libc.dlopen(library) do hdl
        Libc.dlsym_e(hdl, symbol) |> Ptr{type}
    end
catch
    return Ptr{type}(C_NULL)
end

function is_webview2_available()
    version_info = Ref{Cwstring}(C_NULL)
    ret = @wcall GetAvailableCoreWebView2BrowserVersionString(
        C_NULL::Ptr{Cvoid},
        version_info::Ptr{Cwstring}
    )::Clong
    ok = @SUCCEEDED(ret) && version_info[] ≢ C_NULL
    if version_info[] ≢ C_NULL
        @wcall CoTaskMemFree(version_info[]::Ptr{Cvoid})
    end
    ok
end


function enable_dpi_awareness()
    fn = get_cglobal((:SetProcessDpiAwarenessContext, "user32.dll"))
    if fn ≢ C_NULL
        ccall(
            fn, Bool, (DPI_AWARENESS_CONTEXT,),
            DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE
        ) && return true
        return ERROR_ACCESS_DENIED == @ccall GetLastError()::Cint
    end
    fn = get_cglobal((:SetProcessDpiAwareness, "shcore.dll"))
    if fn ≢ C_NULL
        ret = ccall(
            fn, HRESULT, (Cint,),
            PROCESS_PER_MONITOR_DPI_AWARE
        )
        return ret == S_OK || ret == E_ACCESSDENIED
    end
    fn = get_cglobal((:SetProcessDPIAware, "user32.dll"))
    fn ≡ C_NULL || ccall(fn, Bool, ())
end

function _window_proc(hwnd::HWND, msg::Cuint, wp::WPARAM, lp::LPARAM)
    ptr = @wcall "user32" GetWindowLongPtrW(hwnd::HWND, GWLP_USERDATA::Cint)::Ptr{Webview}
    ptr == C_NULL && return 0
    w = unsafe_pointer_to_objref(ptr)
    if msg == WM_SIZE
        _resize(w, hwnd)
    elseif msg == WM_CLOSE
        @wcall "user32" DestroyWindow(hwnd::HWND)
    elseif msg == WM_DESTROY
        terminate(w)
    elseif msg == WM_GETMINMAXINFO
        lpmmi = unsafe_wrap(Array, Ptr{Clong}(lp), 10)
        mx, my = w.max_size.x, w.max_size.y
        if mx > 0 && my > 0
            # ptMaxSize
            lpmmi[3], lpmmi[4] = mx, my
            # ptMaxTrackSize
            lpmmi[9], lpmmi[10] = mx, my
        end
        mx, my = w.min_size.x, w.min_size.y
    else
        return @wcall "user32" DefWindowProcW(hwnd::HWND, msg::cuint, wp::WPARAM, lp::LPARAM)::LRESULT
    end
    return 0

end

function create_window(w::Webview)
    h_instance = @ccall "kernel32" GetModuleHandleW(C_NULL::Ptr{Cvoid})::HINSTANCE
    icon = @ccall LoadImageW(
        h_instance::HINSTANCE,
        IDI_APPLICATION::Cwstring,
        IMAGE_ICON::Cuint,
        @call GetSystemMetrics(SM_CXICON::Cint)::Cint,
        @call GetSystemMetrics(SM_CYICON::Cint)::Cint,
        LR_DEFAULTSIZE::Cuint
    )::HICON
    name = Base.cconvert(Cwstring, "webview")
    wc = Ref(WNDCLASSEXW(
        cbSize = sizeof(WNDCLASSEXW),
        hInstance = h_instance,
        lpszClassName = Base.unsafe_convert(Cwstring, name),
        hIcon = icon,
        lpfnWndProc = @cfunction(_window_proc, LRESULT, (HWND, Cuint, WPARAM, LPARAM))
    ))
    @wcall "user32" RegisterClassExW(wc::Ptr{WNDCLASSEXW})
    window = @wcall "user32" CreateWindowExW(
        "webview"::Cwstring,
        ""::Cwstring,
        WS_OVERLAPPEDWINDOW::Culong,
        CW_USEDEFAULT::Cint,
        CW_USEDEFAULT::Cint,
        640::Cint,
        480::Cint,
        C_NULL::HWND,
        C_NULL::HMENU,
        h_instance::HINSTANCE,
        C_NULL::Ptr{Cvoid}
    )::HWND
    window ≡ C_NULL && error("Failed to create window")
    ptr = pointer_from_objref(w) |> LONG_PTR
    @wcall "user32" SetWindowLongPtrW(window::HWND, GWLP_USERDATA::Cint, ptr::LONG_PTR)
    window
end
