#!/usr/bin/julia -f

hdl = LibALPM.Handle("/", "/var/lib/pacman/")
str = sprint(io->show(io, hdl))
@test contains(str, "LibALPM.Handle(ptr=")

@test LibALPM.get_root(hdl) == "/"
@test LibALPM.get_dbpath(hdl) == "/var/lib/pacman/"
@test LibALPM.get_lockfile(hdl) == "/var/lib/pacman/db.lck"

@test LibALPM.get_cachedirs(hdl) == []
LibALPM.set_cachedirs(hdl, ["/var/cache/pacman/pkg/", "/tmp/"])
@test LibALPM.get_cachedirs(hdl) == ["/var/cache/pacman/pkg/", "/tmp/"]
LibALPM.add_cachedir(hdl, "/tmp/a")
@test LibALPM.get_cachedirs(hdl) == ["/var/cache/pacman/pkg/",
                                     "/tmp/", "/tmp/a/"]
@test LibALPM.remove_cachedir(hdl, "/tmp/")
@test LibALPM.get_cachedirs(hdl) == ["/var/cache/pacman/pkg/", "/tmp/a/"]
@test !LibALPM.remove_cachedir(hdl, "/tmp/")
@test LibALPM.get_cachedirs(hdl) == ["/var/cache/pacman/pkg/", "/tmp/a/"]

@test LibALPM.get_hookdirs(hdl) == ["/usr/share/libalpm/hooks/"]
LibALPM.set_hookdirs(hdl, ["/usr/share/libalpm/hooks/",
                           "/etc/pacman.d/hooks/"])
@test LibALPM.get_hookdirs(hdl) == ["/usr/share/libalpm/hooks/",
                                    "/etc/pacman.d/hooks/"]
LibALPM.add_hookdir(hdl, "/tmp")
@test LibALPM.get_hookdirs(hdl) == ["/usr/share/libalpm/hooks/",
                                    "/etc/pacman.d/hooks/", "/tmp/"]
@test LibALPM.remove_hookdir(hdl, "/tmp/")
@test LibALPM.get_hookdirs(hdl) == ["/usr/share/libalpm/hooks/",
                                    "/etc/pacman.d/hooks/"]
@test !LibALPM.remove_hookdir(hdl, "/tmp/")
@test LibALPM.get_hookdirs(hdl) == ["/usr/share/libalpm/hooks/",
                                    "/etc/pacman.d/hooks/"]

@test LibALPM.get_logfile(hdl) == ""
LibALPM.set_logfile(hdl, "/var/log/pacman.log")
@test LibALPM.get_logfile(hdl) == "/var/log/pacman.log"

@test LibALPM.get_gpgdir(hdl) == ""
LibALPM.set_gpgdir(hdl, "/etc/pacman.d/gnupg")
@test LibALPM.get_gpgdir(hdl) == "/etc/pacman.d/gnupg/"

@test !LibALPM.get_usesyslog(hdl)
LibALPM.set_usesyslog(hdl, true)
@test LibALPM.get_usesyslog(hdl)
LibALPM.set_usesyslog(hdl, false)
@test !LibALPM.get_usesyslog(hdl)

@test LibALPM.get_noupgrades(hdl) == []
LibALPM.set_noupgrades(hdl, ["linux", "!julia"])
@test LibALPM.get_noupgrades(hdl) == ["linux", "!julia"]
LibALPM.add_noupgrade(hdl, "glibc")
@test LibALPM.get_noupgrades(hdl) == ["linux", "!julia", "glibc"]
@test LibALPM.remove_noupgrade(hdl, "linux")
@test LibALPM.get_noupgrades(hdl) == ["!julia", "glibc"]
@test !LibALPM.remove_noupgrade(hdl, "linux")
@test LibALPM.get_noupgrades(hdl) == ["!julia", "glibc"]
@test LibALPM.match_noupgrade(hdl, "glibc") == 0
@test LibALPM.match_noupgrade(hdl, "linux") == -1
@test LibALPM.match_noupgrade(hdl, "julia") == 1

