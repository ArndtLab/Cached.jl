using TestItems
using TestItemRunner
@run_package_tests verbose=true

  

@testitem "Test 1" begin
    @test 1 == 1
end
