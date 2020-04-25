#!/usr/bin/julia -f

module Errno
import LibALPM: libalpm
@enum(errno_t,
      OK = 0,
      MEMORY,
      SYSTEM,
      BADPERMS,
      NOT_A_FILE,
      NOT_A_DIR,
      WRONG_ARGS,
      DISK_SPACE,
      # Interface
      HANDLE_NULL,
      HANDLE_NOT_NULL,
      HANDLE_LOCK,
      # Databases
      DB_OPEN,
      DB_CREATE,
      DB_NULL,
      DB_NOT_NULL,
      DB_NOT_FOUND,
      DB_INVALID,
      DB_INVALID_SIG,
      DB_VERSION,
      DB_WRITE,
      DB_REMOVE,
      # Servers
      SERVER_BAD_URL,
      SERVER_NONE,
      # Transactions
      TRANS_NOT_NULL,
      TRANS_NULL,
      TRANS_DUP_TARGET,
      TRANS_NOT_INITIALIZED,
      TRANS_NOT_PREPARED,
      TRANS_ABORT,
      TRANS_TYPE,
      TRANS_NOT_LOCKED,
      TRANS_HOOK_FAILED,
      # Packages
      PKG_NOT_FOUND,
      PKG_IGNORED,
      PKG_INVALID,
      PKG_INVALID_CHECKSUM,
      PKG_INVALID_SIG,
      PKG_MISSING_SIG,
      PKG_OPEN,
      PKG_CANT_REMOVE,
      PKG_INVALID_NAME,
      PKG_INVALID_ARCH,
      PKG_REPO_NOT_FOUND,
      # Signatures
      SIG_MISSING,
      SIG_INVALID,
      # Dependencies
      UNSATISFIED_DEPS,
      CONFLICTING_DEPS,
      FILE_CONFLICTS,
      # Misc
      RETRIEVE,
      INVALID_REGEX,
      # External library errors
      LIBARCHIVE,
      LIBCURL,
      EXTERNAL_DOWNLOAD,
      GPGME,
      # Missing compile-time features
      MISSING_CAPABILITY_SIGNATURES
      )
Libc.strerror(err::errno_t) =
    unsafe_string(ccall((:alpm_strerror, libalpm), Ptr{UInt8}, (Cint,), err))
end
import .Errno.errno_t
abstract type AbstractError <: Exception end
struct Error <: AbstractError
    errno::errno_t
    msg
end
Base.showerror(io::IO, err::Error) =
    print(io, "ALPM Error: $(err.msg) ($(Libc.strerror(err.errno)))")

"Package install reasons"
module PkgReason
@enum(pkgreason_t,
      # Explicitly requested by the user
      EXPLICIT=0,
      # Installed as a dependency for another package
      DEPEND=1)
end
import .PkgReason.pkgreason_t

"Location a package object was loaded from"
module PkgFrom
@enum(pkgfrom_t,
      FILE=1,
      LOCALDB,
      SYNCDB)
end
import .PkgFrom.pkgfrom_t

"Method used to validate a package"
module PkgValidation
const UNKNOWN = UInt32(0)
const NONE = UInt32(1) << 0
const MD5SUM = UInt32(1) << 1
const SHA256SUM = UInt32(1) << 2
const SIGNATURE = UInt32(1) << 3
end

"Types of version constraints in dependency specs"
module DepMod
@enum(depmod_t,
      # No version constraint
      ANY=1,
      # Test version equality (package=x.y.z)
      EQ,
      # Test for at least a version (package>=x.y.z)
      GE,
      # Test for at most a version (package<=x.y.z)
      LE,
      # Test for greater than some version (package>x.y.z)
      GT,
      # Test for less than some version (package<x.y.z)
      LT)
end
import .DepMod.depmod_t

"""
File conflict type.

Whether the conflict results from a file existing on the filesystem,
or with another target in the transaction.
"""
module FileConflictType
@enum(fileconflicttype_t,
      TARGET=1,
      FILESYSTEM)
end
import .FileConflictType.fileconflicttype_t

