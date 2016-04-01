#!/usr/bin/julia -f

module LibALPM

const depfile = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if isfile(depfile)
    include(depfile)
else
    error("LibALPM not properly installed. Please run Pkg.build(\"LibALPM\")")
end

include("enums.jl")

version() = VersionNumber(ascii(ccall((:alpm_version, libalpm), Ptr{UInt8}, ())))
capabilities() = ccall((:alpm_capabilities, libalpm), UInt32, ())

# checksums
compute_md5sum(fname) =
    pointer_to_string(ccall((:alpm_compute_md5sum, libalpm),
                            Ptr{UInt8}, (Cstring,), fname), true)
compute_sha256sum(fname) =
    pointer_to_string(ccall((:alpm_compute_sha256sum, libalpm),
                            Ptr{UInt8}, (Cstring,), fname), true)

##
# handle

type Handle
    ptr::Ptr{Void}
    function Handle(root, db)
        err = Ref{errno_t}()
        ptr = ccall((:alpm_initialize, libalpm), Ptr{Void},
                    (Cstring, Cstring, Ref{errno_t}), root, db, err)
        if ptr == C_NULL
            throw(Error(err[], "Create ALPM handle"))
        end
        self = new(ptr)
        finalizer(self, release)
        self
    end
end

function release(hdl::Handle)
    ptr = hdl.ptr
    hdl.ptr = C_NULL
    ptr == C_NULL && return
    ccall((:alpm_release, libalpm), Cint, (Ptr{Void},), ptr)
    nothing
end

Base.cconvert(::Type{Ptr{Void}}, hdl::Handle) = hdl
Base.unsafe_convert(::Type{Ptr{Void}}, hdl::Handle) = hdl.ptr

"Returns the current error code from the handle"
errno(hdl::Handle) =
    ccall((:alpm_errno, libalpm), errno_t, (Ptr{Void},), hdl)
Error(hdl::Handle, msg) = Error(errno(hdl), msg)

function unlock(hdl::Handle)
    if ccall((:alpm_unlock, libalpm), Cint, (Ptr{Void},), hdl) != 0
        throw(Error(hdl, "Unlock handle"))
    end
end

# typedef struct __alpm_handle_t alpm_handle_t;
# typedef struct __alpm_db_t alpm_db_t;
# typedef struct __alpm_pkg_t alpm_pkg_t;
# typedef struct __alpm_trans_t alpm_trans_t;

# /** Dependency */
# typedef struct _alpm_depend_t {
# 	char *name;
# 	char *version;
# 	char *desc;
# 	unsigned long name_hash;
# 	alpm_depmod_t mod;
# } alpm_depend_t;

# /** Missing dependency */
# typedef struct _alpm_depmissing_t {
# 	char *target;
# 	alpm_depend_t *depend;
# 	/* this is used only in the case of a remove dependency error */
# 	char *causingpkg;
# } alpm_depmissing_t;

# /** Conflict */
# typedef struct _alpm_conflict_t {
# 	unsigned long package1_hash;
# 	unsigned long package2_hash;
# 	char *package1;
# 	char *package2;
# 	alpm_depend_t *reason;
# } alpm_conflict_t;

# /** File conflict */
# typedef struct _alpm_fileconflict_t {
# 	char *target;
# 	alpm_fileconflicttype_t type;
# 	char *file;
# 	char *ctarget;
# } alpm_fileconflict_t;

# /** Package group */
# typedef struct _alpm_group_t {
# 	/** group name */
# 	char *name;
# 	/** list of alpm_pkg_t packages */
# 	alpm_list_t *packages;
# } alpm_group_t;

# /** Package upgrade delta */
# typedef struct _alpm_delta_t {
# 	/** filename of the delta patch */
# 	char *delta;
# 	/** md5sum of the delta file */
# 	char *delta_md5;
# 	/** filename of the 'before' file */
# 	char *from;
# 	/** filename of the 'after' file */
# 	char *to;
# 	/** filesize of the delta file */
# 	off_t delta_size;
# 	/** download filesize of the delta file */
# 	off_t download_size;
# } alpm_delta_t;

# /** File in a package */
# typedef struct _alpm_file_t {
# 	char *name;
# 	off_t size;
# 	mode_t mode;
# } alpm_file_t;

# /** Package filelist container */
# typedef struct _alpm_filelist_t {
# 	size_t count;
# 	alpm_file_t *files;
# } alpm_filelist_t;

# /** Local package or package file backup entry */
# typedef struct _alpm_backup_t {
# 	char *name;
# 	char *hash;
# } alpm_backup_t;

# typedef struct _alpm_pgpkey_t {
# 	void *data;
# 	char *fingerprint;
# 	char *uid;
# 	char *name;
# 	char *email;
# 	int64_t created;
# 	int64_t expires;
# 	unsigned int length;
# 	unsigned int revoked;
# 	char pubkey_algo;
# } alpm_pgpkey_t;

# /**
#  * Signature result. Contains the key, status, and validity of a given
#  * signature.
#  */
# typedef struct _alpm_sigresult_t {
# 	alpm_pgpkey_t key;
# 	alpm_sigstatus_t status;
# 	alpm_sigvalidity_t validity;
# } alpm_sigresult_t;

