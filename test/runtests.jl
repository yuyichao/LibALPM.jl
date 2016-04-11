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
