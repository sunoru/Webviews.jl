# Examples of Webviews.jl

| Example | Description |
| ------- | ----------- |
| [bind](./bind.jl) | Bind Julia functions and call them from JavaScript. |
| [multiple](./multiple.jl) | Create multiple webviews. |
| [server](./server.jl) | Create a HTTP server asychronously and access it from Webview. |

## Usage

It is recommended to use the environment for running the examples:

```bash
$ julia --project=@. -e 'using Pkg; Pkg.instantiate()'
$ julia --project=@. ./server.jl
```