# /**
#  * Signature list. Contains the number of signatures found and a pointer to an
#  * array of results. The array is of size count.
#  */
# typedef struct _alpm_siglist_t {
# 	size_t count;
# 	alpm_sigresult_t *results;
# } alpm_siglist_t;



# typedef void (*alpm_cb_log)(alpm_loglevel_t, const char *, va_list);

# int alpm_logaction(alpm_handle_t *handle, const char *prefix,
# 		const char *fmt, ...) __attribute__((format(printf, 3, 4)));


# typedef struct _alpm_event_any_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# } alpm_event_any_t;

# typedef struct _alpm_event_package_operation_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Type of operation. */
# 	alpm_package_operation_t operation;
# 	/** Old package. */
# 	alpm_pkg_t *oldpkg;
# 	/** New package. */
# 	alpm_pkg_t *newpkg;
# } alpm_event_package_operation_t;

# typedef struct _alpm_event_optdep_removal_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Package with the optdep. */
# 	alpm_pkg_t *pkg;
# 	/** Optdep being removed. */
# 	alpm_depend_t *optdep;
# } alpm_event_optdep_removal_t;

# typedef struct _alpm_event_delta_patch_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Delta info */
# 	alpm_delta_t *delta;
# } alpm_event_delta_patch_t;

# typedef struct _alpm_event_scriptlet_info_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Line of scriptlet output. */
# 	const char *line;
# } alpm_event_scriptlet_info_t;

# typedef struct _alpm_event_database_missing_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Name of the database. */
# 	const char *dbname;
# } alpm_event_database_missing_t;

# typedef struct _alpm_event_pkgdownload_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Name of the file */
# 	const char *file;
# } alpm_event_pkgdownload_t;

# typedef struct _alpm_event_pacnew_created_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Whether the creation was result of a NoUpgrade or not */
# 	int from_noupgrade;
# 	/** Old package. */
# 	alpm_pkg_t *oldpkg;
# 	/** New Package. */
# 	alpm_pkg_t *newpkg;
# 	/** Filename of the file without the .pacnew suffix */
# 	const char *file;
# } alpm_event_pacnew_created_t;

# typedef struct _alpm_event_pacsave_created_t {
# 	/** Type of event. */
# 	alpm_event_type_t type;
# 	/** Old package. */
# 	alpm_pkg_t *oldpkg;
# 	/** Filename of the file without the .pacsave suffix. */
# 	const char *file;
# } alpm_event_pacsave_created_t;

# typedef struct _alpm_event_hook_t {
# 	/** Type of event.*/
# 	alpm_event_type_t type;
# 	/** Type of hooks. */
# 	alpm_hook_when_t when;
# } alpm_event_hook_t;

# typedef struct _alpm_event_hook_run_t {
# 	/** Type of event.*/
# 	alpm_event_type_t type;
# 	/** Name of hook */
# 	const char *name;
# 	/** Description of hook to be outputted */
# 	const char *desc;
# 	/** position of hook being run */
# 	size_t position;
# 	/** total hooks being run */
# 	size_t total;
# } alpm_event_hook_run_t;

# /** Events.
#  * This is an union passed to the callback, that allows the frontend to know
#  * which type of event was triggered (via type). It is then possible to
#  * typecast the pointer to the right structure, or use the union field, in order
#  * to access event-specific data. */
# typedef union _alpm_event_t {
# 	alpm_event_type_t type;
# 	alpm_event_any_t any;
# 	alpm_event_package_operation_t package_operation;
# 	alpm_event_optdep_removal_t optdep_removal;
# 	alpm_event_delta_patch_t delta_patch;
# 	alpm_event_scriptlet_info_t scriptlet_info;
# 	alpm_event_database_missing_t database_missing;
# 	alpm_event_pkgdownload_t pkgdownload;
# 	alpm_event_pacnew_created_t pacnew_created;
# 	alpm_event_pacsave_created_t pacsave_created;
# 	alpm_event_hook_t hook;
# 	alpm_event_hook_run_t hook_run;
# } alpm_event_t;

# /** Event callback. */
# typedef void (*alpm_cb_event)(alpm_event_t *);

# typedef struct _alpm_question_any_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer. */
# 	int answer;
# } alpm_question_any_t;

# typedef struct _alpm_question_install_ignorepkg_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer: whether or not to install pkg anyway. */
# 	int install;
# 	/* Package in IgnorePkg/IgnoreGroup. */
# 	alpm_pkg_t *pkg;
# } alpm_question_install_ignorepkg_t;

# typedef struct _alpm_question_replace_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer: whether or not to replace oldpkg with newpkg. */
# 	int replace;
# 	/* Package to be replaced. */
# 	alpm_pkg_t *oldpkg;
# 	/* Package to replace with. */
# 	alpm_pkg_t *newpkg;
# 	/* DB of newpkg */
# 	alpm_db_t *newdb;
# } alpm_question_replace_t;

# typedef struct _alpm_question_conflict_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer: whether or not to remove conflict->package2. */
# 	int remove;
# 	/** Conflict info. */
# 	alpm_conflict_t *conflict;
# } alpm_question_conflict_t;

# typedef struct _alpm_question_corrupted_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer: whether or not to remove filepath. */
# 	int remove;
# 	/** Filename to remove */
# 	const char *filepath;
# 	/** Error code indicating the reason for package invalidity */
# 	alpm_errno_t reason;
# } alpm_question_corrupted_t;

