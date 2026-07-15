# Cached

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ArndtLab.github.io/Cached.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ArndtLab.github.io/Cached.jl/dev/)
[![Build Status](https://github.com/ArndtLab/Cached.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ArndtLab/Cached.jl/actions/workflows/CI.yml?query=branch%3Amain)

`Cached.jl` provides `cmap` and `pcmap` — drop-in replacements for `map` and `pmap` that transparently cache results so that repeated calls with the same inputs skip the computation entirely.

## Usage

### Choosing a cache backend

| Backend | Persists? | Best for |
|---|---|---|
| `DictCache()` | No (in-memory) | Deduplication within a single run |
| `FileCache(dir)` | Yes (files on disk) | Large objects; any serializable value |
| `SQLiteCache(path)` | Yes (SQLite file) | Many small/medium items; concurrent access |

### Basic caching with `cmap`

```julia
using Cached

# Replace any persistent backend — results survive across Julia sessions
cache = SQLiteCache("results.sqlite")

# First call: computes and caches all values
results = cmap(x -> expensive_fn(x), cache, 1:100)

# Second call: all results are already cached — no computation
results = cmap(x -> expensive_fn(x), cache, 1:100)
```

`cmap` accepts the same arguments as `Base.map`, including multi-collection forms:

```julia
cmap((x, y) -> f(x, y), cache, xs, ys)
```

### Parallel caching with `pcmap`

`pcmap` distributes work across Julia workers and is a drop-in replacement for `Distributed.pmap`:

```julia
using Cached
using Distributed

addprocs(4)

cache = SQLiteCache("results.sqlite")

# Runs f on 4 workers; only uncached items are computed
results = pcmap(x -> expensive_fn(x), cache, 1:1000)
```

### Switching backends

Cache backends are interchangeable. Start with a `DictCache` for exploration and promote to a persistent backend when needed:

```julia
mem_cache = DictCache()
cmap(f, mem_cache, data)

# Persist everything computed so far
disk_cache = SQLiteCache("results.sqlite")
cmap(f, disk_cache, data)  # only items not already in disk_cache are recomputed
```

To pre-populate a `SQLiteCache` from an existing `DictCache`:

```julia
disk_cache = SQLiteCache("results.sqlite", mem_cache)
```

### Caching a single function

Use `wrap_cache` to add caching to an individual function instead of a `map` call:

```julia
cache = SQLiteCache("results.sqlite")
expensive_fn_cached = wrap_cache(expensive_fn, cache)

expensive_fn_cached(x)  # computed and cached
expensive_fn_cached(x)  # returned from cache
```

### Managing a `SQLiteCache`

A few unexported functions help manage the on-disk database directly:

```julia
Cached.close!(cache)     # release the SQLite file handle
Cached.loadall!(cache)   # load every item into memory
Cached.drop_unused!(cache)  # delete database rows for keys not currently in memory
```

See the [API Reference](https://ArndtLab.github.io/Cached.jl/stable/api/) for details.

## Installation

```julia
using Pkg
Pkg.add("Cached")
```

Or from the Julia REPL package mode (press `]`):

```
pkg> add Cached
```

Requires Julia 1.11 or later.
