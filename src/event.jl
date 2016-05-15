#!/usr/bin/julia -f

module Event
import LibALPM: LibALPM, event_type_t, Handle, DB, Pkg
import ..CTypes
const CEvent = CTypes.Event

abstract AbstractEvent

immutable AnyEvent <: AbstractEvent
    event_type::event_type_t
    function AnyEvent(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.AnyEvent}(ptr))
        new(cevent._type)
    end
end

immutable PackageOperation <: AbstractEvent
    event_type::event_type_t
    operation::LibALPM.package_operation_t
    oldpkg::Nullable{Pkg}
    newpkg::Nullable{Pkg}
    function PackageOperation(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.PackageOperation}(ptr))
        new(cevent._type, cevent.operation,
            Nullable{Pkg}(cevent.oldpkg, hdl),
            Nullable{Pkg}(cevent.newpkg, hdl))
    end
end

immutable OptdepRemoval <: AbstractEvent
    event_type::event_type_t
    # Package with the optdep.
    pkg::Nullable{Pkg}
    # Optdep being removed.
    optdep::LibALPM.Depend
    function OptdepRemoval(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.OptdepRemoval}(ptr))
        new(cevent._type, Nullable{Pkg}(cevent.pkg, hdl),
            LibALPM.Depend(cevent.optdep))
    end
end

immutable DeltaPatch <: AbstractEvent
    event_type::event_type_t
    # Delta info
    delta::Nullable{LibALPM.Delta}
    function DeltaPatch(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.DeltaPatch}(ptr))
        delta = (cevent.delta == C_NULL ? Nullable{LibALPM.Delta}() :
                 Nullable(LibALPM.Delta(cevent.delta)))
        new(cevent._type, delta)
    end
    # DELTA_PATCHES_START and DELTA_PATCHES_DONE has an uninitialized delta
    # field
    function DeltaPatch(hdl::Handle, _type::event_type_t)
        new(_type, Nullable{LibALPM.Delta}())
    end
end

immutable ScriptletInfo <: AbstractEvent
    event_type::event_type_t
    # Line of scriptlet output.
    line::String
    function ScriptletInfo(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.ScriptletInfo}(ptr))
        new(cevent._type, utf8(Ptr{UInt8}(cevent.line)))
    end
end

immutable DatabaseMissing <: AbstractEvent
    event_type::event_type_t
    # Name of the database.
    dbname::String
    function DatabaseMissing(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.DatabaseMissing}(ptr))
        new(cevent._type, utf8(Ptr{UInt8}(cevent.dbname)))
    end
end

immutable PkgDownload <: AbstractEvent
    event_type::event_type_t
    # Name of the file
    file::String
    function PkgDownload(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.PkgDownload}(ptr))
        new(cevent._type, utf8(Ptr{UInt8}(cevent.file)))
    end
end

immutable PacnewCreated <: AbstractEvent
    event_type::event_type_t
    # Whether the creation was result of a NoUpgrade or not
    from_noupgrade::Cint
    # Old package.
    oldpkg::Nullable{Pkg}
    # New Package.
    newpkg::Nullable{Pkg}
    # Filename of the file without the .pacnew suffix
    file::String
    function PacnewCreated(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.PacnewCreated}(ptr))
        new(cevent._type, cevent.from_noupgrade,
            Nullable{Pkg}(cevent.oldpkg, hdl),
            Nullable{Pkg}(cevent.newpkg, hdl), utf8(Ptr{UInt8}(cevent.file)))
    end
end

immutable PacsaveCreated <: AbstractEvent
    event_type::event_type_t
    # Old package.
    oldpkg::Nullable{Pkg}
    # Filename of the file without the .pacsave suffix.
    file::String
    function PacsaveCreated(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.PacsaveCreated}(ptr))
        new(cevent._type, Nullable{Pkg}(cevent.oldpkg, hdl),
            utf8(Ptr{UInt8}(cevent.file)))
    end
end

immutable Hook <: AbstractEvent
    event_type::event_type_t
    # Type of hooks.
    when::LibALPM.hook_when_t
    function Hook(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.Hook}(ptr))
        new(cevent._type, cevent.when)
    end
end

immutable HookRun <: AbstractEvent
    event_type::event_type_t
    # Name of hook
    name::String
    # Description of hook to be outputted
    desc::String
    # position of hook being run
    position::Csize_t
    # total hooks being run
    total::Csize_t
    function HookRun(hdl::Handle, ptr::Ptr{Void})
        cevent = unsafe_load(Ptr{CEvent.HookRun}(ptr))
        new(cevent._type, utf8(Ptr{UInt8}(cevent.name)),
            utf8(Ptr{UInt8}(cevent.desc)), cevent.position, cevent.total)
    end
end
end
import .Event.AbstractEvent

@inline function dispatch_event(cb::ANY, hdl::Handle, ptr::Ptr{Void})
    event_type = unsafe_load(Ptr{event_type_t}(ptr))
    if (event_type == EventType.PACKAGE_OPERATION_START ||
        event_type == EventType.PACKAGE_OPERATION_DONE)
        cb(hdl, Event.PackageOperation(hdl, ptr))
    elseif event_type == EventType.OPTDEP_REMOVAL
        cb(hdl, Event.OptdepRemoval(hdl, ptr))
    elseif (event_type == EventType.DELTA_PATCHES_START ||
            event_type == EventType.DELTA_PATCHES_DONE)
        cb(hdl, Event.DeltaPatch(hdl, event_type))
    elseif (event_type == EventType.DELTA_PATCH_START ||
            event_type == EventType.DELTA_PATCH_DONE ||
            event_type == EventType.DELTA_PATCH_FAILED)
        cb(hdl, Event.DeltaPatch(hdl, ptr))
    elseif event_type == EventType.SCRIPTLET_INFO
        cb(hdl, Event.ScriptletInfo(hdl, ptr))
    elseif event_type == EventType.DATABASE_MISSING
        cb(hdl, Event.DatabaseMissing(hdl, ptr))
    elseif (event_type == EventType.PKGDOWNLOAD_START ||
            event_type == EventType.PKGDOWNLOAD_DONE ||
            event_type == EventType.PKGDOWNLOAD_FAILED)
        cb(hdl, Event.PkgDownload(hdl, ptr))
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
