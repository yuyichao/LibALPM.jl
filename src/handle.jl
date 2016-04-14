#!/usr/bin/julia -f

##
# handle

generic_printf_len = true
if Base.ARCH === :x86_64 && Base.OS_NAME !== :Windows
    immutable __va_list_tag
        gp_offset::Cuint
        fp_offset::Cuint
        overflow_arg_area::Ptr{Void}
        reg_save_area::Ptr{Void}
    end
    typealias va_list_arg_t Ptr{__va_list_tag}
    generic_printf_len = false
    function printf_len(fmt::Ptr{UInt8}, ap::va_list_arg_t)
        aq = unsafe_load(ap) # va_copy
        ccall(:vsnprintf, Cint,
              (Ptr{Void}, Csize_t, Ptr{UInt8}, va_list_arg_t),
              C_NULL, 0, fmt, &aq)
    end
elseif Base.ARCH === :i686 || (Base.ARCH === :x86_64 &&
                               Base.OS_NAME === :Windows)
    typealias va_list_arg_t Ptr{Void}
elseif Base.ARCH === :aarch64
    immutable va_list_arg_t
        __stack::Ptr{Void}
        __gr_top::Ptr{Void}
        __vr_top::Ptr{Void}
        __gr_offs::Cint
        __vr_offs::Cint
    end
elseif startswith(string(Base.ARCH), "arm")
    typealias va_list_arg_t Tuple{Ptr{Void}}
else
    error("Unsupported arch $(Base.ARCH)")
end
if generic_printf_len
    function printf_len(fmt::Ptr{UInt8}, ap::va_list_arg_t)
        ccall(:vsnprintf, Cint,
              (Ptr{Void}, Csize_t, Ptr{UInt8}, va_list_arg_t),
              C_NULL, 0, fmt, ap)
    end
end
function libalpm_log_cb(level::UInt32, fmt::Ptr{UInt8}, ap::va_list_arg_t)
    hdl = get_task_context(hdlctx)
    cb = get(hdl.cbs, :log, nothing)
    cb === nothing && return
    len = printf_len(fmt, ap)
    buf = zeros(UInt8, len - 1)
    ccall(:vsnprintf, Cint,
          (Ptr{UInt8}, Csize_t, Ptr{UInt8}, va_list_arg_t),
          buf, len, fmt, ap)
    str = UTF8String(buf)
    try
        cb(hdl, level, str)
    catch ex
        try
            # Good enough for now...
            Base.showerror(STDERR, ex, catch_backtrace())
            println(STDERR)
        end
    end
    nothing
end

type Handle
    ptr::Ptr{Void}
    dbs::CObjMap
    pkgs::CObjMap
    transpkgs::Set
    rmpkgs::Set
    cbs::Dict{Symbol,Any} # Good enough for now...
    function Handle(root, db)
        err = Ref{errno_t}()
        ptr = ccall((:alpm_initialize, libalpm), Ptr{Void},
                    (Cstring, Cstring, Ref{errno_t}), root, db, err)
        ptr == C_NULL && throw(Error(err[], "Create ALPM handle"))
        self = new(ptr, CObjMap(), CObjMap(), Set{Pkg}(), Set{Pkg}(),
                   Dict{Symbol,Any}())
        finalizer(self, release)
        with_handle(self) do
            ccall((:alpm_option_set_logcb, libalpm),
                  Cint, (Ptr{Void}, Ptr{Void}),
                  self, cfunction(libalpm_log_cb, Void,
                                  Tuple{UInt32,Ptr{UInt8},va_list_arg_t}))
        end
        self
    end
end
const hdlctx = LibALPM.LazyTaskContext{Handle}()

function set_logcb(hdl::Handle, f)
    hdl.cbs[:log] = f
    nothing
end

logaction(hdl::Handle, prefix, msg) = with_handle(hdl) do
    ccall((:alpm_logaction, libalpm),
          Cint, (Ptr{Void}, Cstring, Ptr{UInt8}, Cstring...),
          hdl, prefix, "%s", msg)
end

@inline function with_handle(f, hdl::Handle)
    # TODO: maybe propagate exceptions too
    with_task_context(f, hdlctx, hdl)
end

function Base.show(io::IO, hdl::Handle)
    print(io, "LibALPM.Handle(ptr=")
    show(io, UInt(hdl.ptr))
    print(io, ")")
