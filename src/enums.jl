#!/usr/bin/julia -f

module Error
import LibALPM.libalpm
@enum(errno_t,
      MEMORY = 1,
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
      # Deltas
      DLT_INVALID,
      DLT_PATCHFAILED,
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
      GPGME)
Base.strerror(err::errno_t) =
    utf8(ccall((:alpm_strerror, libalpm), Ptr{UInt8}, (Cint,), err))
end
