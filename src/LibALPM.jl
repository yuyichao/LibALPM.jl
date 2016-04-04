#!/usr/bin/julia -f

module LibALPM

const depfile = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if isfile(depfile)
    include(depfile)
else
    error("LibALPM not properly installed. Please run Pkg.build(\"LibALPM\")")
end

include("enums.jl")
include("list.jl")
include("weakdict.jl")

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
    dbs::CObjMap
    function Handle(root, db)
        err = Ref{errno_t}()
        ptr = ccall((:alpm_initialize, libalpm), Ptr{Void},
                    (Cstring, Cstring, Ref{errno_t}), root, db, err)
        ptr == C_NULL && throw(Error(err[], "Create ALPM handle"))
        self = new(ptr, CObjMap())
        finalizer(self, release)
        all_handlers[ptr] = self
        self
    end
    function Handle(ptr::Ptr{Void})
        ptr == C_NULL && throw(UndefRefError())
        cached = all_handlers[ptr, Handle]
        isnull(cached) || return get(cached)
        self = new(ptr, CObjMap())
        finalizer(self, release)
        all_handlers[ptr] = self
        self
    end
end

const all_handlers = CObjMap()

function _null_all_dbs(cmap::CObjMap)
    for (k, v) in cmap.dict
        val = v.value
        val === nothing && continue
        db = val::DB
        db.ptr = C_NULL
    end
    empty!(cmap.dict)
end

function release(hdl::Handle)
    ptr = hdl.ptr
    hdl.ptr = C_NULL
    dbs = hdl.dbs
    ptr == C_NULL && return
    delete!(all_handlers, ptr)
    _null_all_dbs(dbs)
    ccall((:alpm_release, libalpm), Cint, (Ptr{Void},), ptr)
    nothing
end

Base.cconvert(::Type{Ptr{Void}}, hdl::Handle) = hdl
function Base.unsafe_convert(::Type{Ptr{Void}}, hdl::Handle)
    ptr = hdl.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end

"Returns the current error code from the handle"
Base.errno(hdl::Handle) =
    ccall((:alpm_errno, libalpm), errno_t, (Ptr{Void},), hdl)
Error(hdl::Handle, msg) = Error(errno(hdl), msg)

function unlock(hdl::Handle)
    if ccall((:alpm_unlock, libalpm), Cint, (Ptr{Void},), hdl) != 0
        throw(Error(hdl, "Unlock handle"))
    end
end

type DB
    ptr::Ptr{Void}
    hdl::Handle
    function DB(ptr::Ptr{Void}, hdl::Handle)
        ptr == C_NULL && throw(UndefRefError())
        cached = hdl.dbs[ptr, DB]
        isnull(cached) || return get(cached)
        self = new(ptr, hdl)
        hdl.dbs[ptr] = self
        self
    end
    function DB(ptr::Ptr{Void})
        ptr == C_NULL && throw(UndefRefError())
        # WARNING! Internal libalpm API used
        hdlptr = unsafe_load(Ptr{Ptr{Void}}(ptr))
        DB(ptr, Handle(hdlptr))
    end
end

# typedef struct __alpm_pkg_t alpm_pkg_t;
# typedef struct __alpm_trans_t alpm_trans_t;

"Dependency"
immutable Depend
    name::Cstring
    version::Cstring
    dest::Cstring
    name_hash::Culong
    mod::depmod_t
end

"Missing dependency"
immutable DepMissing
    target::Cstring
    depend::Ptr{Depend}
    # this is used only in the case of a remove dependency error
    causingpkg::Cstring
end

"Conflict"
immutable Conflict
    package1_hash::Culong
    package2_hash::Culong
    package1::Cstring
    package2::Cstring
    reason::Ptr{Depend}
end

"File conflict"
immutable FileConflict
    target::Cstring
    _type::fileconflicttype_t
    file::Cstring
    ctarget::Cstring
end

"Package group"
immutable Group
    name::Cstring
    # FIXME: alpm_list_t*
    package::Ptr{Void}
end

