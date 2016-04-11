#!/usr/bin/julia -f

@inline function pchar_to_array(p::Ptr, own=false)
    p == C_NULL && throw(ArgumentError("Cannot convert NULL to string"))
    len = ccall(:strlen, Csize_t, (Ptr{Void},), p)
    if own
        ccall(:jl_ptr_to_array_1d, Ref{Vector{UInt8}},
              (Any, Ptr{Void}, Csize_t, Cint), Vector{UInt8}, p, len, 1)
    else
        ccall(:jl_pchar_to_array, Ref{Vector{UInt8}}, (Ptr{Void}, Csize_t),
              p, len)
    end
end

@inline ptr_to_utf8(p::Ptr, own=false) = UTF8String(pchar_to_array(p, own))

version() =
    VersionNumber(ascii(ccall((:alpm_version, libalpm), Ptr{UInt8}, ())))
capabilities() = ccall((:alpm_capabilities, libalpm), UInt32, ())

# checksums
compute_md5sum(fname) =
    pointer_to_string(ccall((:alpm_compute_md5sum, libalpm),
                            Ptr{UInt8}, (Cstring,), fname), true)
compute_sha256sum(fname) =
    pointer_to_string(ccall((:alpm_compute_sha256sum, libalpm),
                            Ptr{UInt8}, (Cstring,), fname), true)

"Compare two version strings and determine which one is 'newer'"
vercmp(a, b) = ccall((:alpm_pkg_vercmp, libalpm), Cint, (Cstring, Cstring), a, b)