# typedef struct _alpm_question_remove_pkgs_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer: whether or not to skip packages. */
# 	int skip;
# 	/** List of alpm_pkg_t* with unresolved dependencies. */
# 	alpm_list_t *packages;
# } alpm_question_remove_pkgs_t;

# typedef struct _alpm_question_select_provider_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer: which provider to use (index from providers). */
# 	int use_index;
# 	/** List of alpm_pkg_t* as possible providers. */
# 	alpm_list_t *providers;
# 	/** What providers provide for. */
# 	alpm_depend_t *depend;
# } alpm_question_select_provider_t;

# typedef struct _alpm_question_import_key_t {
# 	/** Type of question. */
# 	alpm_question_type_t type;
# 	/** Answer: whether or not to import key. */
# 	int import;
# 	/** The key to import. */
# 	alpm_pgpkey_t *key;
# } alpm_question_import_key_t;

# /**
#  * Questions.
#  * This is an union passed to the callback, that allows the frontend to know
#  * which type of question was triggered (via type). It is then possible to
#  * typecast the pointer to the right structure, or use the union field, in order
#  * to access question-specific data. */
# typedef union _alpm_question_t {
# 	alpm_question_type_t type;
# 	alpm_question_any_t any;
# 	alpm_question_install_ignorepkg_t install_ignorepkg;
# 	alpm_question_replace_t replace;
# 	alpm_question_conflict_t conflict;
# 	alpm_question_corrupted_t corrupted;
# 	alpm_question_remove_pkgs_t remove_pkgs;
# 	alpm_question_select_provider_t select_provider;
# 	alpm_question_import_key_t import_key;
# } alpm_question_t;

# /** Question callback */
# typedef void (*alpm_cb_question)(alpm_question_t *);

# /** Progress callback */
# typedef void (*alpm_cb_progress)(alpm_progress_t, const char *, int, size_t, size_t);

# /*
#  * Downloading
#  */

# /** Type of download progress callbacks.
#  * @param filename the name of the file being downloaded
#  * @param xfered the number of transferred bytes
#  * @param total the total number of bytes to transfer
#  */
# typedef void (*alpm_cb_download)(const char *filename,
# 		off_t xfered, off_t total);

# typedef void (*alpm_cb_totaldl)(off_t total);

# /** A callback for downloading files
#  * @param url the URL of the file to be downloaded
#  * @param localpath the directory to which the file should be downloaded
#  * @param force whether to force an update, even if the file is the same
#  * @return 0 on success, 1 if the file exists and is identical, -1 on
#  * error.
#  */
# typedef int (*alpm_cb_fetch)(const char *url, const char *localpath,
# 		int force);

# /** Fetch a remote pkg.
#  * @param handle the context handle
#  * @param url URL of the package to download
#  * @return the downloaded filepath on success, NULL on error
#  */
# char *alpm_fetch_pkgurl(alpm_handle_t *handle, const char *url);

# /** @addtogroup alpm_api_options Options
#  * Libalpm option getters and setters
#  * @{
#  */

# /** Returns the callback used for logging. */
# alpm_cb_log alpm_option_get_logcb(alpm_handle_t *handle);
# /** Sets the callback used for logging. */
# int alpm_option_set_logcb(alpm_handle_t *handle, alpm_cb_log cb);

# /** Returns the callback used to report download progress. */
# alpm_cb_download alpm_option_get_dlcb(alpm_handle_t *handle);
# /** Sets the callback used to report download progress. */
# int alpm_option_set_dlcb(alpm_handle_t *handle, alpm_cb_download cb);

# /** Returns the downloading callback. */
# alpm_cb_fetch alpm_option_get_fetchcb(alpm_handle_t *handle);
# /** Sets the downloading callback. */
# int alpm_option_set_fetchcb(alpm_handle_t *handle, alpm_cb_fetch cb);

# /** Returns the callback used to report total download size. */
# alpm_cb_totaldl alpm_option_get_totaldlcb(alpm_handle_t *handle);
# /** Sets the callback used to report total download size. */
# int alpm_option_set_totaldlcb(alpm_handle_t *handle, alpm_cb_totaldl cb);

# /** Returns the callback used for events. */
# alpm_cb_event alpm_option_get_eventcb(alpm_handle_t *handle);
# /** Sets the callback used for events. */
# int alpm_option_set_eventcb(alpm_handle_t *handle, alpm_cb_event cb);

# /** Returns the callback used for questions. */
# alpm_cb_question alpm_option_get_questioncb(alpm_handle_t *handle);
# /** Sets the callback used for questions. */
# int alpm_option_set_questioncb(alpm_handle_t *handle, alpm_cb_question cb);

# /** Returns the callback used for operation progress. */
# alpm_cb_progress alpm_option_get_progresscb(alpm_handle_t *handle);
# /** Sets the callback used for operation progress. */
# int alpm_option_set_progresscb(alpm_handle_t *handle, alpm_cb_progress cb);

# /** Returns the root of the destination filesystem. Read-only. */
# const char *alpm_option_get_root(alpm_handle_t *handle);

# /** Returns the path to the database directory. Read-only. */
# const char *alpm_option_get_dbpath(alpm_handle_t *handle);

