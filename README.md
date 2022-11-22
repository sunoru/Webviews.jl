# Webviews.jl

[![CI Test](https://github.com/sunoru/Webviews.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/sunoru/Webviews.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/sunoru/WebViews.jl/branch/main/graph/badge.svg?token=55lxcNYhBO)](https://codecov.io/gh/sunoru/WebViews.jl)
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://sunoru.github.io/Webviews.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://sunoru.github.io/Webviews.jl/dev)

Julia wrappers for [webview](https://github.com/webview/webview),
a tiny cross-platform webview library.

## Installation & Dependencies

`Webviews.jl` requires Julia v1.8 or later on Windows and macOS, and Julia v1.9 or later on Linux.

You can install this package with Julia's package manager:

```julia
(@v1.8) pkg> add Webviews
```

For Linux users, you need to install the following dependencies:

```bash
# Fedora
sudo dnf install gtk3-devel webkit2gtk3-devel
# Debian/Ubuntu
sudo apt install libwebkit2gtk-4.0-dev
# Arch Linux
sudo pacman -S webkit2gtk
```

**Note**: `Webviews.jl` downloads its own prebuilt binaries and depends on libraries that are provided by the operating system, instead of using JLL packages.

## Usage

See the [docs](https://sunoru.github.io/Webviews.jl/dev/) or [examples](./examples/).

## LICENSE
[MIT License](./LICENSE).
