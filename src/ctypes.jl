#!/usr/bin/julia -f

module CTypes
import LibALPM: LibALPM, EventType

"Dependency"
struct Depend
    name::Cstring
    version::Cstring
    desc::Cstring
    name_hash::Culong
    mod::LibALPM.depmod_t
end

"Missing dependency"
struct DepMissing
    target::Cstring
    depend::Ptr{Depend}
    # this is used only in the case of a remove dependency error
    causingpkg::Cstring
end

"Conflict"
struct Conflict
    package1_hash::Culong
    package2_hash::Culong
    package1::Cstring
    package2::Cstring
    reason::Ptr{Depend}
end

"File conflict"
struct FileConflict
    target::Cstring
    conflicttype::LibALPM.fileconflicttype_t
    file::Cstring
    ctarget::Cstring
end

"Package group"
struct Group
    name::Cstring
    # FIXME: alpm_list_t*
    package::Ptr{Cvoid}
end

"File in a package"
struct File
    name::Cstring
    size::Int64
    mode::Cint # mode_t
end

"Package filelist container"
struct FileList
    count::Csize_t
    files::Ptr{File}
end

"Local package or package file backup entry"
struct Backup
    name::Cstring
    hash::Cstring
end

struct PGPKey
    data::Ptr{Cvoid}
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
struct SigResult
    key::PGPKey
    status::LibALPM.sigstatus_t
    validity::LibALPM.sigvalidity_t
end

"""
Signature list

Contains the number of signatures found and a pointer to an array of results.
The array is of size count.
"""
struct SigList
    count::Csize_t
    results::Ptr{SigResult}
end

module Event
import LibALPM: LibALPM, event_type_t
import ..CTypes

abstract type AbstractEvent end

struct AnyEvent <: AbstractEvent
    _type::event_type_t
end

struct PackageOperation <: AbstractEvent
    _type::event_type_t
    operation::LibALPM.package_operation_t
    oldpkg::Ptr{Cvoid} # alpm_pkg_t*
    newpkg::Ptr{Cvoid} # alpm_pkg_t*
end

struct OptdepRemoval <: AbstractEvent
    _type::event_type_t
    # Package with the optdep.
    pkg::Ptr{Cvoid} # alpm_pkg_t*
    # Optdep being removed.
    optdep::Ptr{CTypes.Depend}
end

struct ScriptletInfo <: AbstractEvent
    _type::event_type_t
    # Line of scriptlet output.
    line::Cstring
end

struct DatabaseMissing <: AbstractEvent
    _type::event_type_t
    # Name of the database.
    dbname::Cstring
end

# struct PkgDownload <: AbstractEvent
#     _type::event_type_t
#     # Name of the file
#     file::Cstring
# end
struct PkgRetrieve <: AbstractEvent
    _type::event_type_t
    # Number of packages to download
    num::Csize_t
    # Total size of packages to download
    total_size::Int # off_t
end

struct PacnewCreated <: AbstractEvent
    _type::event_type_t
    # Whether the creation was result of a NoUpgrade or not
    from_noupgrade::Cint
    # Old package.
    oldpkg::Ptr{Cvoid} # alpm_pkg_t*
    # New Package.
    newpkg::Ptr{Cvoid} # alpm_pkg_t*
    # Filename of the file without the .pacnew suffix
    file::Cstring
end

struct PacsaveCreated <: AbstractEvent
    _type::event_type_t
    # Old package.
    oldpkg::Ptr{Cvoid} # alpm_pkg_t*
    # Filename of the file without the .pacsave suffix.
    file::Cstring
end

struct Hook <: AbstractEvent
    _type::event_type_t
    # Type of hooks.
    when::LibALPM.hook_when_t
end

struct HookRun <: AbstractEvent
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

abstract type AbstractQuestion end

struct AnyQuestion <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer
    answer::Cint
end

struct InstallIgnorepkg <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to install pkg anyway
    install::Cint
    # Package in IgnorePkg/IgnoreGroup
    pkg::Ptr{Cvoid} # alpm_pkg_t*
end

struct Replace <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to replace oldpkg with newpkg
    replace::Cint
    # Package to be replaced
    oldpkg::Ptr{Cvoid} # alpm_pkg_t*
    # Package to replace with
    newpkg::Ptr{Cvoid} # alpm_pkg_t*
    # DB of newpkg
    newdb::Ptr{Cvoid} # alpm_db_t*
end

struct Conflict <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to remove conflict->package2
    remove::Cint
    # Conflict info
    conflict::Ptr{CTypes.Conflict}
