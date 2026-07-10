
"""
    cmap(f, cache::AbstractCache, c; showprogress = true, kwargs...) -> Vector
    cmap(f, cache::AbstractCache, c1, c2, ...; kwargs...) -> Vector

Map `f` over collection `c`, storing and retrieving results from `cache`.
Each input element is hashed with `Base.hash` to form the cache key, so any
previously cached result for a given input value is reused without calling `f`
again — even across separate Julia sessions when using a persistent backend.

The multi-collection form `cmap(f, cache, c1, c2, ...)` zips the collections
and calls `f(x1, x2, ...)` for each tuple of elements.

# Arguments
- `f`: Function to apply to each element.
- `cache`: An `AbstractCache` (e.g. `DictCache`, `FileCache`, `SQLiteCache`).
- `c`: Collection of inputs.
- `showprogress`: Display a progress bar (default: `true`).
- `kwargs...`: Forwarded to `ProgressMeter.progress_map`.

# Examples
```julia
using Cached

cache = SQLiteCache("results.sqlite")

# First call: computes and caches all values
results = cmap(x -> x^2, cache, 1:10)

# Second call: all results are retrieved from cache
results = cmap(x -> x^2, cache, 1:10)

# Multi-collection form
cmap((x, y) -> x + y, cache, 1:5, 6:10)
```
"""
function cmap(f, cache::AbstractCache, c; 
        showprogress = true, kwargs...)
    progex = Progress(length(c), enabled = showprogress,
		barglyphs =BarGlyphs('|','█', ['▁' ,'▂' ,'▃' ,'▄' ,'▅' ,'▆', '▇'],' ','|',),
		barlen = 10)
    
    local keys_to_save  = UInt64[]
    local ids_to_save = UInt64[]
    vals = ProgressMeter.progress_map(enumerate(c); progress = progex, kwargs...) do (i, x)
        id = hash(x)
        if !haskey(cache, id)
            val = f(x)
            push!(keys_to_save, id)
            push!(ids_to_save, i)
        else
            val = cache[id]
        end
        val
    end
    if length(keys_to_save) > 0
        setindices!(cache, view(vals, ids_to_save), keys_to_save)
    end
    vals
end

cmap(f, cache::AbstractCache, c1, c...; kwargs...) = cmap(a->f(a...), cache, zip(c1, c...); kwargs...)


"""
    pcmap(f, p::AbstractWorkerPool, cache::AbstractCache, c; kwargs...) -> Vector
    pcmap(f, cache::AbstractCache, c; kwargs...) -> Vector
    pcmap(f, [p], cache::AbstractCache, c1, c2, ...; kwargs...) -> Vector

Parallel version of [`cmap`](@ref). Maps `f` over collection `c` using the
worker pool `p`, caching results in `cache`. Each input is hashed with
`Base.hash` — cached values are returned immediately without dispatching to a
worker.

When called without a worker pool, `p` defaults to `CachingPool(workers())`.
If the pool contains no remote workers (or only the current process), `f` is
executed locally without any remote dispatch.

The multi-collection form zips the collections and calls `f(x1, x2, ...)`.

# Arguments
- `f`: Function to apply to each element.
- `p`: Worker pool (optional; defaults to `CachingPool(workers())`).
- `cache`: An `AbstractCache` (e.g. `SQLiteCache`).
- `c`: Collection of inputs.
- `distributed`: Whether to dispatch to remote workers (default: `true`).
  Set to `false` to run locally while still using the cache.
- `batch_size`: Number of items per remote call. Currently only `1` is supported.
- `on_error`: Called with `(x, e)` when `f(x)` throws. Forwarded to
  `Distributed.pmap`; `nothing` means errors propagate immediately.
- `retry_delays`: Iterable of delays (seconds) for automatic retry on failure.
- `retry_check`: Predicate `(state, e) -> Bool` controlling whether a retry
  should be attempted. Used together with `retry_delays`.
- `showprogress`: Display a progress bar (default: `true`).

# Examples
```julia
using Cached
using Distributed

addprocs(4)

cache = SQLiteCache("results.sqlite")

# Uncached items are computed on workers; cached items are returned immediately
results = pcmap(x -> x^2, cache, 1:100)
```
"""
function pcmap(f, p::AbstractWorkerPool, cache::AbstractCache, c; 
        distributed=true, batch_size=1, on_error=nothing,
        retry_delays=[], retry_check=nothing,
        showprogress = true
    )
    

    f_orig = f
    # Don't do remote calls if there are no workers.
    if (length(p) == 0) || (length(p) == 1 && fetch(p.channel) == myid())
        distributed = false
    end


    lenex = length(c)
    progex = Progress(lenex, enabled = showprogress,
		barglyphs =BarGlyphs('|','█', ['▁' ,'▂' ,'▃' ,'▄' ,'▅' ,'▆', '▇'],' ','|',),
		barlen = 10)
    channel_bufflen = min(1000, lenex)

    @assert batch_size == 1

    # Don't do batching if not doing remote calls.
    if !distributed
        batch_size = 1
    end

    # If not batching, do simple remote call.
    if on_error !== nothing
        f = Distributed.wrap_on_error(f, on_error)
    end

    if distributed
        f = remote(p, f)
    end

    if length(retry_delays) > 0
        f = Distributed.wrap_retry(f, retry_delays, retry_check)
    end

    progex_channel = RemoteChannel(()->Channel{Bool}(channel_bufflen), 1)
    kv_channel = RemoteChannel(()->Channel{Tuple{UInt64, Any}}(channel_bufflen), 1)


    function cb(timer)
        if isready(kv_channel)
            # println("saving a few key value pairs")
            Cached.setindices!(cache, kv_channel)
        end
    end

    local vals
    
    @sync begin
        @async while take!(progex_channel)
            next!(progex)
        end
            
        @sync begin 
            t = Timer(cb, 0, interval = 10)

            vals = asyncmap(enumerate(c); ntasks=()->nworkers(p)) do (i, x)
                key = hash(x)
                if !haskey(cache, key)
                    val = f(x)
                    put!(kv_channel, (key, val))
                # else
                #     val = cache[key]
                end
                put!(progex_channel, true)
                yield()
                key
            end
            close(t)
            put!(progex_channel, false)
        end
    end
    setindices!(cache, kv_channel) 

    return getindex.(Ref(cache), vals)
end

pcmap(f, p::AbstractWorkerPool, cache::AbstractCache, c1, c...; kwargs...) = pcmap(a->f(a...), p, cache, zip(c1, c...); kwargs...)
pcmap(f, cache::AbstractCache, c; kwargs...) = pcmap(f, CachingPool(workers()), cache, c; kwargs...)
pcmap(f, cache::AbstractCache, c1, c...; kwargs...) = pcmap(a->f(a...), cache, zip(c1, c...); kwargs...)



"""
    wrap_cache(f, cache::AbstractCache) -> Function

Return a new single-argument function that wraps `f` with caching via `cache`.
On the first call with a given input `x`, `f(x)` is computed and stored.
Subsequent calls with the same `x` return the cached value without calling `f`.

The input is keyed by `Base.hash(x)`.

# Arguments
- `f`: The function to wrap. Must accept a single argument.
- `cache`: An `AbstractCache` used to store and retrieve results.

# Examples
```julia
using Cached

cache = SQLiteCache("results.sqlite")
square = wrap_cache(x -> x^2, cache)

square(4)  # computed and cached
square(4)  # returned from cache
```
"""
function wrap_cache(f, cache::AbstractCache)
    return x -> begin
        id = hash(x)
        if !haskey(cache, id)
            cache[id] = f(x)
        end
        return cache[id]
    end
end