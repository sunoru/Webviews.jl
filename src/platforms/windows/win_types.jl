const HRESULT = Clong
const LRESULT = Clong
const S_OK = 0x00000000
const S_FALSE = 0x00000001
const E_ACCESSDENIED = 0x80070005

macro SUCCEEDED(expr)
    :(HRESULT($(esc(expr))) ≥ 0)
end

const HANDLE = Ptr{Cvoid}
const HINSTANCE = HANDLE
const HMODULE = HANDLE
const HICON = HANDLE
const HCURSOR = HANDLE
const HBRUSH = HANDLE
const HWND = HANDLE

const LONG_PTR = Int
const UINT_PTR = UInt
const WPARAM = UINT_PTR
const LPARAM = LONG_PTR

const COINIT_APARTMENTTHREADED = 0x2

const DPI_AWARENESS_CONTEXT = HANDLE
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE = DPI_AWARENESS_CONTEXT(-3)
const ERROR_ACCESS_DENIED = 0x5
const PROCESS_PER_MONITOR_DPI_AWARE = 2

const IDI_APPLICATION = Cwstring(32512)
const IMAGE_ICON = 1
const SM_CXICON = 11
const SM_CYICON = 12
const LR_DEFAULTCOLOR = 0x00000040

Base.@kwdef struct WNDCLASSEXW
    cbSize::Cuint = 0
    style::Cuint = 0
    lpfnWndProc::HANDLE = C_NULL
    cbClsExtra::Cint = 0
    cbWndExtra::Cint = 0
    hInstance::HINSTANCE = C_NULL
    hIcon::HICON = C_NULL
    hCursor::HCURSOR = C_NULL
    hbrBackground::HBRUSH = C_NULL
    lpszMenuName::Cwstring = C_NULL
    lpszClassName::Cwstring = C_NULL
    hIconSm::HICON = C_NULL
end

const GWLP_USERDATA = -21
const WM_DESTROY = 0x0002
const WM_SIZE = 0x0005
const WM_CLOSE = 0x0010
const WM_GETMINMAXINFO = 0x0024

Base.@kwdef struct POINT
    x::Clong = 0
    y::Clong = 0
end

struct MINMAXINFO
    ptReserved::POINT
    ptMaxSize::POINT
    ptMaxPosition::POINT
    ptMinTrackSize::POINT
    ptMaxTrackSize::POINT
end

const WS_OVERLAPPED	= 0x00000000
const WS_CAPTION = 0x00C00000
const WS_SYSMENU = 0x00080000
const WS_THICKFRAME = 0x00040000
const WS_MINIMIZEBOX = 0x00020000
const WS_MAXIMIZEBOX = 0x00010000
const WS_OVERLAPPEDWINDOW = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX

const CW_USERDEFAULT = 0x80000000

const SW_SHOW = 5
