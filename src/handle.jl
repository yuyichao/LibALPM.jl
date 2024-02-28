#!/usr/bin/julia -f

##
# handle

generic_printf_len = true
if Sys.ARCH === :x86_64 && !Sys.iswindows()
    struct __va_list_tag
        gp_offset::Cuint
        fp_offset::Cuint
        overflow_arg_area::Ptr{Cvoid}
        reg_save_area::Ptr{Cvoid}
    end
    const va_list_arg_t = Ptr{__va_list_tag}
    generic_printf_len = false
    function printf_len(fmt::Ptr{UInt8}, ap::va_list_arg_t)
        aq = unsafe_load(ap) # va_copy
        ccall(:vsnprintf, Cint,
              (Ptr{Cvoid}, Csize_t, Ptr{UInt8}, Ref{__va_list_tag}), C_NULL, 0, fmt, aq)
    end
elseif Sys.ARCH === :i686 || (Sys.ARCH === :x86_64 && Sys.iswindows())
    const va_list_arg_t = Ptr{Cvoid}
elseif Sys.ARCH === :aarch64
    struct va_list_arg_t
        __stack::Ptr{Cvoid}
        __gr_top::Ptr{Cvoid}
        __vr_top::Ptr{Cvoid}
        __gr_offs::Cint
        __vr_offs::Cint
    end
elseif startswith(string(Sys.ARCH), "arm")
    const va_list_arg_t = Tuple{Ptr{Cvoid}}
else
    error("Unsupported arch $(Sys.ARCH)")
end
if generic_printf_len
    function printf_len(fmt::Ptr{UInt8}, ap::va_list_arg_t)
        ccall(:vsnprintf, Cint,
              (Ptr{Cvoid}, Csize_t, Ptr{UInt8}, va_list_arg_t),
              C_NULL, 0, fmt, ap)
    end
end

function cb_show_error(ex)
    try
        # Good enough for now...
        Base.showerror(STDERR, ex, catch_backtrace())
        println(STDERR)
    catch
    end
end

function libalpm_log_cb(hdl, level::UInt32, fmt::Ptr{UInt8}, ap::va_list_arg_t)
    cb = get(hdl.cbs, :log, nothing)
    cb === nothing && return
    len = printf_len(fmt, ap)
    buf = zeros(UInt8, len)
    ccall(:vsnprintf, Cint,
          (Ptr{UInt8}, Csize_t, Ptr{UInt8}, va_list_arg_t),
          buf, len, fmt, ap)
    str = String(buf)
    try
        cb(hdl, level, str)
    catch ex
        cb_show_error(ex)
    end
    nothing
end

function libalpm_event_cb(hdl, eventptr::Ptr{Cvoid})
    cb = get(hdl.cbs, :event, nothing)
    cb === nothing && return
    try
        dispatch_event(cb, hdl, eventptr)
    catch ex
        cb_show_error(ex)
    end
    nothing
end

mutable struct Handle
    ptr::Ptr{Cvoid}
    dbs::CObjMap
    pkgs::CObjMap
    transpkgs::Set
    rmpkgs::Set
    cbs::Dict{Symbol,Any} # Good enough for now...
    function Handle(root, db)
        err = Ref{errno_t}()
        ptr = ccall((:alpm_initialize, libalpm), Ptr{Cvoid},
                    (Cstring, Cstring, Ref{errno_t}), root, db, err)
        ptr == C_NULL && throw(Error(err[], "Create ALPM handle"))
        self = new(ptr, CObjMap(), CObjMap(), Set{Pkg}(), Set{Pkg}(),
                   Dict{Symbol,Any}())
        finalizer(self, release)
        ccall((:alpm_option_set_logcb, libalpm),
              Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ref{Handle}),
              self, @cfunction(libalpm_log_cb, Cvoid,
                               (Ref{Handle}, UInt32, Ptr{UInt8}, va_list_arg_t)),
              self)
        ccall((:alpm_option_set_eventcb, libalpm),
              Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ref{Handle}),
              self, @cfunction(libalpm_event_cb,
                               Cvoid, (Ref{Handle}, Ptr{Cvoid})),
              self)
        self
    end
end

function set_logcb(hdl::Handle, @nospecialize(f))
    hdl.cbs[:log] = f
    nothing
end

function set_eventcb(hdl::Handle, @nospecialize(f))
    hdl.cbs[:event] = f
    nothing
end

