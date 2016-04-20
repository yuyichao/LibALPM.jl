#!/usr/bin/julia -f

@testset "Invalid Arch" begin
    mktempdir() do dir
        pkgbuild = joinpath(thisdir, "pkgs", "PKGBUILD.invalid-arch")
        pkgdir = joinpath(dir, "pkgdir")
        pkgpath = makepkg(pkgbuild, pkgdir, "invalid")[1]
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)
        pkg_load = LibALPM.load(hdl, pkgpath, true,
                                LibALPM.SigLevel.PACKAGE_OPTIONAL)

        LibALPM.trans_init(hdl, 0)
        LibALPM.add_pkg(hdl, pkg_load)
        try
            LibALPM.trans_prepare(hdl)
        catch ex
            @test isa(ex, LibALPM.TransPrepareError{UTF8String})
            @test ex.errno == LibALPM.Errno.PKG_INVALID_ARCH
            @test ex.list == ["invalid-arch-0.1-1-invalid"]
            str = sprint(io->Base.showerror(io, ex))
            @test contains(str, "with invalid archs:")
            @test contains(str, "invalid-arch-0.1-1-invalid")
        end
        LibALPM.trans_release(hdl)
        LibALPM.release(hdl)
    end
end

@testset "Missing Dep" begin
    mktempdir() do dir
        pkgbuild = joinpath(thisdir, "pkgs", "PKGBUILD.missing-dep")
        pkgdir = joinpath(dir, "pkgdir")
        pkgpath = makepkg(pkgbuild, pkgdir)[1]
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)
        pkg_load = LibALPM.load(hdl, pkgpath, true,
                                LibALPM.SigLevel.PACKAGE_OPTIONAL)

        LibALPM.trans_init(hdl, 0)
        LibALPM.add_pkg(hdl, pkg_load)
        try
            LibALPM.trans_prepare(hdl)
        catch ex
            @test isa(ex, LibALPM.TransPrepareError{LibALPM.DepMissing})
            @test ex.errno == LibALPM.Errno.UNSATISFIED_DEPS
            dep = LibALPM.Depend("does-not-exist: Just for fun")
            @test ex.list == [LibALPM.DepMissing("missing-dep", dep)]
            str = sprint(io->Base.showerror(io, ex))
            @test contains(str, "Missing dependencies:")
            @test contains(str, "does-not-exist: Just for fun")
        end
        LibALPM.trans_release(hdl)
        LibALPM.release(hdl)
    end
end

@testset "Conflicts" begin
    mktempdir() do dir
        pkgbuild = joinpath(thisdir, "pkgs", "PKGBUILD.conflict")
        pkgdir = joinpath(dir, "pkgdir")
        pkgpaths = makepkg(pkgbuild, pkgdir)
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)
        LibALPM.trans_init(hdl, 0)

        for path in pkgpaths
            pkg = LibALPM.load(hdl, path, true,
                               LibALPM.SigLevel.PACKAGE_OPTIONAL)
            LibALPM.add_pkg(hdl, pkg)
        end

        try
            LibALPM.trans_prepare(hdl)
        catch ex
            @test isa(ex, LibALPM.TransPrepareError{LibALPM.Conflict})
            @test ex.errno == LibALPM.Errno.CONFLICTING_DEPS
            str = sprint(io->Base.showerror(io, ex))
            @test contains(str, "Conflicts:")
            @test contains(str, "conflict1")
            @test contains(str, "conflict2")
        end
        LibALPM.trans_release(hdl)
        LibALPM.release(hdl)
    end
end

@testset "FileConflicts" begin
    mktempdir() do dir
        pkgbuild = joinpath(thisdir, "pkgs", "PKGBUILD.fileconflict")
        pkgdir = joinpath(dir, "pkgdir")
        pkgpaths = makepkg(pkgbuild, pkgdir)
        hdl = setup_handle(dir)
        LibALPM.set_arch(hdl, Base.ARCH)
        LibALPM.trans_init(hdl, 0)

        for path in pkgpaths
            pkg = LibALPM.load(hdl, path, true,
                               LibALPM.SigLevel.PACKAGE_OPTIONAL)
            LibALPM.add_pkg(hdl, pkg)
        end

        LibALPM.trans_prepare(hdl)
        try
            LibALPM.trans_commit(hdl)
        catch ex
            @test isa(ex, LibALPM.TransCommitError{LibALPM.FileConflict})
            @test ex.errno == LibALPM.Errno.FILE_CONFLICTS
            str = sprint(io->Base.showerror(io, ex))
            @test contains(str, "File conflicts:")
            @test contains(str, "fileconflict1")
            @test contains(str, "fileconflict2")
            @test contains(str, "/fileconflict")
        end
        LibALPM.trans_release(hdl)
        LibALPM.release(hdl)
    end
end
