#!/usr/bin/julia -f

Union{Pkg,Nothing}(ptr::Ptr{Cvoid}, hdl::Handle) =
    ptr == C_NULL ? nothing : Pkg(ptr, hdl)

function free(pkg::Pkg)
    # Should not fail
    if isdefined(pkg, :tofree)
        tofree = pkg.tofree
        while !isempty(tofree)
            val = pop!(tofree).value
            val === nothing || free(val)
        end
    end
    ptr = pkg.ptr
    ptr == C_NULL && return
    hdl = pkg.hdl
    pkg.ptr = C_NULL
    delete!(hdl.pkgs, ptr)
    pkg.should_free && ccall((:alpm_pkg_free, libalpm), Cint, (Ptr{Cvoid},), ptr)
    nothing
end

function add_tofree(pkg::Pkg, @nospecialize(obj))
    isdefined(pkg, :tofree) || (pkg.tofree = WeakRef[])
    push!(pkg.tofree, WeakRef(obj))
    nothing
end

Base.cconvert(::Type{Ptr{Cvoid}}, pkg::Pkg) = pkg
function Base.unsafe_convert(::Type{Ptr{Cvoid}}, pkg::Pkg)
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
function checkmd5sum(pkg::Pkg)
    # Can't really find a way to test this
    # (this seems to require the package validation to be not using signatures?)
    # Apparently not used by pacman either...
    ret = ccall((:alpm_pkg_checkmd5sum, libalpm), Cint, (Ptr{Cvoid},), pkg)
    ret == 0 || throw(Error(pkg.hdl, "checkmd5sum"))
    nothing
end

"Computes the list of packages requiring a given package"
function compute_requiredby(pkg::Pkg)
    list = ccall((:alpm_pkg_compute_requiredby, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), pkg)
    list_to_array(String, list, take_cstring, cglobal(:free))
end

"Computes the list of packages optionally requiring a given package"
function compute_optionalfor(pkg::Pkg)
    list = ccall((:alpm_pkg_compute_optionalfor, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), pkg)
    list_to_array(String, list, take_cstring, cglobal(:free))
end

"""
Test if a package should be ignored

Checks if the package is ignored via IgnorePkg,
or if the package is in a group ignored via IgnoreGroup.
"""
should_ignore(pkg::Pkg) =
    ccall((:alpm_pkg_should_ignore, libalpm), Cint, (Ptr{Cvoid}, Ptr{Cvoid}),
          pkg.hdl, pkg) != 0

