#!/usr/bin/julia -f

import LibALPM
import LibArchive
using Base.Test

const thisdir = dirname(@__FILE__)

function get_default_url(repo)
    open("/etc/pacman.d/mirrorlist") do fd
        for line in eachline(fd)
            line[1] == '#' && continue
            isempty(line) && continue
            line = strip(line)
            m = match(r"^ *Server *= *([^ ]*)", line)
            m === nothing && continue
            m = m::RegexMatch
            urltemplate = m.captures[1]
            return replace(replace(urltemplate, "\$repo", repo),
                           "\$arch", string(Base.ARCH))
        end
        warn("Cannot find default server, use mirrors.kernel.org instead")
        return "http://mirrors.kernel.org/archlinux/$repo/os/$(Base.ARCH)"
    end
end

function setup_handle(dir)
    dbpath = joinpath(dir, "var/lib/pacman/")
    cachepath = joinpath(dir, "var/cache/pacman/pkg/")
    mkpath(dbpath)
    mkpath(cachepath)
    hdl = LibALPM.Handle(dir, dbpath)
    LibALPM.set_cachedirs(hdl, [cachepath])
    hdl
end

function makepkg(pkgbuild, dest, arch=string(Base.ARCH); copy_files=String[])
    mktempdir() do dir
        cd(dir) do
            cp(pkgbuild, "PKGBUILD")
            for file in copy_files
                cp(file, basename(file))
            end
            run(setenv(`makepkg`, "PKGEXT"=>".pkg.tar", "CARCH"=>arch))
            pkgs = String[]
            mkpath(dest)
            for fname in readdir()
                endswith(fname, ".pkg.tar") || continue
                pkgdest = joinpath(dest, fname)
                push!(pkgs, pkgdest)
                cp(fname, pkgdest)
            end
            pkgs
        end
    end
end

include("lazycontext.jl")
include("list.jl")

@testset "Errno" begin
    for err in instances(LibALPM.errno_t)
        @test isa(strerror(err), String)
    end
end

@testset "Utils" begin
    @test isa(LibALPM.version(), VersionNumber)
    @test LibALPM.capabilities() != 0

    @test LibALPM.compute_md5sum(joinpath(thisdir, "test_file")) == "95f50f74390e8e4c60ac55b17d5d0e93"
    @test LibALPM.compute_sha256sum(joinpath(thisdir, "test_file")) == "4e22afc956e83e884362343cb2e264f8fafe350768f321ea9d0f41ca7261975c"

    @test LibALPM.vercmp("1.2", "1.2") == 0
    @test LibALPM.vercmp("1.1", "1.2") == -1
    @test LibALPM.vercmp("1.2", "1.1") == 1
end

@testset "Properties" begin
    include("properties.jl")
end

@testset "Fetch" begin
    hdl = LibALPM.Handle("/", "/var/lib/pacman/")
    try
        LibALPM.fetch_pkgurl(hdl, "not-exist-url.abcd")
    catch ex
        @test isa(ex, LibALPM.Error)
        str = sprint(io->Base.showerror(io, ex))
        @test contains(str, "ALPM Error:")
        @test contains(str, "fetch_pkgurl")
    end
    LibALPM.release(hdl)
end

