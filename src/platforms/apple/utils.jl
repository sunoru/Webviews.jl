get_shared_application() = @msg_send ID a"NSApplication"cls a"sharedApplication"sel

function get_associated_webview(self::ID)
    w = @ccall objc_getAssociatedObject(
        self::ID,
        ASSOCIATED_KEY::Cstring
    )::ID
    unsafe_pointer_to_objref(Ptr{Webview}(w))
end

function create_app_delegate()
    cls = @ccall objc_allocateClassPair(a"NSResponder"cls::ID, "WebviewAppDelegate"::Cstring, 0::Int)::ID
    @ccall class_addProtocol(
        cls::ID,
        (@ccall objc_getProtocol("NSTouchBarProvider"::Cstring)::ID)::ID
    )::Bool
    @ccall class_addMethod(
        cls::ID,
        a"applicationShouldTerminateAfterLastWindowClosed:"sel::SEL,
        @cfunction(
            (self, _2, _3) -> begin
                _terminate()
                false
            end,
            Bool, (ID, SEL, ID)
        )::Ptr{Cvoid},
        "c@:@"::Cstring
    )::Bool
    @ccall objc_registerClassPair(cls::ID)::Ptr{Cvoid}
    @msg_send ID cls a"new"sel
end

function get_window_delegate_class()
    cls = @ccall objc_getClass("WebviewWindowDelegate"::Cstring)::ID
    cls == C_NULL || return cls
    cls = @ccall objc_allocateClassPair(a"NSResponder"cls::ID, "WebviewWindowDelegate"::Cstring, 0::Int)::ID
    @ccall class_addProtocol(
        cls::ID,
        (@ccall objc_getProtocol("NSWindowDelegate"::Cstring)::ID)::ID
    )::Bool
    @ccall class_addMethod(
        cls::ID,
        a"windowWillClose:"sel::SEL,
        @cfunction(
            (self, _2, _3) -> begin
                w = get_associated_webview(self)
                window = window_handle(w)
                Webviews.on_window_close(window)
            end,
            Cvoid, (ID, SEL, ID)
        )::Ptr{Cvoid},
        "v@:@"::Cstring
    )::Bool
    @ccall objc_registerClassPair(cls::ID)::Cvoid
    cls
end
function create_window_delegate(w::Webview)
    cls = get_window_delegate_class()
    instance = @msg_send ID cls a"new"sel
    @ccall objc_setAssociatedObject(
        instance::ID,
        ASSOCIATED_KEY::Cstring,
        pointer_from_objref(w)::ID,
        0::UInt  # OBJC_ASSOCIATION_ASSIGN
    )::ID
    instance
end

function get_webkit_ui_delegate_class()
    cls = @ccall objc_getClass("WebkitUIDelegate"::Cstring)::ID
    cls == C_NULL || return cls
    cls = @ccall objc_allocateClassPair(a"NSObject"cls::ID, "WebkitUIDelegate"::Cstring, 0::Int)::ID
    @ccall class_addProtocol(
        cls::ID,
        (@ccall objc_getProtocol("WKUIDelegate"::Cstring)::ID)::ID
    )::Bool
    @ccall class_addMethod(
        cls::ID,
        a"webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:"sel::SEL,
        @cfunction(
            (_1, _2, _3, parameters, _5, completion_handler) -> begin
                allows_multiple_selection = @msg_send Bool parameters a"allowsMultipleSelection"sel
                allows_directories = @msg_send Bool parameters a"allowsDirectories"sel
                # Show a panel for selecting files.
                panel = @msg_send ID a"NSOpenPanel"cls a"openPanel"sel
                @msg_send Cvoid panel a"setCanChooseFiles:"sel true::Bool
                @msg_send Cvoid panel a"setCanChooseDirectories:"sel allows_directories
                @msg_send Cvoid panel a"setAllowsMultipleSelection:"sel allows_multiple_selection
                modal_response = @msg_send Int panel a"runModal"sel
                urls = if modal_response == 1  # NSModalResponseOK
                    @msg_send ID panel a"URLs"sel
                else
                    C_NULL
                end
                url_ref = Ref(urls)
                # Invoke the completion handler block.
                sig = @msg_send ID a"NSMethodSignature"cls a"signatureWithObjCTypes:"sel "v@?@"::Cstring
                invocation = @msg_send ID a"NSInvocation"cls a"invocationWithMethodSignature:"sel sig
                @msg_send Cvoid invocation a"setTarget:"sel completion_handler
                @msg_send Cvoid invocation a"setArgument:atIndex:"sel url_ref 1::Int
                @msg_send Cvoid invocation a"invoke"sel
            end,
            Cvoid, (ID, SEL, ID, ID, ID, ID)
        )::Ptr{Cvoid},
        "v@:@@@@"::Cstring
    )::Bool
    @ccall objc_registerClassPair(cls::ID)::Cvoid
    cls
end
function create_webkit_ui_delegate()
    cls = get_webkit_ui_delegate_class()
    @msg_send ID cls a"new"sel