# /** Get the name of the database lock file. Read-only. */
# const char *alpm_option_get_lockfile(alpm_handle_t *handle);

# /** @name Accessors to the list of package cache directories.
#  * @{
#  */
# alpm_list_t *alpm_option_get_cachedirs(alpm_handle_t *handle);
# int alpm_option_set_cachedirs(alpm_handle_t *handle, alpm_list_t *cachedirs);
# int alpm_option_add_cachedir(alpm_handle_t *handle, const char *cachedir);
# int alpm_option_remove_cachedir(alpm_handle_t *handle, const char *cachedir);
# /** @} */

# /** @name Accessors to the list of package hook directories.
#  * @{
#  */
# alpm_list_t *alpm_option_get_hookdirs(alpm_handle_t *handle);
# int alpm_option_set_hookdirs(alpm_handle_t *handle, alpm_list_t *hookdirs);
# int alpm_option_add_hookdir(alpm_handle_t *handle, const char *hookdir);
# int alpm_option_remove_hookdir(alpm_handle_t *handle, const char *hookdir);
# /** @} */

# /** Returns the logfile name. */
# const char *alpm_option_get_logfile(alpm_handle_t *handle);
# /** Sets the logfile name. */
# int alpm_option_set_logfile(alpm_handle_t *handle, const char *logfile);

# /** Returns the path to libalpm's GnuPG home directory. */
# const char *alpm_option_get_gpgdir(alpm_handle_t *handle);
# /** Sets the path to libalpm's GnuPG home directory. */
# int alpm_option_set_gpgdir(alpm_handle_t *handle, const char *gpgdir);

# /** Returns whether to use syslog (0 is FALSE, TRUE otherwise). */
# int alpm_option_get_usesyslog(alpm_handle_t *handle);
# /** Sets whether to use syslog (0 is FALSE, TRUE otherwise). */
# int alpm_option_set_usesyslog(alpm_handle_t *handle, int usesyslog);

# /** @name Accessors to the list of no-upgrade files.
#  * These functions modify the list of files which should
#  * not be updated by package installation.
#  * @{
#  */
# alpm_list_t *alpm_option_get_noupgrades(alpm_handle_t *handle);
# int alpm_option_add_noupgrade(alpm_handle_t *handle, const char *path);
# int alpm_option_set_noupgrades(alpm_handle_t *handle, alpm_list_t *noupgrade);
# int alpm_option_remove_noupgrade(alpm_handle_t *handle, const char *path);
# int alpm_option_match_noupgrade(alpm_handle_t *handle, const char *path);
# /** @} */

# /** @name Accessors to the list of no-extract files.
#  * These functions modify the list of filenames which should
#  * be skipped packages which should
#  * not be upgraded by a sysupgrade operation.
#  * @{
#  */
# alpm_list_t *alpm_option_get_noextracts(alpm_handle_t *handle);
# int alpm_option_add_noextract(alpm_handle_t *handle, const char *path);
# int alpm_option_set_noextracts(alpm_handle_t *handle, alpm_list_t *noextract);
# int alpm_option_remove_noextract(alpm_handle_t *handle, const char *path);
# int alpm_option_match_noextract(alpm_handle_t *handle, const char *path);
# /** @} */

# /** @name Accessors to the list of ignored packages.
#  * These functions modify the list of packages that
#  * should be ignored by a sysupgrade.
#  * @{
#  */
# alpm_list_t *alpm_option_get_ignorepkgs(alpm_handle_t *handle);
# int alpm_option_add_ignorepkg(alpm_handle_t *handle, const char *pkg);
# int alpm_option_set_ignorepkgs(alpm_handle_t *handle, alpm_list_t *ignorepkgs);
# int alpm_option_remove_ignorepkg(alpm_handle_t *handle, const char *pkg);
# /** @} */

# /** @name Accessors to the list of ignored groups.
#  * These functions modify the list of groups whose packages
#  * should be ignored by a sysupgrade.
#  * @{
#  */
# alpm_list_t *alpm_option_get_ignoregroups(alpm_handle_t *handle);
# int alpm_option_add_ignoregroup(alpm_handle_t *handle, const char *grp);
# int alpm_option_set_ignoregroups(alpm_handle_t *handle, alpm_list_t *ignoregrps);
# int alpm_option_remove_ignoregroup(alpm_handle_t *handle, const char *grp);
# /** @} */

# /** @name Accessors to the list of ignored dependencies.
#  * These functions modify the list of dependencies that
#  * should be ignored by a sysupgrade.
#  * @{
#  */
# alpm_list_t *alpm_option_get_assumeinstalled(alpm_handle_t *handle);
# int alpm_option_add_assumeinstalled(alpm_handle_t *handle, const alpm_depend_t *dep);
# int alpm_option_set_assumeinstalled(alpm_handle_t *handle, alpm_list_t *deps);
# int alpm_option_remove_assumeinstalled(alpm_handle_t *handle, const alpm_depend_t *dep);
# /** @} */

# /** Returns the targeted architecture. */
# const char *alpm_option_get_arch(alpm_handle_t *handle);
# /** Sets the targeted architecture. */
# int alpm_option_set_arch(alpm_handle_t *handle, const char *arch);

# double alpm_option_get_deltaratio(alpm_handle_t *handle);
# int alpm_option_set_deltaratio(alpm_handle_t *handle, double ratio);

