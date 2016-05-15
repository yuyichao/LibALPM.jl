#!/usr/bin/julia -f

module CTypes
import LibALPM: LibALPM, EventType

"Dependency"
immutable Depend
    name::Cstring
    version::Cstring
    desc::Cstring
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

immutable ScriptletInfo <: AbstractEvent
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
    cstr == C_NULL && return ""
    own && return ptr_to_utf8(Ptr{UInt8}(cstr))
    utf8(Ptr{UInt8}(cstr))
end

immutable Depend
    name::String
    version::String
    desc::String
    name_hash::Culong
    mod::depmod_t
    # We don't allow constructing Depend with arbitrary strings
    # Change the `to_c` to include error handling if we do
    function Depend(_ptr::Ptr, own=false)
        ptr = Ptr{CTypes.Depend}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cdep = unsafe_load(ptr)
        own && ccall(:free, Void, (Ptr{Void},), ptr)
        name = cstr_to_utf8(cdep.name, own)
        version = cstr_to_utf8(cdep.version, own)
        desc = cstr_to_utf8(cdep.desc, own)
        new(name, version, desc, cdep.name_hash, cdep.mod)
    end
    Depend(str::AbstractString) =
        Depend(ccall((:alpm_dep_from_string, libalpm), Ptr{CTypes.Depend},
                     (Cstring,), str), true)
end

# Mainly for testing, no hash yet.
Base.:(==)(dep1::Depend, dep2::Depend) =
    (dep1.name == dep2.name && dep1.version == dep2.version &&
     dep1.desc == dep2.desc && dep1.mod == dep2.mod)

# WARNING! Relies on julia internal API:
#     `cconvert(Cstring, ::String)` is no-op
#     Base.RefValue
Base.cconvert(::Type{Ptr{CTypes.Depend}}, dep::Depend) =
    (dep, Ref{CTypes.Depend}())
function Base.unsafe_convert(::Type{Ptr{CTypes.Depend}},
                             tup::Tuple{Depend,Base.RefValue{CTypes.Depend}})
    dep, ref = tup
    cdep = CTypes.Depend(Base.unsafe_convert(Cstring, dep.name),
                         Base.unsafe_convert(Cstring, dep.version),
                         Base.unsafe_convert(Cstring, dep.desc),
                         dep.name_hash, dep.mod)
    ref[] = cdep
    Base.unsafe_convert(Ptr{CTypes.Depend}, ref)
end

function to_c(dep::Depend)
    name = Cstring(C_NULL)
    version = Cstring(C_NULL)
    desc = Cstring(C_NULL)
    name = ccall(:strdup, Cstring, (Ptr{UInt8},), dep.name)
    version = ccall(:strdup, Cstring, (Ptr{UInt8},), dep.version)
    desc = ccall(:strdup, Cstring, (Ptr{UInt8},), dep.desc)
    cdep = CTypes.Depend(name, version, desc, dep.name_hash, dep.mod)
    ptr = ccall(:malloc, Ptr{CTypes.Depend}, (Csize_t,), sizeof(Depend))
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

immutable DepMissing
    target::String
    depend::Depend
    causingpkg::String
    DepMissing(target, depend, causingpkg="") = new(target, depend, causingpkg)
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

# Mainly for testing, no hash yet.
Base.:(==)(obj1::DepMissing, obj2::DepMissing) =
    (obj1.target == obj2.target && obj1.depend == obj2.depend &&
     obj1.causingpkg == obj2.causingpkg)

immutable Conflict
    package1_hash::Culong
    package2_hash::Culong
    package1::String
    package2::String
    reason::Depend
    # Take ownership of the pointer
    function Conflict(_ptr::Ptr)
        ptr = Ptr{CTypes.Conflict}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cconflict = unsafe_load(ptr)
        ccall(:free, Void, (Ptr{Void},), ptr)
        package1 = cstr_to_utf8(cconflict.package1, true)
        package2 = cstr_to_utf8(cconflict.package2, true)
        # But don't take the ownership of the reason.
        # This is the internal API.
        reason = Depend(cconflict.reason)
        new(cconflict.package1_hash, cconflict.package2_hash,
            package1, package2, reason)
    end
end

immutable FileConflict
    target::String
    conflicttype::LibALPM.fileconflicttype_t
    file::String
    ctarget::String
    # Take ownership of the pointer
    function FileConflict(_ptr::Ptr)
        ptr = Ptr{CTypes.FileConflict}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cfileconflict = unsafe_load(ptr)
        ccall(:free, Void, (Ptr{Void},), ptr)
        target = cstr_to_utf8(cfileconflict.target, true)
        file = cstr_to_utf8(cfileconflict.file, true)
        ctarget = cstr_to_utf8(cfileconflict.ctarget, true)
        new(target, cfileconflict.conflicttype, file, ctarget)
    end
end

immutable File
    name::String
    size::Int64
    mode::Cint # mode_t
    function File(_ptr::Ptr)
        ptr = Ptr{CTypes.File}(_ptr)
        cfile = unsafe_load(ptr)
        name = utf8(Ptr{UInt8}(cfile.name))
        new(name, cfile.size, cfile.mode)
    end
end

immutable Backup
    name::String
    hash::String
    function Backup(_ptr::Ptr)
        ptr = Ptr{CTypes.Backup}(_ptr)
        cbackup = unsafe_load(ptr)
        name = utf8(Ptr{UInt8}(cbackup.name))
        hash = utf8(Ptr{UInt8}(cbackup.hash))
        new(name, hash)
    end
end

immutable Delta
    # filename of the delta patch
    delta::String
    # md5sum of the delta file
    delta_md5::String
    # filename of the 'before' file
    from::String
    # filename of the 'after' file
    to::String
    # filesize of the delta file
    delta_size::Int64
    # download filesize of the delta file
    download_size::Int64
    function Delta(_ptr::Ptr)
        ptr = Ptr{CTypes.Delta}(_ptr)
        cdelta = unsafe_load(ptr)
        delta = cstr_to_utf8(Ptr{UInt8}(cdelta.delta), false)
        delta_md5 = cstr_to_utf8(Ptr{UInt8}(cdelta.delta_md5), false)
        from = cstr_to_utf8(Ptr{UInt8}(cdelta.from), false)
        to = cstr_to_utf8(Ptr{UInt8}(cdelta.to), false)
        new(delta, delta_md5, from, to, cdelta.delta_size, cdelta.download_size)
    end
end
