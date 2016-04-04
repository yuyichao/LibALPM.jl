#!/usr/bin/julia -f

type Pkg
    ptr::Ptr{Void}
    hdl::Handle
    function Pkg(ptr::Ptr{Void}, hdl::Handle)
        ptr == C_NULL && throw(UndefRefError())
        cached = hdl.pkgs[ptr, Pkg]
        isnull(cached) || return get(cached)
        self = new(ptr, hdl)
        hdl.pkgs[ptr] = self
        self
    end
end

Base.cconvert(::Type{Ptr{Void}}, db::Pkg) = db
function Base.unsafe_convert(::Type{Ptr{Void}}, db::Pkg)
    ptr = db.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end