"Gets the name of the file from which the package was loaded"
function get_filename(pkg::Pkg)
    convert_cstring(ccall((:alpm_pkg_get_filename, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))
end

"Returns the package base name"
get_base(pkg::Pkg) =
    convert_cstring(ccall((:alpm_pkg_get_base, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))

"Returns the package name"
function get_name(pkg::Pkg)
    convert_cstring(ccall((:alpm_pkg_get_name, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))
end

"""
Returns the package version as a string

This includes all available epoch, version, and pkgrel components. Use
`LibALPM.vercmp()` to compare version strings if necessary.
"""
function get_version(pkg::Pkg)
    convert_cstring(ccall((:alpm_pkg_get_version, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))
end

"Returns the origin of the package"
function get_origin(pkg::Pkg)
    # Should not fail
    ccall((:alpm_pkg_get_origin, libalpm),
          pkgfrom_t, (Ptr{Cvoid},), pkg)
end

"Returns the package description"
get_desc(pkg::Pkg) =
    convert_cstring(ccall((:alpm_pkg_get_desc, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))

"Returns the package URL"
get_url(pkg::Pkg) =
    convert_cstring(ccall((:alpm_pkg_get_url, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))

"Returns the build timestamp of the package"
get_builddate(pkg::Pkg) =
    ccall((:alpm_pkg_get_builddate, libalpm), Int64, (Ptr{Cvoid},), pkg)

"Returns the install timestamp of the package"
get_installdate(pkg::Pkg) =
    ccall((:alpm_pkg_get_installdate, libalpm), Int64, (Ptr{Cvoid},), pkg)

"Returns the packager's name"
get_packager(pkg::Pkg) =
    convert_cstring(ccall((:alpm_pkg_get_packager, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))

"Returns the package's MD5 checksum as a string"
function get_md5sum(pkg::Pkg)
    convert_cstring(ccall((:alpm_pkg_get_md5sum, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))
end

"Returns the package's SHA256 checksum as a string"
function get_sha256sum(pkg::Pkg)
    convert_cstring(ccall((:alpm_pkg_get_sha256sum, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))
end

"Returns the architecture for which the package was built"
get_arch(pkg::Pkg) =
    convert_cstring(ccall((:alpm_pkg_get_arch, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))

"""
Returns the size of the package.

This is only available for sync database packages and package files,
not those loaded from the local database.
"""
get_size(pkg::Pkg) =
    ccall((:alpm_pkg_get_size, libalpm), Int64, (Ptr{Cvoid},), pkg)

"Returns the installed size of the package"
get_isize(pkg::Pkg) =
    ccall((:alpm_pkg_get_isize, libalpm), Int64, (Ptr{Cvoid},), pkg)

"Returns the package installation reason"
get_reason(pkg::Pkg) =
    ccall((:alpm_pkg_get_reason, libalpm), pkgreason_t, (Ptr{Cvoid},), pkg)

"""
Set install reason for a package in the local database

The provided package object must be from the local database or this method
will fail. The write to the local database is performed immediately.
"""
function set_reason(pkg::Pkg, reason)
    ret = ccall((:alpm_pkg_set_reason, libalpm),
                Cint, (Ptr{Cvoid}, pkgreason_t), pkg, reason)
    ret == 0 || throw(Error(pkg.hdl, "set_reason"))
    nothing
end

"Returns the list of package licenses"
function get_licenses(pkg::Pkg)
    list = ccall((:alpm_pkg_get_licenses, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), pkg)
    list_to_array(String, list, convert_cstring)
end

"Returns the list of package groups"
function get_groups(pkg::Pkg)
    list = ccall((:alpm_pkg_get_groups, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), pkg)
    list_to_array(String, list, convert_cstring)
end

"""
Returns the list of files installed by pkg

The filenames are relative to the install root,
and do not include leading slashes.
"""
function get_files(pkg::Pkg)
    listptr = ccall((:alpm_pkg_get_files, libalpm), Ptr{CTypes.FileList},
                    (Ptr{Cvoid},), pkg)
    list = unsafe_load(listptr)
    ary = Vector{File}(undef, list.count)
    for i in 1:list.count
        @inbounds ary[i] = File(list.files + sizeof(CTypes.File) * (i - 1))
    end
    ary
end

"Returns the list of files backed up when installing pkg"
function get_backup(pkg::Pkg)
    list = ccall((:alpm_pkg_get_backup, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), pkg)
    list_to_array(Backup, list, Backup)
end


"Returns the database containing pkg"
get_db(pkg::Pkg) =
    DB(ccall((:alpm_pkg_get_db, libalpm), Ptr{Cvoid}, (Ptr{Cvoid},), pkg),
       pkg.hdl)

"Returns the base64 encoded package signature"
get_base64_sig(pkg::Pkg) =
    convert_cstring(ccall((:alpm_pkg_get_base64_sig, libalpm),
                          Ptr{UInt8}, (Ptr{Cvoid},), pkg))

"Returns the method used to validate a package during install"
get_validation(pkg::Pkg) =
    ccall((:alpm_pkg_get_validation, libalpm), UInt32, (Ptr{Cvoid},), pkg)

"Returns whether the package has an install scriptlet"
has_scriptlet(pkg::Pkg) =
    ccall((:alpm_pkg_has_scriptlet, libalpm), Cint, (Ptr{Cvoid},), pkg) != 0

"""
Returns the size of download

Returns the size of the files that will be downloaded to install a package.
"""
download_size(pkg::Pkg) =
    ccall((:alpm_pkg_download_size, libalpm), Int, (Ptr{Cvoid},), pkg)

"Returns the list of package dependencies"
function get_depends(pkg::Pkg)
    list = ccall((:alpm_pkg_get_depends, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of package optional dependencies"
function get_optdepends(pkg::Pkg)
    list = ccall((:alpm_pkg_get_optdepends, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages conflicting with pkg"
function get_conflicts(pkg::Pkg)
    list = ccall((:alpm_pkg_get_conflicts, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages provided by pkg"
function get_provides(pkg::Pkg)
    list = ccall((:alpm_pkg_get_provides, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), pkg)
    list_to_array(Depend, list, Depend)
end

"Returns the list of packages to be replaced by pkg"
function get_replaces(pkg::Pkg)
    list = ccall((:alpm_pkg_get_replaces, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), pkg)
    list_to_array(Depend, list, Depend)
end

"""
Add a package to the transaction

If the package was loaded by `LibALPM.load()`, it will be freed upon
`LibALPM.trans_release()` invocation.
"""
function add_pkg(hdl::Handle, pkg::Pkg)
    ret = ccall((:alpm_add_pkg, libalpm),
                Cint, (Ptr{Cvoid}, Ptr{Cvoid}), hdl, pkg)
    ret == 0 || throw(Error(hdl, "add_pkg"))
    if pkg.should_free
        push!(hdl.transpkgs, pkg)
        pkg.should_free = false
    end
    nothing
end

"Add a package removal action to the transaction"
function remove_pkg(hdl::Handle, pkg::Pkg)
    ret = ccall((:alpm_remove_pkg, libalpm),
                Cint, (Ptr{Cvoid}, Ptr{Cvoid}), hdl, pkg)
    ret == 0 || throw(Error(hdl, "remove_pkg"))
    push!(hdl.rmpkgs, pkg)
    pkg.should_free = false
    nothing
end

"""
Check for new version of pkg in syncdbs.

If the same package appears multiple dbs only the first will be checked
This only checks the syncdb for a newer version. It does not access the network at all.
See `update()` to update a database.
"""
function sync_get_new_version(pkg::Pkg, dbs)
    db_list = array_to_list(dbs, db->db.ptr)
    GC.@preserve dbs begin
        new_pkg = ccall((:alpm_sync_get_new_version, libalpm), Ptr{Cvoid},
                        (Ptr{Cvoid}, Ptr{list_t}), pkg, db_list)
    end
    free(db_list)
    hdl = pkg.hdl
    new_pkg == C_NULL && throw(Error(hdl, "sync_get_new_version"))
    Pkg(new_pkg, hdl)
end
sync_get_new_version(pkg::Pkg, db::DB) = sync_get_new_version(pkg, [db])

struct ReadPkg <: LibArchive.ReaderData
end

LibArchive.do_open(archive::LibArchive.Reader{ReadPkg}) = nothing

"Open a package mtree file for reading"
function LibArchive.Reader(pkg::Pkg)
    archive = ccall((:alpm_pkg_mtree_open, libalpm),
                    Ptr{Cvoid}, (Ptr{Cvoid},), pkg)
    archive == C_NULL && throw(Error(pkg.hdl, "mtree_open"))
    # Currently the archive doesn't have any relation with the package AFAICT
    # so we don't need to register any tofree callbacks
    LibArchive.Reader{ReadPkg}(ReadPkg(), archive, true)
end

# TODO
#  * Groups
# alpm_list_t *alpm_find_group_pkgs(alpm_list_t *dbs, const char *name);

# /** Create a package from a file.
#  * If full is false, the archive is read only until all necessary
#  * metadata is found. If it is true, the entire archive is read, which
#  * serves as a verification of integrity and the filelist can be created.
#  * The allocated structure should be freed using alpm_pkg_free().
#  * @param handle the context handle
#  * @param filename location of the package tarball
#  * @param full whether to stop the load after metadata is read or continue
#  * through the full archive
#  * @param level what level of package signature checking to perform on the
#  * package; note that this must be a '.sig' file type verification
#  * @param pkg address of the package pointer
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
# int alpm_pkg_load(alpm_handle_t *handle, const char *filename, int full, int level, alpm_pkg_t **pkg);

# /** Returns a list of package check dependencies
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
# alpm_list_t *alpm_pkg_get_checkdepends(alpm_pkg_t *pkg);

# /** Returns a list of package make dependencies
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
# alpm_list_t *alpm_pkg_get_makedepends(alpm_pkg_t *pkg);

# /** Extracts package signature either from embedded package signature
#  * or if it is absent then reads data from detached signature file.
#  * @param pkg a pointer to package.
#  * @param sig output parameter for signature data. Callee function allocates
#  * a buffer needed for the signature data. Caller is responsible for
#  * freeing this buffer.
#  * @param sig_len output parameter for the signature data length.
#  * @return 0 on success, negative number on error.
# int alpm_pkg_get_sig(alpm_pkg_t *pkg, unsigned char **sig, size_t *sig_len);
