module Consts

export HOST_OS_ARCH,
    WebviewPlatform,
    WEBVIEW_COCOA, WEBVIEW_GTK, WEBVIEW_EDGE,
    WEBVIEW_PLATFORM,
    WindowSizeHint,
    WEBVIEW_HINT_NONE, WEBVIEW_HINT_MIN, WEBVIEW_HINT_MAX, WEBVIEW_HINT_FIXED

const HOST_OS_ARCH = let hp = Base.BinaryPlatforms.HostPlatform()
    Base.BinaryPlatforms.os(hp), Base.BinaryPlatforms.arch(hp)
end
@enum WebviewPlatform begin
    WEBVIEW_COCOA
    WEBVIEW_GTK
    WEBVIEW_EDGE
end
const WEBVIEW_PLATFORM = @static if Sys.isapple()
    WEBVIEW_COCOA
elseif Sys.iswindows()
    WEBVIEW_EDGE
else
    WEBVIEW_GTK
end

"""
    WindowSizeHint

Enum to specify the window size hint.
Values:
- `WEBVIEW_HINT_NONE`: Width and height are default size.
- `WEBVIEW_HINT_MIN`: Width and height are minimum bounds.
- `WEBVIEW_HINT_MAX`: Width and height are maximum bounds.
- `WEBVIEW_HINT_FIXED`: Window size can not be changed by a user.
"""
@enum WindowSizeHint begin
    WEBVIEW_HINT_NONE = 0
    WEBVIEW_HINT_MIN = 1
    WEBVIEW_HINT_MAX = 2
    WEBVIEW_HINT_FIXED = 3
end

const TIMEOUT_INTEVAL = 1000 ÷ 30

@enum WebviewStatus begin
    WEBVIEW_PENDING
    WEBVIEW_RUNNING
    WEBVIEW_DESTORYED
end

end