# int alpm_option_get_checkspace(alpm_handle_t *handle);
# int alpm_option_set_checkspace(alpm_handle_t *handle, int checkspace);

# const char *alpm_option_get_dbext(alpm_handle_t *handle);
# int alpm_option_set_dbext(alpm_handle_t *handle, const char *dbext);

# alpm_siglevel_t alpm_option_get_default_siglevel(alpm_handle_t *handle);
# int alpm_option_set_default_siglevel(alpm_handle_t *handle, alpm_siglevel_t level);

# alpm_siglevel_t alpm_option_get_local_file_siglevel(alpm_handle_t *handle);
# int alpm_option_set_local_file_siglevel(alpm_handle_t *handle, alpm_siglevel_t level);

# alpm_siglevel_t alpm_option_get_remote_file_siglevel(alpm_handle_t *handle);
# int alpm_option_set_remote_file_siglevel(alpm_handle_t *handle, alpm_siglevel_t level);

# /** @} */

# /** @addtogroup alpm_api_databases Database Functions
#  * Functions to query and manipulate the database of libalpm.
#  * @{
#  */

# /** Get the database of locally installed packages.
#  * The returned pointer points to an internal structure
#  * of libalpm which should only be manipulated through
#  * libalpm functions.
#  * @return a reference to the local database
#  */
# alpm_db_t *alpm_get_localdb(alpm_handle_t *handle);

# /** Get the list of sync databases.
#  * Returns a list of alpm_db_t structures, one for each registered
#  * sync database.
#  * @param handle the context handle
#  * @return a reference to an internal list of alpm_db_t structures
#  */
# alpm_list_t *alpm_get_syncdbs(alpm_handle_t *handle);

# /** Register a sync database of packages.
#  * @param handle the context handle
#  * @param treename the name of the sync repository
#  * @param level what level of signature checking to perform on the
#  * database; note that this must be a '.sig' file type verification
#  * @return an alpm_db_t* on success (the value), NULL on error
#  */
# alpm_db_t *alpm_register_syncdb(alpm_handle_t *handle, const char *treename,
# 		alpm_siglevel_t level);

# /** Unregister all package databases.
#  * @param handle the context handle
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_unregister_all_syncdbs(alpm_handle_t *handle);

# /** Unregister a package database.
#  * @param db pointer to the package database to unregister
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_db_unregister(alpm_db_t *db);

# /** Get the name of a package database.
#  * @param db pointer to the package database
#  * @return the name of the package database, NULL on error
#  */
# const char *alpm_db_get_name(const alpm_db_t *db);

# /** Get the signature verification level for a database.
#  * Will return the default verification level if this database is set up
#  * with ALPM_SIG_USE_DEFAULT.
#  * @param db pointer to the package database
#  * @return the signature verification level
#  */
# alpm_siglevel_t alpm_db_get_siglevel(alpm_db_t *db);

# /** Check the validity of a database.
#  * This is most useful for sync databases and verifying signature status.
#  * If invalid, the handle error code will be set accordingly.
#  * @param db pointer to the package database
#  * @return 0 if valid, -1 if invalid (pm_errno is set accordingly)
#  */
# int alpm_db_get_valid(alpm_db_t *db);

# /** @name Accessors to the list of servers for a database.
#  * @{
#  */
# alpm_list_t *alpm_db_get_servers(const alpm_db_t *db);
# int alpm_db_set_servers(alpm_db_t *db, alpm_list_t *servers);
# int alpm_db_add_server(alpm_db_t *db, const char *url);
# int alpm_db_remove_server(alpm_db_t *db, const char *url);
# /** @} */

# int alpm_db_update(int force, alpm_db_t *db);

# /** Get a package entry from a package database.
#  * @param db pointer to the package database to get the package from
#  * @param name of the package
#  * @return the package entry on success, NULL on error
#  */
# alpm_pkg_t *alpm_db_get_pkg(alpm_db_t *db, const char *name);

# /** Get the package cache of a package database.
#  * @param db pointer to the package database to get the package from
#  * @return the list of packages on success, NULL on error
#  */
# alpm_list_t *alpm_db_get_pkgcache(alpm_db_t *db);

# /** Get a group entry from a package database.
#  * @param db pointer to the package database to get the group from
#  * @param name of the group
#  * @return the groups entry on success, NULL on error
#  */
# alpm_group_t *alpm_db_get_group(alpm_db_t *db, const char *name);

# /** Get the group cache of a package database.
#  * @param db pointer to the package database to get the group from
#  * @return the list of groups on success, NULL on error
#  */
# alpm_list_t *alpm_db_get_groupcache(alpm_db_t *db);

# /** Searches a database with regular expressions.
#  * @param db pointer to the package database to search in
#  * @param needles a list of regular expressions to search for
#  * @return the list of packages matching all regular expressions on success, NULL on error
#  */
# alpm_list_t *alpm_db_search(alpm_db_t *db, const alpm_list_t *needles);

# /** Sets the usage of a database.
#  * @param db pointer to the package database to set the status for
#  * @param usage a bitmask of alpm_db_usage_t values
#  * @return 0 on success, or -1 on error
#  */
# int alpm_db_set_usage(alpm_db_t *db, alpm_db_usage_t usage);

