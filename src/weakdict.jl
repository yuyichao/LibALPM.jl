#!/usr/bin/julia -f

type CObjMap{T}
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
    filter!(map.dict) do k, v
        v.value !== nothing
    end
end

function Base.setindex!{T}(map::CObjMap{T}, val::T, ptr::Ptr{Void})
    maybe_gc(map)
    ref = WeakRef(val)
    map.new_added += 1
    map.dict[ptr] = ref
    nothing
end

function Base.getindex{T}(map::CObjMap{T}, ptr::Ptr{Void})
    if ptr in keys(map)
        val = map.dict[ptr].value
        val !== nothing && return Nullable{T}(val::T)
    end
    Nullable{T}()
end

Base.delete!(map::CObjMap, ptr::Ptr{Void}) =
    delete!(map.dict, ptr)