logaction(hdl::Handle, prefix, msg) =
    ccall((:alpm_logaction, libalpm), Cint,
          (Ptr{Cvoid}, Cstring, Ptr{UInt8}, Cstring...), hdl, prefix, "%s", msg)

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
    empty!(hdl.transpkgs::Set{Pkg})
    empty!(hdl.rmpkgs::Set{Pkg})
    _null_all_pkgs(pkgs)
    _null_all_dbs(dbs)
    hdl.ptr = C_NULL
    # The callback table contains a reference to the julia hdl object
    # so we still need to preserve hdl even though
    # the finalizer (i.e. ourselves) won't mess with the C pointer anymore.
    GC.@preserve hdl begin
        ccall((:alpm_release, libalpm), Cint, (Ptr{Cvoid},), ptr)
    end
    nothing
end

Base.cconvert(::Type{Ptr{Cvoid}}, hdl::Handle) = hdl
function Base.unsafe_convert(::Type{Ptr{Cvoid}}, hdl::Handle)
    ptr = hdl.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end

"Returns the current error code from the handle"
Libc.errno(hdl::Handle) =
    ccall((:alpm_errno, libalpm), errno_t, (Ptr{Cvoid},), hdl)
Error(hdl::Handle, msg) = Error(Libc.errno(hdl), msg)

function unlock(hdl::Handle)
    if ccall((:alpm_unlock, libalpm), Cint, (Ptr{Cvoid},), hdl) != 0
        throw(Error(hdl, "Unlock handle"))
    end
end

"""
Fetch a list of remote packages.

`hdl`: the context handle
`urls`: urls list of package URLs to download
Returns the downloaded filepaths on success.
"""
function fetch_pkgurl(hdl::Handle, urls)
    path_list = Ref{Ptr{list_t}}(0)
    # TODO, we should be able to avoid copying in some cases
    url_list = array_to_list(urls, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                             cglobal(:free))
    ret = ccall((:alpm_fetch_pkgurl, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}, Ptr{Ptr{list_t}}),
                hdl, url_list, path_list)
    free(url_list, cglobal(:free))
    ret != 0 && throw(Error(hdl, "fetch_pkgurl"))
    return list_to_array(String, path_list[], take_cstring, cglobal(:free))
end
fetch_pkgurl(hdl::Handle, url::AbstractString) = fetch_pkgurl(hdl, [url])[1]

"Returns the root of the destination filesystem"
function get_root(hdl::Handle)
    # Should not trigger callback
    convert_cstring(ccall((:alpm_option_get_root, libalpm), Ptr{UInt8},
                          (Ptr{Cvoid},), hdl))
end

"Returns the path to the database directory"
function get_dbpath(hdl::Handle)
    # Should not trigger callback
    convert_cstring(ccall((:alpm_option_get_dbpath, libalpm), Ptr{UInt8},
                          (Ptr{Cvoid},), hdl))
end

"Get the name of the database lock file"
function get_lockfile(hdl::Handle)
    # Should not trigger callback
    convert_cstring(ccall((:alpm_option_get_lockfile, libalpm), Ptr{UInt8},
                          (Ptr{Cvoid},), hdl))
end

# Accessors to the list of package cache directories
function get_cachedirs(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_cachedirs, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), hdl)
    list_to_array(String, dirs, convert_cstring)
