```@meta
CurrentModule = Cached
```

# [API Reference](@id api)

## Cache types

```@docs
DictCache
FileCache
SQLiteCache
```

## Mapping functions

```@docs
cmap
pcmap
```

## Utilities

```@docs
wrap_cache
```

## Cache maintenance

These functions are unexported (call them as `Cached.loadall!`, etc.) and
apply to [`SQLiteCache`](@ref).

```@docs
Cached.close!
Cached.loadall!
Cached.drop_unused!
```
