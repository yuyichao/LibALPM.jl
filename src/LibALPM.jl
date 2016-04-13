#!/usr/bin/julia -f

module LibALPM

const depfile = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if isfile(depfile)
    include(depfile)
else
    error("LibALPM not properly installed. Please run Pkg.build(\"LibALPM\")")
end

include("utils.jl")
include("enums.jl")
include("ctypes.jl")
include("list.jl")
include("weakdict.jl")
include("handle.jl")
include("db.jl")
include("pkg.jl")

# TODO

# /** Open a package changelog for reading.
#  * Similar to fopen in functionality, except that the returned 'file
#  * stream' could really be from an archive as well as from the database.
#  * @param pkg the package to read the changelog of (either file or db)
#  * @return a 'file stream' to the package changelog
#
# void *alpm_pkg_changelog_open(alpm_pkg_t *pkg);

# /** Read data from an open changelog 'file stream'.
#  * Similar to fread in functionality, this function takes a buffer and
#  * amount of data to read. If an error occurs pm_errno will be set.
#  * @param ptr a buffer to fill with raw changelog data
#  * @param size the size of the buffer
#  * @param pkg the package that the changelog is being read from
#  * @param fp a 'file stream' to the package changelog
#  * @return the number of characters read, or 0 if there is no more data or an
#  * error occurred.
#
# size_t alpm_pkg_changelog_read(void *ptr, size_t size,
# const alpm_pkg_t *pkg, void *fp);

# int alpm_pkg_changelog_close(const alpm_pkg_t *pkg, void *fp);

# /** Open a package mtree file for reading.
#  * @param pkg the local package to read the changelog of
#  * @return a archive structure for the package mtree file
#
# struct archive *alpm_pkg_mtree_open(alpm_pkg_t *pkg);

# /** Read next entry from a package mtree file.
#  * @param pkg the package that the mtree file is being read from
#  * @param archive the archive structure reading from the mtree file
#  * @param entry an archive_entry to store the entry header information
#  * @return 0 if end of archive is reached, non-zero otherwise.
#
# int alpm_pkg_mtree_next(const alpm_pkg_t *pkg, struct archive *archive,
# struct archive_entry **entry);

# int alpm_pkg_mtree_close(const alpm_pkg_t *pkg, struct archive *archive);

# /*
#  * Signatures
#

# int alpm_pkg_check_pgp_signature(alpm_pkg_t *pkg, alpm_siglist_t *siglist);

# int alpm_db_check_pgp_signature(alpm_db_t *db, alpm_siglist_t *siglist);

# int alpm_siglist_cleanup(alpm_siglist_t *siglist);

# int alpm_decode_signature(const char *base64_data,
# unsigned char **data, size_t *data_len);

# int alpm_extract_keyid(alpm_handle_t *handle, const char *identifier,
# const unsigned char *sig, const size_t len, alpm_list_t **keys);


# typedef void (*alpm_cb_log)(alpm_loglevel_t, const char *, va_list);

# int alpm_logaction(alpm_handle_t *handle, const char *prefix,
# const char *fmt, ...) __attribute__((format(printf, 3, 4)));

# Event callback.
# typedef void (*alpm_cb_event)(alpm_event_t *);

# Question callback
# typedef void (*alpm_cb_question)(alpm_question_t *);

# Progress callback
# typedef void (*alpm_cb_progress)(alpm_progress_t, const char *, int, size_t, size_t);

#  * Downloading

# /** Type of download progress callbacks.
#  * @param filename the name of the file being downloaded
#  * @param xfered the number of transferred bytes
#  * @param total the total number of bytes to transfer
#
# typedef void (*alpm_cb_download)(const char *filename,
# off_t xfered, off_t total);

# typedef void (*alpm_cb_totaldl)(off_t total);

# /** A callback for downloading files
#  * @param url the URL of the file to be downloaded
#  * @param localpath the directory to which the file should be downloaded
#  * @param force whether to force an update, even if the file is the same
#  * @return 0 on success, 1 if the file exists and is identical, -1 on
#  * error.
#
# typedef int (*alpm_cb_fetch)(const char *url, const char *localpath,
# int force);

#  * Libalpm option getters and setters

# /** Returns the callback used for logging.
# alpm_cb_log alpm_option_get_logcb(alpm_handle_t *handle);
# /** Sets the callback used for logging.
# int alpm_option_set_logcb(alpm_handle_t *handle, alpm_cb_log cb);

# /** Returns the callback used to report download progress.
# alpm_cb_download alpm_option_get_dlcb(alpm_handle_t *handle);
# /** Sets the callback used to report download progress.
# int alpm_option_set_dlcb(alpm_handle_t *handle, alpm_cb_download cb);

# /** Returns the downloading callback.
# alpm_cb_fetch alpm_option_get_fetchcb(alpm_handle_t *handle);
# /** Sets the downloading callback.
# int alpm_option_set_fetchcb(alpm_handle_t *handle, alpm_cb_fetch cb);

# /** Returns the callback used to report total download size.
# alpm_cb_totaldl alpm_option_get_totaldlcb(alpm_handle_t *handle);
# /** Sets the callback used to report total download size.
# int alpm_option_set_totaldlcb(alpm_handle_t *handle, alpm_cb_totaldl cb);

# /** Returns the callback used for events.
# alpm_cb_event alpm_option_get_eventcb(alpm_handle_t *handle);
# /** Sets the callback used for events.
# int alpm_option_set_eventcb(alpm_handle_t *handle, alpm_cb_event cb);

# /** Returns the callback used for questions.
# alpm_cb_question alpm_option_get_questioncb(alpm_handle_t *handle);
# /** Sets the callback used for questions.
# int alpm_option_set_questioncb(alpm_handle_t *handle, alpm_cb_question cb);

# /** Returns the callback used for operation progress.
# alpm_cb_progress alpm_option_get_progresscb(alpm_handle_t *handle);
# /** Sets the callback used for operation progress.
# int alpm_option_set_progresscb(alpm_handle_t *handle, alpm_cb_progress cb);

end