"Package upgrade delta"
immutable Delta
    # filename of the delta patch
    delta::Cstring
    # md5sum of the delta file
    delta_md5::Cstring
    # filename of the 'before' file
    from::Cstring
    # filename of the 'after' file
    to::Cstring
    # filesize of the delta file
    delta_size::Int64
    # download filesize of the delta file
    download_size::Int64
end

"File in a package"
immutable File
    name::Cstring
    size::Int64
    mode::Cint # mode_t
end

"Package filelist container"
immutable FileList
    count::Csize_t
    files::Ptr{File}
end

"Local package or package file backup entry"
immutable Backup
    name::Cstring
    hash::Cstring
end

immutable PGPKey
    data::Ptr{Void}
    fingerprint::Cstring
    uid::Cstring
    name::Cstring
    email::Cstring
    created::Int64
    expires::Int64
    length::Cuint
    revoked::Cuint
    pubkey_algo::Cchar
end

"""
Signature result

Contains the key, status, and validity of a given signature.
"""
immutable SigResult
    key::PGPKey
    status::sigstatus_t
    validity::sigvalidity_t
end

"""
Signature list

Contains the number of signatures found and a pointer to an array of results.
The array is of size count.
"""
immutable SigList
    count::Csize_t
    results::Ptr{SigResult}
end

# typedef void (*alpm_cb_log)(alpm_loglevel_t, const char *, va_list);

# int alpm_logaction(alpm_handle_t *handle, const char *prefix,
# const char *fmt, ...) __attribute__((format(printf, 3, 4)));

module Event
import LibALPM: LibALPM, event_type_t

abstract AbstractEvent

immutable AnyEvent <: AbstractEvent
    _type::event_type_t
end

immutable PackageOperation <: AbstractEvent
    _type::event_type_t
    operation::LibALPM.package_operation_t
    oldpkg::Ptr{Void} # alpm_pkg_t*
    newpkg::Ptr{Void} # alpm_pkg_t*
end

immutable OptdepRemoval <: AbstractEvent
    _type::event_type_t
    # Package with the optdep.
    pkg::Ptr{Void} # alpm_pkg_t*
    # Optdep being removed.
    optdep::Ptr{LibALPM.Depend}
end

immutable DeltaPatch <: AbstractEvent
    _type::event_type_t
    # Delta info
    delta::Ptr{LibALPM.Delta}
end

immutable ScripletInfo <: AbstractEvent
    _type::event_type_t
    # Line of scriptlet output.
    line::Cstring
end

immutable DatabaseMissing <: AbstractEvent
    _type::event_type_t
    # Name of the database.
    dbname::Cstring
end

immutable PkgDownload <: AbstractEvent
    _type::event_type_t
    # Name of the file
    file::Cstring
end

immutable PacnewCreated <: AbstractEvent
    _type::event_type_t
    # Whether the creation was result of a NoUpgrade or not
    from_noupgrade::Cint
    # Old package.
    oldpkg::Ptr{Void} # alpm_pkg_t*
    # New Package.
    newpkg::Ptr{Void} # alpm_pkg_t*
    # Filename of the file without the .pacnew suffix
    file::Cstring
end

immutable PacsaveCreated <: AbstractEvent
    _type::event_type_t
    # Whether the creation was result of a NoUpgrade or not
    from_noupgrade::Cint
    # Old package.
    oldpkg::Ptr{Void} # alpm_pkg_t*
    # Filename of the file without the .pacsave suffix.
    file::Cstring
end

immutable Hook <: AbstractEvent
    _type::event_type_t
    # Type of hooks.
    when::LibALPM.hook_when_t
end

immutable HookRun <: AbstractEvent
    _type::event_type_t
    # Name of hook
    name::Cstring
    # Description of hook to be outputted
    desc::Cstring
    # position of hook being run
    position::Csize_t
    # total hooks being run
    total::Csize_t
end
end
import .Event.AbstractEvent

