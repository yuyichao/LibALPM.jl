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

# /** Check the integrity (with md5) of a package from the sync cache.
#  * @param pkg package pointer
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_pkg_checkmd5sum(alpm_pkg_t *pkg);

# /** Computes the list of packages requiring a given package.
#  * The return value of this function is a newly allocated
#  * list of package names (char*), it should be freed by the caller.
#  * @param pkg a package
#  * @return the list of packages requiring pkg
#
# alpm_list_t *alpm_pkg_compute_requiredby(alpm_pkg_t *pkg);

# /** Computes the list of packages optionally requiring a given package.
#  * The return value of this function is a newly allocated
#  * list of package names (char*), it should be freed by the caller.
#  * @param pkg a package
#  * @return the list of packages optionally requiring pkg
#
# alpm_list_t *alpm_pkg_compute_optionalfor(alpm_pkg_t *pkg);

# /** Test if a package should be ignored.
#  * Checks if the package is ignored via IgnorePkg, or if the package is
#  * in a group ignored via IgnoreGroup.
#  * @param handle the context handle
#  * @param pkg the package to test
#  * @return 1 if the package should be ignored, 0 otherwise
#
# int alpm_pkg_should_ignore(alpm_handle_t *handle, alpm_pkg_t *pkg);

# /** @name Package Property Accessors
#  * Any pointer returned by these functions points to internal structures
#  * allocated by libalpm. They should not be freed nor modified in any
#  * way.

# /** Gets the name of the file from which the package was loaded.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_filename(alpm_pkg_t *pkg);

# /** Returns the package base name.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_base(alpm_pkg_t *pkg);

# /** Returns the package name.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_name(alpm_pkg_t *pkg);

# /** Returns the package version as a string.
#  * This includes all available epoch, version, and pkgrel components. Use
#  * alpm_pkg_vercmp() to compare version strings if necessary.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_version(alpm_pkg_t *pkg);

# /** Returns the origin of the package.
#  * @return an alpm_pkgfrom_t constant, -1 on error
#
# alpm_pkgfrom_t alpm_pkg_get_origin(alpm_pkg_t *pkg);

# /** Returns the package description.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_desc(alpm_pkg_t *pkg);

# /** Returns the package URL.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_url(alpm_pkg_t *pkg);

# /** Returns the build timestamp of the package.
#  * @param pkg a pointer to package
#  * @return the timestamp of the build time
#
# int64_t alpm_pkg_get_builddate(alpm_pkg_t *pkg);

# /** Returns the install timestamp of the package.
#  * @param pkg a pointer to package
#  * @return the timestamp of the install time
#
# int64_t alpm_pkg_get_installdate(alpm_pkg_t *pkg);

# /** Returns the packager's name.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_packager(alpm_pkg_t *pkg);

# /** Returns the package's MD5 checksum as a string.
#  * The returned string is a sequence of 32 lowercase hexadecimal digits.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_md5sum(alpm_pkg_t *pkg);

# /** Returns the package's SHA256 checksum as a string.
#  * The returned string is a sequence of 64 lowercase hexadecimal digits.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_sha256sum(alpm_pkg_t *pkg);

# /** Returns the architecture for which the package was built.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_arch(alpm_pkg_t *pkg);

# /** Returns the size of the package. This is only available for sync database
#  * packages and package files, not those loaded from the local database.
#  * @param pkg a pointer to package
#  * @return the size of the package in bytes.
#
# off_t alpm_pkg_get_size(alpm_pkg_t *pkg);

# /** Returns the installed size of the package.
#  * @param pkg a pointer to package
#  * @return the total size of files installed by the package.
#
# off_t alpm_pkg_get_isize(alpm_pkg_t *pkg);

# /** Returns the package installation reason.
#  * @param pkg a pointer to package
#  * @return an enum member giving the install reason.
#
# alpm_pkgreason_t alpm_pkg_get_reason(alpm_pkg_t *pkg);

# /** Returns the list of package licenses.
#  * @param pkg a pointer to package
#  * @return a pointer to an internal list of strings.
#
# alpm_list_t *alpm_pkg_get_licenses(alpm_pkg_t *pkg);

# /** Returns the list of package groups.
#  * @param pkg a pointer to package
#  * @return a pointer to an internal list of strings.
#
# alpm_list_t *alpm_pkg_get_groups(alpm_pkg_t *pkg);

# /** Returns the list of package dependencies as alpm_depend_t.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#
# alpm_list_t *alpm_pkg_get_depends(alpm_pkg_t *pkg);

# /** Returns the list of package optional dependencies.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#
# alpm_list_t *alpm_pkg_get_optdepends(alpm_pkg_t *pkg);

# /** Returns the list of packages conflicting with pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#
# alpm_list_t *alpm_pkg_get_conflicts(alpm_pkg_t *pkg);

# /** Returns the list of packages provided by pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#
# alpm_list_t *alpm_pkg_get_provides(alpm_pkg_t *pkg);

# /** Returns the list of available deltas for pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of strings.
#
# alpm_list_t *alpm_pkg_get_deltas(alpm_pkg_t *pkg);

# /** Returns the list of packages to be replaced by pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#
# alpm_list_t *alpm_pkg_get_replaces(alpm_pkg_t *pkg);

# /** Returns the list of files installed by pkg.
#  * The filenames are relative to the install root,
#  * and do not include leading slashes.
#  * @param pkg a pointer to package
#  * @return a pointer to a filelist object containing a count and an array of
#  * package file objects
#
# alpm_filelist_t *alpm_pkg_get_files(alpm_pkg_t *pkg);

# /** Returns the list of files backed up when installing pkg.
#  * @param pkg a pointer to package
#  * @return a reference to a list of alpm_backup_t objects
#
# alpm_list_t *alpm_pkg_get_backup(alpm_pkg_t *pkg);

# /** Returns the database containing pkg.
#  * Returns a pointer to the alpm_db_t structure the package is
#  * originating from, or NULL if the package was loaded from a file.
#  * @param pkg a pointer to package
#  * @return a pointer to the DB containing pkg, or NULL.
#
# alpm_db_t *alpm_pkg_get_db(alpm_pkg_t *pkg);

# /** Returns the base64 encoded package signature.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#
# const char *alpm_pkg_get_base64_sig(alpm_pkg_t *pkg);

# /** Returns the method used to validate a package during install.
#  * @param pkg a pointer to package
#  * @return an enum member giving the validation method
#
# alpm_pkgvalidation_t alpm_pkg_get_validation(alpm_pkg_t *pkg);

# /** Returns whether the package has an install scriptlet.
#  * @return 0 if FALSE, TRUE otherwise
#
# int alpm_pkg_has_scriptlet(alpm_pkg_t *pkg);

# /** Returns the size of download.
#  * Returns the size of the files that will be downloaded to install a
#  * package.
#  * @param newpkg the new package to upgrade to
#  * @return the size of the download
#
# off_t alpm_pkg_download_size(alpm_pkg_t *newpkg);

# alpm_list_t *alpm_pkg_unused_deltas(alpm_pkg_t *pkg);

# /** Set install reason for a package in the local database.
#  * The provided package object must be from the local database or this method
#  * will fail. The write to the local database is performed immediately.
#  * @param pkg the package to update
#  * @param reason the new install reason
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_pkg_set_reason(alpm_pkg_t *pkg, alpm_pkgreason_t reason);
