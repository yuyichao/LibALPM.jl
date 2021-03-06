#!/usr/bin/julia -f

module TestList

using Test
using LibALPM

# Not a public API
@testset "List" begin
    @test_throws(ErrorException,
                 LibALPM.array_to_list(["1", "3", "44"],
                                       s->(length(s) == 1 || error(1);
                                           ccall(:strdup, Ptr{Cvoid},
                                                 (Cstring,), s)),
                                       cglobal(:free)))
    list = LibALPM.array_to_list(["1", "3", "44"],
                                 s->ccall(:strdup, Ptr{Cvoid}, (Cstring,), s),
                                 cglobal(:free))
    ary = LibALPM.list_to_array(String, list, LibALPM.take_cstring)
    LibALPM.free(list)
    @test ary == ["1", "3", "44"]

    list = LibALPM.array_to_list(["1", "44", "3"],
                                 s->ccall(:strdup, Ptr{Cvoid}, (Cstring,), s),
                                 cglobal(:free))
    @test_throws(ErrorException,
                 LibALPM.list_to_array(String, list,
                                       p->(s = unsafe_string(Ptr{UInt8}(p));
                                           length(s) > 1 && error();
                                           ccall(:free, Cvoid, (Ptr{Cvoid},), p);
                                           s), cglobal(:free)))
end

end