end

function _null_all_dbs(cmap::CObjMap)
    # Must be called in a handle context
    for (k, v) in cmap.dict
        val = v.value
        val === nothing && continue
        db = val::DB
        _null_all_pkgs(db)
        db.ptr = C_NULL
    end
    empty!(cmap.dict)
end

function _null_all_pkgs(cmap::CObjMap)
    # Must be called in a handle context
    for (k, v) in cmap.dict
        val = v.value
        val === nothing && continue
        pkg = val::Pkg
        free(pkg)
    end
    empty!(cmap.dict)
end

function release(hdl::Handle)
    ptr = hdl.ptr
    dbs = hdl.dbs
    pkgs = hdl.pkgs
    ptr == C_NULL && return
    with_handle(hdl) do
        empty!(hdl.transpkgs::Set{Pkg})
        empty!(hdl.rmpkgs::Set{Pkg})
        _null_all_pkgs(pkgs)
        _null_all_dbs(dbs)
        hdl.ptr = C_NULL
        ccall((:alpm_release, libalpm), Cint, (Ptr{Void},), ptr)
    end
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

unlock(hdl::Handle) = with_handle(hdl) do
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
fetch_pkgurl(hdl::Handle, url) = with_handle(hdl) do
    ptr = ccall((:alpm_fetch_pkgurl, libalpm), Ptr{UInt8},
                (Ptr{Void}, Cstring), hdl, url)
    ptr == C_NULL && throw(Error(hdl, "fetch_pkgurl"))
    utf8(ptr)
end