# /** Gets the usage of a database.
#  * @param db pointer to the package database to get the status of
#  * @param usage pointer to an alpm_db_usage_t to store db's status
#  * @return 0 on success, or -1 on error
#  */
# int alpm_db_get_usage(alpm_db_t *db, alpm_db_usage_t *usage);

# /** @} */

# /** @addtogroup alpm_api_packages Package Functions
#  * Functions to manipulate libalpm packages
#  * @{
#  */

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
#  */
# int alpm_pkg_load(alpm_handle_t *handle, const char *filename, int full,
# 		alpm_siglevel_t level, alpm_pkg_t **pkg);

# /** Find a package in a list by name.
#  * @param haystack a list of alpm_pkg_t
#  * @param needle the package name
#  * @return a pointer to the package if found or NULL
#  */
# alpm_pkg_t *alpm_pkg_find(alpm_list_t *haystack, const char *needle);

# /** Free a package.
#  * @param pkg package pointer to free
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_pkg_free(alpm_pkg_t *pkg);

# /** Check the integrity (with md5) of a package from the sync cache.
#  * @param pkg package pointer
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_pkg_checkmd5sum(alpm_pkg_t *pkg);

# /** Compare two version strings and determine which one is 'newer'. */
# int alpm_pkg_vercmp(const char *a, const char *b);

# /** Computes the list of packages requiring a given package.
#  * The return value of this function is a newly allocated
#  * list of package names (char*), it should be freed by the caller.
#  * @param pkg a package
#  * @return the list of packages requiring pkg
#  */
# alpm_list_t *alpm_pkg_compute_requiredby(alpm_pkg_t *pkg);

# /** Computes the list of packages optionally requiring a given package.
#  * The return value of this function is a newly allocated
#  * list of package names (char*), it should be freed by the caller.
#  * @param pkg a package
#  * @return the list of packages optionally requiring pkg
#  */
# alpm_list_t *alpm_pkg_compute_optionalfor(alpm_pkg_t *pkg);

# /** Test if a package should be ignored.
#  * Checks if the package is ignored via IgnorePkg, or if the package is
#  * in a group ignored via IgnoreGroup.
#  * @param handle the context handle
#  * @param pkg the package to test
#  * @return 1 if the package should be ignored, 0 otherwise
#  */
# int alpm_pkg_should_ignore(alpm_handle_t *handle, alpm_pkg_t *pkg);

# /** @name Package Property Accessors
#  * Any pointer returned by these functions points to internal structures
#  * allocated by libalpm. They should not be freed nor modified in any
#  * way.
#  * @{
#  */

# /** Gets the name of the file from which the package was loaded.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_filename(alpm_pkg_t *pkg);

# /** Returns the package base name.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_base(alpm_pkg_t *pkg);

# /** Returns the package name.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_name(alpm_pkg_t *pkg);

# /** Returns the package version as a string.
#  * This includes all available epoch, version, and pkgrel components. Use
#  * alpm_pkg_vercmp() to compare version strings if necessary.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_version(alpm_pkg_t *pkg);

# /** Returns the origin of the package.
#  * @return an alpm_pkgfrom_t constant, -1 on error
#  */
# alpm_pkgfrom_t alpm_pkg_get_origin(alpm_pkg_t *pkg);

# /** Returns the package description.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_desc(alpm_pkg_t *pkg);

# /** Returns the package URL.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_url(alpm_pkg_t *pkg);

# /** Returns the build timestamp of the package.
#  * @param pkg a pointer to package
#  * @return the timestamp of the build time
#  */
# int64_t alpm_pkg_get_builddate(alpm_pkg_t *pkg);

# /** Returns the install timestamp of the package.
#  * @param pkg a pointer to package
#  * @return the timestamp of the install time
#  */
# int64_t alpm_pkg_get_installdate(alpm_pkg_t *pkg);

# /** Returns the packager's name.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_packager(alpm_pkg_t *pkg);

# /** Returns the package's MD5 checksum as a string.
#  * The returned string is a sequence of 32 lowercase hexadecimal digits.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_md5sum(alpm_pkg_t *pkg);

# /** Returns the package's SHA256 checksum as a string.
#  * The returned string is a sequence of 64 lowercase hexadecimal digits.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_sha256sum(alpm_pkg_t *pkg);

# /** Returns the architecture for which the package was built.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_arch(alpm_pkg_t *pkg);

# /** Returns the size of the package. This is only available for sync database
#  * packages and package files, not those loaded from the local database.
#  * @param pkg a pointer to package
#  * @return the size of the package in bytes.
#  */
# off_t alpm_pkg_get_size(alpm_pkg_t *pkg);

# /** Returns the installed size of the package.
#  * @param pkg a pointer to package
#  * @return the total size of files installed by the package.
#  */
# off_t alpm_pkg_get_isize(alpm_pkg_t *pkg);

# /** Returns the package installation reason.
#  * @param pkg a pointer to package
#  * @return an enum member giving the install reason.
#  */
# alpm_pkgreason_t alpm_pkg_get_reason(alpm_pkg_t *pkg);

# /** Returns the list of package licenses.
#  * @param pkg a pointer to package
#  * @return a pointer to an internal list of strings.
#  */
# alpm_list_t *alpm_pkg_get_licenses(alpm_pkg_t *pkg);