@testset "DB" begin
    hdl = LibALPM.Handle("/", "/var/lib/pacman/")
    localdb = LibALPM.get_localdb(hdl)
    str = sprint(io->show(io, localdb))
    @test contains(str, "LibALPM.DB(ptr=")
    @test contains(str, "name=\"local\"")
    LibALPM.get_siglevel(localdb)
    LibALPM.check_valid(localdb)
    @test LibALPM.get_servers(localdb) == []
    pacmanpkg = LibALPM.get_pkg(localdb, "pacman")
    # Local package don't have a changelog
    @test_throws LibALPM.Error LibALPM.ChangeLog(pacmanpkg)
    @test LibALPM.get_pkg(localdb, "pacman") === pacmanpkg
    @test !isempty(LibALPM.get_pkgcache(localdb))
    # Only syncdb can be updated
    @test_throws LibALPM.Error LibALPM.update(localdb, false)

    coredb = LibALPM.register_syncdb(hdl, "core",
                                     LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                     LibALPM.SigLevel.DATABASE_OPTIONAL)

    @test LibALPM.get_servers(coredb) == []
    mirrorurl = "http://mirrors.kernel.org/archlinux/core/os/$(Base.ARCH)"
    mirrorurl2 = "http://mirror.rit.edu/archlinux/core/os/$(Base.ARCH)"
    LibALPM.set_servers(coredb, [mirrorurl])
    @test LibALPM.get_servers(coredb) == [mirrorurl]
    LibALPM.add_server(coredb, mirrorurl2)
    @test LibALPM.get_servers(coredb) == [mirrorurl, mirrorurl2]
    LibALPM.remove_server(coredb, mirrorurl)
    @test LibALPM.get_servers(coredb) == [mirrorurl2]

    LibALPM.unregister(coredb)
    @test coredb.ptr == C_NULL

    LibALPM.release(hdl)
end

@testset "Pkg" begin
    hdl = LibALPM.Handle("/", "/var/lib/pacman/")
    localdb = LibALPM.get_localdb(hdl)
    glibcpkg = LibALPM.get_pkg(localdb, "glibc")
    str = sprint(io->show(io, glibcpkg))
    @test contains(str, "name=\"glibc\"")
    # checkmd5sum is only for package from local file?
    @test_throws LibALPM.Error LibALPM.checkmd5sum(glibcpkg)
    @test !isempty(LibALPM.compute_requiredby(glibcpkg))
    # no known package that optionally depend on glibc...
    @test isempty(LibALPM.compute_optionalfor(glibcpkg))
    @test !LibALPM.should_ignore(glibcpkg)
    # no filename for localdb package
    @test_throws ArgumentError LibALPM.get_filename(glibcpkg)
    # no pkgbase for localdb package
    @test_throws ArgumentError LibALPM.get_base(glibcpkg)
    @test LibALPM.get_name(glibcpkg) == "glibc"
    @test isa(LibALPM.get_version(glibcpkg), String)
    @test LibALPM.get_origin(glibcpkg) == LibALPM.PkgFrom.LOCALDB
    # GNU C Library
    @test contains(LibALPM.get_desc(glibcpkg), "Library")
    @test contains(LibALPM.get_url(glibcpkg), "http")
    @test LibALPM.get_builddate(glibcpkg) > 0
    @test LibALPM.get_installdate(glibcpkg) > 0
    @test isa(LibALPM.get_packager(glibcpkg), String)
    # Apparently local package doesn't have checksum...
    @test_throws ArgumentError LibALPM.get_md5sum(glibcpkg)
    @test_throws ArgumentError LibALPM.get_sha256sum(glibcpkg)
    # This may fail on 32bit...
    @test LibALPM.get_arch(glibcpkg) == string(Base.ARCH)
    # Not available for local pkg
    @test LibALPM.get_size(glibcpkg) == 0
    @test LibALPM.get_isize(glibcpkg) > 0
    @test LibALPM.get_reason(glibcpkg) in [LibALPM.PkgReason.EXPLICIT,
                                           LibALPM.PkgReason.DEPEND]
    @test LibALPM.get_licenses(glibcpkg) == ["GPL", "LGPL"]
    @test LibALPM.get_groups(glibcpkg) == ["base"]
    @test !isempty(LibALPM.get_files(glibcpkg))
    @test !isempty(LibALPM.get_backup(glibcpkg))
    @test LibALPM.get_db(glibcpkg) === localdb
    @test LibALPM.get_validation(glibcpkg) != 0
    @test LibALPM.get_validation(glibcpkg) < 16
    @test LibALPM.download_size(glibcpkg) == 0
    # These relies on the detail about the glibc package
    @test LibALPM.has_scriptlet(glibcpkg)
    @test !isempty(LibALPM.get_depends(glibcpkg))
    @test isempty(LibALPM.get_optdepends(glibcpkg))
    @test isempty(LibALPM.get_conflicts(glibcpkg))
    @test isempty(LibALPM.get_provides(glibcpkg))
    @test isempty(LibALPM.get_replaces(glibcpkg))

    coredb = LibALPM.register_syncdb(hdl, "core",
                                     LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                     LibALPM.SigLevel.DATABASE_OPTIONAL)

    glibcpkg2 = LibALPM.get_pkg(coredb, "glibc")
    # this might assume the package file is available, let's see...
    @test !isempty(LibALPM.get_filename(glibcpkg2))
    @test !isempty(LibALPM.get_md5sum(glibcpkg2))
    @test !isempty(LibALPM.get_sha256sum(glibcpkg2))
    @test LibALPM.get_size(glibcpkg2) > 0
    @test LibALPM.get_db(glibcpkg2) === coredb
    @test !isempty(LibALPM.get_base64_sig(glibcpkg2))
    @test LibALPM.download_size(glibcpkg2) > 0
    # Not sure what to expect ...
    LibALPM.get_deltas(glibcpkg2)
    LibALPM.unused_deltas(glibcpkg2)

    LibALPM.unregister(coredb)
    @test coredb.ptr == C_NULL
    @test glibcpkg2.ptr == C_NULL
    @test glibcpkg.ptr != C_NULL
    @test LibALPM.get_name(glibcpkg) == "glibc"

    coredb = LibALPM.register_syncdb(hdl, "core",
                                     LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                     LibALPM.SigLevel.DATABASE_OPTIONAL)
    LibALPM.unregister_all_syncdbs(hdl)
    @test glibcpkg.ptr != C_NULL
    @test LibALPM.get_name(glibcpkg) == "glibc"

    LibALPM.release(hdl)
    @test glibcpkg.ptr == C_NULL
