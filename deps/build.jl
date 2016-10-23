using BinDeps

@BinDeps.setup

library_dependency("libalpm", aliases=["libalpm"])

@BinDeps.install Dict(:libalpm => :libalpm)
