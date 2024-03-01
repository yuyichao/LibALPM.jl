#!/usr/bin/julia -f

mutable struct CObjMap
    const dict::Dict{Ptr{Cvoid},WeakRef}
    new_added::Int
    last_pause::Int
    CObjMap() = new(Dict{Ptr{Cvoid},WeakRef}(), 0, 0)
end

function maybe_gc(map)
    cur_pause = Base.gc_num().pause
    if map.last_pause == cur_pause
        # Try again 20 cycles later
        map.new_added = 80
        return
    end
    map.last_pause = cur_pause
    map.new_added = 0
    filter!(map.dict) do kv
        kv[2].value !== nothing
    end
    return
end

function Base.setindex!(map::CObjMap, @nospecialize(val), ptr::Ptr{Cvoid})
    if map.new_added > 100
        maybe_gc(map)
    end
    ref = WeakRef(val)
    map.new_added += 1
    map.dict[ptr] = ref
    nothing
end

function Base.getindex(map::CObjMap, ptr::Ptr{Cvoid}, ::Type{T}) where T
    if ptr in keys(map.dict)
        val = map.dict[ptr].value
        val !== nothing && return val::T
    end
    return nothing
end

Base.delete!(map::CObjMap, ptr::Ptr{Cvoid}) =
    delete!(map.dict, ptr)
