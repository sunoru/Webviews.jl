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
dispatch
window_handle
title!
resize!(::Webview, ::Tuple{Integer, Integer}; hint::WindowSizeHint)
navigate!
html!
init!
eval!
bind_raw
bind(::Function, ::Webview, ::AbstractString)
unbind
return_raw
set_timeout
clear_timeout
```