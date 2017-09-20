#!/usr/bin/julia -f

__precompile__(true)

module LibALPM

import LibArchive

using Compat

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

# /** Returns the callback used for questions.
# alpm_cb_question alpm_option_get_questioncb(alpm_handle_t *handle);
# /** Sets the callback used for questions.
# int alpm_option_set_questioncb(alpm_handle_t *handle, alpm_cb_question cb);

# /** Returns the callback used for operation progress.
# alpm_cb_progress alpm_option_get_progresscb(alpm_handle_t *handle);
# /** Sets the callback used for operation progress.
# int alpm_option_set_progresscb(alpm_handle_t *handle, alpm_cb_progress cb);

end
