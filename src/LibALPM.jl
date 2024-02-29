#!/usr/bin/julia -f

__precompile__(true)

module LibALPM

import LibArchive

@inline function finalizer(obj, func)
    Base.finalizer(func, obj)
end

const libalpm = "/usr/lib/libalpm.so"

include("utils.jl")
include("enums.jl")
include("list.jl")
include("ctypes.jl")
include("weakdict.jl")
include("handle.jl")
include("db.jl")
include("pkg.jl")
include("event.jl")
include("changelog.jl")

# TODO

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

# Question callback
# typedef void (*alpm_cb_question)(alpm_question_t *);

# Progress callback
# typedef void (*alpm_cb_progress)(void *ctx, alpm_progress_t progress, const char *pkg,
#               int percent, size_t howmany, size_t current);

#  * Downloading

# /** Type of download progress callbacks.
#  * @param ctx user-provided context
#  * @param filename the name of the file being downloaded
#  * @param event the event type
#  * @param data the event data of type alpm_download_event_*_t
#  */
# typedef void (*alpm_cb_download)(void *ctx, const char *filename,
# 		alpm_download_event_type_t event, void *data);

# typedef void (*alpm_cb_totaldl)(off_t total);

# /** A callback for downloading files
#  * @param ctx user-provided context
#  * @param url the URL of the file to be downloaded
#  * @param localpath the directory to which the file should be downloaded
#  * @param force whether to force an update, even if the file is the same
#  * @return 0 on success, 1 if the file exists and is identical, -1 on
#  * error.
#  */
# typedef int (*alpm_cb_fetch)(void *ctx, const char *url, const char *localpath,
# 		int force);

#  * Libalpm option getters and setters

# /** Returns the callback used to report download progress.
#  * @param handle the context handle
#  * @return the currently set download callback
# alpm_cb_download alpm_option_get_dlcb(alpm_handle_t *handle);

# /** Returns the callback used to report download progress.
#  * @param handle the context handle
#  * @return the currently set download callback context
# void *alpm_option_get_dlcb_ctx(alpm_handle_t *handle);

# /** Sets the callback used to report download progress.
#  * @param handle the context handle
#  * @param cb the cb to use
#  * @param ctx user-provided context to pass to cb
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
# int alpm_option_set_dlcb(alpm_handle_t *handle, alpm_cb_download cb, void *ctx);

# /** Returns the downloading callback.
#  * @param handle the context handle
#  * @return the currently set fetch callback
# alpm_cb_fetch alpm_option_get_fetchcb(alpm_handle_t *handle);

# /** Returns the downloading callback.
#  * @param handle the context handle
#  * @return the currently set fetch callback context
# void *alpm_option_get_fetchcb_ctx(alpm_handle_t *handle);

# /** Sets the downloading callback.
#  * @param handle the context handle
#  * @param cb the cb to use
#  * @param ctx user-provided context to pass to cb
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
# int alpm_option_set_fetchcb(alpm_handle_t *handle, alpm_cb_fetch cb, void *ctx);

# /** Returns the callback used for questions.
#  * @param handle the context handle
#  * @return the currently set question callback
# alpm_cb_question alpm_option_get_questioncb(alpm_handle_t *handle);

# /** Returns the callback used for questions.
#  * @param handle the context handle
#  * @return the currently set question callback context
# void *alpm_option_get_questioncb_ctx(alpm_handle_t *handle);

# /** Sets the callback used for questions.
#  * @param handle the context handle
#  * @param cb the cb to use
#  * @param ctx user-provided context to pass to cb
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
# int alpm_option_set_questioncb(alpm_handle_t *handle, alpm_cb_question cb, void *ctx);

# /**Returns the callback used for operation progress.
#  * @param handle the context handle
#  * @return the currently set progress callback
# alpm_cb_progress alpm_option_get_progresscb(alpm_handle_t *handle);

# /**Returns the callback used for operation progress.
#  * @param handle the context handle
#  * @return the currently set progress callback context
# void *alpm_option_get_progresscb_ctx(alpm_handle_t *handle);

# /** Sets the callback used for operation progress.
#  * @param handle the context handle
#  * @param cb the cb to use
#  * @param ctx user-provided context to pass to cb
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
# int alpm_option_set_progresscb(alpm_handle_t *handle, alpm_cb_progress cb, void *ctx);

end