end

function get_script_message_handler_class()
    cls = @ccall objc_getClass("WebkitScriptMessageHandler"::Cstring)::ID
    cls == C_NULL || return cls
    cls = @ccall objc_allocateClassPair(a"NSResponder"cls::ID, "WebkitScriptMessageHandler"::Cstring, 0::Int)::ID
    @ccall class_addProtocol(
        cls::ID,
        (@ccall objc_getProtocol("WKScriptMessageHandler"::Cstring)::ID)::ID
    )::Bool
    @ccall class_addMethod(
        cls::ID,
        a"userContentController:didReceiveScriptMessage:"sel::SEL,
        @cfunction(
            (self, _2, _3, msg) -> begin
                w = get_associated_webview(self)
                s = @msg_send(
                    Ptr{Cchar},
                    (@msg_send ID msg a"body"sel),
                    a"UTF8String"sel
                )
                on_message(w.callback_handler, s)
            end,
            Cvoid, (ID, SEL, ID, ID)
        )::Ptr{Cvoid},
        "v@:@@"::Cstring
    )::Bool
    @ccall objc_registerClassPair(cls::ID)::Cvoid
    cls
end
function create_script_message_handler(w::Webview)
    cls = get_script_message_handler_class()
    instance = @msg_send ID cls a"new"sel
    @ccall objc_setAssociatedObject(
        instance::ID,
        ASSOCIATED_KEY::Cstring,
        pointer_from_objref(w)::ID,
        0::UInt  # OBJC_ASSOCIATION_ASSIGN
    )::ID
    instance
end

get_main_bundle() = @msg_send ID a"NSBundle"cls a"mainBundle"sel

function is_app_bundled()
    bundle = get_main_bundle()
    bundle ≡ C_NULL && return false
    bundle_path = @msg_send ID bundle a"bundlePath"sel
    bundled = @msg_send Bool bundle_path a"hasSuffix:"sel a".app"str
end

function on_application_did_finish_launching(w::Webview, app::ID)
    if w.parent_window ≡ C_NULL
        @msg_send Cvoid app a"stop:"sel C_NULL
    end
    if !is_app_bundled()
        @msg_send Cvoid app a"setActivationPolicy:"sel 0::Int  # NSApplicationActivationPolicyRegular
        @msg_send Cvoid app a"activateIgnoringOtherApps:"sel true::Bool
    end

    # Main window
    window = w.window = if w.parent_window ≡ C_NULL
        @msg_send(
            ID,
            (@msg_send ID a"NSWindow"cls a"alloc"sel),
            a"initWithContentRect:styleMask:backing:defer:"sel,
            CGRect(0, 0, 0, 0)::CGRect,
            NSWindowStyleMaskTitled::UInt,
            2::UInt,
            false::Bool
        )
    else
        w.parent_window
    end
    create_window_delegate(w)

    # Webview
    config = w.config = @msg_send ID a"WKWebViewConfiguration"cls a"new"sel
    manager = w.manager = @msg_send ID config a"userContentController"sel
    webview = w.webview = @msg_send ID a"WKWebView"cls a"alloc"sel
    if w.debug
        @msg_send(
            ID,
            (@msg_send ID config a"preferences"sel),
            a"setValue:forKey:"sel,
            (@msg_send ID a"NSNumber"cls a"numberWithBool:"sel true::Bool),
            a"developerExtrasEnabled"str
        )
    end
    @msg_send(
        ID,
        (@msg_send ID config a"preferences"sel),
        a"setValue:forKey:"sel,
        (@msg_send ID a"NSNumber"cls a"numberWithBool:"sel true::Bool),
        a"fullScreenEnabled"str
    )
    @msg_send(
        ID,
        (@msg_send ID config a"preferences"sel),
        a"setValue:forKey:"sel,
        (@msg_send ID a"NSNumber"cls a"numberWithBool:"sel true::Bool),
        a"javaScriptCanAccessClipboard"str
    )
    @msg_send(
        ID,
        (@msg_send ID config a"preferences"sel),
        a"setValue:forKey:"sel,
        (@msg_send ID a"NSNumber"cls a"numberWithBool:"sel true::Bool),
        a"DOMPasteAllowed"str
    )

    ui_delegate = create_webkit_ui_delegate()
    @msg_send(
        Cvoid,
        webview,
        a"initWithFrame:configuration:"sel,
        CGRect(0, 0, 0, 0)::CGRect,
        config
    )
    @msg_send Cvoid webview a"setUIDelegate:"sel ui_delegate
    script_message_handler = create_script_message_handler(w);
    @msg_send Cvoid manager a"addScriptMessageHandler:name:"sel script_message_handler a"external"str

    init!(w, "window.external={invoke:function(s){window.webkit.messageHandlers.external.postMessage(s);}}")
    @msg_send Cvoid window a"setContentView:"sel webview
    @msg_send Cvoid window a"makeKeyAndOrderFront:"sel C_NULL
end
