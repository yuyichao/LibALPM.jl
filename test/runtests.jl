#!/usr/bin/julia -f

using LibALPM

for err in instances(LibALPM.Error.errno_t)
    strerror(err)::UTF8String
end