end

struct Corrupted <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to remove filepath.
    remove::Cint
    # Filename to remove
    filepath::Cstring
    # Error code indicating the reason for package invalidity
    reason::LibALPM.errno_t
end

struct RemovePkgs <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: whether or not to skip packages
    skip::Cint
    # List of alpm_pkg_t* with unresolved dependencies
    # FIXME: alpm_list_t*
    packages::Ptr{Cvoid}
end

struct SelectProvider <: AbstractQuestion
    # Type of question
    _type::Cint
    # Answer: which provider to use (index from providers)
    use_index::Cint
    # List of alpm_pkg_t* as possible providers
    # FIXME: alpm_list_t*
    providers::Ptr{Cvoid}
    # What providers provide for
    depend::Ptr{CTypes.Depend}
end

struct ImportKey <: AbstractQuestion
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
    res = unsafe_string(Ptr{UInt8}(cstr))
    own && ccall(:free, Cvoid, (Ptr{Cvoid},), Ptr{Cvoid}(cstr))
    return res
end

struct Depend
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
        own && ccall(:free, Cvoid, (Ptr{Cvoid},), ptr)
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
#     Base.RefValue
Base.cconvert(::Type{Ptr{CTypes.Depend}}, dep::Depend) =
    (Ref{CTypes.Depend}(), Base.cconvert(Cstring, dep.name),
     Base.cconvert(Cstring, dep.version), Base.cconvert(Cstring, dep.desc),
     dep.name_hash, dep.mod)
function Base.unsafe_convert(::Type{Ptr{CTypes.Depend}}, tup::Tuple)
    ref, name, version, desc, name_hash, mod = tup
    cdep = CTypes.Depend(Base.unsafe_convert(Cstring, name),
                         Base.unsafe_convert(Cstring, version),
                         Base.unsafe_convert(Cstring, desc),
                         name_hash, mod)
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
    take_cstring(ccall((:alpm_dep_compute_string, libalpm), Ptr{UInt8},
                       (Ptr{CTypes.Depend},), dep))

function Base.show(io::IO, dep::Depend)
    print(io, "LibALPM.Depend(")
    show(io, compute_string(dep))
    print(io, ")")
end

struct DepMissing
    target::String
    depend::Depend
    causingpkg::String
    DepMissing(target, depend, causingpkg="") = new(target, depend, causingpkg)
    # Take ownership of the pointer
    function DepMissing(_ptr::Ptr)
        ptr = Ptr{CTypes.DepMissing}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cdepmissing = unsafe_load(ptr)
        ccall(:free, Cvoid, (Ptr{Cvoid},), ptr)
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

struct Conflict
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
        ccall(:free, Cvoid, (Ptr{Cvoid},), ptr)
        package1 = cstr_to_utf8(cconflict.package1, true)
        package2 = cstr_to_utf8(cconflict.package2, true)
        # But don't take the ownership of the reason.
        # This is the internal API.
        reason = Depend(cconflict.reason)
        new(cconflict.package1_hash, cconflict.package2_hash,
            package1, package2, reason)
    end
end

struct FileConflict
    target::String
    conflicttype::LibALPM.fileconflicttype_t
    file::String
    ctarget::String
    # Take ownership of the pointer
    function FileConflict(_ptr::Ptr)
        ptr = Ptr{CTypes.FileConflict}(_ptr)
        # WARNING! Relies on alpm internal API (freeing fields with `free`)
        cfileconflict = unsafe_load(ptr)
        ccall(:free, Cvoid, (Ptr{Cvoid},), ptr)
        target = cstr_to_utf8(cfileconflict.target, true)
        file = cstr_to_utf8(cfileconflict.file, true)
        ctarget = cstr_to_utf8(cfileconflict.ctarget, true)
        new(target, cfileconflict.conflicttype, file, ctarget)
    end
end

struct File
    name::String
    size::Int64
    mode::Cint # mode_t
    function File(_ptr::Ptr)
        ptr = Ptr{CTypes.File}(_ptr)
        cfile = unsafe_load(ptr)
        name = unsafe_string(Ptr{UInt8}(cfile.name))
        new(name, cfile.size, cfile.mode)
    end
end

struct Backup
    name::String
    hash::String
    function Backup(_ptr::Ptr)
        ptr = Ptr{CTypes.Backup}(_ptr)
        cbackup = unsafe_load(ptr)
        name = unsafe_string(Ptr{UInt8}(cbackup.name))
        hash = unsafe_string(Ptr{UInt8}(cbackup.hash))
        new(name, hash)
    end
end
