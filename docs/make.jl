using Cached
using Documenter

DocMeta.setdocmeta!(Cached, :DocTestSetup, :(using Cached); recursive=true)

makedocs(;
    modules=[Cached],
    authors="Peter Arndt <arndt@molgen.mpg.de> and contributors",
    sitename="Cached.jl",
    format=Documenter.HTML(;
        canonical="https://ArndtLab.github.io/Cached.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
    warnonly=[:missing_docs],
)

deploydocs(;
    repo="github.com/ArndtLab/Cached.jl",
    devbranch="main",
)
