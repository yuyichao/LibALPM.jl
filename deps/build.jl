using BinDeps

@BinDeps.setup

libarchive = library_dependency("libalpm", aliases=["libalpm"])

@BinDeps.install Dict(:libalpm => :libalpm)
