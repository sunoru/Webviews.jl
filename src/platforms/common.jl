using Libdl

using ..Consts
using ..Consts: TIMEOUT_INTEVAL,
    WebviewStatus, WEBVIEW_PENDING, WEBVIEW_RUNNING, WEBVIEW_DESTORYED
using ..API
using ..API: AbstractPlatformImpl
using ..Utils: CallbackHandler, on_message

_event_loop_timeout(_...) = (yield(); nothing)