function dispatch_event(ptr::Ptr{Void}, cb)
    event_type = unsafe_load(Ptr{event_type_t}(ptr))
    if (event_type == EventType.PACKAGE_OPERATION_START ||
        event_type == EventType.PACKAGE_OPERATION_DONE)
        cb(event_type, unsafe_load(Ptr{Event.PackageOperation}(ptr)))
    elseif event_type == EventType.OPTDEP_REMOVAL
        cb(event_type, unsafe_load(Ptr{Event.OptdepRemoval}(ptr)))
    elseif (event_type == EventType.DELTA_PATCHES_START ||
            event_type == EventType.DELTA_PATCH_START ||
            event_type == EventType.DELTA_PATCH_DONE ||
            event_type == EventType.DELTA_PATCH_FAILED ||
            event_type == EventType.DELTA_PATCHES_DONE)
        cb(event_type, unsafe_load(Ptr{Event.DeltaPatch}(ptr)))
    elseif event_type == EventType.SCRIPTLET_INFO
        cb(event_type, unsafe_load(Ptr{Event.ScriptletInfo}(ptr)))
    elseif event_type == EventType.DATABASE_MISSING
        cb(event_type, unsafe_load(Ptr{Event.DatabaseMissing}(ptr)))
    elseif (event_type == EventType.PKGDOWNLOAD_START ||
            event_type == EventType.PKGDOWNLOAD_DONE ||
            event_type == EventType.PKGDOWNLOAD_FAILED)
        cb(event_type, unsafe_load(Ptr{Event.PkgDownload}(ptr)))
    elseif event_type == EventType.PACNEW_CREATED
        cb(event_type, unsafe_load(Ptr{Event.PacnewCreated}(ptr)))
    elseif event_type == EventType.PACSAVE_CREATED
        cb(event_type, unsafe_load(Ptr{Event.PacsaveCreated}(ptr)))
    elseif (event_type == EventType.HOOK_START ||
            event_type == EventType.HOOK_DONE)
        cb(event_type, unsafe_load(Ptr{Event.Hook}(ptr)))
    elseif (event_type == EventType.HOOK_RUN_START ||
            event_type == EventType.HOOK_RUN_DONE)
        cb(event_type, unsafe_load(Ptr{Event.HookRun}(ptr)))
    else
        cb(event_type, unsafe_load(Ptr{Event.AnyEvent}(ptr)))
    end
end

# Event callback.
# typedef void (*alpm_cb_event)(alpm_event_t *);

module Question
import LibALPM
abstract AbstractQuestion

immutable AnyQuestion
    # Type of question
    _type::Cint
    # Answer
    answer::Cint
end

immutable InstallIgnorepkg
    # Type of question
    _type::Cint
    # Answer: whether or not to install pkg anyway
    install::Cint
    # Package in IgnorePkg/IgnoreGroup
    pkg::Ptr{Void} # alpm_pkg_t*
end

immutable Replace
    # Type of question
    _type::Cint
    # Answer: whether or not to replace oldpkg with newpkg
    replace::Cint
    # Package to be replaced
    oldpkg::Ptr{Void} # alpm_pkg_t*
    # Package to replace with
    newpkg::Ptr{Void} # alpm_pkg_t*
    # DB of newpkg
    newdb::Ptr{Void} # alpm_db_t*
end

immutable Conflict
    # Type of question
    _type::Cint
    # Answer: whether or not to remove conflict->package2
    remove::Cint
    # Conflict info
    conflict::Ptr{LibALPM.Conflict}
end

immutable Corrupted
    # Type of question
    _type::Cint
    # Answer: whether or not to remove filepath.
    remove::Cint
    # Filename to remove
    filepath::Cstring
    # Error code indicating the reason for package invalidity
    reason::LibALPM.errno_t
end

immutable RemovePkgs
    # Type of question
    _type::Cint
    # Answer: whether or not to skip packages
    skip::Cint
    # List of alpm_pkg_t* with unresolved dependencies
    # FIXME: alpm_list_t*
    packages::Ptr{Void}
end

immutable SelectProvider
    # Type of question
    _type::Cint
    # Answer: which provider to use (index from providers)
    use_index::Cint
    # List of alpm_pkg_t* as possible providers
    # FIXME: alpm_list_t*
    providers::Ptr{Void}
    # What providers provide for
    depend::Ptr{LibALPM.Depend}
end

immutable ImportKey
    # Type of question
    _type::Cint
    # Answer: whether or not to import key
    _import::Cint
    # The key to import
    key::Ptr{LibALPM.PGPKey}
end

end

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

