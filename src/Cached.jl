module Cached





using Serialization
using SQLite
using Distributed
using ProgressMeter


export AbstractCache, DictCache, FileCache, SQLiteCache, cmap, pcmap, wrap_cache



include("CacheTypes.jl")
include("cmap.jl")


end
