#!/usr/bin/julia -f

version() =
    VersionNumber(unsafe_string(ccall((:alpm_version, libalpm), Ptr{UInt8}, ())))
capabilities() = ccall((:alpm_capabilities, libalpm), UInt32, ())

function take_cstring(ptr)
    str = unsafe_string(Ptr{UInt8}(ptr))
    ccall(:free, Cvoid, (Ptr{Cvoid},), Ptr{Cvoid}(ptr))
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