"Returns the root of the destination filesystem"
function get_root(hdl::Handle)
    # Should not trigger callback
    utf8(ccall((:alpm_option_get_root, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end

"Returns the path to the database directory"
function get_dbpath(hdl::Handle)
    # Should not trigger callback
    utf8(ccall((:alpm_option_get_dbpath, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end

"Get the name of the database lock file"
function get_lockfile(hdl::Handle)
    # Should not trigger callback
    utf8(ccall((:alpm_option_get_lockfile, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end

# Accessors to the list of package cache directories
function get_cachedirs(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_cachedirs, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
set_cachedirs(hdl::Handle, dirs) = with_handle(hdl) do
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_cachedirs, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_cachedirs"))
    end
end
add_cachedir(hdl::Handle, cachedir) = with_handle(hdl) do
    ret = ccall((:alpm_option_add_cachedir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, cachedir)
    ret == 0 || throw(Error(hdl, "add_cachedir"))
    nothing
end
remove_cachedir(hdl::Handle, cachedir) = with_handle(hdl) do
    ret = ccall((:alpm_option_remove_cachedir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, cachedir)
    ret < 0 && throw(Error(hdl, "remove_cachedir"))
    ret != 0
end

# Accessors to the list of package hook directories
function get_hookdirs(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_hookdirs, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
set_hookdirs(hdl::Handle, dirs) = with_handle(hdl) do
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_hookdirs, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_hookdirs"))
    end
end
add_hookdir(hdl::Handle, hookdir) = with_handle(hdl) do
    ret = ccall((:alpm_option_add_hookdir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, hookdir)
    ret == 0 || throw(Error(hdl, "add_hookdir"))
    nothing
end
remove_hookdir(hdl::Handle, hookdir) = with_handle(hdl) do
    ret = ccall((:alpm_option_remove_hookdir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, hookdir)
    ret < 0 && throw(Error(hdl, "remove_hookdir"))
    ret != 0
end

"Returns the logfile name"
function get_logfile(hdl::Handle)
    # Should not trigger callback
    utf8(ccall((:alpm_option_get_logfile, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end
"Sets the logfile name"
set_logfile(hdl::Handle, logfile) = with_handle(hdl) do
    ret = ccall((:alpm_option_set_logfile, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, logfile)
    ret == 0 || throw(Error(hdl, "set_logfile"))
    nothing
end

"Returns the path to libalpm's GnuPG home directory"
function get_gpgdir(hdl::Handle)
    # Should not trigger callback
    utf8(ccall((:alpm_option_get_gpgdir, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end
"Sets the path to libalpm's GnuPG home directory"
set_gpgdir(hdl::Handle, gpgdir) = with_handle(hdl) do
    ret = ccall((:alpm_option_set_gpgdir, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, gpgdir)
    ret == 0 || throw(Error(hdl, "set_gpgdir"))
    nothing
end

"Returns whether to use syslog"
function get_usesyslog(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_usesyslog, libalpm), Cint, (Ptr{Void},), hdl) != 0
end
"Sets whether to use syslog"
function set_usesyslog(hdl::Handle, usesyslog)
    # Should not trigger callback and should not fail
    ccall((:alpm_option_set_usesyslog, libalpm), Cint,
          (Ptr{Void}, Cint), hdl, usesyslog)
    nothing
end

# Accessors to the list of no-upgrade files.
#
# These functions modify the list of files which should
# not be updated by package installation.
function get_noupgrades(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_noupgrades, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_noupgrades(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_noupgrades, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_noupgrades"))
    end
end
add_noupgrade(hdl::Handle, noupgrade) = with_handle(hdl) do
    ret = ccall((:alpm_option_add_noupgrade, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, noupgrade)
    ret == 0 || throw(Error(hdl, "add_noupgrade"))
    nothing
end
remove_noupgrade(hdl::Handle, noupgrade) = with_handle(hdl) do
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
    # Should not trigger callback
    ccall((:alpm_option_match_noupgrade, libalpm), Cint,
          (Ptr{Void}, Cstring), hdl, noupgrade)
end

# Accessors to the list of no-extract files.
#
# These functions modify the list of filenames which should
# be skipped packages which should not be upgraded by a sysupgrade operation.
function get_noextracts(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_noextracts, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_noextracts(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_noextracts, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_noextracts"))
    end
end
add_noextract(hdl::Handle, noextract) = with_handle(hdl) do
    ret = ccall((:alpm_option_add_noextract, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, noextract)
    ret == 0 || throw(Error(hdl, "add_noextract"))
    nothing
end
remove_noextract(hdl::Handle, noextract) = with_handle(hdl) do
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
    # Should not trigger callback
    ccall((:alpm_option_match_noextract, libalpm), Cint,
          (Ptr{Void}, Cstring), hdl, noextract)
end

# Accessors to the list of ignored packages.
#
# These functions modify the list of packages that
# should be ignored by a sysupgrade.
function get_ignorepkgs(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_ignorepkgs, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_ignorepkgs(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_ignorepkgs, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "ignorepkgs"))
    end
end
add_ignorepkg(hdl::Handle, ignorepkg) = with_handle(hdl) do
    ret = ccall((:alpm_option_add_ignorepkg, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, ignorepkg)
    ret == 0 || throw(Error(hdl, "add_ignorepkg"))
    nothing
end
remove_ignorepkg(hdl::Handle, ignorepkg) = with_handle(hdl) do
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
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_ignoregroups, libalpm), Ptr{list_t},
                 (Ptr{Void},), hdl)
    list_to_array(UTF8String, dirs, p->utf8(Ptr{UInt8}(p)))
end
function set_ignoregroups(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_ignoregroups, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_ignoregroups"))
    end
end
add_ignoregroup(hdl::Handle, ignoregroup) = with_handle(hdl) do
    ret = ccall((:alpm_option_add_ignoregroup, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, ignoregroup)
    ret == 0 || throw(Error(hdl, "add_ignoregroup"))
    nothing
end
remove_ignoregroup(hdl::Handle, ignoregroup) = with_handle(hdl) do
    ret = ccall((:alpm_option_remove_ignoregroup, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, ignoregroup)
    ret < 0 && throw(Error(hdl, "remove_ignoregroup"))
    ret != 0
end

"Returns the targeted architecture"
function get_arch(hdl::Handle)
    # Should not trigger callback
    ascii(ccall((:alpm_option_get_arch, libalpm),
                Ptr{UInt8}, (Ptr{Void},), hdl))
end
"Sets the targeted architecture"
set_arch(hdl::Handle, arch) = with_handle(hdl) do
    ret = ccall((:alpm_option_set_arch, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, arch)
    ret == 0 || throw(Error(hdl, "set_arch"))
    nothing
end

function get_deltaratio(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_deltaratio, libalpm), Cdouble,
          (Ptr{Void},), hdl)
end
set_deltaratio(hdl::Handle, deltaratio) = with_handle(hdl) do
    ret = ccall((:alpm_option_set_deltaratio, libalpm), Cint,
                (Ptr{Void}, Cdouble), hdl, deltaratio)
    ret == 0 || throw(Error(hdl, "set_deltaratio"))
    nothing
end

function get_checkspace(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_checkspace, libalpm), Cint, (Ptr{Void},), hdl) != 0
end
function set_checkspace(hdl::Handle, checkspace)
    # Should not trigger callback and should not fail
    ccall((:alpm_option_set_checkspace, libalpm), Cint,
          (Ptr{Void}, Cint), hdl, checkspace)
    nothing
end

function get_dbext(hdl::Handle)
    # Should not trigger callback
    utf8(ccall((:alpm_option_get_dbext, libalpm), Ptr{UInt8},
               (Ptr{Void},), hdl))
end
set_dbext(hdl::Handle, dbext) = with_handle(hdl) do
    ret = ccall((:alpm_option_set_dbext, libalpm), Cint,
                (Ptr{Void}, Cstring), hdl, dbext)
    ret == 0 || throw(Error(hdl, "set_dbext"))
    nothing
end

function get_default_siglevel(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_default_siglevel, libalpm), Cint, (Ptr{Void},), hdl)
end
set_default_siglevel(hdl::Handle, siglevel) = with_handle(hdl) do
    ret = ccall((:alpm_option_set_default_siglevel, libalpm), Cint,
                (Ptr{Void}, Cint), hdl, siglevel)
    ret == 0 || throw(Error(hdl, "set_default_siglevel"))
    nothing
end

function get_local_file_siglevel(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_local_file_siglevel, libalpm),
          Cint, (Ptr{Void},), hdl)
end
set_local_file_siglevel(hdl::Handle, siglevel) = with_handle(hdl) do
    ret = ccall((:alpm_option_set_local_file_siglevel, libalpm), Cint,
                (Ptr{Void}, Cint), hdl, siglevel)
    ret == 0 || throw(Error(hdl, "set_local_file_siglevel"))
    nothing
end

function get_remote_file_siglevel(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_remote_file_siglevel, libalpm),
          Cint, (Ptr{Void},), hdl)
end
set_remote_file_siglevel(hdl::Handle, siglevel) = with_handle(hdl) do
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
    # Should not trigger callback
    DB(ccall((:alpm_get_localdb, libalpm), Ptr{Void}, (Ptr{Void},), hdl), hdl)

"""
Get the list of sync databases.

Returns an array of DB's, one for each registered sync database.
"""
function get_syncdbs(hdl::Handle)
    # Should not trigger callback
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
register_syncdb(hdl::Handle, treename, level) = with_handle(hdl) do
    db = ccall((:alpm_register_syncdb, libalpm), Ptr{Void},
               (Ptr{Void}, Cstring, UInt32), hdl, treename, level)
    db == C_NULL && throw(Error(hdl, "register_syncdb"))
    DB(db, hdl)
end

"Unregister all package databases"
unregister_all_syncdbs(hdl::Handle) = with_handle(hdl) do
    for ptr in list_iter(ccall((:alpm_get_syncdbs, libalpm),
                               Ptr{list_t}, (Ptr{Void},), hdl))
        cached = hdl.dbs[ptr, DB]
        isnull(cached) && continue
        db = get(cached)
        _null_all_pkgs(db)
        db.ptr = C_NULL
    end
    ret = ccall((:alpm_unregister_all_syncdbs, libalpm),
                Cint, (Ptr{Void},), hdl)
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
load(hdl::Handle, filename, full, level) = with_handle(hdl) do
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
    # Should not trigger callback
    list = ccall((:alpm_option_get_assumeinstalled, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Depend, list, Depend)
end
add_assumeinstalled(hdl::Handle, dep) = with_handle(hdl) do
    ret = ccall((:alpm_option_add_assumeinstalled, libalpm),
                Cint, (Ptr{Void}, Ptr{CTypes.Depend}), hdl, Depend(dep))
    ret == 0 || throw(Error(hdl, "add_assumeinstalled"))
    nothing
end
set_assumeinstalled(hdl::Handle, deps) = with_handle(hdl) do
    list = array_to_list(deps, dep->Ptr{Void}(to_c(Depend(dep))),
                         cglobal((:alpm_dep_free, libalpm)))
    ret = ccall((:alpm_option_set_assumeinstalled, libalpm),
                Cint, (Ptr{Void}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal((:alpm_dep_free, libalpm)))
        throw(Error(hdl, "set_assumeinstalled"))
    end
    nothing
end
remove_assumeinstalled(hdl::Handle, dep) = with_handle(hdl) do
    ret = ccall((:alpm_option_remove_assumeinstalled, libalpm),
                Cint, (Ptr{Void}, Ptr{CTypes.Depend}), hdl, Depend(dep))
    ret < 0 && throw(Error(hdl, "remove_assumeinstalled"))
    ret != 0
end

# Transaction Functions
# Functions to manipulate libalpm transactions

"Returns the bitfield of flags for the current transaction"
get_flags(hdl::Handle) = with_handle(hdl) do
    ccall((:alpm_trans_get_flags, libalpm), UInt32, (Ptr{Void},), hdl)
end

"Returns a list of packages added by the transaction"
get_add(hdl::Handle) = with_handle(hdl) do
    pkgs = ccall((:alpm_trans_get_add, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Pkg, pkgs, p->Pkg(p, hdl))
end

"Returns the list of packages removed by the transaction"
get_remove(hdl::Handle) = with_handle(hdl) do
    pkgs = ccall((:alpm_trans_get_remove, libalpm),
                 Ptr{list_t}, (Ptr{Void},), hdl)
    list_to_array(Pkg, pkgs, p->(pkg = Pkg(p, hdl);
                                 push!(hdl.rmpkgs::Set{Pkg}, pkg);
                                 pkg.should_free = false; pkg))
end

"Initialize the transaction"
trans_init(hdl::Handle, flags) = with_handle(hdl) do
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
    elseif err.errno == Errno.UNSATISFIED_DEPS
        println(io, "Missing dependencies:")
    elseif err.errno == Errno.CONFLICTING_DEPS
        println(io, "Conflicts:")
    end
    for pkg in err.list
        print(io, "    ")
        show(io, pkg)
        println()
    end
end

"Prepare a transaction"
trans_prepare(hdl::Handle) = with_handle(hdl) do
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
            ary = list_to_array(UTF8String, list[], ptr_to_utf8, cglobal(:free))
            throw(TransPrepareError(errno, ary))
        elseif errno == Errno.UNSATISFIED_DEPS
            ary = list_to_array(DepMissing, list[], DepMissing,
                                cglobal((:alpm_depmissing_free, libalpm)))
            throw(TransPrepareError(errno, ary))
        elseif errno == Errno.CONFLICTING_DEPS
            ary = list_to_array(Conflict, list[], Conflict,
                                cglobal((:alpm_conflict_free, libalpm)))
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
trans_commit(hdl::Handle) = with_handle(hdl) do
    rmpkgs = hdl.rmpkgs::Set{Pkg}
    for pkg in rmpkgs
        free(pkg)
    end
    empty!(rmpkgs)
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
            ary = list_to_array(FileConflict, list[], FileConflict,
                                cglobal((:alpm_fileconflict_free, libalpm)))
            throw(TransCommitError(errno, ary))
        else
            ary = list_to_array(UTF8String, list[], ptr_to_utf8, cglobal(:free))
            throw(TransCommitError(errno, ary))
        end
    end
    nothing
end

"Interrupt a transaction"
trans_interrupt(hdl::Handle) = with_handle(hdl) do
    ret = ccall((:alpm_trans_interrupt, libalpm), Cint, (Ptr{Void},), hdl)
    ret == 0 || throw(Error(hdl, "interrupt"))
    nothing
end

"Release a transaction"
trans_release(hdl::Handle) = with_handle(hdl) do
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
sysupgrade(hdl::Handle, enable_downgrade) = with_handle(hdl) do
    ret = ccall((:alpm_sync_sysupgrade, libalpm),
                Cint, (Ptr{Void}, Cint), hdl, enable_downgrade)
    ret == 0 || throw(Error(hdl, "sysupgrade"))
    nothing
end

# TODO
# alpm_list_t *alpm_checkdeps(alpm_handle_t *handle, alpm_list_t *pkglist,
# alpm_list_t *remove, alpm_list_t *upgrade, int reversedeps);
# alpm_pkg_t *alpm_find_satisfier(alpm_list_t *pkgs, const char *depstring);
# alpm_pkg_t *alpm_find_dbs_satisfier(alpm_handle_t *handle,
# alpm_list_t *dbs, const char *depstring);

# alpm_list_t *alpm_checkconflicts(alpm_handle_t *handle, alpm_list_t *pkglist);
