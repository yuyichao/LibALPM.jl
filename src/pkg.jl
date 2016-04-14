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

(::Type{Nullable{Pkg}})(ptr::Ptr{Void}, hdl::Handle) =
    ptr == C_NULL ? Nullable{Pkg}() : Nullable(Pkg(ptr, hdl))

function free(pkg::Pkg)
    # Should not trigger callback and should not fail
    ptr = pkg.ptr
    ptr == C_NULL && return
    hdl = pkg.hdl
    pkg.ptr = C_NULL
    delete!(hdl.pkgs, ptr)
    pkg.should_free && ccall((:alpm_pkg_free, libalpm), Cint, (Ptr{Void},), ptr)
    nothing
end

Base.cconvert(::Type{Ptr{Void}}, pkg::Pkg) = pkg
function Base.unsafe_convert(::Type{Ptr{Void}}, pkg::Pkg)
    ptr = pkg.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end

function Base.show(io::IO, pkg::Pkg)
    print(io, "LibALPM.Pkg(ptr=")
    show(io, UInt(pkg.ptr))
    print(io, ",name=")
    show(io, get_name(pkg))
    print(io, ")")
end

"Check the integrity (with md5) of a package from the sync cache"
checkmd5sum(pkg::Pkg) = with_handle(pkg.hdl) do
    # Can't really find a way to test this
    # (this seems to require the package validation to be not using signatures?)
    # Apparently not used by pacman either...
    ret = ccall((:alpm_pkg_checkmd5sum, libalpm), Cint, (Ptr{Void},), pkg)
    ret == 0 || throw(Error(pkg.hdl, "checkmd5sum"))
    nothing
end

"Computes the list of packages requiring a given package"
compute_requiredby(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_compute_requiredby, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, ptr_to_utf8, cglobal(:free))
end

"Computes the list of packages optionally requiring a given package"
compute_optionalfor(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_compute_optionalfor, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, ptr_to_utf8, cglobal(:free))
end

"""
Test if a package should be ignored

Checks if the package is ignored via IgnorePkg,
or if the package is in a group ignored via IgnoreGroup.
"""
should_ignore(pkg::Pkg) =
    # Should not trigger callback
    ccall((:alpm_pkg_should_ignore, libalpm), Cint, (Ptr{Void}, Ptr{Void}),
          pkg.hdl, pkg) != 0

