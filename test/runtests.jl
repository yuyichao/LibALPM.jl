#!/usr/bin/julia -f

using LibALPM
using Base.Test

const thisdir = dirname(@__FILE__)

include("lazycontext.jl")
include("list.jl")

@testset "Errno" begin
    for err in instances(LibALPM.errno_t)
        @test isa(strerror(err), UTF8String)
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
    @test isa(LibALPM.get_version(glibcpkg), UTF8String)
    @test LibALPM.get_origin(glibcpkg) == LibALPM.PkgFrom.LOCALDB
    # GNU C Library
    @test contains(LibALPM.get_desc(glibcpkg), "Library")
    @test contains(LibALPM.get_url(glibcpkg), "http")
    @test LibALPM.get_builddate(glibcpkg) > 0
    @test LibALPM.get_installdate(glibcpkg) > 0
    @test isa(LibALPM.get_packager(glibcpkg), UTF8String)
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
    # Not really sure what to expect yet...
    LibALPM.get_validation(glibcpkg)
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

@testset "Pkgroot" begin
    mktempdir() do dir
        dbpath = joinpath(dir, "var/lib/pacman/")
        cachepath = joinpath(dir, "var/cache/pacman/pkg/")
        mkpath(dbpath)
        mkpath(cachepath)
        hdl = LibALPM.Handle(dir, dbpath)
        LibALPM.set_cachedirs(hdl, [cachepath])
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

        LibALPM.trans_init(hdl, 0)
        glibcpkg_local = LibALPM.get_pkg(localdb, "glibc")
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
    end
end