@test LibALPM.get_noextracts(hdl) == []
LibALPM.set_noextracts(hdl, ["linux", "!julia"])
@test LibALPM.get_noextracts(hdl) == ["linux", "!julia"]
LibALPM.add_noextract(hdl, "glibc")
@test LibALPM.get_noextracts(hdl) == ["linux", "!julia", "glibc"]
@test LibALPM.remove_noextract(hdl, "linux")
@test LibALPM.get_noextracts(hdl) == ["!julia", "glibc"]
@test !LibALPM.remove_noextract(hdl, "linux")
@test LibALPM.get_noextracts(hdl) == ["!julia", "glibc"]
@test LibALPM.match_noextract(hdl, "glibc") == 0
@test LibALPM.match_noextract(hdl, "linux") == -1
@test LibALPM.match_noextract(hdl, "julia") == 1

@test LibALPM.get_ignorepkgs(hdl) == []
LibALPM.set_ignorepkgs(hdl, ["linux", "julia"])
@test LibALPM.get_ignorepkgs(hdl) == ["linux", "julia"]
LibALPM.add_ignorepkg(hdl, "glibc")
@test LibALPM.get_ignorepkgs(hdl) == ["linux", "julia", "glibc"]
@test LibALPM.remove_ignorepkg(hdl, "linux")
@test LibALPM.get_ignorepkgs(hdl) == ["julia", "glibc"]
@test !LibALPM.remove_ignorepkg(hdl, "linux")
@test LibALPM.get_ignorepkgs(hdl) == ["julia", "glibc"]

@test LibALPM.get_ignoregroups(hdl) == []
LibALPM.set_ignoregroups(hdl, ["base", "base-devel"])
@test LibALPM.get_ignoregroups(hdl) == ["base", "base-devel"]
LibALPM.add_ignoregroup(hdl, "xorg")
@test LibALPM.get_ignoregroups(hdl) == ["base", "base-devel",
                                                  "xorg"]
@test LibALPM.remove_ignoregroup(hdl, "base")
@test LibALPM.get_ignoregroups(hdl) == ["base-devel", "xorg"]
@test !LibALPM.remove_ignoregroup(hdl, "base")
@test LibALPM.get_ignoregroups(hdl) == ["base-devel", "xorg"]

@test LibALPM.get_assumeinstalled(hdl) == []
LibALPM.set_assumeinstalled(hdl, ["linux=4.4", "glibc"])
@test LibALPM.get_assumeinstalled(hdl) == [LibALPM.Depend("linux=4.4"),
                                           LibALPM.Depend("glibc")]
LibALPM.add_assumeinstalled(hdl, "pacman=5.0")
@test LibALPM.get_assumeinstalled(hdl) == [LibALPM.Depend("linux=4.4"),
                                           LibALPM.Depend("glibc"),
                                           LibALPM.Depend("pacman=5.0")]
@test LibALPM.remove_assumeinstalled(hdl, "glibc")
@test LibALPM.get_assumeinstalled(hdl) == [LibALPM.Depend("linux=4.4"),
                                           LibALPM.Depend("pacman=5.0")]
@test !LibALPM.remove_assumeinstalled(hdl, "glibc")
@test LibALPM.get_assumeinstalled(hdl) == [LibALPM.Depend("linux=4.4"),
                                           LibALPM.Depend("pacman=5.0")]

@test LibALPM.get_architectures(hdl) == []
LibALPM.add_architecture(hdl, Sys.ARCH)
@test LibALPM.get_architectures(hdl) == [string(Sys.ARCH)]
LibALPM.set_architectures(hdl, ["x86_64", "aarch64"])
@test LibALPM.get_architectures(hdl) == ["x86_64", "aarch64"]
LibALPM.remove_architecture(hdl, "x86_64")
@test LibALPM.get_architectures(hdl) == ["aarch64"]
LibALPM.set_architectures(hdl, [Sys.ARCH])
@test LibALPM.get_architectures(hdl) == [string(Sys.ARCH)]

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
