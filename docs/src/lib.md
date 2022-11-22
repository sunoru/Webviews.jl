# Library

## Index

```@index
Pages = ["lib.md"]
```

## Public Interface

```@docs
Webviews
Webview
WindowSizeHint
run(::Webview)
terminate
destroy
window_handle
title!
resize!(::Webview)
sizehint!(::Webview, ::WindowSizeHint)
navigate!
html!
init!
eval!
bind(::Function, ::Webview, ::AbstractString)
unbind
```