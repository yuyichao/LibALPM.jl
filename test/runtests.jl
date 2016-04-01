#!/usr/bin/julia -f

using LibALPM
using Base.Test

for err in instances(LibALPM.errno_t)
    strerror(err)::UTF8String
end

@test isa(LibALPM.version(), VersionNumber)
@test LibALPM.capabilities() != 0
