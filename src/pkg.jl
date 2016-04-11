#!/usr/bin/julia -f

type Pkg
    ptr::Ptr{Void}
    hdl::Handle
    should_free::Bool
    function Pkg(ptr::Ptr{Void}, hdl::Handle, should_free=false)
        ptr == C_NULL && throw(UndefRefError())
        cached = hdl.pkgs[ptr, Pkg]
        isnull(cached) || return get(cached)
        self = new(ptr, hdl, should_free)
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
    if pkg.should_free
        ret = ccall((:alpm_pkg_free, libalpm), Cint, (Ptr{Void},), ptr)
        ret == 0 || throw(Error(hdl, "free"))
    end
    nothing
end

Base.cconvert(::Type{Ptr{Void}}, pkg::Pkg) = pkg
function Base.unsafe_convert(::Type{Ptr{Void}}, pkg::Pkg)
    ptr = pkg.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end

"Check the integrity (with md5) of a package from the sync cache"
function checkmd5sum(pkg::Pkg)
    ret = ccall((:alpm_pkg_checkmd5sum, libalpm), Cint, (Ptr{Void},), pkg)
    ret == 0 || throw(Error(pkg.hdl, "checkmd5sum"))
    nothing
end

"Computes the list of packages requiring a given package"
function compute_requiredby(pkg::Pkg)
    list = ccall((:alpm_pkg_compute_requiredby, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list == C_NULL && throw(Error(pkg.hdl, "compute_requiredby"))
    try
        ary = list_to_array(UTF8String, list, p->ptr_to_utf8(p, true))
    catch
        free(list, cglobal(:free))
        rethrow()
    end
    free(list)
    ary
end

"Computes the list of packages optionally requiring a given package"
function compute_optionalfor(pkg::Pkg)
    list = ccall((:alpm_pkg_compute_optionalfor, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list == C_NULL && throw(Error(pkg.hdl, "compute_optionalfor"))
    try
        ary = list_to_array(UTF8String, list, p->ptr_to_utf8(p, true))
    catch
        free(list, cglobal(:free))
        rethrow()
    end
    free(list)
    ary
end

"""
Test if a package should be ignored

Checks if the package is ignored via IgnorePkg,
or if the package is in a group ignored via IgnoreGroup.
"""
should_ignore(pkg::Pkg) =
    ccall((:alpm_pkg_should_ignore, libalpm), Cint, (Ptr{Void}, Ptr{Void}),
          pkg.hdl, pkg) != 0

"Gets the name of the file from which the package was loaded"
function get_filename(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_filename, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package base name"
function get_base(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_base, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package name"
function get_name(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_name, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"""
Returns the package version as a string

This includes all available epoch, version, and pkgrel components. Use
`LibALPM.vercmp()` to compare version strings if necessary.
"""
function get_version(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_version, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the origin of the package"
function get_origin(pkg::Pkg)
    from = ccall((:alpm_pkg_get_origin, libalpm),
                 pkgfrom_t, (Ptr{Void},), pkg)
    Int32(from) == -1 && throw(Error(pkg.hdl, "get_origin"))
    from
end

"Returns the package description"
function get_desc(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_desc, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package URL"
function get_url(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_url, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the build timestamp of the package"
get_builddate(pkg::Pkg) =
    ccall((:alpm_pkg_get_builddate, libalpm), Int64, (Ptr{Void},), pkg)

"Returns the install timestamp of the package"
get_installdate(pkg::Pkg) =
    ccall((:alpm_pkg_get_installdate, libalpm), Int64, (Ptr{Void},), pkg)

"Returns the packager's name"
function get_packager(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_packager, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package's MD5 checksum as a string"
function get_md5sum(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_md5sum, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package's SHA256 checksum as a string"
function get_sha256sum(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_sha256sum, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the architecture for which the package was built"
function get_arch(pkg::Pkg)
    ptr_to_utf8(ccall((:alpm_pkg_get_arch, libalpm),
                      Ptr{UInt8}, (Ptr{Void},), pkg))
end

"""
Returns the size of the package.

This is only available for sync database packages and package files,
not those loaded from the local database.
"""
get_size(pkg::Pkg) =
    ccall((:alpm_pkg_get_size, libalpm), Int64, (Ptr{Void},), pkg)

"Returns the installed size of the package"
get_isize(pkg::Pkg) =
    ccall((:alpm_pkg_get_isize, libalpm), Int64, (Ptr{Void},), pkg)

"Returns the package installation reason"
get_reason(pkg::Pkg) =
    ccall((:alpm_pkg_get_reason, libalpm), pkgreason_t, (Ptr{Void},), pkg)

"""
Set install reason for a package in the local database

The provided package object must be from the local database or this method
will fail. The write to the local database is performed immediately.
"""
function set_reason(pkg::Pkg, reason)
    ret = ccall((:alpm_pkg_set_reason, libalpm),
                Cint, (Ptr{Void}, pkgreason_t), pkg, reason)
    ret == 0 || throw(Error(pkg.hdl, "set_reason"))
    nothing
end

"Returns the list of package licenses"
function get_licenses(pkg::Pkg)
    list = ccall((:alpm_pkg_get_licenses, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, ptr_to_utf8)
end

"Returns the list of package groups"
function get_groups(pkg::Pkg)
    list = ccall((:alpm_pkg_get_groups, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, ptr_to_utf8)
end

"""
Returns the list of files installed by pkg

The filenames are relative to the install root,
and do not include leading slashes.
"""
function get_files(pkg::Pkg)
    list = ccall((:alpm_pkg_get_files, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, ptr_to_utf8)
end

"Returns the list of files backed up when installing pkg"
function get_backup(pkg::Pkg)
    list = ccall((:alpm_pkg_get_backup, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, ptr_to_utf8)
end


"Returns the database containing pkg"
get_db(pkg::Pkg) =
    DB(ccall((:alpm_pkg_get_db, libalpm), Ptr{Void}, (Ptr{Void},), pkg),
       pkg.hdl)

"Returns the base64 encoded package signature"
get_base64_sig(pkg::Pkg) =
    ascii(ccall((:alpm_pkg_get_base64_sig, libalpm),
                Ptr{UInt8}, (Ptr{Void},), pkg))

"Returns the method used to validate a package during install"
get_validation(pkg::Pkg) =
    ccall((:alpm_pkg_get_base64_sig, libalpm), UInt32, (Ptr{Void},), pkg)

"Returns whether the package has an install scriptlet"
has_scriptlet(pkg::Pkg) =
    ccall((:alpm_pkg_has_scriptlet, libalpm), Cint, (Ptr{Void},), pkg) != 0

"""
Returns the size of download

Returns the size of the files that will be downloaded to install a package.
"""
download_size(pkg::Pkg) =
    ccall((:alpm_pkg_download_size, libalpm), Int, (Ptr{Void},), pkg)

"Returns the list of package dependencies"
function get_depends(pkg::Pkg)
    list = ccall((:alpm_pkg_get_depends, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Depend, list, Depend)
end

"Returns the list of package optional dependencies"
function get_optdepends(pkg::Pkg)
    list = ccall((:alpm_pkg_get_optdepends, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages conflicting with pkg"
function get_conflicts(pkg::Pkg)
    list = ccall((:alpm_pkg_get_conflicts, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages provided by pkg"
function get_provides(pkg::Pkg)
    list = ccall((:alpm_pkg_get_provides, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages to be replaced by pkg"
function get_replaces(pkg::Pkg)
    list = ccall((:alpm_pkg_get_replaces, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Depend, list, Depend)
end

"Returns the list of available deltas for pkg"
function get_deltas(pkg::Pkg)
    list = ccall((:alpm_pkg_get_deltas, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, ptr_to_utf8)
end

function unused_deltas(pkg::Pkg)
    list = ccall((:alpm_pkg_unused_deltas, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    try
        list_to_array(UTF8String, list, ptr_to_utf8)
    catch
        free(list)
        rethrow()
    end
end

#  * Groups
# alpm_list_t *alpm_find_group_pkgs(alpm_list_t *dbs, const char *name);

#  * Sync
# alpm_pkg_t *alpm_sync_newversion(alpm_pkg_t *pkg, alpm_list_t *dbs_sync);
