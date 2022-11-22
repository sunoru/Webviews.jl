using Documenter
using Webviews

makedocs(
    sitename = "Webviews",
    format = Documenter.HTML(),
    modules = [Webviews]
)

deploydocs(
    repo = "github.com/sunoru/Webviews.jl.git"
)
