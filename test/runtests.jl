#!/usr/bin/julia -f

using LibALPM
using Base.Test

const thisdir = dirname(@__FILE__)

for err in instances(LibALPM.errno_t)
    strerror(err)::UTF8String
end

@test isa(LibALPM.version(), VersionNumber)
@test LibALPM.capabilities() != 0

@test LibALPM.compute_md5sum(joinpath(thisdir, "test_file")) == "95f50f74390e8e4c60ac55b17d5d0e93"
@test LibALPM.compute_sha256sum(joinpath(thisdir, "test_file")) == "4e22afc956e83e884362343cb2e264f8fafe350768f321ea9d0f41ca7261975c"

hdl = LibALPM.Handle("/", "/var/lib/pacman/")
@test LibALPM.get_root(hdl) == "/"
@test LibALPM.get_dbpath(hdl) == "/var/lib/pacman/"
@test LibALPM.get_lockfile(hdl) == "/var/lib/pacman/db.lck"

@test LibALPM.get_cachedirs(hdl) == UTF8String[]
LibALPM.set_cachedirs(hdl, ["/var/cache/pacman/pkg/", "/tmp/"])
@test LibALPM.get_cachedirs(hdl) == UTF8String["/var/cache/pacman/pkg/",
                                               "/tmp/"]
LibALPM.add_cachedir(hdl, "/tmp/a")
@test LibALPM.get_cachedirs(hdl) == UTF8String["/var/cache/pacman/pkg/",
                                               "/tmp/", "/tmp/a/"]
@test LibALPM.remove_cachedir(hdl, "/tmp/")
@test LibALPM.get_cachedirs(hdl) == UTF8String["/var/cache/pacman/pkg/",
                                               "/tmp/a/"]
@test !LibALPM.remove_cachedir(hdl, "/tmp/")
@test LibALPM.get_cachedirs(hdl) == UTF8String["/var/cache/pacman/pkg/",
                                               "/tmp/a/"]

@test LibALPM.get_hookdirs(hdl) == UTF8String["/usr/share/libalpm/hooks/"]
LibALPM.set_hookdirs(hdl, ["/usr/share/libalpm/hooks/", "/etc/pacman.d/hooks/"])
@test LibALPM.get_hookdirs(hdl) == UTF8String["/usr/share/libalpm/hooks/",
                                              "/etc/pacman.d/hooks/"]
LibALPM.add_hookdir(hdl, "/tmp")
@test LibALPM.get_hookdirs(hdl) == UTF8String["/usr/share/libalpm/hooks/",
                                              "/etc/pacman.d/hooks/", "/tmp/"]
@test LibALPM.remove_hookdir(hdl, "/tmp/")
@test LibALPM.get_hookdirs(hdl) == UTF8String["/usr/share/libalpm/hooks/",
                                              "/etc/pacman.d/hooks/"]
@test !LibALPM.remove_hookdir(hdl, "/tmp/")
@test LibALPM.get_hookdirs(hdl) == UTF8String["/usr/share/libalpm/hooks/",
                                              "/etc/pacman.d/hooks/"]

@test_throws ArgumentError LibALPM.get_logfile(hdl)
LibALPM.set_logfile(hdl, "/var/log/pacman.log")
@test LibALPM.get_logfile(hdl) == "/var/log/pacman.log"

@test_throws ArgumentError LibALPM.get_gpgdir(hdl)
LibALPM.set_gpgdir(hdl, "/etc/pacman.d/gnupg")
@test LibALPM.get_gpgdir(hdl) == "/etc/pacman.d/gnupg/"

@test !LibALPM.get_usesyslog(hdl)
LibALPM.set_usesyslog(hdl, true)
@test LibALPM.get_usesyslog(hdl)
LibALPM.set_usesyslog(hdl, false)
@test !LibALPM.get_usesyslog(hdl)

LibALPM.unlock(hdl)
LibALPM.release(hdl)
