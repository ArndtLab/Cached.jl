abstract type AbstractCache end


Base.show(io::IO, cache::AbstractCache) = print(io, "$(typeof(cache))")


function setindices!(cache::AbstractCache, keys::Vector{UInt}, values::AbstractVector)
    for (key, value) in zip(keys, values)
        cache[key] = value
    end
end

function setindices!(cache::AbstractCache, kv::Union{Channel,RemoteChannel})
    while true
        isready(kv) || break
        (key, value) = take!(kv)
        cache[key] = value
    end
end


"""
    DictCache()

A cache that stores items in memory only.
"""
struct DictCache <: AbstractCache
    cache::Dict{UInt64, Any}
end

DictCache() = DictCache(Dict())

Base.getindex(cache::DictCache, key::UInt64) = cache.cache[key]
Base.setindex!(cache::DictCache, value, key::UInt64) = cache.cache[key] = value
Base.haskey(cache::DictCache, key::UInt64) = haskey(cache.cache, key)
Base.length(cache::DictCache) = length(cache.cache)

function Base.summary(io::IO, cache::DictCache)
    print(io, "$(typeof(cache))")
    print(io, ": $(length(cache.cache)) items in memory")
end	



struct FileCache <: AbstractCache
    dir::String
    loaded::Dict{UInt64, Any}
end

"""
    FileCache(dir::AbstractString; clear = false, gitignore = true)

Creates a cache at `dir`. If `clear` is `true` the directory is removed before creating.
If `gitignore` is `true` a `.gitignore` file is created in the directory and all its contents will be ignored by git.
"""
function FileCache(dir::AbstractString; 
    clear = false,
    gitignore = true,)

    if clear && isdir(dir)
        rm(dir, recursive = true)
    end
    mkpath(dir, mode = 0o700)
    if gitignore
        gitignorefile = joinpath(dir, ".gitignore")
        if !isfile(gitignorefile)
            open(gitignorefile, "w") do io
                println(io, "*")
            end
        end
    end
    FileCache(dir, Dict())
end

Base.show(io::IO, cache::FileCache) = print(io, "$(typeof(cache)) at $(cache.dir)")

function getfilename(cache::FileCache, key::UInt64)
    h = lpad(string(key, base = 16), 16, '0')
    joinpath(cache.dir, h[1:2], h)
end

Base.getindex(cache::FileCache, key::UInt64) = get!(cache.loaded, key) do
    fname = getfilename(cache, key)
    if isfile(fname)
        deserialize(fname)
    else
        error("File not found: $fname")
    end
end

function Base.setindex!(cache::FileCache, value, key::UInt64)
    cache.loaded[key] = value
    fname = getfilename(cache, key)
    mkpath(dirname(fname))
    serialize(fname, value)
end

function Base.haskey(cache::FileCache, key::UInt64)
    haskey(cache.loaded, key) || isfile(getfilename(cache, key))
end

function Base.length(cache::FileCache)
    n = 0
    for (dirpath, dirnames, filenames) in walkdir(cache.dir)
        for filename in filenames
            if filename != ".gitignore"
                n += 1
            end
        end
    end
    n
end




function Base.summary(io::IO, cache::FileCache)
    size = 0
    for (dirpath, dirnames, filenames) in walkdir(cache.dir)
        for filename in filenames
            if filename != ".gitignore"
                size += filesize(joinpath(dirpath, filename))
            end
        end
    end
    human_size = Base.format_bytes(size)

    print(io, "$(typeof(cache)) at $(cache.dir)")
    print(io, ": $(length(cache.loaded)) items in memory, $(length(cache)) items on disk, $(human_size) on disk")
end 



mutable struct SQLiteCache <: AbstractCache
    path::String
    db::SQLite.DB
    read_statement::SQLite.Stmt
    write_statement::SQLite.Stmt
    haskey_statement::SQLite.Stmt

    loaded::Dict{UInt64, Any}

    function SQLiteCache(path::AbstractString, db::SQLite.DB, read_statement::SQLite.Stmt, write_statement::SQLite.Stmt, haskey_statement::SQLite.Stmt, loaded::Dict{UInt64, Any})
        x = new(path, db, read_statement, write_statement, haskey_statement, loaded)
        f(t) = @async DBInterface.close!(t.db)
        finalizer(f, x)
    end