end

@testset "Finalize" begin
    mktempdir() do dir
        hdl = setup_handle(dir)
        hdl2 = LibALPM.Handle("/", "/var/lib/pacman/")
        hdl2_finalized = false
        freehdl2 = ()->begin
            h = hdl2
            hdl2 = nothing
            h === nothing && return
            LibALPM.release(h::LibALPM.Handle)
            hdl2_finalized = true
        end
        logcb = (cbhdl, level, msg)->begin
            freehdl2()
            @test cbhdl === hdl
            if level < LibALPM.LogLevel.WARNING
                println("ALPM($level): $msg")
            end
        end
        LibALPM.set_logcb(hdl, logcb)
        LibALPM.set_eventcb(hdl,
                            (cbhdl, event)->(@test cbhdl === hdl;
                                             freehdl2();
                                             @test isa(event,
                                                       LibALPM.AbstractEvent)))
        # AFAIK this log goes directly to the log file or syslog
        LibALPM.logaction(hdl, "LibALPM.jl", "Message")
        localdb = LibALPM.get_localdb(hdl)
        coredb = LibALPM.register_syncdb(hdl, "core",
                                         LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                         LibALPM.SigLevel.DATABASE_OPTIONAL)

        mirrorurl = get_default_url("core")
        LibALPM.set_servers(coredb, [mirrorurl])
        @test !LibALPM.update(coredb, false)
        # This can fail if the remote is updated right in between the two calls
        @test LibALPM.update(coredb, false)
        @test hdl2 === nothing
        @test hdl2_finalized
        LibALPM.release(hdl)
    end
end

