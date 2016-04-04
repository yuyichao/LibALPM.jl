#!/usr/bin/julia -f

version() = VersionNumber(ascii(ccall((:alpm_version, libalpm), Ptr{UInt8}, ())))
capabilities() = ccall((:alpm_capabilities, libalpm), UInt32, ())

# checksums
compute_md5sum(fname) =
    pointer_to_string(ccall((:alpm_compute_md5sum, libalpm),
                            Ptr{UInt8}, (Cstring,), fname), true)
compute_sha256sum(fname) =
    pointer_to_string(ccall((:alpm_compute_sha256sum, libalpm),
                            Ptr{UInt8}, (Cstring,), fname), true)