# /** Returns the list of package groups.
#  * @param pkg a pointer to package
#  * @return a pointer to an internal list of strings.
#  */
# alpm_list_t *alpm_pkg_get_groups(alpm_pkg_t *pkg);

# /** Returns the list of package dependencies as alpm_depend_t.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#  */
# alpm_list_t *alpm_pkg_get_depends(alpm_pkg_t *pkg);

# /** Returns the list of package optional dependencies.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#  */
# alpm_list_t *alpm_pkg_get_optdepends(alpm_pkg_t *pkg);

# /** Returns the list of packages conflicting with pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#  */
# alpm_list_t *alpm_pkg_get_conflicts(alpm_pkg_t *pkg);

# /** Returns the list of packages provided by pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#  */
# alpm_list_t *alpm_pkg_get_provides(alpm_pkg_t *pkg);

# /** Returns the list of available deltas for pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of strings.
#  */
# alpm_list_t *alpm_pkg_get_deltas(alpm_pkg_t *pkg);

# /** Returns the list of packages to be replaced by pkg.
#  * @param pkg a pointer to package
#  * @return a reference to an internal list of alpm_depend_t structures.
#  */
# alpm_list_t *alpm_pkg_get_replaces(alpm_pkg_t *pkg);

# /** Returns the list of files installed by pkg.
#  * The filenames are relative to the install root,
#  * and do not include leading slashes.
#  * @param pkg a pointer to package
#  * @return a pointer to a filelist object containing a count and an array of
#  * package file objects
#  */
# alpm_filelist_t *alpm_pkg_get_files(alpm_pkg_t *pkg);

# /** Returns the list of files backed up when installing pkg.
#  * @param pkg a pointer to package
#  * @return a reference to a list of alpm_backup_t objects
#  */
# alpm_list_t *alpm_pkg_get_backup(alpm_pkg_t *pkg);

# /** Returns the database containing pkg.
#  * Returns a pointer to the alpm_db_t structure the package is
#  * originating from, or NULL if the package was loaded from a file.
#  * @param pkg a pointer to package
#  * @return a pointer to the DB containing pkg, or NULL.
#  */
# alpm_db_t *alpm_pkg_get_db(alpm_pkg_t *pkg);

# /** Returns the base64 encoded package signature.
#  * @param pkg a pointer to package
#  * @return a reference to an internal string
#  */
# const char *alpm_pkg_get_base64_sig(alpm_pkg_t *pkg);

# /** Returns the method used to validate a package during install.
#  * @param pkg a pointer to package
#  * @return an enum member giving the validation method
#  */
# alpm_pkgvalidation_t alpm_pkg_get_validation(alpm_pkg_t *pkg);

# /* End of alpm_pkg_t accessors */
# /* @} */

# /** Open a package changelog for reading.
#  * Similar to fopen in functionality, except that the returned 'file
#  * stream' could really be from an archive as well as from the database.
#  * @param pkg the package to read the changelog of (either file or db)
#  * @return a 'file stream' to the package changelog
#  */
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
#  */
# size_t alpm_pkg_changelog_read(void *ptr, size_t size,
# 		const alpm_pkg_t *pkg, void *fp);

# int alpm_pkg_changelog_close(const alpm_pkg_t *pkg, void *fp);

# /** Open a package mtree file for reading.
#  * @param pkg the local package to read the changelog of
#  * @return a archive structure for the package mtree file
#  */
# struct archive *alpm_pkg_mtree_open(alpm_pkg_t *pkg);

# /** Read next entry from a package mtree file.
#  * @param pkg the package that the mtree file is being read from
#  * @param archive the archive structure reading from the mtree file
#  * @param entry an archive_entry to store the entry header information
#  * @return 0 if end of archive is reached, non-zero otherwise.
#  */
# int alpm_pkg_mtree_next(const alpm_pkg_t *pkg, struct archive *archive,
# 		struct archive_entry **entry);

# int alpm_pkg_mtree_close(const alpm_pkg_t *pkg, struct archive *archive);

# /** Returns whether the package has an install scriptlet.
#  * @return 0 if FALSE, TRUE otherwise
#  */
# int alpm_pkg_has_scriptlet(alpm_pkg_t *pkg);

# /** Returns the size of download.
#  * Returns the size of the files that will be downloaded to install a
#  * package.
#  * @param newpkg the new package to upgrade to
#  * @return the size of the download
#  */
# off_t alpm_pkg_download_size(alpm_pkg_t *newpkg);

# alpm_list_t *alpm_pkg_unused_deltas(alpm_pkg_t *pkg);

# /** Set install reason for a package in the local database.
#  * The provided package object must be from the local database or this method
#  * will fail. The write to the local database is performed immediately.
#  * @param pkg the package to update
#  * @param reason the new install reason
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_pkg_set_reason(alpm_pkg_t *pkg, alpm_pkgreason_t reason);


# /* End of alpm_pkg */
# /** @} */

# /*
#  * Filelists
#  */

# /** Determines whether a package filelist contains a given path.
#  * The provided path should be relative to the install root with no leading
#  * slashes, e.g. "etc/localtime". When searching for directories, the path must
#  * have a trailing slash.
#  * @param filelist a pointer to a package filelist
#  * @param path the path to search for in the package
#  * @return a pointer to the matching file or NULL if not found
#  */
# alpm_file_t *alpm_filelist_contains(alpm_filelist_t *filelist, const char *path);