"Gets the name of the file from which the package was loaded"
function get_filename(pkg::Pkg)
    # Should not trigger callback
    utf8(ccall((:alpm_pkg_get_filename, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package base name"
get_base(pkg::Pkg) = with_handle(pkg.hdl) do
    utf8(ccall((:alpm_pkg_get_base, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package name"
function get_name(pkg::Pkg)
    # Should not trigger callback
    utf8(ccall((:alpm_pkg_get_name, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"""
Returns the package version as a string

This includes all available epoch, version, and pkgrel components. Use
`LibALPM.vercmp()` to compare version strings if necessary.
"""
function get_version(pkg::Pkg)
    # Should not trigger callback
    utf8(ccall((:alpm_pkg_get_version, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the origin of the package"
function get_origin(pkg::Pkg)
    # Should not trigger callback and should not fail
    ccall((:alpm_pkg_get_origin, libalpm),
          pkgfrom_t, (Ptr{Void},), pkg)
end

"Returns the package description"
get_desc(pkg::Pkg) = with_handle(pkg.hdl) do
    utf8(ccall((:alpm_pkg_get_desc, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package URL"
get_url(pkg::Pkg) = with_handle(pkg.hdl) do
    utf8(ccall((:alpm_pkg_get_url, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the build timestamp of the package"
get_builddate(pkg::Pkg) = with_handle(pkg.hdl) do
    ccall((:alpm_pkg_get_builddate, libalpm), Int64, (Ptr{Void},), pkg)
end

"Returns the install timestamp of the package"
get_installdate(pkg::Pkg) = with_handle(pkg.hdl) do
    ccall((:alpm_pkg_get_installdate, libalpm), Int64, (Ptr{Void},), pkg)
end

"Returns the packager's name"
get_packager(pkg::Pkg) = with_handle(pkg.hdl) do
    utf8(ccall((:alpm_pkg_get_packager, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package's MD5 checksum as a string"
function get_md5sum(pkg::Pkg)
    # Should not trigger callback
    utf8(ccall((:alpm_pkg_get_md5sum, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the package's SHA256 checksum as a string"
function get_sha256sum(pkg::Pkg)
    # Should not trigger callback
    utf8(ccall((:alpm_pkg_get_sha256sum, libalpm),
               Ptr{UInt8}, (Ptr{Void},), pkg))
end

"Returns the architecture for which the package was built"
get_arch(pkg::Pkg) = with_handle(pkg.hdl) do
    utf8(ccall((:alpm_pkg_get_arch, libalpm), Ptr{UInt8}, (Ptr{Void},), pkg))
end

"""
Returns the size of the package.

This is only available for sync database packages and package files,
not those loaded from the local database.
"""
get_size(pkg::Pkg) =
    # Should not trigger callback
    ccall((:alpm_pkg_get_size, libalpm), Int64, (Ptr{Void},), pkg)

"Returns the installed size of the package"
get_isize(pkg::Pkg) = with_handle(pkg.hdl) do
    ccall((:alpm_pkg_get_isize, libalpm), Int64, (Ptr{Void},), pkg)
end

"Returns the package installation reason"
get_reason(pkg::Pkg) = with_handle(pkg.hdl) do
    ccall((:alpm_pkg_get_reason, libalpm), pkgreason_t, (Ptr{Void},), pkg)
end

"""
Set install reason for a package in the local database

The provided package object must be from the local database or this method
will fail. The write to the local database is performed immediately.
"""
set_reason(pkg::Pkg, reason) = with_handle(pkg.hdl) do
    ret = ccall((:alpm_pkg_set_reason, libalpm),
                Cint, (Ptr{Void}, pkgreason_t), pkg, reason)
    ret == 0 || throw(Error(pkg.hdl, "set_reason"))
    nothing
end

"Returns the list of package licenses"
get_licenses(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_licenses, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, p->utf8(Ptr{UInt8}(p)))
end

"Returns the list of package groups"
get_groups(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_groups, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(UTF8String, list, p->utf8(Ptr{UInt8}(p)))
end

"""
Returns the list of files installed by pkg

The filenames are relative to the install root,
and do not include leading slashes.
"""
get_files(pkg::Pkg) = with_handle(pkg.hdl) do
    listptr = ccall((:alpm_pkg_get_files, libalpm), Ptr{CTypes.FileList},
                    (Ptr{Void},), pkg)
    list = unsafe_load(listptr)
    ary = Vector{File}(list.count)
    for i in 1:list.count
        @inbounds ary[i] = File(list.files + sizeof(CTypes.File) * (i - 1))
    end
    ary
end

"Returns the list of files backed up when installing pkg"
get_backup(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_backup, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(Backup, list, Backup)
end


"Returns the database containing pkg"
get_db(pkg::Pkg) =
    # Should not trigger callback
    DB(ccall((:alpm_pkg_get_db, libalpm), Ptr{Void}, (Ptr{Void},), pkg),
       pkg.hdl)

"Returns the base64 encoded package signature"
get_base64_sig(pkg::Pkg) =
    # Should not trigger callback
    ascii(ccall((:alpm_pkg_get_base64_sig, libalpm),
                Ptr{UInt8}, (Ptr{Void},), pkg))

"Returns the method used to validate a package during install"
get_validation(pkg::Pkg) = with_handle(pkg.hdl) do
    ccall((:alpm_pkg_get_validation, libalpm), UInt32, (Ptr{Void},), pkg)
end

"Returns whether the package has an install scriptlet"
has_scriptlet(pkg::Pkg) = with_handle(pkg.hdl) do
    ccall((:alpm_pkg_has_scriptlet, libalpm), Cint, (Ptr{Void},), pkg) != 0
end

"""
Returns the size of download

Returns the size of the files that will be downloaded to install a package.
"""
download_size(pkg::Pkg) = with_handle(pkg.hdl) do
    ccall((:alpm_pkg_download_size, libalpm), Int, (Ptr{Void},), pkg)
end

"Returns the list of package dependencies"
get_depends(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_depends, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of package optional dependencies"
get_optdepends(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_optdepends, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages conflicting with pkg"
get_conflicts(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_conflicts, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages provided by pkg"
get_provides(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_provides, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages to be replaced by pkg"
get_replaces(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_replaces, libalpm),
                 Ptr{list_t}, (Ptr{Void},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of available deltas for pkg"
get_deltas(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_get_deltas, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(Delta, list, Delta)
end

unused_deltas(pkg::Pkg) = with_handle(pkg.hdl) do
    list = ccall((:alpm_pkg_unused_deltas, libalpm), Ptr{list_t},
                 (Ptr{Void},), pkg)
    list_to_array(Delta, list, Delta, C_NULL)
end

"""
Add a package to the transaction

If the package was loaded by `LibALPM.load()`, it will be freed upon
`LibALPM.trans_release()` invocation.
"""
add_pkg(hdl::Handle, pkg::Pkg) = with_handle(hdl) do
    ret = ccall((:alpm_add_pkg, libalpm),
                Cint, (Ptr{Void}, Ptr{Void}), hdl, pkg)
    ret == 0 || throw(Error(hdl, "add_pkg"))
    if pkg.should_free
        push!(hdl.transpkgs::Set{Pkg}, pkg)
        pkg.should_free = false
    end
    nothing
end

"Add a package removal action to the transaction"
remove_pkg(hdl::Handle, pkg::Pkg) = with_handle(hdl) do
    ret = ccall((:alpm_remove_pkg, libalpm),
                Cint, (Ptr{Void}, Ptr{Void}), hdl, pkg)
    ret == 0 || throw(Error(hdl, "remove_pkg"))
    push!(hdl.rmpkgs::Set{Pkg}, pkg)
    pkg.should_free = false
    nothing
end

# TODO
#  * Groups
# alpm_list_t *alpm_find_group_pkgs(alpm_list_t *dbs, const char *name);

#  * Sync
# alpm_pkg_t *alpm_sync_newversion(alpm_pkg_t *pkg, alpm_list_t *dbs_sync);
