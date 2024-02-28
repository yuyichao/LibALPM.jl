#!/usr/bin/julia -f

@inline function cstr_to_utf8(cstr, own)
    cstr == C_NULL && return ""
    res = unsafe_string(Ptr{UInt8}(cstr))
    own && ccall(:free, Cvoid, (Ptr{Cvoid},), Ptr{Cvoid}(cstr))
    return res
end

take_cstring(ptr) = cstr_to_utf8(ptr, true)
convert_cstring(ptr) = cstr_to_utf8(ptr, false)

version() =
    VersionNumber(convert_cstring(ccall((:alpm_version, libalpm), Ptr{UInt8}, ())))
capabilities() = ccall((:alpm_capabilities, libalpm), UInt32, ())

# checksums
compute_md5sum(fname) =
    take_cstring(ccall((:alpm_compute_md5sum, libalpm),
                       Ptr{UInt8}, (Cstring,), fname))
compute_sha256sum(fname) =
    take_cstring(ccall((:alpm_compute_sha256sum, libalpm),
                       Ptr{UInt8}, (Cstring,), fname))

"Compare two version strings and determine which one is 'newer'"
vercmp(a, b) = ccall((:alpm_pkg_vercmp, libalpm), Cint, (Cstring, Cstring), a, b)
