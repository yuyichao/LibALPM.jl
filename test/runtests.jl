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

@test LibALPM.get_noupgrades(hdl) == UTF8String[]
LibALPM.set_noupgrades(hdl, ["linux", "!julia"])
@test LibALPM.get_noupgrades(hdl) == UTF8String["linux", "!julia"]
LibALPM.add_noupgrade(hdl, "glibc")
@test LibALPM.get_noupgrades(hdl) == UTF8String["linux", "!julia", "glibc"]
@test LibALPM.remove_noupgrade(hdl, "linux")
@test LibALPM.get_noupgrades(hdl) == UTF8String["!julia", "glibc"]
@test !LibALPM.remove_noupgrade(hdl, "linux")
@test LibALPM.get_noupgrades(hdl) == UTF8String["!julia", "glibc"]
@test LibALPM.match_noupgrade(hdl, "glibc") == 0
@test LibALPM.match_noupgrade(hdl, "linux") == -1
@test LibALPM.match_noupgrade(hdl, "julia") == 1

@test LibALPM.get_noextracts(hdl) == UTF8String[]
LibALPM.set_noextracts(hdl, ["linux", "!julia"])
@test LibALPM.get_noextracts(hdl) == UTF8String["linux", "!julia"]
LibALPM.add_noextract(hdl, "glibc")
@test LibALPM.get_noextracts(hdl) == UTF8String["linux", "!julia", "glibc"]
@test LibALPM.remove_noextract(hdl, "linux")
@test LibALPM.get_noextracts(hdl) == UTF8String["!julia", "glibc"]
@test !LibALPM.remove_noextract(hdl, "linux")
@test LibALPM.get_noextracts(hdl) == UTF8String["!julia", "glibc"]
@test LibALPM.match_noextract(hdl, "glibc") == 0
@test LibALPM.match_noextract(hdl, "linux") == -1
@test LibALPM.match_noextract(hdl, "julia") == 1

@test LibALPM.get_ignorepkgs(hdl) == UTF8String[]
LibALPM.set_ignorepkgs(hdl, ["linux", "julia"])
@test LibALPM.get_ignorepkgs(hdl) == UTF8String["linux", "julia"]
LibALPM.add_ignorepkg(hdl, "glibc")
@test LibALPM.get_ignorepkgs(hdl) == UTF8String["linux", "julia", "glibc"]
@test LibALPM.remove_ignorepkg(hdl, "linux")
@test LibALPM.get_ignorepkgs(hdl) == UTF8String["julia", "glibc"]
@test !LibALPM.remove_ignorepkg(hdl, "linux")
@test LibALPM.get_ignorepkgs(hdl) == UTF8String["julia", "glibc"]

@test LibALPM.get_ignoregroups(hdl) == UTF8String[]
LibALPM.set_ignoregroups(hdl, ["base", "base-devel"])
@test LibALPM.get_ignoregroups(hdl) == UTF8String["base", "base-devel"]
LibALPM.add_ignoregroup(hdl, "xorg")
@test LibALPM.get_ignoregroups(hdl) == UTF8String["base", "base-devel", "xorg"]
@test LibALPM.remove_ignoregroup(hdl, "base")
@test LibALPM.get_ignoregroups(hdl) == UTF8String["base-devel", "xorg"]
@test !LibALPM.remove_ignoregroup(hdl, "base")
@test LibALPM.get_ignoregroups(hdl) == UTF8String["base-devel", "xorg"]

@test_throws ArgumentError LibALPM.get_arch(hdl)
LibALPM.set_arch(hdl, Base.ARCH)
@test LibALPM.get_arch(hdl) == string(Base.ARCH)

@test LibALPM.get_deltaratio(hdl) == 0
LibALPM.set_deltaratio(hdl, 0.7)
@test LibALPM.get_deltaratio(hdl) == 0.7

@test !LibALPM.get_checkspace(hdl)
LibALPM.set_checkspace(hdl, true)
@test LibALPM.get_checkspace(hdl)

@test LibALPM.get_dbext(hdl) == ".db"
LibALPM.set_dbext(hdl, ".db2")
@test LibALPM.get_dbext(hdl) == ".db2"
LibALPM.set_dbext(hdl, ".db")
@test LibALPM.get_dbext(hdl) == ".db"

@test LibALPM.get_default_siglevel(hdl) == 0
LibALPM.set_default_siglevel(hdl, LibALPM.SigLevel.PACKAGE_OPTIONAL |
                             LibALPM.SigLevel.DATABASE)
@test LibALPM.get_default_siglevel(hdl) == (LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                            LibALPM.SigLevel.DATABASE)

@test LibALPM.get_local_file_siglevel(hdl) == 0
LibALPM.set_local_file_siglevel(hdl, LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                LibALPM.SigLevel.DATABASE)
@test (LibALPM.get_local_file_siglevel(hdl) ==
       LibALPM.SigLevel.PACKAGE_OPTIONAL | LibALPM.SigLevel.DATABASE)

@test LibALPM.get_remote_file_siglevel(hdl) == 0
LibALPM.set_remote_file_siglevel(hdl, LibALPM.SigLevel.PACKAGE_OPTIONAL |
                                 LibALPM.SigLevel.DATABASE)
@test (LibALPM.get_remote_file_siglevel(hdl) ==
       LibALPM.SigLevel.PACKAGE_OPTIONAL | LibALPM.SigLevel.DATABASE)

localdb = LibALPM.get_localdb(hdl)
@test LibALPM.get_name(localdb) == "local"
syncdbs = LibALPM.get_syncdbs(hdl)

LibALPM.unlock(hdl)
LibALPM.release(hdl)
