```@meta
CurrentModule = Cached
```

# Cached.jl

`Cached.jl` provides [`cmap`](@ref) and [`pcmap`](@ref) — drop-in replacements
for `Base.map` and `Distributed.pmap` that transparently cache results. On the
first call each input is hashed and the result stored in the chosen backend; on
any subsequent call the cached value is returned immediately without re-running
the function.

## Quick start

```julia
using Cached

# Pick a backend — results persist across Julia sessions
cache = SQLiteCache("results.sqlite")

# First call: every element is computed and stored
results = cmap(x -> x^2, cache, 1:100)

# Second call: everything is already cached, no computation
results = cmap(x -> x^2, cache, 1:100)
```

### Cache backends

| Type | Persists? | Best for |
|---|---|---|
| [`DictCache`](@ref) | No | Deduplication within a single run |
| [`FileCache`](@ref) | Yes (files) | Large objects, any serializable value |
| [`SQLiteCache`](@ref) | Yes (SQLite) | Many small/medium items, concurrent access |

### Parallel mapping

```julia
using Cached, Distributed
addprocs(4)

cache = SQLiteCache("results.sqlite")
results = pcmap(x -> expensive_fn(x), cache, 1:1000)
```

See the [API Reference](@ref api) for full documentation of all types and functions.
