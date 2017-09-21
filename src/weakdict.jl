#!/usr/bin/julia -f

type CObjMap
    dict::Dict{Ptr{Void},WeakRef}
    new_added::Int
    last_pause::Int
    CObjMap() = new(Dict{Ptr{Void},WeakRef}(), 0, 0)
end

function maybe_gc(map::CObjMap)
    map.new_added <= 100 && return
    cur_pause = Base.gc_num().pause
    map.last_pause == cur_pause && return
    map.last_pause = cur_pause
    map.new_added = 0
    @static if VERSION >= v"0.7.0-DEV.1393"
        filter!(map.dict) do kv
            kv[2].value !== nothing
        end
    else
        filter!(map.dict) do k, v
            v.value !== nothing
        end
    end
end

function Base.setindex!(map::CObjMap, @nospecialize(val), ptr::Ptr{Void})
    maybe_gc(map)
    ref = WeakRef(val)
    map.new_added += 1
    map.dict[ptr] = ref
    nothing
end

function Base.getindex(map::CObjMap, ptr::Ptr{Void}, ::Type{T}) where T
    if ptr in keys(map.dict)
        val = map.dict[ptr].value
        val !== nothing && return Nullable{T}(val::T)
    end
    Nullable{T}()
end

Base.delete!(map::CObjMap, ptr::Ptr{Void}) =
    delete!(map.dict, ptr)
