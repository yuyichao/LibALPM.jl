#!/usr/bin/julia -f

type DB
    ptr::Ptr{Void}
    hdl::Handle
    function DB(ptr::Ptr{Void}, hdl::Handle)
        ptr == C_NULL && throw(UndefRefError())
        cached = hdl.dbs[ptr, DB]
        isnull(cached) || return get(cached)
        self = new(ptr, hdl)
        hdl.dbs[ptr] = self
        self
    end
end

function _null_all_pkgs(db::DB)
    # Must be called in a handle context
    db.ptr == C_NULL && return
    hdl = db.hdl
    for ptr in list_iter(ccall((:alpm_db_get_pkgcache, libalpm),
                               Ptr{list_t}, (Ptr{Void},), db))
        cached = hdl.pkgs[ptr, Pkg]
        isnull(cached) && continue
        free(get(cached))
    end
end

Base.cconvert(::Type{Ptr{Void}}, db::DB) = db
function Base.unsafe_convert(::Type{Ptr{Void}}, db::DB)
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
    with_handle(hdl) do
        _null_all_pkgs(db)
        db.ptr = C_NULL
        delete!(hdl.dbs, ptr)
        ret = ccall((:alpm_db_unregister, libalpm), Cint, (Ptr{Void},), ptr)
        ret == 0 || throw(Error(hdl, "unregister"))
    end
    nothing
end

"""
Get the name of a package database.
"""
function get_name(db::DB)
    # Should not trigger callback
    utf8(ccall((:alpm_db_get_name, libalpm), Ptr{UInt8}, (Ptr{Void},), db))
end

"""
Get the signature verification level for a database

Will return the default verification level if this database is set up
with ALPM_SIG_USE_DEFAULT.
"""
get_siglevel(db::DB) =
    # Should not trigger callback
    ccall((:alpm_db_get_siglevel, libalpm), UInt32, (Ptr{Void},), db)

"""
Check the validity of a database.

This is most useful for sync databases and verifying signature status.
If invalid, the handle error code will be set accordingly.
Return 0 if valid, -1 if invalid (errno is set accordingly)
"""
get_valid(db::DB) = with_handle(db.hdl) do
    ccall((:alpm_db_get_valid, libalpm), Cint, (Ptr{Void},), db)
end
function check_valid(db::DB)
    get_valid(db) == 0 || throw(Error(db.hdl, "check_valid"))
    nothing
end

# Accessors to the list of servers for a database.
function get_servers(db::DB)
    # Should not trigger callback
    servers = ccall((:alpm_db_get_servers, libalpm), Ptr{list_t},
                    (Ptr{Void},), db)
    list_to_array(UTF8String, servers, p->utf8(Ptr{UInt8}(p)))
end
function set_servers(db::DB, servers)
    # Should not trigger callback
    list = array_to_list(servers,
                         str->ccall(:strdup, Ptr{Void}, (Cstring,), str),
                         cglobal(:free))
    ret = ccall((:alpm_db_set_servers, libalpm), Cint,
                (Ptr{Void}, Ptr{list_t}), db, list)
    if ret != 0
        free(list, cglobal(:free))
        throw(Error(db.hdl, "set_servers"))
    end
end
add_server(db::DB, server) = with_handle(db.hdl) do
    ret = ccall((:alpm_db_add_server, libalpm), Cint,
                (Ptr{Void}, Cstring), db, server)
    ret == 0 || throw(Error(db.hdl, "add_server"))
    nothing
end
remove_server(db::DB, server) = with_handle(db.hdl) do
    ret = ccall((:alpm_db_remove_server, libalpm), Cint,
                (Ptr{Void}, Cstring), db, server)
    ret < 0 && throw(Error(db.hdl, "remove_server"))
    ret != 0
end

"Return true if db is already up to date."
update(db::DB, force) = with_handle(db.hdl) do
    ret = ccall((:alpm_db_update, libalpm), Cint, (Cint, Ptr{Void}), force, db)
    ret < 0 && throw(Error(db.hdl, "update"))
    ret != 0
end

"""
Get a package entry from a package database.

`name`: of the package
"""
get_pkg(db::DB, name) = with_handle(db.hdl) do
    pkg = ccall((:alpm_db_get_pkg, libalpm), Ptr{Void}, (Ptr{Void}, Cstring),
                db, name)
    hdl = db.hdl
    pkg == C_NULL && throw(Error(hdl, "get_pkg"))
    Pkg(pkg, hdl)
end

"Get the package cache of a package database"
get_pkgcache(db::DB) = with_handle(db.hdl) do
    pkgs = ccall((:alpm_db_get_pkgcache, libalpm), Ptr{list_t}, (Ptr{Void},), db)
    hdl = db.hdl
    list_to_array(Pkg, pkgs, p->Pkg(p, hdl))
end

# TODO
# /** Get a group entry from a package database.
#  * @param db pointer to the package database to get the group from
#  * @param name of the group
#  * @return the groups entry on success, NULL on error
#
# alpm_group_t *alpm_db_get_group(alpm_db_t *db, const char *name);

# /** Get the group cache of a package database.
#  * @param db pointer to the package database to get the group from
#  * @return the list of groups on success, NULL on error
#
# alpm_list_t *alpm_db_get_groupcache(alpm_db_t *db);

# /** Searches a database with regular expressions.
#  * @param db pointer to the package database to search in
#  * @param needles a list of regular expressions to search for
#  * @return the list of packages matching all regular expressions on success, NULL on error
#
# alpm_list_t *alpm_db_search(alpm_db_t *db, const alpm_list_t *needles);

# /** Sets the usage of a database.
#  * @param db pointer to the package database to set the status for
#  * @param usage a bitmask of alpm_db_usage_t values
#  * @return 0 on success, or -1 on error
#
# int alpm_db_set_usage(alpm_db_t *db, alpm_db_usage_t usage);

# /** Gets the usage of a database.
#  * @param db pointer to the package database to get the status of
#  * @param usage pointer to an alpm_db_usage_t to store db's status
#  * @return 0 on success, or -1 on error
#
# int alpm_db_get_usage(alpm_db_t *db, alpm_db_usage_t *usage);