"""
Fetch a remote pkg

`hdl`: the context handle
`url` URL of the package to download
Returns the downloaded filepath on success.
"""
function fetch_pkgurl(hdl::Handle, url)
    utf8(ccall((:alpm_fetch_pkgurl, libalpm), Ptr{UInt8},
               (Ptr{Void}, Cstring), hdl, url))
end

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

"Returns the root of the destination filesystem"
function get_root(hdl::Handle)
    utf8(ccall((:alpm_option_get_root, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end

"Returns the path to the database directory"
function get_dbpath(hdl::Handle)
    utf8(ccall((:alpm_option_get_dbpath, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end

"Get the name of the database lock file"
function get_lockfile(hdl::Handle)
    utf8(ccall((:alpm_option_get_lockfile, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end

# Accessors to the list of package cache directories
function get_cachedirs(hdl::Handle)
    dirs = ccall((:alpm_option_get_cachedirs, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_cachedirs(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_cachedirs, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_cachedirs"))
    end
end
function add_cachedir(hdl::Handle, cachedir)
    ret = ccall((:alpm_option_add_cachedir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, cachedir)
    ret == 0 || throw(Error(hdl, "add_cachedir"))
    nothing
end
function remove_cachedir(hdl::Handle, cachedir)
    ret = ccall((:alpm_option_remove_cachedir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, cachedir)
    ret < 0 && throw(Error(hdl, "remove_cachedir"))
    ret != 0
end

# Accessors to the list of package hook directories
function get_hookdirs(hdl::Handle)
    dirs = ccall((:alpm_option_get_hookdirs, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_hookdirs(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_hookdirs, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_hookdirs"))
    end
end
function add_hookdir(hdl::Handle, hookdir)
    ret = ccall((:alpm_option_add_hookdir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, hookdir)
    ret == 0 || throw(Error(hdl, "add_hookdir"))
    nothing
end
function remove_hookdir(hdl::Handle, hookdir)
    ret = ccall((:alpm_option_remove_hookdir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, hookdir)
    ret < 0 && throw(Error(hdl, "remove_hookdir"))
    ret != 0
end

"Returns the logfile name"
function get_logfile(hdl::Handle)
    utf8(ccall((:alpm_option_get_logfile, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end
"Sets the logfile name"
function set_logfile(hdl::Handle, logfile)
    ret = ccall((:alpm_option_set_logfile, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, logfile)
    ret == 0 || throw(Error(hdl, "set_logfile"))
    nothing
end

"Returns the path to libalpm's GnuPG home directory"
function get_gpgdir(hdl::Handle)
    utf8(ccall((:alpm_option_get_gpgdir, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end
"Sets the path to libalpm's GnuPG home directory"
function set_gpgdir(hdl::Handle, gpgdir)
    ret = ccall((:alpm_option_set_gpgdir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, gpgdir)
    ret == 0 || throw(Error(hdl, "set_gpgdir"))
    nothing
end

"Returns whether to use syslog"
function get_usesyslog(hdl::Handle)
    ccall((:alpm_option_get_usesyslog, libalpm), Cint, (Ptr{Void},), hdl) != 0
end
"Sets whether to use syslog"
function set_usesyslog(hdl::Handle, usesyslog)
    ret = ccall((:alpm_option_set_usesyslog, libalpm), Cint,
                (Ptr{Void}, Cint), hdl, usesyslog)
    ret == 0 || throw(Error(hdl, "usesyslog"))
    nothing
end

# Accessors to the list of no-upgrade files.
#
# These functions modify the list of files which should
# not be updated by package installation.
function get_noupgrades(hdl::Handle)
    dirs = ccall((:alpm_option_get_noupgrades, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_noupgrades(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_noupgrades, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_noupgrades"))
    end
end
function add_noupgrade(hdl::Handle, noupgrade)
    ret = ccall((:alpm_option_add_noupgrade, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, noupgrade)
    ret == 0 || throw(Error(hdl, "add_noupgrade"))
    nothing
end
function remove_noupgrade(hdl::Handle, noupgrade)
    ret = ccall((:alpm_option_remove_noupgrade, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, noupgrade)
    ret < 0 && throw(Error(hdl, "remove_noupgrade"))
    ret != 0
end
"""
Return 0 if string matches pattern,
negative if they don't match and positive if the last match was inverted.
"""
function match_noupgrade(hdl::Handle, noupgrade)
    ccall((:alpm_option_match_noupgrade, libalpm), Cint,
          (Ptr{Void}, Cstring), hdl, noupgrade)
end

# Accessors to the list of no-extract files.
#
# These functions modify the list of filenames which should
# be skipped packages which should not be upgraded by a sysupgrade operation.
function get_noextracts(hdl::Handle)
    dirs = ccall((:alpm_option_get_noextracts, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_noextracts(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_noextracts, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_noextracts"))
    end
end
function add_noextract(hdl::Handle, noextract)
    ret = ccall((:alpm_option_add_noextract, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, noextract)
    ret == 0 || throw(Error(hdl, "add_noextract"))
    nothing
end
function remove_noextract(hdl::Handle, noextract)
    ret = ccall((:alpm_option_remove_noextract, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, noextract)
    ret < 0 && throw(Error(hdl, "remove_noextract"))
    ret != 0
end
"""
Return 0 if string matches pattern,
negative if they don't match and positive if the last match was inverted.
"""
function match_noextract(hdl::Handle, noextract)
    ccall((:alpm_option_match_noextract, libalpm), Cint,
          (Ptr{Void}, Cstring), hdl, noextract)
end

# Accessors to the list of ignored packages.
#
# These functions modify the list of packages that
# should be ignored by a sysupgrade.
function get_ignorepkgs(hdl::Handle)
    dirs = ccall((:alpm_option_get_ignorepkgs, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_ignorepkgs(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_ignorepkgs, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "ignorepkgs"))
    end
end
function add_ignorepkg(hdl::Handle, ignorepkg)
    ret = ccall((:alpm_option_add_ignorepkg, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, ignorepkg)
    ret == 0 || throw(Error(hdl, "add_ignorepkg"))
    nothing
end
function remove_ignorepkg(hdl::Handle, ignorepkg)
    ret = ccall((:alpm_option_remove_ignorepkg, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, ignorepkg)
    ret < 0 && throw(Error(hdl, "remove_ignorepkg"))
    ret != 0
end

# Accessors to the list of ignored groups.
#
# These functions modify the list of groups whose packages
# should be ignored by a sysupgrade.
function get_ignoregroups(hdl::Handle)
    dirs = ccall((:alpm_option_get_ignoregroups, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_ignoregroups(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_ignoregroups, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_ignoregroups"))
    end
end
function add_ignoregroup(hdl::Handle, ignoregroup)
    ret = ccall((:alpm_option_add_ignoregroup, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, ignoregroup)
    ret == 0 || throw(Error(hdl, "add_ignoregroup"))
    nothing
end
function remove_ignoregroup(hdl::Handle, ignoregroup)
    ret = ccall((:alpm_option_remove_ignoregroup, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, ignoregroup)
    ret < 0 && throw(Error(hdl, "remove_ignoregroup"))
    ret != 0
end

# Accessors to the list of ignored dependencies.
# These functions modify the list of dependencies that
# should be ignored by a sysupgrade.
#
# alpm_list_t *alpm_option_get_assumeinstalled(alpm_handle_t *handle);
# int alpm_option_add_assumeinstalled(alpm_handle_t *handle, const alpm_depend_t *dep);
# int alpm_option_set_assumeinstalled(alpm_handle_t *handle, alpm_list_t *deps);
# int alpm_option_remove_assumeinstalled(alpm_handle_t *handle, const alpm_depend_t *dep);
# /** @}

"Returns the targeted architecture"
function get_arch(hdl::Handle)
    ascii(ccall((:alpm_option_get_arch, libalpm), Ptr{UInt8},
                (Ptr{Void},), hdl))
end
"Sets the targeted architecture"
function set_arch(hdl::Handle, arch)
    ret = ccall((:alpm_option_set_arch, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, arch)
    ret == 0 || throw(Error(hdl, "set_arch"))
    nothing
end

function get_deltaratio(hdl::Handle)
    ccall((:alpm_option_get_deltaratio, libalpm), Cdouble,
          (Ptr{Void},), hdl)
end
function set_deltaratio(hdl::Handle, deltaratio)
    ret = ccall((:alpm_option_set_deltaratio, libalpm), Cint,
                (Ptr{Void}, Cdouble), hdl, deltaratio)
    ret == 0 || throw(Error(hdl, "set_deltaratio"))
    nothing
end

function get_checkspace(hdl::Handle)
    ccall((:alpm_option_get_checkspace, libalpm), Cint, (Ptr{Void},), hdl) != 0
end
function set_checkspace(hdl::Handle, checkspace)
    ret = ccall((:alpm_option_set_checkspace, libalpm), Cint,
                (Ptr{Void}, Cint), hdl, checkspace)
    ret == 0 || throw(Error(hdl, "set_checkspace"))
    nothing
end

function get_dbext(hdl::Handle)
    utf8(ccall((:alpm_option_get_dbext, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end
function set_dbext(hdl::Handle, dbext)
    ret = ccall((:alpm_option_set_dbext, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, dbext)
    ret == 0 || throw(Error(hdl, "set_dbext"))
    nothing
end

function get_default_siglevel(hdl::Handle)
    ccall((:alpm_option_get_default_siglevel, libalpm), Cint, (Ptr{Void},), hdl)
end
function set_default_siglevel(hdl::Handle, siglevel)
    ret = ccall((:alpm_option_set_default_siglevel, libalpm), Cint,
                (Ptr{Void}, Cint), hdl, siglevel)
    ret == 0 || throw(Error(hdl, "set_default_siglevel"))
    nothing
end

function get_local_file_siglevel(hdl::Handle)
    ccall((:alpm_option_get_local_file_siglevel, libalpm),
          Cint, (Ptr{Void},), hdl)
end
function set_local_file_siglevel(hdl::Handle, siglevel)
    ret = ccall((:alpm_option_set_local_file_siglevel, libalpm), Cint,
                (Ptr{Void}, Cint), hdl, siglevel)
    ret == 0 || throw(Error(hdl, "set_local_file_siglevel"))
    nothing
end

function get_remote_file_siglevel(hdl::Handle)
    ccall((:alpm_option_get_remote_file_siglevel, libalpm),
          Cint, (Ptr{Void},), hdl)
end
function set_remote_file_siglevel(hdl::Handle, siglevel)
    ret = ccall((:alpm_option_set_remote_file_siglevel, libalpm), Cint,
                (Ptr{Void}, Cint), hdl, siglevel)
    ret == 0 || throw(Error(hdl, "set_remote_file_siglevel"))
    nothing
end

# Database Functions
#
# Functions to query and manipulate the database of libalpm.

"""
Get the database of locally installed packages.

Return a reference to the local database
"""
get_localdb(hdl::Handle) =
    DB(ccall((:alpm_get_localdb, libalpm), Ptr{Void}, (Ptr{Void},), hdl), hdl)

"""
Get the list of sync databases.

Returns an array of DB's, one for each registered sync database.
"""
function get_syncdbs(hdl::Handle)
    dbs = ccall((:alpm_get_syncdbs, libalpm), Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(DB, dbs, p->DB(p, hdl))
end

"""
Register a sync database of packages.

`treename`: the name of the sync repository
`level`: what level of signature checking to perform on the database;
         note that this must be a '.sig' file type verification

Returns an DB on success
"""
function register_syncdb(hdl::Handle, treename, level)
    db = ccall((:alpm_register_syncdb, libalpm), Ptr{Void},
               (Ptr{Void}, Cstring, UInt32), hdl, treename, level)
    db == C_NULL && throw(Error(hdl, "register_syncdb"))
    DB(db, hdl)
end

"Unregister all package databases"
function unregister_all_syncdbs(hdl::Handle)
    # This covers local db too
    _null_all_dbs(hdl.dbs)
    ret = ccall((:alpm_unregister_all_syncdbs, libalpm), Cint, (Ptr{Void},), hdl)
    ret == 0 || throw(Error(hdl, "unregister_all_syncdbs"))
    nothing
end

"Unregister a package database"
function unregister(db::DB)
    ptr = db.ptr
    ptr == C_NULL && throw(UndefRefError())
    hdl = db.hdl
    db.ptr = C_NULL
    delete!(hdl.dbs, ptr)
    ret = ccall((:alpm_db_unregister, libalpm), Cint, (Ptr{Void},), ptr)
    ret == 0 || throw(Error(hdl, "unregister"))
    nothing
end

# /** Get the name of a package database.
#  * @param db pointer to the package database
#  * @return the name of the package database, NULL on error
#
# const char *alpm_db_get_name(const alpm_db_t *db);

# /** Get the signature verification level for a database.
#  * Will return the default verification level if this database is set up
#  * with ALPM_SIG_USE_DEFAULT.
#  * @param db pointer to the package database
#  * @return the signature verification level
#
# alpm_siglevel_t alpm_db_get_siglevel(alpm_db_t *db);

# /** Check the validity of a database.
#  * This is most useful for sync databases and verifying signature status.
#  * If invalid, the handle error code will be set accordingly.
#  * @param db pointer to the package database
#  * @return 0 if valid, -1 if invalid (pm_errno is set accordingly)
#
# int alpm_db_get_valid(alpm_db_t *db);

# /** @name Accessors to the list of servers for a database.
#  * @{
#
# alpm_list_t *alpm_db_get_servers(const alpm_db_t *db);
# int alpm_db_set_servers(alpm_db_t *db, alpm_list_t *servers);
# int alpm_db_add_server(alpm_db_t *db, const char *url);
# int alpm_db_remove_server(alpm_db_t *db, const char *url);
# /** @}

# int alpm_db_update(int force, alpm_db_t *db);

# /** Get a package entry from a package database.
#  * @param db pointer to the package database to get the package from
#  * @param name of the package
#  * @return the package entry on success, NULL on error
#
# alpm_pkg_t *alpm_db_get_pkg(alpm_db_t *db, const char *name);

# /** Get the package cache of a package database.
#  * @param db pointer to the package database to get the package from
#  * @return the list of packages on success, NULL on error
#
# alpm_list_t *alpm_db_get_pkgcache(alpm_db_t *db);

# /** Get a group entry from a package database.
#  * @param db pointer to the package database to get the group from
#  * @param name of the group
#  * @return the groups entry on success, NULL on error
#
# alpm_group_t *alpm_db_get_group(alpm_db_t *db, const char *name);

# /** Get the group cache of a package database.
#  * @param db pointer to the package database to get the group from
#  * @return the list of groups on success, NULL on error
#
# alpm_list_t *alpm_db_get_groupcache(alpm_db_t *db);

# /** Searches a database with regular expressions.
#  * @param db pointer to the package database to search in
#  * @param needles a list of regular expressions to search for
#  * @return the list of packages matching all regular expressions on success, NULL on error
#
# alpm_list_t *alpm_db_search(alpm_db_t *db, const alpm_list_t *needles);

# /** Sets the usage of a database.
#  * @param db pointer to the package database to set the status for
#  * @param usage a bitmask of alpm_db_usage_t values
#  * @return 0 on success, or -1 on error
#
# int alpm_db_set_usage(alpm_db_t *db, alpm_db_usage_t usage);

# /** Gets the usage of a database.
#  * @param db pointer to the package database to get the status of
#  * @param usage pointer to an alpm_db_usage_t to store db's status
#  * @return 0 on success, or -1 on error
#
# int alpm_db_get_usage(alpm_db_t *db, alpm_db_usage_t *usage);

# /** @}

# /** @addtogroup alpm_api_packages Package Functions
#  * Functions to manipulate libalpm packages
#  * @{
#

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
#
# int alpm_pkg_load(alpm_handle_t *handle, const char *filename, int full,
# alpm_siglevel_t level, alpm_pkg_t **pkg);

# /** Find a package in a list by name.
#  * @param haystack a list of alpm_pkg_t
#  * @param needle the package name
#  * @return a pointer to the package if found or NULL
#
# alpm_pkg_t *alpm_pkg_find(alpm_list_t *haystack, const char *needle);

# /** Free a package.
#  * @param pkg package pointer to free
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
#
# int alpm_pkg_free(alpm_pkg_t *pkg);

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
#  * @{
#

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