"PGP signature verification options"
module SigLevel
const PACKAGE = UInt32(1) << 0
const PACKAGE_OPTIONAL = UInt32(1) << 1
const PACKAGE_MARGINAL_OK = UInt32(1) << 2
const PACKAGE_UNKNOWN_OK = UInt32(1) << 3

const DATABASE = UInt32(1) << 10
const DATABASE_OPTIONAL = UInt32(1) << 11
const DATABASE_MARGINAL_OK = UInt32(1) << 12
const DATABASE_UNKNOWN_OK = UInt32(1) << 13

const USE_DEFAULT = (UInt32(1) << 30)
end

"PGP signature verification status return codes"
module SigStatus
@enum(sigstatus_t,
      VALID,
      KEY_EXPIRED,
      SIG_EXPIRED,
      KEY_UNKNOWN,
      KEY_DISABLED,
      INVALID)
end
import .SigStatus.sigstatus_t

"PGP signature verification status return codes"
module SigValidity
@enum(sigvalidity_t,
      FULL,
      MARGINAL,
      NEVER,
      UNKNOWN)
end
import .SigValidity.sigvalidity_t

module HookWhen
@enum(hook_when_t,
      PRE_TRANSACTION=1,
      POST_TRANSACTION)
end
import .HookWhen.hook_when_t

"Logging Levels"
module LogLevel
const ERROR = UInt32(1)
const WARNING = UInt32(1) << 1
const DEBUG = UInt32(1) << 2
const FUNCTION = UInt32(1) << 3
end

"Type of events"
module EventType
@enum(event_type_t,
      # Dependencies will be computed for a package.
      CHECKDEPS_START = 1,
      # Dependencies were computed for a package.
      CHECKDEPS_DONE,
      # File conflicts will be computed for a package.
      FILECONFLICTS_START,
      # File conflicts were computed for a package.
      FILECONFLICTS_DONE,
      # Dependencies will be resolved for target package.
      RESOLVEDEPS_START,
      # Dependencies were resolved for target package.
      RESOLVEDEPS_DONE,
      # Inter-conflicts will be checked for target package.
      INTERCONFLICTS_START,
      # Inter-conflicts were checked for target package.
      INTERCONFLICTS_DONE,
      # Processing the package transaction is starting.
      TRANSACTION_START,
      # Processing the package transaction is finished.
      TRANSACTION_DONE,
      # Package will be installed/upgraded/downgraded/re-installed/removed; See
      # alpm_event_package_operation_t for arguments.
      PACKAGE_OPERATION_START,
      # Package was installed/upgraded/downgraded/re-installed/removed; See
      # alpm_event_package_operation_t for arguments.
      PACKAGE_OPERATION_DONE,
      # Target package's integrity will be checked.
      INTEGRITY_START,
      # Target package's integrity was checked.
      INTEGRITY_DONE,
      # Target package will be loaded.
      LOAD_START,
      # Target package is finished loading.
      LOAD_DONE,
      # Scriptlet has printed information; See alpm_event_scriptlet_info_t for
      # arguments.
      SCRIPTLET_INFO,
      # Files will be downloaded from a repository.
      RETRIEVE_START,
      # Files were downloaded from a repository.
      RETRIEVE_DONE,
      # Not all files were successfully downloaded from a repository.
      RETRIEVE_FAILED,
      # A file will be downloaded from a repository; See alpm_event_pkgdownload_t
      # for arguments
      PKGDOWNLOAD_START,
      # A file was downloaded from a repository; See alpm_event_pkgdownload_t
      # for arguments
      PKGDOWNLOAD_DONE,
      # A file failed to be downloaded from a repository; See
      # alpm_event_pkgdownload_t for arguments
      PKGDOWNLOAD_FAILED,
      # Disk space usage will be computed for a package.
      DISKSPACE_START,
      # Disk space usage was computed for a package.
      DISKSPACE_DONE,
      # An optdepend for another package is being removed; See
      # alpm_event_optdep_removal_t for arguments.
      OPTDEP_REMOVAL,
      # A configured repository database is missing; See
      # alpm_event_database_missing_t for arguments.
      DATABASE_MISSING,
      # Checking keys used to create signatures are in keyring.
      KEYRING_START,
      # Keyring checking is finished.
      KEYRING_DONE,
      # Downloading missing keys into keyring.
      KEY_DOWNLOAD_START,
      # Key downloading is finished.
      KEY_DOWNLOAD_DONE,
      # A .pacnew file was created; See alpm_event_pacnew_created_t for arguments.
      PACNEW_CREATED,
      # A .pacsave file was created; See alpm_event_pacsave_created_t for
      # arguments
      PACSAVE_CREATED,
      # Processing hooks will be started.
      HOOK_START,
      # Processing hooks is finished.
      HOOK_DONE,
      # A hook is starting
      HOOK_RUN_START,
      # A hook has finished running
      HOOK_RUN_DONE)
