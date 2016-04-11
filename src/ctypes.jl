#!/usr/bin/julia -f

module CTypes
import LibALPM: LibALPM, EventType

"Dependency"
immutable Depend
    name::Cstring
    version::Cstring
    dest::Cstring
    name_hash::Culong
    mod::LibALPM.depmod_t
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
    conflicttype::LibALPM.fileconflicttype_t
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
    status::LibALPM.sigstatus_t
    validity::LibALPM.sigvalidity_t
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

module Event
import LibALPM: LibALPM, event_type_t
import ..CTypes

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
    optdep::Ptr{CTypes.Depend}
end

immutable DeltaPatch <: AbstractEvent
    _type::event_type_t
    # Delta info
    delta::Ptr{CTypes.Delta}
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

module Question
import LibALPM
import ..CTypes

abstract AbstractQuestion

immutable AnyQuestion <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer
    answer::Cint
end

immutable InstallIgnorepkg <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to install pkg anyway
    install::Cint
    # Package in IgnorePkg/IgnoreGroup
    pkg::Ptr{Void} # alpm_pkg_t*
end

immutable Replace <: AbstractQuestion
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

immutable Conflict <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to remove conflict->package2
    remove::Cint
    # Conflict info
    conflict::Ptr{CTypes.Conflict}
end

immutable Corrupted <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to remove filepath.
    remove::Cint
    # Filename to remove
    filepath::Cstring
    # Error code indicating the reason for package invalidity
    reason::LibALPM.errno_t
end

immutable RemovePkgs <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to skip packages
    skip::Cint
    # List of alpm_pkg_t* with unresolved dependencies
    # FIXME: alpm_list_t*
    packages::Ptr{Void}
end

immutable SelectProvider <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: which provider to use (index from providers)
    use_index::Cint
    # List of alpm_pkg_t* as possible providers
    # FIXME: alpm_list_t*
    providers::Ptr{Void}
    # What providers provide for
    depend::Ptr{CTypes.Depend}
end

immutable ImportKey <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to import key
    _import::Cint
    # The key to import
    key::Ptr{CTypes.PGPKey}
end

end

end

function cstr_to_utf8(cstr, own)
    cstr == C_NULL && return UTF8String("")
    own && return ptr_to_utf8(Ptr{UInt8}(cstr))
    utf8(Ptr{UInt8}(cstr))
end

type Depend
    name::UTF8String
    version::UTF8String
    dest::UTF8String
    name_hash::Culong
    mod::depmod_t
    function Depend(_ptr::Ptr, own=false)
        ptr = Ptr{CTypes.Depend}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cdep = unsafe_load(ptr)
        own && ccall(:free, Void, (Ptr{Void},), ptr)
        name = cstr_to_utf8(cdep.name, own)
        version = cstr_to_utf8(cdep.version, own)
        dest = cstr_to_utf8(cdep.dest, own)
        new(name, version, dest, cdep.name_hash, cdep.mod)
    end
    Depend(str::AbstractString) =
        Depend(ccall((:alpm_dep_from_string, libalpm), Ptr{CTypes.Depend},
                     (Cstring,), str), true)
end

# WARNING! Relies on julia internal API:
#     `cconvert(Cstring, ::UTF8String)` is no-op
#     Base.RefValue
Base.cconvert(::Type{Ptr{CTypes.Depend}}, dep::Depend) =
    (dep, Ref{CTypes.Depend}())
function Base.unsafe_convert(::Type{Ptr{CTypes.Depend}},
                             tup::Tuple{Depend,Base.RefValue{CTypes.Depend}})
    dep, ref = tup
    cdep = CTypes.Depend(Base.unsafe_convert(Cstring, dep.name),
                         Base.unsafe_convert(Cstring, dep.version),
                         Base.unsafe_convert(Cstring, dep.dest),
                         dep.name_hash, dep.mod)
    ref[] = cdep
    Base.unsafe_convert(Ptr{CTypes.Depend}, ref)
