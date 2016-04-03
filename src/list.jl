#!/usr/bin/julia -f

immutable list_t
    data::Ptr{Void} # data held by the list node
    prev::Ptr{list_t} # pointer to the previous node
    next::Ptr{list_t} # pointer to the next node
end

function list_to_array{T}(::Type{T}, list::Ptr{list_t}, cb)
    res = T[]
    while list != C_NULL
        push!(res, cb(list.data))
        list = ccall((:alpm_list_next, libalpm),
                     Ptr{list_t}, (Ptr{list_t},), list)
    end
    res
end

function free(list::Ptr{list_t}, freecb::Ptr{Void}=C_NULL)
    if freecb != C_NULL
        ccall((:alpm_list_free_inner, libalpm), Void,
              (Ptr{list_t}, Ptr{Void}), list, freecb)
    end
    ccall((:alpm_list_free, libalpm), Void, (Ptr{list_t},), list)
end

function array_to_list(ary, cb, freecb::Ptr{Void}=C_NULL)
    list = Ptr{list_t}(0)
    try
        for obj in ary
            data = cb(obj)::Ptr{Void}
            list = ccall((:alpm_list_add, libalpm), Ptr{list_t},
                         (Ptr{list_t}, Ptr{Void}), list, data)
        end
    catch ex
        free(list, freecb)
        rethrow(ex)
    end
    list
end
