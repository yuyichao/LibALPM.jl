#!/usr/bin/julia -f

using LibALPM
using Base.Test

const thisdir = dirname(@__FILE__)

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

    glibcpkg = LibALPM.get_pkg(coredb, "glibc")
    # this might assume the package file is available, let's see...
    @test !isempty(LibALPM.get_filename(glibcpkg))
    @test !isempty(LibALPM.get_md5sum(glibcpkg))
    @test !isempty(LibALPM.get_sha256sum(glibcpkg))
    @test LibALPM.get_size(glibcpkg) > 0
    @test LibALPM.get_db(glibcpkg) === coredb
    @test !isempty(LibALPM.get_base64_sig(glibcpkg))
    @test LibALPM.download_size(glibcpkg) > 0
    # Not sure what to expect ...
    LibALPM.get_deltas(glibcpkg)
    LibALPM.unused_deltas(glibcpkg)

    LibALPM.unregister(coredb)
    @test coredb.ptr == C_NULL

    LibALPM.release(hdl)
end

@testset "Pkgroot" begin
    mktempdir() do dir
        dbpath = joinpath(dir, "var/lib/pacman/")
        mkpath(dbpath)
        hdl = LibALPM.Handle(dir, dbpath)
        coredb = LibALPM.register_syncdb(hdl, "core",
                                         LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                         LibALPM.SigLevel.DATABASE_OPTIONAL)

        @test LibALPM.get_servers(coredb) == []
        mirrorurl = "http://mirrors.kernel.org/archlinux/core/os/$(Base.ARCH)"
        LibALPM.set_servers(coredb, [mirrorurl])
        @test !LibALPM.update(coredb, false)
        # This can fail if the remote is updated right in between the two calls
        @test LibALPM.update(coredb, false)
    end
end
