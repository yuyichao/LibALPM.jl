#!/usr/bin/julia -f

module LibALPM

const depfile = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if isfile(depfile)
    include(depfile)
else
    error("LibALPM not properly installed. Please run Pkg.build(\"LibALPM\")")
end

include("enums.jl")
include("ctypes.jl")
include("list.jl")
include("weakdict.jl")
include("utils.jl")
include("handle.jl")
include("db.jl")
include("pkg.jl")

# typedef struct __alpm_pkg_t alpm_pkg_t;

# typedef void (*alpm_cb_log)(alpm_loglevel_t, const char *, va_list);

# int alpm_logaction(alpm_handle_t *handle, const char *prefix,
# const char *fmt, ...) __attribute__((format(printf, 3, 4)));

# Event callback.
# typedef void (*alpm_cb_event)(alpm_event_t *);

# Question callback
# typedef void (*alpm_cb_question)(alpm_question_t *);

# Progress callback
# typedef void (*alpm_cb_progress)(alpm_progress_t, const char *, int, size_t, size_t);

#  * Downloading

# /** Type of download progress callbacks.
#  * @param filename the name of the file being downloaded
#  * @param xfered the number of transferred bytes
#  * @param total the total number of bytes to transfer
#
# typedef void (*alpm_cb_download)(const char *filename,
# off_t xfered, off_t total);

# typedef void (*alpm_cb_totaldl)(off_t total);

# /** A callback for downloading files
#  * @param url the URL of the file to be downloaded
#  * @param localpath the directory to which the file should be downloaded
#  * @param force whether to force an update, even if the file is the same
#  * @return 0 on success, 1 if the file exists and is identical, -1 on
#  * error.
#
# typedef int (*alpm_cb_fetch)(const char *url, const char *localpath,
# int force);

#  * Libalpm option getters and setters

# /** Returns the callback used for logging.
# alpm_cb_log alpm_option_get_logcb(alpm_handle_t *handle);
# /** Sets the callback used for logging.
# int alpm_option_set_logcb(alpm_handle_t *handle, alpm_cb_log cb);

# /** Returns the callback used to report download progress.
# alpm_cb_download alpm_option_get_dlcb(alpm_handle_t *handle);
# /** Sets the callback used to report download progress.
# int alpm_option_set_dlcb(alpm_handle_t *handle, alpm_cb_download cb);

# /** Returns the downloading callback.
# alpm_cb_fetch alpm_option_get_fetchcb(alpm_handle_t *handle);
# /** Sets the downloading callback.
# int alpm_option_set_fetchcb(alpm_handle_t *handle, alpm_cb_fetch cb);

# /** Returns the callback used to report total download size.
# alpm_cb_totaldl alpm_option_get_totaldlcb(alpm_handle_t *handle);
# /** Sets the callback used to report total download size.
# int alpm_option_set_totaldlcb(alpm_handle_t *handle, alpm_cb_totaldl cb);

# /** Returns the callback used for events.
# alpm_cb_event alpm_option_get_eventcb(alpm_handle_t *handle);
# /** Sets the callback used for events.
# int alpm_option_set_eventcb(alpm_handle_t *handle, alpm_cb_event cb);

# /** Returns the callback used for questions.
# alpm_cb_question alpm_option_get_questioncb(alpm_handle_t *handle);
# /** Sets the callback used for questions.
# int alpm_option_set_questioncb(alpm_handle_t *handle, alpm_cb_question cb);

# /** Returns the callback used for operation progress.
# alpm_cb_progress alpm_option_get_progresscb(alpm_handle_t *handle);
# /** Sets the callback used for operation progress.
# int alpm_option_set_progresscb(alpm_handle_t *handle, alpm_cb_progress cb);

# /** Find a package in a list by name.
#  * @param haystack a list of alpm_pkg_t
#  * @param needle the package name
#  * @return a pointer to the package if found or NULL
#
# alpm_pkg_t *alpm_pkg_find(alpm_list_t *haystack, const char *needle);

