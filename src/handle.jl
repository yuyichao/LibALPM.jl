#!/usr/bin/julia -f

##
# handle

type Handle
    ptr::Ptr{Void}
    dbs::CObjMap
    pkgs::CObjMap
    function Handle(root, db)
        err = Ref{errno_t}()
        ptr = ccall((:alpm_initialize, libalpm), Ptr{Void},
                    (Cstring, Cstring, Ref{errno_t}), root, db, err)
        ptr == C_NULL && throw(Error(err[], "Create ALPM handle"))
        self = new(ptr, CObjMap(), CObjMap())
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

function _null_all_pkgs(cmap::CObjMap)
    for (k, v) in cmap.dict
        val = v.value
        val === nothing && continue
        pkg = val::Pkg
        pkg.ptr = C_NULL
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
    _null_all_pkgs(dbs)
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

# Accessors to the list of ignored dependencies.
# These functions modify the list of dependencies that
# should be ignored by a sysupgrade.
#
# alpm_list_t *alpm_option_get_assumeinstalled(alpm_handle_t *handle);
# int alpm_option_add_assumeinstalled(alpm_handle_t *handle, const alpm_depend_t *dep);
# int alpm_option_set_assumeinstalled(alpm_handle_t *handle, alpm_list_t *deps);
# int alpm_option_remove_assumeinstalled(alpm_handle_t *handle, const alpm_depend_t *dep);
