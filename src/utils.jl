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

"Decode a loaded signature in base64 form."
function decode_signature(base64_data)
    sig = Ref{Ptr{UInt8}}()
    sig_len = Ref{Csize_t}()
    ret = ccall((:alpm_decode_signature, libalpm),
                Cint, (Cstring, Ptr{Ptr{UInt8}}, Ptr{Csize_t}),
                base64_data, sig, sig_len)
    ret != 0 && throw(Error(Errno.SIG_INVALID, Libc.strerror(Errno.SIG_INVALID)))
    return unsafe_wrap(Array, sig[], sig_len[], own=true)
end