end

function to_c(dep::Depend)
    name = Cstring(C_NULL)
    version = Cstring(C_NULL)
    dest = Cstring(C_NULL)
    try
        name = ccall(:strdup, Cstring, (Cstring,), dep.name)
        version = ccall(:strdup, Cstring, (Cstring,), dep.version)
        dest = ccall(:strdup, Cstring, (Cstring,), dep.dest)
    catch
        ccall(:free, Void, (Cstring,), name)
        ccall(:free, Void, (Cstring,), version)
        ccall(:free, Void, (Cstring,), dest)
        rethrow()
    end
    cdep = CTypes(name, version, dest, dep.name_hash, dep.mod)
    ptr = ccall(:malloc, Ptr{CType.Depend}, (Csize_t,), sizeof(Depend))
    unsafe_store!(ptr, cdep)
    ptr
end

"Returns a string representing the dependency information"
compute_string(dep::Depend) =
    ptr_to_utf8(ccall((:alpm_dep_compute_string, libalpm), Ptr{UInt8},
                      (Ptr{CTypes.Depend},), dep))

function Base.show(io::IO, dep::Depend)
    print(io, "LibALPM.Depend(")
    show(io, compute_string(dep))
    print(io, ")")
end

type DepMissing
    target::UTF8String
    depend::Depend
    causingpkg::UTF8String
    # Take ownership of the pointer
    function DepMissing(_ptr::Ptr)
        ptr = Ptr{CTypes.DepMissing}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cdepmissing = unsafe_load(ptr)
        ccall(:free, Void, (Ptr{Void},), ptr)
        target = cstr_to_utf8(cdepmissing.target, true)
        depend = Depend(cdepmissing.depend, true)
        causingpkg = cstr_to_utf8(cdepmissing.causingpkg, true)
        new(target, depend, causingpkg)
    end
end

type Conflict
    package1_hash::Culong
    package2_hash::Culong
    package1::UTF8String
    package2::UTF8String
    reason::Depend
    # Take ownership of the pointer
    function Conflict(_ptr::Ptr)
        ptr = Ptr{CTypes.Conflict}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cconflict = unsafe_load(ptr)
        ccall(:free, Void, (Ptr{Void},), ptr)
        package1 = cstr_to_utf8(cconflict.package1, true)
        package2 = cstr_to_utf8(cconflict.package2, true)
        reason = Depend(cconflict.reason, true)
        new(cconflict.package1_hash, cconflict.package2_hash,
            package1, package2, reason)
    end
end

type FileConflict
    target::UTF8String
    conflicttype::LibALPM.fileconflicttype_t
    file::UTF8String
    ctarget::UTF8String
    # Take ownership of the pointer
    function FileConflict(_ptr::Ptr)
        _ptr = Ptr{CTypes.FileConflict}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cfileconflict = unsafe_load(ptr)
        ccall(:free, Void, (Ptr{Void},), ptr)
        target = cstr_to_utf8(cfileconflict.target, true)
        file = cstr_to_utf8(cfileconflict.file, true)
        ctarget = cstr_to_utf8(cfileconflict.ctarget, true)
        new(target, cfileconflict.conflicttype, file, ctarget)
    end
end

type File
    name::UTF8String
    size::Int64
    mode::Cint # mode_t
    function File(_ptr::Ptr)
        ptr = Ptr{CTypes.File}(_ptr)
        cfile = unsafe_load(ptr)
        name = utf8(Ptr{UInt8}(cfile.name))
        new(name, cfile.size, cfile.mode)
    end
end

type Backup
    name::UTF8String
    hash::UTF8String
    function Backup(_ptr::Ptr)
        ptr = Ptr{CTypes.Backup}(_ptr)
        cbackup = unsafe_load(ptr)
        name = utf8(Ptr{UInt8}(cbackup.name))
        hash = utf8(Ptr{UInt8}(cbackup.hash))
        new(name, hash)
    end
end
