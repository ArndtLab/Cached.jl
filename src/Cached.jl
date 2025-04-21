module Cached





using Serialization
using SQLite
using Distributed
using ProgressMeter


export DictCache, FileCache, SQLiteCache, cmap, pcmap



include("CacheTypes.jl")
include("cmap.jl")


end
