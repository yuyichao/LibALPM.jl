#!/usr/bin/julia -f

type Pkg
    ptr::Ptr{Void}
    hdl::Handle
    function Pkg(ptr::Ptr{Void}, hdl::Handle, should_free=false)
        ptr == C_NULL && throw(UndefRefError())
        cached = hdl.pkgs[ptr, Pkg]
        isnull(cached) || return get(cached)
        self = new(ptr, hdl)
        should_free && finalizer(self, free)
        hdl.pkgs[ptr] = self
        self
    end
end

function free(pkg::Pkg)
    ptr = pkg.ptr
    ptr == C_NULL && return
    hdl = pkg.hdl
    pkg.ptr = C_NULL
    delete!(hdl.pkgs, ptr)
    ret = ccall((:alpm_pkg_free, libalpm), Cint, (Ptr{Void},), ptr)
    ret == 0 || throw(Error(hdl, "free"))
    nothing
end

Base.cconvert(::Type{Ptr{Void}}, pkg::Pkg) = pkg
function Base.unsafe_convert(::Type{Ptr{Void}}, pkg::Pkg)
    ptr = pkg.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end