# /** Check the integrity (with md5) of a package from the sync cache.
#  * @param pkg package pointer
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_pkg_checkmd5sum(alpm_pkg_t *pkg);

# /** Compare two version strings and determine which one is 'newer'.
# int alpm_pkg_vercmp(const char *a, const char *b);

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

# /* End of alpm_pkg_t accessors
# /* @}

# /** Open a package changelog for reading.
#  * Similar to fopen in functionality, except that the returned 'file
#  * stream' could really be from an archive as well as from the database.
#  * @param pkg the package to read the changelog of (either file or db)
#  * @return a 'file stream' to the package changelog
#
# void *alpm_pkg_changelog_open(alpm_pkg_t *pkg);

# /** Read data from an open changelog 'file stream'.
#  * Similar to fread in functionality, this function takes a buffer and
#  * amount of data to read. If an error occurs pm_errno will be set.
#  * @param ptr a buffer to fill with raw changelog data
#  * @param size the size of the buffer
#  * @param pkg the package that the changelog is being read from
#  * @param fp a 'file stream' to the package changelog
#  * @return the number of characters read, or 0 if there is no more data or an
#  * error occurred.
#
# size_t alpm_pkg_changelog_read(void *ptr, size_t size,
# const alpm_pkg_t *pkg, void *fp);

# int alpm_pkg_changelog_close(const alpm_pkg_t *pkg, void *fp);

# /** Open a package mtree file for reading.
#  * @param pkg the local package to read the changelog of
#  * @return a archive structure for the package mtree file
#
# struct archive *alpm_pkg_mtree_open(alpm_pkg_t *pkg);

# /** Read next entry from a package mtree file.
#  * @param pkg the package that the mtree file is being read from
#  * @param archive the archive structure reading from the mtree file
#  * @param entry an archive_entry to store the entry header information
#  * @return 0 if end of archive is reached, non-zero otherwise.
#
# int alpm_pkg_mtree_next(const alpm_pkg_t *pkg, struct archive *archive,
# struct archive_entry **entry);

# int alpm_pkg_mtree_close(const alpm_pkg_t *pkg, struct archive *archive);

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


# /* End of alpm_pkg
# /** @}

# /*
#  * Filelists
#

# /** Determines whether a package filelist contains a given path.
#  * The provided path should be relative to the install root with no leading
#  * slashes, e.g. "etc/localtime". When searching for directories, the path must
#  * have a trailing slash.
#  * @param filelist a pointer to a package filelist
#  * @param path the path to search for in the package
#  * @return a pointer to the matching file or NULL if not found
#
# alpm_file_t *alpm_filelist_contains(alpm_filelist_t *filelist, const char *path);

# /*
#  * Signatures
#

# int alpm_pkg_check_pgp_signature(alpm_pkg_t *pkg, alpm_siglist_t *siglist);

# int alpm_db_check_pgp_signature(alpm_db_t *db, alpm_siglist_t *siglist);

# int alpm_siglist_cleanup(alpm_siglist_t *siglist);

# int alpm_decode_signature(const char *base64_data,
# unsigned char **data, size_t *data_len);

# int alpm_extract_keyid(alpm_handle_t *handle, const char *identifier,
# const unsigned char *sig, const size_t len, alpm_list_t **keys);

# /*
#  * Groups
#

# alpm_list_t *alpm_find_group_pkgs(alpm_list_t *dbs, const char *name);

# /*
#  * Sync
#

# alpm_pkg_t *alpm_sync_newversion(alpm_pkg_t *pkg, alpm_list_t *dbs_sync);

# /** @addtogroup alpm_api_trans Transaction Functions
#  * Functions to manipulate libalpm transactions
#  * @{
#

# /** Returns the bitfield of flags for the current transaction.
#  * @param handle the context handle
#  * @return the bitfield of transaction flags
#
# alpm_transflag_t alpm_trans_get_flags(alpm_handle_t *handle);

