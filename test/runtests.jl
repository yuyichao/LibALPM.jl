#!/usr/bin/julia -f

using LibALPM

for err in instances(LibALPM.errno_t)
    strerror(err)::UTF8String
end