@testset "Pkgroot" begin
    mktempdir() do dir
        hdl = setup_handle(dir)
        logcb = (cbhdl, level, msg)->begin
            @test cbhdl === hdl
            if level < LibALPM.LogLevel.WARNING
                println("ALPM($level): $msg")
            end
        end
        LibALPM.set_logcb(hdl, logcb)
        LibALPM.set_eventcb(hdl,
                            (cbhdl, event)->(@test cbhdl === hdl;
                                             @test isa(event,
                                                       LibALPM.AbstractEvent)))
        # AFAIK this log goes directly to the log file or syslog
        LibALPM.logaction(hdl, "LibALPM.jl", "Message")
        localdb = LibALPM.get_localdb(hdl)
        coredb = LibALPM.register_syncdb(hdl, "core",
                                         LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                         LibALPM.SigLevel.DATABASE_OPTIONAL)

        @test LibALPM.get_servers(coredb) == []
        mirrorurl = get_default_url("core")
        info("Mirror used: \"$mirrorurl\"")
        LibALPM.set_servers(coredb, [mirrorurl])
        @test !LibALPM.update(coredb, false)
        # This can fail if the remote is updated right in between the two calls
        @test LibALPM.update(coredb, false)

        glibcpkg = LibALPM.get_pkg(coredb, "glibc")
        glibcfname = LibALPM.get_filename(glibcpkg)
        glibcpath = LibALPM.fetch_pkgurl(hdl, "$mirrorurl/$glibcfname")
        glibcpath_sig = LibALPM.fetch_pkgurl(hdl, "$mirrorurl/$glibcfname.sig")
        @test isfile(glibcpath)
        @test isfile(glibcpath_sig)
        glibcpkg_load = LibALPM.load(hdl, glibcpath, true,
                                     LibALPM.SigLevel.PACKAGE_OPTIONAL)
        LibALPM.free(glibcpkg_load)
        glibcpkg_load = LibALPM.load(hdl, glibcpath, true,
                                     LibALPM.SigLevel.PACKAGE_OPTIONAL)

        LibALPM.trans_init(hdl, 0)
        LibALPM.add_pkg(hdl, glibcpkg_load)
        LibALPM.sysupgrade(hdl, true)
        @test LibALPM.get_flags(hdl) == 0
        @test LibALPM.get_remove(hdl) == []
        @test LibALPM.get_add(hdl) == [glibcpkg_load]
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        @test_throws LibALPM.Error LibALPM.trans_interrupt(hdl)
        LibALPM.trans_release(hdl)

        glibcpkg_local = LibALPM.get_pkg(localdb, "glibc")
        @test LibALPM.get_reason(glibcpkg_local) == LibALPM.PkgReason.EXPLICIT
        LibALPM.set_reason(glibcpkg_local, LibALPM.PkgReason.DEPEND)
        @test LibALPM.get_reason(glibcpkg_local) == LibALPM.PkgReason.DEPEND
        LibALPM.trans_init(hdl, 0)
        LibALPM.remove_pkg(hdl, glibcpkg_local)
        @test LibALPM.get_flags(hdl) == 0
        # The package returned from `get_remove` is somehow different
        # from the localdb one...
        @test [LibALPM.get_name(pkg)
               for pkg in LibALPM.get_remove(hdl)] == ["glibc"]
        @test LibALPM.get_add(hdl) == []
        LibALPM.trans_prepare(hdl)
        @test LibALPM.get_name(glibcpkg_local) == "glibc"
        LibALPM.trans_commit(hdl)
        @test glibcpkg_local.ptr == C_NULL
        LibALPM.trans_release(hdl)
        LibALPM.release(hdl)
    end
end

include("pkgerror.jl")

