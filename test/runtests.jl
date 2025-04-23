using TestItems
using TestItemRunner
@run_package_tests verbose=true





@testitem "DictCache" begin
    objs = [true, false, 2, 3.0, π, (1,2), (3.1415, π), [1,2,3], [π, 3.1415], 
			Dict(1=>2, 3=>4), Dict(π=>3.1415, 3.1415=>π), 
			"hello", "world", "π", "πππ"]


	c = DictCache()
	@test length(c) == 0

	for obj in objs
		c[hash(obj)] = obj
	end
	
	@test length(c) == length(objs)
	for obj in objs
		@test c[hash(obj)] == obj
	end
	println(summary(c))
end
		


@testitem "SqliteCache" begin
    objs = [true, false, 2, 3.0, π, (1,2), (3.1415, π), [1,2,3], [π, 3.1415], 
			Dict(1=>2, 3=>4), Dict(π=>3.1415, 3.1415=>π), 
			"hello", "world", "π", "πππ"]

	mktempdir() do d
		p = joinpath(d, "a1.sqlite")
		c = Cached.SQLiteCache(p)
		@test isfile(p)
		@test isempty(c.loaded)
		@test length(c) == 0
		@test length(c.loaded) == 0

		for obj in objs
			c[hash(obj)] = obj
		end
		for obj in objs
			c[hash(obj)] = obj
		end

		
		@test length(c) == length(objs)
		@test length(c.loaded) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end

		c = Cached.SQLiteCache(p)
		@test length(c) == length(objs)
		@test length(c.loaded) == 0
		for obj in objs
			@test c[hash(obj)] == obj
		end
		println(summary(c))

		c = Cached.SQLiteCache(p)
		@test length(c) == length(objs)
		@test length(c.loaded) == 0
        Cached.loadall!(c)
        @test length(c.loaded) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end


		# cd = Cached.DictCache(c)
		# @test length(cd) == length(objs)
		# @test all(cd[hash(obj)] == obj for obj in objs)
	end
end


@testitem "SqliteCache Droping" begin
    objs = [true, false, 2, 3.0, π, (1,2), (3.1415, π), [1,2,3], [π, 3.1415], 
			Dict(1=>2, 3=>4), Dict(π=>3.1415, 3.1415=>π), 
			"hello", "world", "π", "πππ"]

	mktempdir() do d
		p = joinpath(d, "a1.sqlite")
		c = Cached.SQLiteCache(p)

		for obj in objs
			c[hash(obj)] = obj
		end

		@test length(c) == length(objs)
		Cached.close!(c)


		c = Cached.SQLiteCache(p)
		@test length(c) == length(objs)
		@test length(c.loaded) == 0

		n = 4
		for obj in objs[1:n]
			@test c[hash(obj)] == obj
		end
		@test length(c.loaded) == n
		@test length(c) == length(objs)

		Cached.drop_unused!(c)

		@test length(c.loaded) == n
		@test length(c) == n
		for obj in objs[n+1:end]
			@test haskey(c, hash(obj)) == false
		end

	end

end



@testitem "FileCache" begin

    objs = [true, false, 2, 3.0, π, (1,2), (3.1415, π), [1,2,3], [π, 3.1415], 
            Dict(1=>2, 3=>4), Dict(π=>3.1415, 3.1415=>π), 
            "hello", "world", "π", "πππ"]

	mktempdir() do d
		p = joinpath(d, "a1.fcache")
		c = FileCache(p)
		@test isdir(p)
		@test isempty(c.loaded)
		@test length(c) == 0
		@test length(c.loaded) == 0

		for obj in objs
			c[hash(obj)] = obj
		end
		for obj in objs
			c[hash(obj)] = obj
		end
		
		@test length(c) == length(objs)
		@test length(c.loaded) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end

		c = FileCache(p)
		@test length(c) == length(objs)
		@test length(c.loaded) == 0
		for obj in objs
			@test c[hash(obj)] == obj
		end
		println(summary(c))
	end
end




@testitem "FileCache II" begin

    objs = [true, false, 2, 3.0, π, (1,2), (3.1415, π), [1,2,3], [π, 3.1415], 
            Dict(1=>2, 3=>4), Dict(π=>3.1415, 3.1415=>π), 
            "hello", "world", "π", "πππ"]
	
	mktempdir() do d

		c = Cached.FileCache(joinpath(d, "a1"))
		@test isdir(c.dir)
		@test isempty(c.loaded)
		@test isfile(joinpath(c.dir, ".gitignore"))
		
		@show c

		c[UInt(1)] = "hello"
		c[UInt(3)] = 45
		@show c

		@test isdir(c.dir)
		@test isdir(joinpath(c.dir, "00"))
		@test isfile(joinpath(c.dir, "00", "0000000000000001"))
		@test isfile(joinpath(c.dir, "00", "0000000000000003"))
		@test length(c.loaded) == 2
		@test length(c) == 2

		@test c[UInt(1)] == "hello"
		@test c[UInt(3)] == 45

		d = Cached.FileCache(joinpath(d, "a1"))
		@test length(d.loaded) == 0
		@test length(d) == 2

		@test d[UInt(1)] == "hello"
		@test d[UInt(3)] == 45
		@test length(d.loaded) == 2
		@test length(d) == 2

	end