end
import .EventType.event_type_t

module PackageOperation
@enum(package_operation_t,
      # Package (to be) installed. (No oldpkg)
      INSTALL=1,
      # Package (to be) upgraded
      UPGRADE,
      # Package (to be) re-installed
      REINSTALL,
      # Package (to be) downgraded
      DOWNGRADE,
      # Package (to be) removed. (No newpkg)
      REMOVE)
end
import .PackageOperation.package_operation_t

"""
Type of questions.

Unlike the events or progress enumerations, this enum has bitmask values
so a frontend can use a bitmask map to supply preselected answers to the
different types of questions.
"""
module QuestionType
const INSTALL_IGNOREPKG = UInt32(1) << 0
const REPLACE_PKG = UInt32(1) << 1
const CONFLICT_PKG = UInt32(1) << 2
const CORRUPTED_PKG = UInt32(1) << 3
const REMOVE_PKGS = UInt32(1) << 4
const SELECT_PROVIDER = UInt32(1) << 5
const IMPORT_KEY = UInt32(1) << 6
end

"Progress"
module Progress
@enum(progress_t,
      ADD_START,
      UPGRADE_START,
      DOWNGRADE_START,
      REINSTALL_START,
      REMOVE_START,
      CONFLICTS_START,
      DISKSPACE_START,
      INTEGRITY_START,
      LOAD_START,
      KEYRING_START)
end
import .Progress.progress_t

module DBUsage
const SYNC = UInt32(1)
const SEARCH = UInt32(1) << 1
const INSTALL = UInt32(1) << 2
const UPGRADE = UInt32(1) << 3
const ALL = UInt32(1) << 4 - 1
end

"Transaction flags"
module TransactionFlag
# Ignore dependency checks
const NODEPS = UInt32(1)
# Ignore file conflicts and overwrite files
const FORCE = UInt32(1) << 1
# Delete files even if they are tagged as backup
const NOSAVE = UInt32(1) << 2
# Ignore version numbers when checking dependencies
const NODEPVERSION = UInt32(1) << 3
# Remove also any packages depending on a package being removed
const CASCADE = UInt32(1) << 4
# Remove packages and their unneeded deps (not explicitly installed)
const RECURSE = UInt32(1) << 5
# Modify database but do not commit changes to the filesystem
const DBONLY = UInt32(1) << 6
# `UInt32(1) << 7` flag can go here
# Use PkgReason.DEPEND when installing packages
const ALLDEPS = UInt32(1) << 8
# Only download packages and do not actually install
const DOWNLOADONLY = UInt32(1) << 9
# Do not execute install scriptlets after installing
const NOSCRIPTLET = UInt32(1) << 10
# Ignore dependency conflicts
const NOCONFLICTS = UInt32(1) << 11
# UInt32(1) << 12 flag can go here
# Do not install a package if it is already installed and up to date
const NEEDED = UInt32(1) << 13
# Use PkgReason.EXPLICIT when installing packages
const ALLEXPLICIT = UInt32(1) << 14
# Do not remove a package if it is needed by another one
const UNNEEDED = UInt32(1) << 15
# Remove also explicitly installed unneeded deps
# (use with TransactionFlag.RECURSE)
const RECURSEALL = UInt32(1) << 16
# Do not lock the database during the operation
const NOLOCK = UInt32(1) << 17
end

module Capability
const NLS = UInt32(1) << 0
const DOWNLOADER = UInt32(1) << 1
const SIGNATURES = UInt32(1) << 2
end
