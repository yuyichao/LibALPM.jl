#!/usr/bin/julia -f

module Event
import LibALPM: LibALPM, event_type_t, Handle, DB, Pkg
import ..CTypes
const CEvent = CTypes.Event

abstract type AbstractEvent end

struct AnyEvent <: AbstractEvent
    event_type::event_type_t
    function AnyEvent(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.AnyEvent}(ptr))
        new(cevent._type)
    end
end

struct PackageOperation <: AbstractEvent
    event_type::event_type_t
    operation::LibALPM.package_operation_t
    oldpkg::Union{Pkg,Nothing}
    newpkg::Union{Pkg,Nothing}
    function PackageOperation(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.PackageOperation}(ptr))
        new(cevent._type, cevent.operation,
            Union{Pkg,Nothing}(cevent.oldpkg, hdl),
            Union{Pkg,Nothing}(cevent.newpkg, hdl))
    end
end

struct OptdepRemoval <: AbstractEvent
    event_type::event_type_t
    # Package with the optdep.
    pkg::Union{Pkg,Nothing}
    # Optdep being removed.
    optdep::LibALPM.Depend
    function OptdepRemoval(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.OptdepRemoval}(ptr))
        new(cevent._type, Union{Pkg,Nothing}(cevent.pkg, hdl),
            LibALPM.Depend(cevent.optdep))
    end
end

struct ScriptletInfo <: AbstractEvent
    event_type::event_type_t
    # Line of scriptlet output.
    line::String
    function ScriptletInfo(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.ScriptletInfo}(ptr))
        new(cevent._type, unsafe_string(Ptr{UInt8}(cevent.line)))
    end
end

struct DatabaseMissing <: AbstractEvent
    event_type::event_type_t
    # Name of the database.
    dbname::String
    function DatabaseMissing(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.DatabaseMissing}(ptr))
        new(cevent._type, unsafe_string(Ptr{UInt8}(cevent.dbname)))
    end
end

# struct PkgDownload <: AbstractEvent
#     event_type::event_type_t
#     # Name of the file
#     file::String
#     function PkgDownload(hdl::Handle, ptr::Ptr{Cvoid})
#         cevent = unsafe_load(Ptr{CEvent.PkgDownload}(ptr))
#         new(cevent._type, unsafe_string(Ptr{UInt8}(cevent.file)))
#     end
# end
struct PkgRetrieve <: AbstractEvent
    event_type::event_type_t
    # Number of packages to download
    num::Csize_t
    # Total size of packages to download
    total_size::Int
    function PkgRetrieve(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.PkgRetrieve}(ptr))
        new(cevent._type, cevent.num, cevent.total_size)
    end
end

struct PacnewCreated <: AbstractEvent
    event_type::event_type_t
    # Whether the creation was result of a NoUpgrade or not
    from_noupgrade::Cint
    # Old package.
    oldpkg::Union{Pkg,Nothing}
    # New Package.
    newpkg::Union{Pkg,Nothing}
    # Filename of the file without the .pacnew suffix
    file::String
    function PacnewCreated(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.PacnewCreated}(ptr))
        new(cevent._type, cevent.from_noupgrade,
            Union{Pkg,Nothing}(cevent.oldpkg, hdl),
            Union{Pkg,Nothing}(cevent.newpkg, hdl),
            unsafe_string(Ptr{UInt8}(cevent.file)))
    end
end

struct PacsaveCreated <: AbstractEvent
    event_type::event_type_t
    # Old package.
    oldpkg::Union{Pkg,Nothing}
    # Filename of the file without the .pacsave suffix.
    file::String
    function PacsaveCreated(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.PacsaveCreated}(ptr))
        new(cevent._type, Union{Pkg,Nothing}(cevent.oldpkg, hdl),
            unsafe_string(Ptr{UInt8}(cevent.file)))
    end
end

struct Hook <: AbstractEvent
    event_type::event_type_t
    # Type of hooks.
    when::LibALPM.hook_when_t
    function Hook(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.Hook}(ptr))
        new(cevent._type, cevent.when)
    end
end

struct HookRun <: AbstractEvent
    event_type::event_type_t
    # Name of hook
    name::String
    # Description of hook to be outputted
    desc::String
    # position of hook being run
    position::Csize_t
    # total hooks being run
    total::Csize_t
    function HookRun(hdl::Handle, ptr::Ptr{Cvoid})
        cevent = unsafe_load(Ptr{CEvent.HookRun}(ptr))
        new(cevent._type, unsafe_string(Ptr{UInt8}(cevent.name)),
            unsafe_string(Ptr{UInt8}(cevent.desc)), cevent.position,
            cevent.total)
    end
end
end
import .Event.AbstractEvent

@inline function dispatch_event(@nospecialize(cb), hdl::Handle, ptr::Ptr{Cvoid})
    event_type = unsafe_load(Ptr{event_type_t}(ptr))
    if (event_type == EventType.PACKAGE_OPERATION_START ||
        event_type == EventType.PACKAGE_OPERATION_DONE)
        cb(hdl, Event.PackageOperation(hdl, ptr))
    elseif event_type == EventType.OPTDEP_REMOVAL
        cb(hdl, Event.OptdepRemoval(hdl, ptr))
    elseif event_type == EventType.SCRIPTLET_INFO
        cb(hdl, Event.ScriptletInfo(hdl, ptr))
    elseif event_type == EventType.DATABASE_MISSING
        cb(hdl, Event.DatabaseMissing(hdl, ptr))
    elseif (event_type == EventType.PKG_RETRIEVE_START ||
            event_type == EventType.PKG_RETRIEVE_DONE ||
            event_type == EventType.PKG_RETRIEVE_FAILED)
        cb(hdl, Event.PkgRetrieve(hdl, ptr))
    elseif event_type == EventType.PACNEW_CREATED
        cb(hdl, Event.PacnewCreated(hdl, ptr))
    elseif event_type == EventType.PACSAVE_CREATED
        cb(hdl, Event.PacsaveCreated(hdl, ptr))
    elseif (event_type == EventType.HOOK_START ||
            event_type == EventType.HOOK_DONE)
        cb(hdl, Event.Hook(hdl, ptr))
    elseif (event_type == EventType.HOOK_RUN_START ||
            event_type == EventType.HOOK_RUN_DONE)
        cb(hdl, Event.HookRun(hdl, ptr))
    else
        cb(hdl, Event.AnyEvent(hdl, ptr))
    end
end
