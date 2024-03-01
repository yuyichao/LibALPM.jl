#!/usr/bin/julia -f

function _null_all_pkgs(db::DB)
    db.ptr == C_NULL && return
    hdl = db.hdl
    for ptr in list_iter(ccall((:alpm_db_get_pkgcache, libalpm),
                               Ptr{list_t}, (Ptr{Cvoid},), db))
        cached = hdl.pkgs[ptr, Pkg]
        cached === nothing && continue
        free(cached)
    end
end

Base.cconvert(::Type{Ptr{Cvoid}}, db::DB) = db
function Base.unsafe_convert(::Type{Ptr{Cvoid}}, db::DB)
    ptr = db.ptr
    ptr == C_NULL && throw(UndefRefError())
    ptr
end

function Base.show(io::IO, db::DB)
    print(io, "LibALPM.DB(ptr=")
    show(io, UInt(db.ptr))
    print(io, ",name=")
    show(io, get_name(db))
    print(io, ")")
end

"Unregister a package database"
function unregister(db::DB)
    ptr = db.ptr
    ptr == C_NULL && throw(UndefRefError())
    hdl = db.hdl
    _null_all_pkgs(db)
    db.ptr = C_NULL
    delete!(hdl.dbs, ptr)
    ret = ccall((:alpm_db_unregister, libalpm), Cint, (Ptr{Cvoid},), ptr)
    ret == 0 || throw(Error(hdl, "unregister"))
    nothing
end

"""
Get the name of a package database.
"""
function get_name(db::DB)
    convert_cstring(ccall((:alpm_db_get_name, libalpm), Ptr{UInt8}, (Ptr{Cvoid},), db))
end

"""
Get the signature verification level for a database

Will return the default verification level if this database is set up
with ALPM_SIG_USE_DEFAULT.
"""
get_siglevel(db::DB) =
    ccall((:alpm_db_get_siglevel, libalpm), UInt32, (Ptr{Cvoid},), db)

"""
Check the validity of a database.

This is most useful for sync databases and verifying signature status.
If invalid, the handle error code will be set accordingly.
Return 0 if valid, -1 if invalid (errno is set accordingly)
"""
get_valid(db::DB) = ccall((:alpm_db_get_valid, libalpm), Cint, (Ptr{Cvoid},), db)
function check_valid(db::DB)
    get_valid(db) == 0 || throw(Error(db.hdl, "check_valid"))
    nothing
end

# Accessors to the list of servers for a database.
function get_servers(db::DB)
    servers = ccall((:alpm_db_get_servers, libalpm), Ptr{list_t},
                    (Ptr{Cvoid},), db)
    list_to_array(String, servers, convert_cstring)
end
function set_servers(db::DB, servers)
    list = array_to_list(servers,
                         str->ccall(:strdup, Ptr{Cvoid}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_db_set_servers, libalpm), Cint,
                (Ptr{Cvoid}, Ptr{list_t}), db, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(db.hdl, "set_servers"))
    end
end
function add_server(db::DB, server)
    ret = ccall((:alpm_db_add_server, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), db, server)
    ret == 0 || throw(Error(db.hdl, "add_server"))
    nothing
end
function remove_server(db::DB, server)
    ret = ccall((:alpm_db_remove_server, libalpm), Cint,
                (Ptr{Cvoid}, Cstring), db, server)
    ret < 0 && throw(Error(db.hdl, "remove_server"))
    ret != 0
end

"""
Update package databases.

An update of the package databases in the list `dbs` will be attempted.
Unless `force` is `true`, the update will only be performed if the remote
databases were modified since the last update.

This operation requires a database lock, and will return an applicable error
if the lock could not be obtained.

After a successful update, the `get_pkgcache()` package cache will be invalidated
`dbs`: list of package databases to update
`force`: if `true`, then forces the update, otherwise update only in case
         the databases aren't up to date.
Return true if db is already up to date.
"""
function update(dbs, force)
    hdl = Ref{Handle}()
    function db_convert(db)
        if isassigned(hdl)
            if hdl[] !== db.hdl
                throw(ArgumentError("Handle mismatch from multiple DBs"))
            end
        else
            hdl[] = db.hdl
        end
        return db.ptr
    end
    db_list = array_to_list(dbs, db_convert)
    if !isassigned(hdl)
        free(db_list)
        return true
    end
    # For now just assume this will keep the DBs alive,
    # which might not be the case for mutable iterators...
    GC.@preserve dbs begin
        ret = ccall((:alpm_db_update, libalpm), Cint,
                    (Ptr{Cvoid}, Ptr{list_t}, Cint), hdl[], db_list, force)
    end
    free(db_list)
    ret < 0 && throw(Error(hdl[], "update"))
    ret != 0
end
update(db::DB, force) = update([db], force)

"""
Get a package entry from a package database.

`name`: of the package
"""
function get_pkg(db::DB, name)
    pkg = ccall((:alpm_db_get_pkg, libalpm), Ptr{Cvoid}, (Ptr{Cvoid}, Cstring),
                db, name)
    hdl = db.hdl
    pkg == C_NULL && throw(Error(hdl, "get_pkg"))
    Pkg(pkg, hdl)
end

"Get the package cache of a package database"
function get_pkgcache(db::DB)
    pkgs = ccall((:alpm_db_get_pkgcache, libalpm), Ptr{list_t}, (Ptr{Cvoid},), db)
    hdl = db.hdl
    list_to_array(Pkg, pkgs, p->Pkg(p, hdl))
end

# TODO
# /** Get a group entry from a package database.
#  * Looking up a group is O(1) and will be significantly faster than
#  * iterating over the groupcahe.
#  * @param db pointer to the package database to get the group from
#  * @param name of the group
#  * @return the groups entry on success, NULL on error
# alpm_group_t *alpm_db_get_group(alpm_db_t *db, const char *name);

# /** Get the group cache of a package database.
#  * @param db pointer to the package database to get the group from
#  * @return the list of groups on success, NULL on error
# alpm_list_t *alpm_db_get_groupcache(alpm_db_t *db);

# /** Searches a database with regular expressions.
#  * @param db pointer to the package database to search in
#  * @param needles a list of regular expressions to search for
#  * @param ret pointer to list for storing packages matching all
#  * regular expressions - must point to an empty (NULL) alpm_list_t *.
#  * @return 0 on success, -1 on error (pm_errno is set accordingly)
# int alpm_db_search(alpm_db_t *db, const alpm_list_t *needles, alpm_list_t **ret);

# /** Sets the usage of a database.
#  * @param db pointer to the package database to set the status for
#  * @param usage a bitmask of alpm_db_usage_t values
#  * @return 0 on success, or -1 on error
# int alpm_db_set_usage(alpm_db_t *db, int usage);

# /** Gets the usage of a database.
#  * @param db pointer to the package database to get the status of
#  * @param usage pointer to an alpm_db_usage_t to store db's status
#  * @return 0 on success, or -1 on error
# int alpm_db_get_usage(alpm_db_t *db, int *usage);