end




@testitem "setindicies" begin

    objs = [true, false, 2, 3.0, π, (1,2), (3.1415, π), [1,2,3], [π, 3.1415], 
            Dict(1=>2, 3=>4), Dict(π=>3.1415, 3.1415=>π), 
            "hello", "world", "π", "πππ"]

	mktempdir() do d
		c = Cached.DictCache()
		Cached.setindices!(c, hash.(objs), objs)
		@test length(c) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end

		c = Cached.SQLiteCache(joinpath(d, "a.sqlite"))
		Cached.setindices!(c, hash.(objs), objs)
		@test length(c) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end

		c = Cached.FileCache(joinpath(d, "a1"))
		Cached.setindices!(c, hash.(objs), objs)
		@test length(c) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end
	end
end


@testitem "setindicies from channel" begin

    objs = [true, false, 2, 3.0, π, (1,2), (3.1415, π), [1,2,3], [π, 3.1415], 
            Dict(1=>2, 3=>4), Dict(π=>3.1415, 3.1415=>π), 
            "hello", "world", "π", "πππ"]

	mktempdir() do d
		c = Cached.DictCache()
		ch = Channel(length(objs))
		for obj in objs
			put!(ch, (hash(obj), obj))
		end
		Cached.setindices!(c, ch)

		@test length(c) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end

		c = Cached.SQLiteCache(joinpath(d, "a.sqlite"))
		ch = Channel(length(objs))
		for obj in objs
			put!(ch, (hash(obj), obj))
		end
		Cached.setindices!(c, ch)
		@test length(c) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end

		c = Cached.FileCache(joinpath(d, "a1"))
		ch = Channel(length(objs))
		for obj in objs
			put!(ch, (hash(obj), obj))
		end
		Cached.setindices!(c, ch)
		@test length(c) == length(objs)
		for obj in objs
			@test c[hash(obj)] == obj
		end
	end
end





@testitem "cmap" begin

	c = Cached.DictCache()
	k = 0
	f(i) = (getpid(), gethostname(), i, global k+=1)
	r = Cached.cmap(f, c, 1:10)
	@test length(r) == 10
	@test length(unique(getindex.(r, 1))) == 1
	@test length(unique(getindex.(r, 2))) == 1
	@test length(unique(getindex.(r, 3))) == 10
	@test length(unique(getindex.(r, 4))) == 10
	@test getindex.(r, 3) == collect(1:10)
	@test getindex.(r, 4) == collect(1:10)
	@test k == 10

	r = Cached.cmap(f, c, 1:10)
	@test length(r) == 10
	@test length(unique(getindex.(r, 1))) == 1
	@test length(unique(getindex.(r, 2))) == 1
	@test length(unique(getindex.(r, 3))) == 10
	@test length(unique(getindex.(r, 4))) == 10
	@test getindex.(r, 3) == collect(1:10)
	@test getindex.(r, 4) == collect(1:10)
	@test k == 10

	r = map(f, 1:10)
	@test length(r) == 10
	@test length(unique(getindex.(r, 1))) == 1
	@test length(unique(getindex.(r, 2))) == 1
	@test length(unique(getindex.(r, 3))) == 10
	@test length(unique(getindex.(r, 4))) == 10
	@test getindex.(r, 3) == collect(1:10)
	@test getindex.(r, 4) == collect(11:20)
	@test k == 20
end

@testitem "cmap with multi argument" begin
	c = Cached.DictCache()

	f2(x, y) = (getpid(), gethostname(), x, y)
	r = Cached.cmap(f2, c, 1:10, 11:20)
	@test length(r) == 10
	@test length(unique(getindex.(r, 1))) == 1
	@test length(unique(getindex.(r, 2))) == 1
	@test length(unique(getindex.(r, 3))) == 10
	@test length(unique(getindex.(r, 4))) == 10
	@test getindex.(r, 3) == collect(1:10)
	@test getindex.(r, 4) == collect(11:20)
end

@testitem "[p]cmap with matrix argument" begin
	c = Cached.DictCache()

	A = rand(10, 10)
	r = Cached.cmap(identity, c, A)
	@test size(r) == (10, 10)
	@test length(c) == 100

	v = vec(A)
	r = Cached.cmap(identity, c, v)
	@test length(r) == 100
	@test length(c) == 100

	r = Cached.pcmap(identity, c, v)
	@test length(r) == 100
	@test length(c) == 100

end




