struct POINT
    x::Clong
    y::Clong
end

struct RECT
    left::Clong
    top::Clong
    right::Clong
    bottom::Clong
end

const DWORD = Culong
const WM_APP = 0x8000
const WM_QUIT = 0x0012
const WM_TIMER = 0x0113

const UINT_PTR = UInt
const LONG_PTR = Int
const WPARAM = UINT_PTR
const LPARAM = LONG_PTR

const HANDLE = Ptr{Cvoid}
const HWND = HANDLE

struct MSG
    hwnd::HWND
    message::Cuint
    wParam::WPARAM
    lParam::LPARAM
    time::DWORD
    pt::POINT
    lPrivate::DWORD
end
