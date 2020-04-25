#!/usr/bin/julia -f

"Open a package changelog for reading"
mutable struct ChangeLog <: IO
    ptr::Ptr{Cvoid}
    pkg::Pkg
    function ChangeLog(pkg::Pkg)
        ptr = with_handle(pkg.hdl) do
            ccall((:alpm_pkg_changelog_open, libalpm),
                  Ptr{Cvoid}, (Ptr{Cvoid},), pkg)
        end
        ptr == C_NULL && throw(Error(pkg.hdl, "ChangeLog"))
        clog = new(ptr, pkg)
        add_tofree(pkg, clog)
        clog
    end
end

Base.cconvert(::Type{Ptr{Cvoid}}, clog::ChangeLog) = clog
function Base.unsafe_convert(::Type{Ptr{Cvoid}}, clog::ChangeLog)
    ptr = clog.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end

function Base.show(io::IO, clog::ChangeLog)
    print(io, "LibALPM.ChangeLog(ptr=")
    show(io, UInt(clog.ptr))
    print(io, ",pkg=")
    show(io, clog.pkg)
    print(io, ")")
end

function Base.close(clog::ChangeLog)
    ptr = clog.ptr
    ptr == C_NULL && return
    clog.ptr = C_NULL
    ccall((:alpm_pkg_changelog_close, libalpm),
          Cint, (Ptr{Cvoid}, Ptr{Cvoid}), clog.pkg, ptr)
    nothing
end
free(clog::ChangeLog) = close(clog)

@inline function unsafe_changelog_read(clog::ChangeLog, ptr::Ptr{UInt8},
                                       sz::UInt)
    ccall((:alpm_pkg_changelog_read, libalpm),
          Csize_t, (Ptr{UInt8}, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}),
          ptr, sz, clog.pkg, clog)
end

"Read data from `ChangeLog`"
function Base.unsafe_read(clog::ChangeLog, ptr::Ptr{UInt8}, sz::UInt)
    unsafe_changelog_read(clog, ptr, sz) != sz && throw(EOFError())
    nothing
end

"Read data from `ChangeLog`"
function Base.read(clog::ChangeLog, ::Type{UInt8})
    b = Ref{UInt8}()
    unsafe_read(clog, Base.unsafe_convert(Ptr{UInt8}, b), UInt(1))
    b[]
end

"Read data from `ChangeLog`"
function Base.readbytes!(clog::ChangeLog, b::Array{UInt8}, nb=length(b))
    nbread = unsafe_changelog_read(clog, Base.unsafe_convert(Ptr{UInt8}, b),
                                   UInt(nb))
    nbread < nb && resize!(b, nbread)
    nbread
end

"Read data from `ChangeLog`"
function Base.read(clog::ChangeLog)
    block_size = UInt(1024)
    res = Vector{UInt8}(block_size)
    pos = 1
    while true
        ptr = Base.unsafe_convert(Ptr{UInt8}, Ref(res, pos))
        nbread = unsafe_changelog_read(clog, ptr, block_size)
        if nbread < block_size
            resize!(res, nbread + pos - 1)
            return res
        end
        pos = Int(pos + block_size)
        resize!(res, pos + block_size - 1)
    end
end

"Read data from `ChangeLog`"
@inline Base.readavailable(clog::ChangeLog) = read(clog)
