#!/usr/bin/julia -f

struct list_t
    data::Ptr{Cvoid} # data held by the list node
    prev::Ptr{list_t} # pointer to the previous node
    next::Ptr{list_t} # pointer to the next node
end

struct list_iter
    ptr::Ptr{list_t}
end

@inline Base.iterate(iter::list_iter) = iterate(iter, iter.ptr)
@inline function Base.iterate(iter::list_iter, ptr::Ptr{list_t})
    if ptr == C_NULL
        return
    end
    return unsafe_load(ptr).data, ccall((:alpm_list_next, libalpm),
                                        Ptr{list_t}, (Ptr{list_t},), ptr)
end

function list_to_array(::Type{T}, list::Ptr{list_t}, cb) where T
    res = T[]
    for data in list_iter(list)
        push!(res, cb(data))
    end
    res
end

# The callback should always consume the pointer, even if it throws
# an error.
function list_to_array(::Type{T}, list::Ptr{list_t}, cb, freecb::Ptr{Cvoid}) where T
    res = T[]
    iter = list_iter(list)
    next = iterate(iter)
    try
        while next !== nothing
            (data, i) = next
            push!(res, cb(data))
            next = iterate(iter, i)
        end
    catch
        if freecb != C_NULL
            while next !== nothing
                (data, i) = next
                ccall(freecb, Cvoid, (Ptr{Cvoid},), data)
                next = iterate(iter, i)
            end
        end
        free(list)
        rethrow()
    end
    free(list)
    return res
end

function free(list::Ptr{list_t}, freecb::Ptr{Cvoid}=C_NULL)
    if freecb != C_NULL
        ccall((:alpm_list_free_inner, libalpm), Cvoid,
              (Ptr{list_t}, Ptr{Cvoid}), list, freecb)
    end
    ccall((:alpm_list_free, libalpm), Cvoid, (Ptr{list_t},), list)
end

function array_to_list(ary, cb, freecb::Ptr{Cvoid}=C_NULL)
    list = Ptr{list_t}(0)
    try
        for obj in ary
            data = cb(obj)::Ptr{Cvoid}
            list = ccall((:alpm_list_add, libalpm), Ptr{list_t},
                         (Ptr{list_t}, Ptr{Cvoid}), list, data)
        end
    catch ex
        free(list, freecb)
        rethrow(ex)
    end
    list
end