# /** Returns a list of packages added by the transaction.
#  * @param handle the context handle
#  * @return a list of alpm_pkg_t structures
#
# alpm_list_t *alpm_trans_get_add(alpm_handle_t *handle);

# /** Returns the list of packages removed by the transaction.
#  * @param handle the context handle
#  * @return a list of alpm_pkg_t structures
#
# alpm_list_t *alpm_trans_get_remove(alpm_handle_t *handle);

# /** Initialize the transaction.
#  * @param handle the context handle
#  * @param flags flags of the transaction (like nodeps, etc)
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_trans_init(alpm_handle_t *handle, alpm_transflag_t flags);

# /** Prepare a transaction.
#  * @param handle the context handle
#  * @param data the address of an alpm_list where a list
#  * of alpm_depmissing_t objects is dumped (conflicting packages)
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_trans_prepare(alpm_handle_t *handle, alpm_list_t **data);

# /** Commit a transaction.
#  * @param handle the context handle
#  * @param data the address of an alpm_list where detailed description
#  * of an error can be dumped (i.e. list of conflicting files)
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_trans_commit(alpm_handle_t *handle, alpm_list_t **data);

# /** Interrupt a transaction.
#  * @param handle the context handle
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_trans_interrupt(alpm_handle_t *handle);

# /** Release a transaction.
#  * @param handle the context handle
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_trans_release(alpm_handle_t *handle);
# /** @}

# /** @name Common Transactions
# /** @{

# /** Search for packages to upgrade and add them to the transaction.
#  * @param handle the context handle
#  * @param enable_downgrade allow downgrading of packages if the remote version is lower
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_sync_sysupgrade(alpm_handle_t *handle, int enable_downgrade);

# /** Add a package to the transaction.
#  * If the package was loaded by alpm_pkg_load(), it will be freed upon
#  * alpm_trans_release() invocation.
#  * @param handle the context handle
#  * @param pkg the package to add
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
# int alpm_add_pkg(alpm_handle_t *handle, alpm_pkg_t *pkg);

# /** Add a package removal action to the transaction.
#  * @param handle the context handle
#  * @param pkg the package to uninstall
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_remove_pkg(alpm_handle_t *handle, alpm_pkg_t *pkg);

# /** @}

# /** @addtogroup alpm_api_depends Dependency Functions
#  * Functions dealing with libalpm representation of dependency
#  * information.
#  * @{
#

# alpm_list_t *alpm_checkdeps(alpm_handle_t *handle, alpm_list_t *pkglist,
# alpm_list_t *remove, alpm_list_t *upgrade, int reversedeps);
# alpm_pkg_t *alpm_find_satisfier(alpm_list_t *pkgs, const char *depstring);
# alpm_pkg_t *alpm_find_dbs_satisfier(alpm_handle_t *handle,
# alpm_list_t *dbs, const char *depstring);

# alpm_list_t *alpm_checkconflicts(alpm_handle_t *handle, alpm_list_t *pkglist);

# /** Returns a newly allocated string representing the dependency information.
#  * @param dep a dependency info structure
#  * @return a formatted string, e.g. "glibc>=2.12"
#
# char *alpm_dep_compute_string(const alpm_depend_t *dep);

# /** Return a newly allocated dependency information parsed from a string
#  * @param depstring a formatted string, e.g. "glibc=2.12"
#  * @return a dependency info structure
#
# alpm_depend_t *alpm_dep_from_string(const char *depstring);

# /** Free a dependency info structure
#  * @param dep struct to free
#
# void alpm_dep_free(alpm_depend_t *dep);
# void alpm_fileconflict_free(alpm_fileconflict_t *conflict);
# void alpm_depmissing_free(alpm_depmissing_t *miss);
# void alpm_conflict_free(alpm_conflict_t *conflict);

end