@testset "Backups" begin
    mktempdir() do dir
        pkgdir = joinpath(dir, "pkgdir")
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)
        pacnew_created = false
        pacsave_created = false
        eventcb = (cbhdl::LibALPM.Handle, event::LibALPM.AbstractEvent) -> begin
            @test cbhdl === hdl
            if isa(event, LibALPM.Event.PacnewCreated)
                event = event::LibALPM.Event.PacnewCreated
                @test event.file == joinpath(dir, "backups")
                pacnew_created = true
            elseif isa(event, LibALPM.Event.PacsaveCreated)
                event = event::LibALPM.Event.PacsaveCreated
                @test event.file == joinpath(dir, "backups")
                pacsave_created = true
            end
        end

        LibALPM.set_eventcb(hdl, eventcb)

        backup_file = joinpath(dir, "backups")

        touch(backup_file)

        LibALPM.trans_init(hdl, 0)
        pkgbuild = joinpath(thisdir, "pkgs", "PKGBUILD.backups")
        for path in makepkg(pkgbuild, pkgdir)
            pkg = LibALPM.load(hdl, path, true,
                               LibALPM.SigLevel.PACKAGE_OPTIONAL)
            LibALPM.add_pkg(hdl, pkg)
        end
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)
        @test pacnew_created
        @test !pacsave_created
        @test readstring(backup_file) == ""
        @test readstring("$backup_file.pacnew") == "1\n"
        pacnew_created = false

        LibALPM.trans_init(hdl, 0)
        pkgbuild = joinpath(thisdir, "pkgs", "PKGBUILD.backups2")
        for path in makepkg(pkgbuild, pkgdir)
            pkg = LibALPM.load(hdl, path, true,
                               LibALPM.SigLevel.PACKAGE_OPTIONAL)
            LibALPM.add_pkg(hdl, pkg)
        end
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)
        @test pacnew_created
        @test !pacsave_created
        @test readstring(backup_file) == ""
        @test readstring("$backup_file.pacnew") == "2\n"
        pacnew_created = false

        localdb = LibALPM.get_localdb(hdl)
        pkg_local = LibALPM.get_pkg(localdb, "backups")
        LibALPM.trans_init(hdl, 0)
        LibALPM.remove_pkg(hdl, pkg_local)
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)
        @test !pacnew_created
        @test pacsave_created
        @test !ispath(backup_file)
        @test readstring("$backup_file.pacsave") == ""
        pacsave_created = false

        LibALPM.release(hdl)
    end
end

function repo_add(repodir, reponame, pkg)
    mkpath(repodir)
    cd(repodir) do
        run(`repo-add "$reponame.db.tar.gz" $pkg`)
    end
end

@testset "Delta" begin
    mktempdir() do dir
        pkgdir = joinpath(dir, "pkgdir")
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)
        delta_event = false
        delta_event_nonnull = false
        eventcb = (cbhdl::LibALPM.Handle, event::LibALPM.AbstractEvent) -> begin
            @test cbhdl === hdl
            if isa(event, LibALPM.Event.DeltaPatch)
                event = event::LibALPM.Event.DeltaPatch
                delta_event = true
                !isnull(event.delta) && (delta_event_nonnull = true)
            end
        end
        LibALPM.set_eventcb(hdl, eventcb)
        LibALPM.set_deltaratio(hdl, 2.0)

        pkg1 = makepkg(joinpath(thisdir, "pkgs", "PKGBUILD.backups"),
                       pkgdir)[1]
        repo_add(pkgdir, "alpmtest", pkg1)

        testdb = LibALPM.register_syncdb(hdl, "alpmtest",
                                         LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                         LibALPM.SigLevel.DATABASE_OPTIONAL)

        LibALPM.set_servers(testdb, ["file://$pkgdir"])
        @test !LibALPM.update(testdb, false)
        @test LibALPM.update(testdb, false)
        pkg_load = LibALPM.get_pkg(testdb, "backups")

        LibALPM.trans_init(hdl, 0)
        LibALPM.add_pkg(hdl, pkg_load)
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)

        @test !delta_event
        @test !delta_event_nonnull

        pkg2 = makepkg(joinpath(thisdir, "pkgs", "PKGBUILD.backups2"),
                       pkgdir)[1]
        cd(pkgdir) do
            run(`pkgdelta --min-pkg-size=0 $pkg1 $pkg2`)
        end
        deltapath = joinpath(pkgdir,
                             "backups-0.1-1_to_0.2-1-$(Base.ARCH).delta")
        # Wait 2 second so that the timestamp changes...
        sleep(2)
        repo_add(pkgdir, "alpmtest", [deltapath, pkg2])

        @test !LibALPM.update(testdb, false)
        @test LibALPM.update(testdb, false)
        pkg_load = LibALPM.get_pkg(testdb, "backups")
        @test !isempty(LibALPM.get_deltas(pkg_load))
        @test isempty(LibALPM.unused_deltas(pkg_load))

        LibALPM.trans_init(hdl, 0)
        LibALPM.sysupgrade(hdl, false)
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)

        @test delta_event
        @test delta_event_nonnull

        LibALPM.release(hdl)

        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)

        localdb = LibALPM.get_localdb(hdl)
        pkg_local = LibALPM.get_pkg(localdb, "backups")

        # It seems that newly installed package doesn't support this interface
        LibArchive.Reader(pkg_local) do reader
            entry = LibArchive.next_header(reader)
            # Somehow reading the content doesn't work...
            @test LibArchive.pathname(entry) == "./.BUILDINFO"
            @test LibArchive.filetype(entry) == LibArchive.FileType.REG
            LibArchive.free(entry)
            entry = LibArchive.next_header(reader)
            @test LibArchive.pathname(entry) == "./.PKGINFO"
            @test LibArchive.filetype(entry) == LibArchive.FileType.REG
            LibArchive.free(entry)
            entry = LibArchive.next_header(reader)
            @test LibArchive.pathname(entry) == "./backups"
            @test LibArchive.filetype(entry) == LibArchive.FileType.REG
            LibArchive.free(entry)
        end

        LibALPM.release(hdl)
    end
