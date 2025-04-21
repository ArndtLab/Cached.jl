
"""
    cmap(f, cache::AbstractCache, c; showprogress = true, kwargs...)

Map a function over a collection, caching the results in `cache`.

Example:
```julia
using Cached

cache = SQLiteCache("test.sqlite")
cmap(x->x^2, cache, 1:10)
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
        setindices!(cache, keys_to_save, view(vals, ids_to_save))
    end
    vals
end

cmap(f, cache::AbstractCache, c1, c...; kwargs...) = cmap(a->f(a...), cache, zip(c1, c...); kwargs...)


"""
    pcmap(f, [p::AbstractWorkerPool], cache::AbstractCache, c...;
        distributed=true, batch_size=1, 
        on_error=nothing, retry_delays=[], retry_check=nothing, 
        showprogress = true)

Map a function over a collection, caching the results in `cache`, using `p` workers.

Example:
```julia
using Cached
using Distributed

cache = SQLiteCache("test.sqlite")
pcmap(x->x^2, cache, 1:10)
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

pcmap(f, p::AbstractWorkerPool, cache::AbstractCache, c1, c...; kwargs...) = pcmap(a->f(a...), cache, p, zip(c1, c...); kwargs...)
pcmap(f, cache::AbstractCache, c; kwargs...) = pcmap(f, CachingPool(workers()), cache, c; kwargs...)
pcmap(f, cache::AbstractCache, c1, c...; kwargs...) = pcmap(a->f(a...), cache, zip(c1, c...); kwargs...)



"""
    wrap_cache(f, cache::AbstractCache)

Wrap a function `f` so that its results are cached in `cache`.

Example:
```julia
using Cached

cache = SQLiteCache("test.sqlite")
f(x) = x^2
f = wrap_cache(f, cache)

f(4)
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