end




"""
    SQLiteCache(path::AbstractString; clear = false)

Creates a SQLite based cache at `path`. If `clear` is `true` the file is removed before creating.
"""
function SQLiteCache(path::AbstractString; clear = false)
    if clear && isfile(path)
        rm(path)
    end
    needs_init = !isfile(path)
    db = SQLite.DB(path)
    SQLite.busy_timeout(db, 1000)
    if needs_init
        SQLite.execute(db, "CREATE TABLE KeyValue (key BIGINT PRIMARY KEY, value BLOB);")
    end

    s1 = SQLite.Stmt(db, "SELECT value FROM KeyValue WHERE key = ?;")
    s2 = SQLite.Stmt(db, "INSERT OR REPLACE INTO KeyValue (key, value) VALUES (?, ?);")
    s3 = SQLite.Stmt(db, "SELECT 1 FROM KeyValue WHERE key = ? LIMIT 1;")
    return SQLiteCache(path, db, s1, s2, s3, Dict{UInt64, Any}())
end

Base.show(io::IO, cache::SQLiteCache) = print(io, "$(typeof(cache)) at $(cache.path)")


function Base.getindex(cache::SQLiteCache, key::UInt64)
    get!(cache.loaded, key) do
        res = first(first(DBInterface.execute(cache.read_statement, (key,))))
        io = IOBuffer(res, read = true, write = false)
        deserialize(io)
    end
end

function Base.setindex!(cache::SQLiteCache, value, key::UInt64)
    cache.loaded[key] = value
    io = IOBuffer()
    serialize(io, value)
    DBInterface.execute(cache.write_statement, (key, take!(io)))
end

function setindices!(cache::SQLiteCache, keys::Vector{UInt}, values::AbstractVector)
    svalues = Base.map(keys, values) do k, v
        cache.loaded[k] = v
        io = IOBuffer()
        serialize(io, v)
        take!(io)
    end
    # this is a lot faster
    DBInterface.executemany(cache.write_statement, (keys, svalues))
end


function setindices!(cache::SQLiteCache, kv::Union{Channel,RemoteChannel})
    DBInterface.transaction(DBInterface.getconnection(cache.write_statement)) do
        while true
            isready(kv) || break
            (key, value) = take!(kv)
            cache.loaded[key] = value
            io = IOBuffer()
            serialize(io, value)
            DBInterface.execute(cache.write_statement, (key, take!(io)))
        end
    end
end


function Base.haskey(cache::SQLiteCache, key::UInt64)
    haskey(cache.loaded, key) || !isempty(DBInterface.execute(cache.haskey_statement, (key,)))
end

function Base.length(cache::SQLiteCache)
    res = DBInterface.execute(cache.db, "SELECT COUNT(*) FROM KeyValue;")
    count = first(first(res))
    return count
end

function close!(cache::SQLiteCache)
    DBInterface.close!(cache.db)
end

"""
    Cached.loadall!(cache::SQLiteCache)

Load all items from the SQLite database into memory.
"""
function loadall!(cache::SQLiteCache)

    s = SQLite.Stmt(cache.db, "SELECT * FROM KeyValue;")
    res = DBInterface.execute(s)

    for row in res
        key = row[1]
        value = row[2]
        io = IOBuffer(value, read=true, write=false)
        cache.loaded[key] = deserialize(io)
    end
    cache
end



"""
    Cached.drop_unused!(cache::SQLiteCache)

Drop all items from the SQLite database that are not in memory.
"""
function drop_unused!(cache::SQLiteCache)
    valid_ids = collect(keys(cache.loaded))

    # Build the SQL query with placeholders
    placeholders = join(("?" for _ in valid_ids), ", ")
    query = "DELETE FROM KeyValue WHERE key NOT IN ($placeholders)"

    # Execute the query with parameters
    DBInterface.execute(cache.db, query, valid_ids)
    cache
end



function Base.summary(io::IO, cache::SQLiteCache)
    size = filesize(cache.path)
    human_size = Base.format_bytes(size)

    print(io, "$(typeof(cache)) at $(cache.path)")
    print(io, ": $(length(cache.loaded)) items in memory, $(length(cache)) items on disk, $(human_size) on disk")
end 





# function DictCache(s::SQLiteCache)
#     return DictCache(deepcopy(s.loaded))
# end