end

@testset "ChangeLog" begin
    mktempdir() do dir
        pkgdir = joinpath(dir, "pkgdir")
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)

        pkg = makepkg(joinpath(thisdir, "pkgs", "PKGBUILD.changelog"),
                      pkgdir; copy_files=[joinpath(thisdir, "pkgs",
                                                   "changelog")])[1]
        pkg_load = LibALPM.load(hdl, pkg, true,
                                LibALPM.SigLevel.PACKAGE_OPTIONAL)

        clog = LibALPM.ChangeLog(pkg_load)
        clog_str = string(clog)
        @test contains(clog_str, string(pkg_load))
        @test contains(clog_str, "LibALPM.ChangeLog")
        logstart = "# Version 0.0\n\n"
        @test String(read(clog, length(logstart))) == logstart
        lognext = "Random text\n\n"
        buf = Vector{UInt8}(length(lognext))
        @test readbytes!(clog, buf) == length(lognext)
        @test String(buf) == lognext
        logend = "# Version 0.1\n\nNothing new here\n"
        @test readstring(clog) == logend
        @test_throws EOFError read(clog, UInt8)

        clog2 = LibALPM.ChangeLog(pkg_load)
        clog3 = LibALPM.ChangeLog(pkg_load)
        @test read(clog3, UInt8) == UInt8('#')
        @test String(readavailable(clog2)) == logstart * lognext * logend
        @test "#" * String(read(clog3)) == logstart * lognext * logend
        close(clog3)
        close(clog2)
        close(clog)

        clog_str = randstring(100_000)
        pkg = mktempdir() do dir
            changelog2 = joinpath(dir, "changelog2")
            open(changelog2, "w") do fd
                write(fd, clog_str)
            end
            makepkg(joinpath(thisdir, "pkgs", "PKGBUILD.changelog2"),
                    pkgdir; copy_files=[changelog2])[1]
        end
        pkg_load = LibALPM.load(hdl, pkg, true,
                                LibALPM.SigLevel.PACKAGE_OPTIONAL)

        clog = LibALPM.ChangeLog(pkg_load)
        @test String(read(clog)) == clog_str
        close(clog)

        LibALPM.release(hdl)
    end
end

