#!/usr/bin/julia -f

type LazyTaskContext{T}
    dict::Dict{Task,T}
    dictcnt::Int
    curtask::Task
    curref::T
    function LazyTaskContext{T}() where T
        new(Dict{Task,T}(), 0)
    end
end

@noinline function start_task_context_slow(ctx::LazyTaskContext,
                                           t, curtask::Task)
    if ctx.curtask === curtask || curtask in keys(ctx.dict)
        throw(ArgumentError("Cannot nest two context on the same task"))
    end
    ctx.dict[ctx.curtask] = ctx.curref
    ctx.dictcnt = length(ctx.dict)
    ctx.curtask = curtask
    ctx.curref = t
    nothing
end

@inline function start_task_context(ctx::LazyTaskContext{T},
                                    t::T, curtask::Task) where T
    taskslot = pointer_from_objref(ctx) + sizeof(Int) * 2
    taskptr = unsafe_load(Ptr{Ptr{Void}}(taskslot))
    if taskptr == C_NULL
        # Fast path
        ctx.curref = t
        ctx.curtask = curtask
        return
    end
    start_task_context_slow(ctx, t, curtask)
end

@noinline function end_task_context_slow(ctx::LazyTaskContext, curtask::Task)
    if ctx.curtask === curtask
        # need to pop one from the dict
        k, v = first(ctx.dict)
        pop!(ctx.dict, k)
        ctx.curtask = k
        ctx.curref = v
        ctx.dictcnt = length(ctx.dict)
    else
        pop!(ctx.dict, curtask)
        ctx.dictcnt = length(ctx.dict)
    end
    nothing
end

@inline function end_task_context(ctx::LazyTaskContext, curtask::Task)
    taskslot = pointer_from_objref(ctx) + sizeof(Int) * 2
    refslot = pointer_from_objref(ctx) + sizeof(Int) * 3
    taskptr = unsafe_load(Ptr{Ptr{Void}}(taskslot))
    if taskptr == pointer_from_objref(curtask) && ctx.dictcnt == 0
        # Fast path
        unsafe_store!(Ptr{Ptr{Void}}(taskslot), C_NULL)
        unsafe_store!(Ptr{Ptr{Void}}(refslot), C_NULL)
        return
    end
    end_task_context_slow(ctx, curtask)
end

@inline function with_task_context(f, ctx::LazyTaskContext{T}, t::T) where T
    curtask = current_task()
    start_task_context(ctx, t, curtask)
    try
        f()
    finally
        end_task_context(ctx, curtask)
    end
end

@inline function with_task_context_nested(f, ctx::LazyTaskContext{T}, t::T) where T
    # Not very efficient when actually called nested but should be good enough.
    curtask = current_task()
    nested = false
    try
        start_task_context(ctx, t, curtask)
    catch
        t′ = get_task_context(ctx)
        end_task_context(ctx, curtask)
        with_task_context(f, ctx, t)
        start_task_context(ctx, t′, curtask)
        return
    end
    try
        f()
    finally
        end_task_context(ctx, curtask)
    end
end

function get_task_context(ctx::LazyTaskContext{T}) where T
    taskslot = pointer_from_objref(ctx) + sizeof(Int) * 2
    taskptr = unsafe_load(Ptr{Ptr{Void}}(taskslot))
    curtask = current_task()
    taskptr == pointer_from_objref(curtask) && return ctx.curref
    ctx.dict[curtask]
end

function ptr_to_utf8(p::Ptr)
    p == C_NULL && throw(ArgumentError("Cannot convert NULL to string"))
    len = ccall(:strlen, Csize_t, (Ptr{Void},), p)
    ary = ccall(:jl_ptr_to_array_1d, Ref{Vector{UInt8}},
                (Any, Ptr{Void}, Csize_t, Cint), Vector{UInt8}, p, len, 1)
    String(ary)
end

version() =
    VersionNumber(unsafe_string(ccall((:alpm_version, libalpm), Ptr{UInt8}, ())))
capabilities() = ccall((:alpm_capabilities, libalpm), UInt32, ())

function take_cstring(ptr)
    str = unsafe_string(ptr)
    ccall(:free, Void, (Ptr{Void},), ptr)
    return str
end

# checksums
compute_md5sum(fname) =
    take_cstring(ccall((:alpm_compute_md5sum, libalpm),
                       Ptr{UInt8}, (Cstring,), fname))
compute_sha256sum(fname) =
    take_cstring(ccall((:alpm_compute_sha256sum, libalpm),
                       Ptr{UInt8}, (Cstring,), fname))

"Compare two version strings and determine which one is 'newer'"
vercmp(a, b) = ccall((:alpm_pkg_vercmp, libalpm), Cint, (Cstring, Cstring), a, b)
