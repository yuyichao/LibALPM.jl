#!/usr/bin/julia -f

##
# handle

type Handle
    ptr::Ptr{Void}
    dbs::CObjMap
    pkgs::CObjMap
    transpkgs::Set
    function Handle(root, db)
        err = Ref{errno_t}()
        ptr = ccall((:alpm_initialize, libalpm), Ptr{Void},
                    (Cstring, Cstring, Ref{errno_t}), root, db, err)
        ptr == C_NULL && throw(Error(err[], "Create ALPM handle"))
        self = new(ptr, CObjMap(), CObjMap(), Set{Pkg}())
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

function Base.show(io::IO, hdl::Handle)
    print(io, "LibALPM.Handle(ptr=")
    show(io, UInt(hdl.ptr))
    print(io, ")")
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
        pkg.should_free && try
            free(pkg)
        end
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
    empty!(hdl.transpkgs)
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
    ptr = ccall((:alpm_fetch_pkgurl, libalpm), Ptr{UInt8},
                (Ptr{Void}, Cstring), hdl, url)
    ptr == C_NULL && throw(Error(hdl, "fetch_pkgurl"))
    ptr_to_utf8(ptr)
end

"Returns the root of the destination filesystem"
function get_root(hdl::Handle)
    ptr_to_utf8(ccall((:alpm_option_get_root, libalpm), Ptr{UInt8},
                      (Ptr{Void},), hdl))
end

"Returns the path to the database directory"
function get_dbpath(hdl::Handle)
    ptr_to_utf8(ccall((:alpm_option_get_dbpath, libalpm), Ptr{UInt8},
                      (Ptr{Void},), hdl))
end

"Get the name of the database lock file"
function get_lockfile(hdl::Handle)
    ptr_to_utf8(ccall((:alpm_option_get_lockfile, libalpm), Ptr{UInt8},
                      (Ptr{Void},), hdl))
end