@testset "Optdep" begin
    mktempdir() do dir
        pkgdir = joinpath(dir, "pkgdir")
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)
        optdep_rm_event = false
        eventcb = (cbhdl::LibALPM.Handle, event::LibALPM.AbstractEvent) -> begin
            @test cbhdl === hdl
            if isa(event, LibALPM.Event.OptdepRemoval)
                event = event::LibALPM.Event.OptdepRemoval
                @test LibALPM.get_name(get(event.pkg)) == "optdeps2"
                @test event.optdep == LibALPM.Depend("optdeps1=0.1")
                optdep_rm_event = true
            end
        end
        LibALPM.set_eventcb(hdl, eventcb)

        pkg1, pkg2 = makepkg(joinpath(thisdir, "pkgs", "PKGBUILD.optdeps"),
                             pkgdir)
        repo_add(pkgdir, "alpmtest", [pkg1, pkg2])

        testdb = LibALPM.register_syncdb(hdl, "alpmtest",
                                         LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                         LibALPM.SigLevel.DATABASE_OPTIONAL)

        LibALPM.set_servers(testdb, ["file://$pkgdir"])
        @test !LibALPM.update(testdb, false)
        @test LibALPM.update(testdb, false)
        pkg_load1 = LibALPM.get_pkg(testdb, "optdeps1")
        pkg_load2 = LibALPM.get_pkg(testdb, "optdeps2")

        LibALPM.trans_init(hdl, 0)
        LibALPM.add_pkg(hdl, pkg_load1)
        LibALPM.add_pkg(hdl, pkg_load2)
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)

        @test !optdep_rm_event

        localdb = LibALPM.get_localdb(hdl)
        pkg_local = LibALPM.get_pkg(localdb, "optdeps1")
        LibALPM.trans_init(hdl, 0)
        LibALPM.remove_pkg(hdl, pkg_local)
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)
        @test optdep_rm_event

        LibALPM.release(hdl)
    end
end

@testset "Hooks" begin
    mktempdir() do dir
        hdl = setup_handle(dir)
        hook_event = false
        hookrun_event = false
        eventcb = (cbhdl, event)->begin
            @test cbhdl === hdl
            @test isa(event, LibALPM.AbstractEvent)
            isa(event, LibALPM.Event.Hook) && (hook_event = true)
            isa(event, LibALPM.Event.HookRun) && (hookrun_event = true)
        end
        LibALPM.set_eventcb(hdl, eventcb)
        localdb = LibALPM.get_localdb(hdl)
        coredb = LibALPM.register_syncdb(hdl, "core",
                                         LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                         LibALPM.SigLevel.DATABASE_OPTIONAL)
        mirrorurl = get_default_url("core")
        info("Mirror used: \"$mirrorurl\"")
        LibALPM.set_servers(coredb, [mirrorurl])
        extradb = LibALPM.register_syncdb(hdl, "extra",
                                          LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                          LibALPM.SigLevel.DATABASE_OPTIONAL)
        mirrorurl = get_default_url("extra")
        info("Mirror used: \"$mirrorurl\"")
        LibALPM.set_servers(extradb, [mirrorurl])

        LibALPM.update(coredb, false)
        LibALPM.update(extradb, false)

        mimepkg = LibALPM.get_pkg(extradb, "shared-mime-info")

        LibALPM.trans_init(hdl, 0)
        LibALPM.add_pkg(hdl, mimepkg)
        LibALPM.trans_prepare(hdl)
        LibALPM.trans_commit(hdl)
        LibALPM.trans_release(hdl)

        @test hook_event
        @test hookrun_event

        LibALPM.release(hdl)
    end
end

@testset "Callback Error" begin
    mktempdir() do dir
        hdl = setup_handle(dir)
        event_error = false
        log_error = false
        eventcb = (cbhdl, event)->begin
            event_error && return
            event_error = true
            error("This error is expected")
        end
        LibALPM.set_eventcb(hdl, eventcb)
        logcb = (cbhdl, level, msg)->begin
            log_error && return
            log_error = true
            error("This error is expected")
        end
        LibALPM.set_logcb(hdl, logcb)
        localdb = LibALPM.get_localdb(hdl)
        coredb = LibALPM.register_syncdb(hdl, "core",
                                         LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                         LibALPM.SigLevel.DATABASE_OPTIONAL)
        mirrorurl = get_default_url("core")
        info("Mirror used: \"$mirrorurl\"")
        LibALPM.set_servers(coredb, [mirrorurl])
        LibALPM.update(coredb, false)

        @test event_error
        @test log_error

        LibALPM.release(hdl)
    end
end