# /*
#  * Signatures
#  */

# int alpm_pkg_check_pgp_signature(alpm_pkg_t *pkg, alpm_siglist_t *siglist);

# int alpm_db_check_pgp_signature(alpm_db_t *db, alpm_siglist_t *siglist);

# int alpm_siglist_cleanup(alpm_siglist_t *siglist);

# int alpm_decode_signature(const char *base64_data,
# 		unsigned char **data, size_t *data_len);

# int alpm_extract_keyid(alpm_handle_t *handle, const char *identifier,
# 		const unsigned char *sig, const size_t len, alpm_list_t **keys);

# /*
#  * Groups
#  */

# alpm_list_t *alpm_find_group_pkgs(alpm_list_t *dbs, const char *name);

# /*
#  * Sync
#  */

# alpm_pkg_t *alpm_sync_newversion(alpm_pkg_t *pkg, alpm_list_t *dbs_sync);

# /** @addtogroup alpm_api_trans Transaction Functions
#  * Functions to manipulate libalpm transactions
#  * @{
#  */

# /** Returns the bitfield of flags for the current transaction.
#  * @param handle the context handle
#  * @return the bitfield of transaction flags
#  */
# alpm_transflag_t alpm_trans_get_flags(alpm_handle_t *handle);

# /** Returns a list of packages added by the transaction.
#  * @param handle the context handle
#  * @return a list of alpm_pkg_t structures
#  */
# alpm_list_t *alpm_trans_get_add(alpm_handle_t *handle);

# /** Returns the list of packages removed by the transaction.
#  * @param handle the context handle
#  * @return a list of alpm_pkg_t structures
#  */
# alpm_list_t *alpm_trans_get_remove(alpm_handle_t *handle);

# /** Initialize the transaction.
#  * @param handle the context handle
#  * @param flags flags of the transaction (like nodeps, etc)
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_trans_init(alpm_handle_t *handle, alpm_transflag_t flags);

# /** Prepare a transaction.
#  * @param handle the context handle
#  * @param data the address of an alpm_list where a list
#  * of alpm_depmissing_t objects is dumped (conflicting packages)
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_trans_prepare(alpm_handle_t *handle, alpm_list_t **data);

# /** Commit a transaction.
#  * @param handle the context handle
#  * @param data the address of an alpm_list where detailed description
#  * of an error can be dumped (i.e. list of conflicting files)
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_trans_commit(alpm_handle_t *handle, alpm_list_t **data);

# /** Interrupt a transaction.
#  * @param handle the context handle
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_trans_interrupt(alpm_handle_t *handle);

# /** Release a transaction.
#  * @param handle the context handle
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_trans_release(alpm_handle_t *handle);
# /** @} */

# /** @name Common Transactions */
# /** @{ */

# /** Search for packages to upgrade and add them to the transaction.
#  * @param handle the context handle
#  * @param enable_downgrade allow downgrading of packages if the remote version is lower
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_sync_sysupgrade(alpm_handle_t *handle, int enable_downgrade);

# /** Add a package to the transaction.
#  * If the package was loaded by alpm_pkg_load(), it will be freed upon
#  * alpm_trans_release() invocation.
#  * @param handle the context handle
#  * @param pkg the package to add
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_add_pkg(alpm_handle_t *handle, alpm_pkg_t *pkg);

# /** Add a package removal action to the transaction.
#  * @param handle the context handle
#  * @param pkg the package to uninstall
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#  */
# int alpm_remove_pkg(alpm_handle_t *handle, alpm_pkg_t *pkg);

# /** @} */

# /** @addtogroup alpm_api_depends Dependency Functions
#  * Functions dealing with libalpm representation of dependency
#  * information.
#  * @{
#  */

# alpm_list_t *alpm_checkdeps(alpm_handle_t *handle, alpm_list_t *pkglist,
# 		alpm_list_t *remove, alpm_list_t *upgrade, int reversedeps);
# alpm_pkg_t *alpm_find_satisfier(alpm_list_t *pkgs, const char *depstring);
# alpm_pkg_t *alpm_find_dbs_satisfier(alpm_handle_t *handle,
# 		alpm_list_t *dbs, const char *depstring);

# alpm_list_t *alpm_checkconflicts(alpm_handle_t *handle, alpm_list_t *pkglist);

# /** Returns a newly allocated string representing the dependency information.
#  * @param dep a dependency info structure
#  * @return a formatted string, e.g. "glibc>=2.12"
#  */
# char *alpm_dep_compute_string(const alpm_depend_t *dep);

# /** Return a newly allocated dependency information parsed from a string
#  * @param depstring a formatted string, e.g. "glibc=2.12"
#  * @return a dependency info structure
#  */
# alpm_depend_t *alpm_dep_from_string(const char *depstring);

# /** Free a dependency info structure
#  * @param dep struct to free
#  */
# void alpm_dep_free(alpm_depend_t *dep);

# /** @} */

# /** @} */

# void alpm_fileconflict_free(alpm_fileconflict_t *conflict);
# void alpm_depmissing_free(alpm_depmissing_t *miss);
# void alpm_conflict_free(alpm_conflict_t *conflict);

end