# Accessors to the list of package cache directories
function get_cachedirs(hdl::Handle)
    dirs = ccall((:alpm_option_get_cachedirs, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, ptr_to_utf8)
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
    list_to_array(UTF8String, dirs, ptr_to_utf8)
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
    list_to_array(UTF8String, dirs, ptr_to_utf8)
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
    list_to_array(UTF8String, dirs, ptr_to_utf8)
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
    list_to_array(UTF8String, dirs, ptr_to_utf8)
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
    list_to_array(UTF8String, dirs, ptr_to_utf8)
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
    ptr_to_ascii(ccall((:alpm_option_get_arch, libalpm), Ptr{UInt8},
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

# Package Functions
# Functions to manipulate libalpm packages

"""
Create a package from a file.

If `full` is `false`, the archive is read only until all necessary metadata is
found. If it is `true`, the entire archive is read,
which serves as a verification of integrity and the filelist can be created.

`handle: the context handle
`filename`: location of the package tarball
`full`: whether to stop the load after metadata is read or continue
        through the full archive
`level`: what level of package signature checking to perform on the
         package; note that this must be a '.sig' file type verification
"""
function load(hdl::Handle, filename, full, level)
    pkgout = Ref{Ptr{Void}}()
    ret = ccall((:alpm_pkg_load, libalpm), Cint,
                (Ptr{Void}, Cstring, Cint, UInt32, Ptr{Ptr{Void}}),
                hdl, filename, full, level, pkgout)
    ret == 0 || throw(Error(hdl, "load"))
    Pkg(pkgout[], hdl, true)
end

# Accessors to the list of ignored dependencies.
# These functions modify the list of dependencies that
# should be ignored by a sysupgrade.
function get_assumeinstalled(hdl::Handle)
    list = ccall((:alpm_option_get_assumeinstalled, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Depend, list, Depend)
end
function add_assumeinstalled(hdl::Handle, dep)
    ret = ccall((:alpm_option_add_assumeinstalled, libalpm),
                Ptr{list_t}, (Ptr{Void}, Ptr{CType.Depend}), hdl, Depend(dep))
    ret == 0 || throw(Error(hdl, "add_assumeinstalled"))
    nothing
end
function set_assumeinstalled(hdl::Handle, deps)
    list = array_to_list(deps, dep->to_c(Depend(dep)),
                         cglobal((:alpm_dep_free, libalpm)))
    ret = ccall((:alpm_option_set_assumeinstalled, libalpm),
                Ptr{list_t}, (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal((:alpm_dep_free, libalpm)))
        throw(Error(hdl, "set_assumeinstalled"))
    end
    nothing
end
function remove_assumeinstalled(hdl::Handle, dep)
    ret = ccall((:alpm_option_remove_assumeinstalled, libalpm),
                Ptr{list_t}, (Ptr{Void}, Ptr{CType.Depend}), hdl, Depend(dep))
    ret < 0 && throw(Error(hdl, "remove_assumeinstalled"))
    ret != 0
end

# Transaction Functions
# Functions to manipulate libalpm transactions

"Returns the bitfield of flags for the current transaction"
get_flags(hdl::Handle) =
    ccall((:alpm_trans_get_flags, libalpm), UInt32, (Ptr{Void},), hdl)

"Returns a list of packages added by the transaction"
function get_add(hdl::Handle)
    pkgs = ccall((:alpm_trans_get_add, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Pkg, pkgs, p->Pkg(p, hdl))
end

"Returns the list of packages removed by the transaction"
function get_remove(hdl::Handle)
    pkgs = ccall((:alpm_trans_get_remove, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Pkg, pkgs, p->Pkg(p, hdl))
end

"Initialize the transaction"
function trans_init(hdl::Handle, flags)
    ret = ccall((:alpm_trans_init, libalpm),
                Cint, (Ptr{Void}, UInt32), hdl, flags)
    ret == 0 || throw(Error(hdl, "init"))
    nothing
end

immutable TransPrepareError{T} <: AbstractError
    errno::errno_t
    list::Vector{T}
end
function Base.showerror(io::IO, err::TransPrepareError)
    println(io, "ALPM Transaction Prepare Error: $(strerror(err.errno))")
    if err.errno == Errno.PKG_INVALID_ARCH
        println(io, "Packages with invalid archs:")
    elseif errno == Errno.UNSATISFIED_DEPS
        println(io, "Missing dependencies:")
    elseif errno == Errno.CONFLICTING_DEPS
        println(io, "Conflicts:")
    end
    for pkg in err.list
        print(io, "    ")
        show(io, pkg)
        println()
    end
end

"Prepare a transaction"
function trans_prepare(hdl::Handle)
    list = Ref{Ptr{list_t}}(0)
    ret = ccall((:alpm_trans_prepare, libalpm),
                Cint, (Ptr{Void}, Ptr{Ptr{list_t}}), hdl, list)
    if ret != 0
        list[] == C_NULL && throw(Error(hdl, "trans_prepare"))
        errno = Base.errno(hdl)
        # The following part is not documented anyware AFAIK and
        # is purely based on libalpm source code...
        # What the list is for each error code
        # PKG_INVALID_ARCH:
        #     allocated string of format "<pkgname>-<pkgver>-<pkgarch>"
        # UNSATISFIED_DEPS:
        #     DepMissing with all internal pointer allocated (dup'd)
        # CONFLICTING_DEPS:
        #     Conflict with all internal pointer allocated (dup'd)
        if errno == Errno.PKG_INVALID_ARCH
            try
                ary = list_to_array(UTF8String, list[], p->ptr_to_utf8(p, true))
            catch
                free(list[], cglobal(:free))
                rethrow()
            end
            throw(TransPrepareError(errno, ary))
        elseif errno == Errno.UNSATISFIED_DEPS
            try
                ary = list_to_array(DepMissing, list[], p->DepMissing(p, true))
            catch
                free(list[], cglobal((:alpm_depmissing_free, libalpm)))
                rethrow()
            end
            throw(TransPrepareError(errno, ary))
        elseif errno == Errno.CONFLICTING_DEPS
            try
                ary = list_to_array(Conflict, list[], p->Conflict(p, true))
            catch
                free(list[], cglobal((:alpm_conflict_free, libalpm)))
                rethrow()
            end
            throw(TransPrepareError(errno, ary))
        else
            warn("LibALPM<trans_prepare>: ",
                 "ignore unknown list return for error code $errno.")
            free(list[])
            throw(Error(hdl, "trans_prepare"))
        end
    end
    nothing
end

immutable TransCommitError{T} <: AbstractError
    errno::errno_t
    list::Vector{T}
end
function Base.showerror(io::IO, err::TransCommitError)
    println(io, "ALPM Transaction Commit Error: $(strerror(err.errno))")
    if err.errno == Errno.FILE_CONFLICTS
        println(io, "File conflicts:")
    else
        println(io, "Packages:")
    end
    for pkg in err.list
        print(io, "    ")
        show(io, pkg)
        println()
    end
end

"Commit a transaction"
function trans_commit(hdl::Handle)
    list = Ref{Ptr{list_t}}(0)
    ret = ccall((:alpm_trans_commit, libalpm),
                Cint, (Ptr{Void}, Ptr{Ptr{list_t}}), hdl, list)
    if ret != 0
        list[] == C_NULL && throw(Error(hdl, "trans_commit"))
        errno = Base.errno(hdl)
        # The following part is not documented anyware AFAIK and
        # is purely based on libalpm source code...
        # What the list is for each error code
        # FILE_CONFLICTS:
        #     fileconflict dup
        # everything else:
        #     pkgname dup
        if errno == Errno.FILE_CONFLICTS
            try
                ary = list_to_array(Fileconflict, list[],
                                    p->Fileconflict(p, true))
            catch
                free(list[], cglobal((:alpm_fileconflict_free, libalpm)))
                rethrow()
            end
            throw(TransCommitError(errno, ary))
        else
            try
                ary = list_to_array(UTF8String, list[], p->ptr_to_utf8(p, true))
            catch
                free(list[], cglobal(:free))
                rethrow()
            end
            throw(TransCommitError(errno, ary))
        end
    end
    nothing
end

"Interrupt a transaction"
function trans_interrupt(hdl::Handle)
    ret = ccall((:alpm_trans_interrupt, libalpm), Cint, (Ptr{Void},), hdl)
    ret == 0 || throw(Error(hdl, "interrupt"))
    nothing
end

"Release a transaction"
function trans_release(hdl::Handle)
    transpkg = hdl.transpkgs::Set{Pkg}
    for pkg in transpkg
        free(pkg)
    end
    empty!(transpkg)
    ret = ccall((:alpm_trans_release, libalpm), Cint, (Ptr{Void},), hdl)
    ret == 0 || throw(Error(hdl, "release"))
    nothing
end

# Common Transactions

"""
Search for packages to upgrade and add them to the transaction

`enable_downgrade`: allow downgrading of packages if the remote version is lower
"""
function sysupgrade(hdl::Handle, enable_downgrade)
    ret = ccall((:alpm_sync_sysupgrade, libalpm),
                Cint, (Ptr{Void}, Cint), hdl, enable_downgrade)
    ret == 0 || throw(Error(hdl, "sysupgrade"))
    nothing
end

"""
Add a package to the transaction

If the package was loaded by `LibALPM.load()`, it will be freed upon
`LibALPM.trans_release()` invocation.
"""
function add_pkg(hdl::Handle, pkg)
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
function remove_pkg(hdl::Handle, pkg)
    ret = ccall((:alpm_remove_pkg, libalpm),
                Cint, (Ptr{Void}, Ptr{Void}), hdl, pkg)
    ret == 0 || throw(Error(hdl, "remove_pkg"))
    nothing
end

# TODO
# alpm_list_t *alpm_checkdeps(alpm_handle_t *handle, alpm_list_t *pkglist,
# alpm_list_t *remove, alpm_list_t *upgrade, int reversedeps);
# alpm_pkg_t *alpm_find_satisfier(alpm_list_t *pkgs, const char *depstring);
# alpm_pkg_t *alpm_find_dbs_satisfier(alpm_handle_t *handle,
# alpm_list_t *dbs, const char *depstring);

# alpm_list_t *alpm_checkconflicts(alpm_handle_t *handle, alpm_list_t *pkglist);
