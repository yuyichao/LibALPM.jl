#!/usr/bin/julia -f

module TestList

using Base.Test
using LibALPM

# Not a public API
@testset "List" begin
    @test_throws(ErrorException,
                 LibALPM.array_to_list(["1", "3", "44"],
                                       s->(length(s) == 1 || error(1);
                                           ccall(:strdup, Ptr{Void},
                                                 (Cstring,), s)),
                                       cglobal(:free)))
    list = LibALPM.array_to_list(["1", "3", "44"],
                                 s->ccall(:strdup, Ptr{Void}, (Cstring,), s),
                                 cglobal(:free))
    ary = LibALPM.list_to_array(UTF8String, list, LibALPM.ptr_to_utf8)
    LibALPM.free(list)
    @test ary == ["1", "3", "44"]

    list = LibALPM.array_to_list(["1", "3", "44"],
                                 s->ccall(:strdup, Ptr{Void}, (Cstring,), s),
                                 cglobal(:free))
    @test_throws(ErrorException,
                 LibALPM.list_to_array(UTF8String, list,
                                       p->(s = LibALPM.ptr_to_utf8(p);
                                           length(s) > 1 && error();
                                           s), cglobal(:free)))
end

end
