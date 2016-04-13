#!/usr/bin/julia -f

module TestLazyContext

using Base.Test
using LibALPM

# Not a public API
@testset "LazyContext" begin
    # Basic stuff
    ctx = LibALPM.LazyTaskContext{Vector{Int}}()
    @test_throws KeyError LibALPM.get_task_context(ctx)
    LibALPM.with_task_context(ctx, Int[123]) do
        @test LibALPM.get_task_context(ctx) == Int[123]
        @test_throws(ArgumentError,
                     LibALPM.with_task_context(()->nothing, ctx, Int[1]))
        @test LibALPM.get_task_context(ctx) == Int[123]
    end
    @test_throws ErrorException LibALPM.with_task_context(ctx, Int[123]) do
        error()
    end
    @test_throws KeyError LibALPM.get_task_context(ctx)

    # Now some fun (that I'm not sure if anyone would actually use...)
    @sync begin
        run_task = id->begin
            LibALPM.with_task_context(ctx, Int[id]) do
                for i in 1:100
                    @test LibALPM.get_task_context(ctx) == Int[id]
                    @test_throws(ArgumentError,
                                 LibALPM.with_task_context(()->nothing,
                                                           ctx, Int[-1]))
                    @test LibALPM.get_task_context(ctx) == Int[id]
                    rand() > 0.5 && yield()
                end
            end
        end
        for i in 1:10
            @async run_task(i)
        end
    end
end

end