end
function set_cachedirs(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_cachedirs, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_cachedirs"))
    end
end
function add_cachedir(hdl::Handle, cachedir)
    ret = ccall((:alpm_option_add_cachedir, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, cachedir)
    ret == 0 || throw(Error(hdl, "add_cachedir"))
    nothing
end
function remove_cachedir(hdl::Handle, cachedir)
    ret = ccall((:alpm_option_remove_cachedir, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, cachedir)
    ret < 0 && throw(Error(hdl, "remove_cachedir"))
    ret != 0
end

# Accessors to the list of package hook directories
function get_hookdirs(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_hookdirs, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), hdl)
    list_to_array(String, dirs, convert_cstring)
end
function set_hookdirs(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_hookdirs, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_hookdirs"))
    end
end
function add_hookdir(hdl::Handle, hookdir)
    ret = ccall((:alpm_option_add_hookdir, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, hookdir)
    ret == 0 || throw(Error(hdl, "add_hookdir"))
    nothing
end
function remove_hookdir(hdl::Handle, hookdir)
    ret = ccall((:alpm_option_remove_hookdir, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, hookdir)
    ret < 0 && throw(Error(hdl, "remove_hookdir"))
    ret != 0
end

"Returns the logfile name"
function get_logfile(hdl::Handle)
    # Should not trigger callback
    convert_cstring(ccall((:alpm_option_get_logfile, libalpm), Ptr{UInt8},
                          (Ptr{Cvoid},), hdl))
end
"Sets the logfile name"
function set_logfile(hdl::Handle, logfile)
    ret = ccall((:alpm_option_set_logfile, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, logfile)
    ret == 0 || throw(Error(hdl, "set_logfile"))
    nothing
end

"Returns the path to libalpm's GnuPG home directory"
function get_gpgdir(hdl::Handle)
    # Should not trigger callback
    convert_cstring(ccall((:alpm_option_get_gpgdir, libalpm), Ptr{UInt8},
                          (Ptr{Cvoid},), hdl))
end
"Sets the path to libalpm's GnuPG home directory"
function set_gpgdir(hdl::Handle, gpgdir)
    ret = ccall((:alpm_option_set_gpgdir, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, gpgdir)
    ret == 0 || throw(Error(hdl, "set_gpgdir"))
    nothing
end

"Returns whether to use syslog"
function get_usesyslog(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_usesyslog, libalpm), Cint, (Ptr{Cvoid},), hdl) != 0
end
"Sets whether to use syslog"
function set_usesyslog(hdl::Handle, usesyslog)
    # Should not trigger callback and should not fail
    ccall((:alpm_option_set_usesyslog, libalpm), Cint,
          (Ptr{Cvoid}, Cint), hdl, usesyslog)
    nothing
end

# Accessors to the list of no-upgrade files.
#
# These functions modify the list of files which should
# not be updated by package installation.
function get_noupgrades(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_noupgrades, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), hdl)
    list_to_array(String, dirs, convert_cstring)
end
function set_noupgrades(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_noupgrades, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_noupgrades"))
    end
end
function add_noupgrade(hdl::Handle, noupgrade)
    ret = ccall((:alpm_option_add_noupgrade, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, noupgrade)
    ret == 0 || throw(Error(hdl, "add_noupgrade"))
    nothing
end
function remove_noupgrade(hdl::Handle, noupgrade)
    ret = ccall((:alpm_option_remove_noupgrade, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, noupgrade)
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
          (Ptr{Cvoid}, Cstring), hdl, noupgrade)
end

# Accessors to the list of no-extract files.
#
# These functions modify the list of filenames which should
# be skipped packages which should not be upgraded by a sysupgrade operation.
function get_noextracts(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_noextracts, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), hdl)
    list_to_array(String, dirs, convert_cstring)
end
function set_noextracts(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_noextracts, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_noextracts"))
    end
end
function add_noextract(hdl::Handle, noextract)
    ret = ccall((:alpm_option_add_noextract, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, noextract)
    ret == 0 || throw(Error(hdl, "add_noextract"))
    nothing
end
function remove_noextract(hdl::Handle, noextract)
    ret = ccall((:alpm_option_remove_noextract, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, noextract)
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
          (Ptr{Cvoid}, Cstring), hdl, noextract)
end

# Accessors to the list of ignored packages.
#
# These functions modify the list of packages that
# should be ignored by a sysupgrade.
function get_ignorepkgs(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_ignorepkgs, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), hdl)
    list_to_array(String, dirs, convert_cstring)
end
function set_ignorepkgs(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_ignorepkgs, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "ignorepkgs"))
    end
end
function add_ignorepkg(hdl::Handle, ignorepkg)
    ret = ccall((:alpm_option_add_ignorepkg, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, ignorepkg)
    ret == 0 || throw(Error(hdl, "add_ignorepkg"))
    nothing
end
function remove_ignorepkg(hdl::Handle, ignorepkg)
    ret = ccall((:alpm_option_remove_ignorepkg, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, ignorepkg)
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
                 (Ptr{Cvoid},), hdl)
    list_to_array(String, dirs, convert_cstring)
end
function set_ignoregroups(hdl::Handle, dirs)
    # Should not trigger callback
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_ignoregroups, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_ignoregroups"))
    end
end
function add_ignoregroup(hdl::Handle, ignoregroup)
    ret = ccall((:alpm_option_add_ignoregroup, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, ignoregroup)
    ret == 0 || throw(Error(hdl, "add_ignoregroup"))
    nothing
end
function remove_ignoregroup(hdl::Handle, ignoregroup)
    ret = ccall((:alpm_option_remove_ignoregroup, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, ignoregroup)
    ret < 0 && throw(Error(hdl, "remove_ignoregroup"))
    ret != 0
end

"Returns the allowed package architecture."
function get_architectures(hdl::Handle)
    # Should not trigger callback
    dirs = ccall((:alpm_option_get_architectures, libalpm), Ptr{list_t},
                 (Ptr{Cvoid},), hdl)
    list_to_array(String, dirs, convert_cstring)
end
"Sets the allowed package architecture."
function set_architectures(hdl::Handle, dirs)
    list = array_to_list(dirs, str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_option_set_architectures, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(hdl, "set_architectures"))
    end
end
"Adds an allowed package architecture."
function add_architecture(hdl::Handle, architecture)
    ret = ccall((:alpm_option_add_architecture, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, architecture)
    ret == 0 || throw(Error(hdl, "add_architecture"))
    nothing
end
"Removes an allowed package architecture."
function remove_architecture(hdl::Handle, architecture)
    ret = ccall((:alpm_option_remove_architecture, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, architecture)
    ret < 0 && throw(Error(hdl, "remove_architecture"))
    ret != 0
end

function get_checkspace(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_checkspace, libalpm), Cint, (Ptr{Cvoid},), hdl) != 0
end
function set_checkspace(hdl::Handle, checkspace)
    # Should not trigger callback and should not fail
    ccall((:alpm_option_set_checkspace, libalpm), Cint,
          (Ptr{Cvoid}, Cint), hdl, checkspace)
    nothing
end

function get_dbext(hdl::Handle)
    # Should not trigger callback
    convert_cstring(ccall((:alpm_option_get_dbext, libalpm), Ptr{UInt8},
                          (Ptr{Cvoid},), hdl))
end
function set_dbext(hdl::Handle, dbext)
    ret = ccall((:alpm_option_set_dbext, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), hdl, dbext)
    ret == 0 || throw(Error(hdl, "set_dbext"))
    nothing
end

function get_default_siglevel(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_default_siglevel, libalpm), Cint, (Ptr{Cvoid},), hdl)
end
function set_default_siglevel(hdl::Handle, siglevel)
    ret = ccall((:alpm_option_set_default_siglevel, libalpm), Cint,
                (Ptr{Cvoid}, Cint), hdl, siglevel)
    ret == 0 || throw(Error(hdl, "set_default_siglevel"))
    nothing
end

function get_local_file_siglevel(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_local_file_siglevel, libalpm),
          Cint, (Ptr{Cvoid},), hdl)
end
function set_local_file_siglevel(hdl::Handle, siglevel)
    ret = ccall((:alpm_option_set_local_file_siglevel, libalpm), Cint,
                (Ptr{Cvoid}, Cint), hdl, siglevel)
    ret == 0 || throw(Error(hdl, "set_local_file_siglevel"))
    nothing
end

function get_remote_file_siglevel(hdl::Handle)
    # Should not trigger callback
    ccall((:alpm_option_get_remote_file_siglevel, libalpm),
          Cint, (Ptr{Cvoid},), hdl)
end
function set_remote_file_siglevel(hdl::Handle, siglevel)
    ret = ccall((:alpm_option_set_remote_file_siglevel, libalpm), Cint,
                (Ptr{Cvoid}, Cint), hdl, siglevel)
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
    DB(ccall((:alpm_get_localdb, libalpm), Ptr{Cvoid}, (Ptr{Cvoid},), hdl), hdl)

"""
Get the list of sync databases.

Returns an array of DB's, one for each registered sync database.
"""
function get_syncdbs(hdl::Handle)
    # Should not trigger callback
    dbs = ccall((:alpm_get_syncdbs, libalpm), Ptr{list_t}, (Ptr{Cvoid},), hdl)
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
    db = ccall((:alpm_register_syncdb, libalpm), Ptr{Cvoid},
               (Ptr{Cvoid}, Cstring, UInt32), hdl, treename, level)
    db == C_NULL && throw(Error(hdl, "register_syncdb"))
    DB(db, hdl)
end

"Unregister all package databases"
function unregister_all_syncdbs(hdl::Handle)
    for ptr in list_iter(ccall((:alpm_get_syncdbs, libalpm),
                               Ptr{list_t}, (Ptr{Cvoid},), hdl))
        cached = hdl.dbs[ptr, DB]
        cached === nothing && continue
        db = cached
        _null_all_pkgs(db)
        db.ptr = C_NULL
    end
    ret = ccall((:alpm_unregister_all_syncdbs, libalpm),
                Cint, (Ptr{Cvoid},), hdl)
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
    pkgout = Ref{Ptr{Cvoid}}()
    ret = ccall((:alpm_pkg_load, libalpm), Cint,
                (Ptr{Cvoid}, Cstring, Cint, UInt32, Ptr{Ptr{Cvoid}}),
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
                 Ptr{list_t}, (Ptr{Cvoid},), hdl)
    list_to_array(Depend, list, Depend)
end
function add_assumeinstalled(hdl::Handle, dep)
    ret = ccall((:alpm_option_add_assumeinstalled, libalpm),
                Cint, (Ptr{Cvoid}, Ptr{CTypes.Depend}), hdl, Depend(dep))
    ret == 0 || throw(Error(hdl, "add_assumeinstalled"))
    nothing
end
function set_assumeinstalled(hdl::Handle, deps)
    list = array_to_list(deps, dep->Ptr{Cvoid}(to_c(Depend(dep))),
                         cglobal((:alpm_dep_free, libalpm)))
    ret = ccall((:alpm_option_set_assumeinstalled, libalpm),
                Cint, (Ptr{Cvoid}, Ptr{list_t}), hdl, list)
    if ret != 0
        free(list, cglobal((:alpm_dep_free, libalpm)))
        throw(Error(hdl, "set_assumeinstalled"))
    end
    nothing
end
function remove_assumeinstalled(hdl::Handle, dep)
    ret = ccall((:alpm_option_remove_assumeinstalled, libalpm),
                Cint, (Ptr{Cvoid}, Ptr{CTypes.Depend}), hdl, Depend(dep))
    ret < 0 && throw(Error(hdl, "remove_assumeinstalled"))
    ret != 0
end

# Transaction Functions
# Functions to manipulate libalpm transactions

"Returns the bitfield of flags for the current transaction"
get_flags(hdl::Handle) =
    ccall((:alpm_trans_get_flags, libalpm), UInt32, (Ptr{Cvoid},), hdl)

"Returns a list of packages added by the transaction"
function get_add(hdl::Handle)
    pkgs = ccall((:alpm_trans_get_add, libalpm), Ptr{list_t}, (Ptr{Cvoid},), hdl)
    list_to_array(Pkg, pkgs, p->Pkg(p, hdl))
end

"Returns the list of packages removed by the transaction"
function get_remove(hdl::Handle)
    pkgs = ccall((:alpm_trans_get_remove, libalpm),
                 Ptr{list_t}, (Ptr{Cvoid},), hdl)
    list_to_array(Pkg, pkgs, p->(pkg = Pkg(p, hdl);
                                 push!(hdl.rmpkgs::Set{Pkg}, pkg);
                                 pkg.should_free = false; pkg))
end

"Initialize the transaction"
function trans_init(hdl::Handle, flags)
    ret = ccall((:alpm_trans_init, libalpm), Cint, (Ptr{Cvoid}, UInt32), hdl, flags)
    ret == 0 || throw(Error(hdl, "init"))
    nothing
end

struct TransPrepareError{T} <: AbstractError
    errno::errno_t
    list::Vector{T}
end
function Base.showerror(io::IO, err::TransPrepareError)
    println(io, "ALPM Transaction Prepare Error: $(Libc.strerror(err.errno))")
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
function trans_prepare(hdl::Handle)
    list = Ref{Ptr{list_t}}(0)
    ret = ccall((:alpm_trans_prepare, libalpm),
                Cint, (Ptr{Cvoid}, Ptr{Ptr{list_t}}), hdl, list)
    if ret != 0
        list[] == C_NULL && throw(Error(hdl, "trans_prepare"))
        errno = Libc.errno(hdl)
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
            ary = list_to_array(String, list[], take_cstring, cglobal(:free))
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
            @warn("LibALPM<trans_prepare>: ignore unknown list return for error code $errno.")
            free(list[])
            throw(Error(hdl, "trans_prepare"))
        end
    end
    nothing
end

struct TransCommitError{T} <: AbstractError
    errno::errno_t
    list::Vector{T}
end
function Base.showerror(io::IO, err::TransCommitError)
    println(io, "ALPM Transaction Commit Error: $(Libc.strerror(err.errno))")
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
    rmpkgs = hdl.rmpkgs::Set{Pkg}
    for pkg in rmpkgs
        free(pkg)
    end
    empty!(rmpkgs)
    list = Ref{Ptr{list_t}}(0)
    ret = ccall((:alpm_trans_commit, libalpm),
                Cint, (Ptr{Cvoid}, Ptr{Ptr{list_t}}), hdl, list)
    if ret != 0
        list[] == C_NULL && throw(Error(hdl, "trans_commit"))
        errno = Libc.errno(hdl)
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
            ary = list_to_array(String, list[], take_cstring, cglobal(:free))
            throw(TransCommitError(errno, ary))
        end
    end
    nothing
end

"Interrupt a transaction"
function trans_interrupt(hdl::Handle)
    ret = ccall((:alpm_trans_interrupt, libalpm), Cint, (Ptr{Cvoid},), hdl)
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
    ret = ccall((:alpm_trans_release, libalpm), Cint, (Ptr{Cvoid},), hdl)
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
                Cint, (Ptr{Cvoid}, Cint), hdl, enable_downgrade)
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
