local LayerService = {}

LayerService.__index = LayerService

local HttpService = game:GetService('HttpService') --
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local ServerScriptService = game:GetService('ServerScriptService')
local CollectionService = game:GetService('CollectionService')

local Terrain = workspace.Terrain
local Enemies = ReplicatedStorage.Assets.Enemies
local Events = ReplicatedStorage.Events

local CombatService = require(ServerScriptService.Combat.CombatService)
local LayerInfo = require(script.LayerInfo)

local Chunks = {}

local cell_size = 3
local chunk_size = 64
local resolution = 20
local frequency = 2
local amplification = 2

local RNGSeed = Random.new()

local render_distance = 15
local center_size = chunk_size * 6

LayerService.CurrentLayer = 1

function LayerService:SetLayer(NewLayer)
	LayerService.CurrentLayer = NewLayer
	
	if LayerInfo.Layers[LayerService.CurrentLayer].GrassColor then
		Terrain:SetMaterialColor(Enum.Material.Grass, LayerInfo.Layers[LayerService.CurrentLayer].GrassColor)
	end
end

function LayerService:CreateChunk(Offset_CFrame: CFrame?)
	local self = setmetatable({}, LayerService)
	self.Id = HttpService:GenerateGUID(false)
	
	local GenerationSeed = math.random(-10000000, 10000000)
	local Targets = {}
	local LayerFactors = LayerInfo.Layers[LayerService.CurrentLayer].LayerFactors
	local CenterCf = nil
	
	local CenterPart = Instance.new('Part')
	CenterPart.Name = self.Id
	CenterPart.Anchored = true
	
	if LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Natural' then
		CenterPart.Size = Vector3.new(center_size, 50, center_size)
	elseif LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Predefined' then
		CenterPart.Size = Vector3.new(chunk_size, 50, chunk_size)
	end
	
	CenterPart.Transparency = 1
	CenterPart.CanCollide = false
	CenterPart.CastShadow = false
	self.CenterPart = CenterPart

	Chunks[self.Id] = self

	--// Random terrain generation
	if LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Natural' then

		task.desynchronize()

		for x = -chunk_size, chunk_size do
			for z = -chunk_size, chunk_size do
				local height = math.noise(x/resolution*frequency, z/resolution*frequency) * amplification * cell_size

				local Cf = CFrame.new(x * cell_size, height, z * cell_size)

				if Offset_CFrame then Cf *= Offset_CFrame end

				table.insert(Targets, Cf)

				if x == 0 and z == 0 then
					CenterCf = Cf
				end
			end
		end

		task.synchronize()

		local LastTick = tick()
		
		for _, v in pairs(Targets) do
			Terrain:FillBlock(v, Vector3.new(cell_size, cell_size, cell_size), Enum.Material.Grass)
			if tick() - LastTick > 0.04 then
				task.wait()
				LastTick = tick()
			end
		end

	elseif LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Predefined' then
		
		local Cf = CFrame.new(0, 0, 0)

		if not table.find(LayerFactors, 'Flat') then
			Cf *= CFrame.new(0, math.noise(GenerationSeed/resolution*frequency, GenerationSeed/resolution*frequency) * amplification * cell_size, 0)
		end

		if Offset_CFrame then Cf *= Offset_CFrame end

		local Variations = LayerInfo.Layers[LayerService.CurrentLayer].PredefinedVariations:GetChildren()
		local Selection: Model = Variations[RNGSeed:NextInteger(1, #Variations)]:Clone()
		Selection.Parent = CenterPart
		Selection:PivotTo(Cf)
		CenterCf = Cf
	end
	
	CenterPart.CFrame = CenterCf
	CenterPart.Parent = workspace.Chunks
	
	local pos = CenterPart.CFrame:PointToWorldSpace()

	for _, v in pairs(LayerInfo.Layers[LayerService.CurrentLayer].LayerEvents) do
		if RNGSeed:NextInteger(1, 100) <= v.Chance then
			local RandomPosition = Vector3.new(RNGSeed:NextInteger(-math.floor(pos.X), math.floor(pos.X)), 3, RNGSeed:NextInteger(-math.floor(pos.Z), math.floor(pos.Z)))
			local asset: Model = v.Asset:Clone()
			CollectionService:AddTag(asset, asset.Name)
			asset:PivotTo(CFrame.new(RandomPosition))
			asset.Parent = self.CenterPart
		end
	end

	if RNGSeed:NextInteger(1, 20) == 1 then
		local RandomPosition = Vector3.new(RNGSeed:NextInteger(-math.floor(pos.X), math.floor(pos.X)), 3, RNGSeed:NextInteger(-math.floor(pos.Z), math.floor(pos.Z)))
		ReplicatedStorage.Events.Environment.SpawnEnemy:Fire(LayerService:GetLayerInfo(LayerService.CurrentLayer).Enemies[RNGSeed:NextInteger(1, #LayerInfo.Layers[LayerService.CurrentLayer].Enemies)], RandomPosition)
	end

	print(`LayerService - finished preparing Chunk {self.Id}`)

	return self
end

function LayerService:DeleteChunk(id: string)
	local Chunk = Chunks[id]
	
	if Chunk then
		LayerService:WipeChunkEnemies(Chunk.Id)
		Terrain:FillBlock(Chunk.CenterPart.CFrame, Chunk.CenterPart.Size + Vector3.new(4, 4, 4), Enum.Material.Air)
		Chunk.CenterPart:Destroy()
		Chunks[id] = nil
	end
	
	print(`LayerService - finished deleting Chunk {id}`)
end

function LayerService:GetAvailableAdjacentCFrames(id: string)
	local results = {}
	local targets = {}
	local Chunk = Chunks[id]
	
	if LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Natural' then
		targets = {
			left = Chunk.CenterPart.CFrame * CFrame.new(0, 0, -center_size),
			front = Chunk.CenterPart.CFrame * CFrame.new(center_size, 0, 0),
			right = Chunk.CenterPart.CFrame * CFrame.new(0, 0, center_size),
			back = Chunk.CenterPart.CFrame * CFrame.new(-center_size, 0, 0),
			back_left = Chunk.CenterPart.CFrame * CFrame.new(-center_size, 0, -center_size),
			back_right = Chunk.CenterPart.CFrame * CFrame.new(-center_size, 0, center_size),
			front_left = Chunk.CenterPart.CFrame * CFrame.new(center_size, 0, -center_size),
			front_right = Chunk.CenterPart.CFrame * CFrame.new(center_size, 0, center_size)
		}
		
	elseif LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Predefined' then
		targets = {
			left = Chunk.CenterPart.CFrame * CFrame.new(0, 0, -chunk_size),
			front = Chunk.CenterPart.CFrame * CFrame.new(chunk_size, 0, 0),
			right = Chunk.CenterPart.CFrame * CFrame.new(0, 0, chunk_size),
			back = Chunk.CenterPart.CFrame * CFrame.new(-chunk_size, 0, 0),
			back_left = Chunk.CenterPart.CFrame * CFrame.new(-chunk_size, 0, -chunk_size),
			back_right = Chunk.CenterPart.CFrame * CFrame.new(-chunk_size, 0, chunk_size),
			front_left = Chunk.CenterPart.CFrame * CFrame.new(chunk_size, 0, -chunk_size),
			front_right = Chunk.CenterPart.CFrame * CFrame.new(chunk_size, 0, chunk_size)
		}
	end
	
	for _, v in pairs(targets) do
		local overlaps = workspace:GetPartBoundsInBox(v, Vector3.one)
		if #overlaps == 0 then
			table.insert(results, v)
		end
	end
	
	return results
end

function LayerService:CreateEligibleAdjacentChunks()
	for _, Chunk in pairs(Chunks) do
		
		for _, Player in Players:GetPlayers() do
			for _, v in pairs(LayerService:GetAvailableAdjacentCFrames(Chunk.Id)) do
				if (v.Position - Player.Character.HumanoidRootPart.Position).Magnitude < chunk_size * render_distance then
					LayerService:CreateChunk(v)
				end
			end
		end
	end
end

function LayerService:WipeIrrelevantChunks()
	for _, v in pairs(Chunks) do
		local Preserve = false

		for _, Player in Players:GetPlayers() do
			if (v.CenterPart.CFrame.Position - Player.Character.HumanoidRootPart.Position).Magnitude < chunk_size * (render_distance * 1.3) then
				Preserve = true
				break
			end
		end

		if Preserve == false then
			LayerService:DeleteChunk(v.Id)
		end
	end
end

function LayerService:WipeAllChunks()
	for _, v in pairs(Chunks) do
		LayerService:DeleteChunk(v.Id)
	end
end

function LayerService:GetAmountOfChunks()
	local amount = 0
	
	for _, v in pairs(Chunks) do
		amount += 1
	end
	
	return amount
end

function LayerService:GetChunkFromPosition(Position: Vector3)
	local result = workspace:GetPartBoundsInBox(CFrame.new(Position), Vector3.new(0.01, 0.01, 0.01))

	for _, v in pairs(Chunks) do
		if table.find(result, v.CenterPart) then
			return v
		end
	end
end

function LayerService:GetChunkFromCFrame(Cf: CFrame)
	local result = workspace:GetPartBoundsInBox(Cf, Vector3.new(0.01, 0.01, 0.01))
	
	for _, v in pairs(Chunks) do
		if table.find(result, v.CenterPart) then
			return v
		end
	end
end

function LayerService:GetChunkEnemies(id: string)
	local targets = {}
	local results = {}
	
	if LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Natural' then
		targets = workspace:GetPartBoundsInBox(Chunks[id].CenterPart.CFrame, Vector3.new(center_size, center_size, center_size))
	elseif LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Predefined' then
		targets = workspace:GetPartBoundsInBox(Chunks[id].CenterPart.CFrame, Vector3.new(chunk_size, chunk_size, chunk_size))
	end

	for _, v in pairs(targets) do
		if v:GetAttribute('Enemy') then
			table.insert(results, v)
		end
	end
	
	return results
end

function LayerService:WipeChunkEnemies(id: string)
	for _, v in pairs(LayerService:GetChunkEnemies(id)) do
		v:Destroy()
	end
end

function LayerService:ChunkExists(id: string)
	if Chunks[id] then
		return true else return false
	end
end

function LayerService:GetPlayerChunk(player: Player)
	if player.Character then
		return LayerService:GetChunkFromCFrame(player.Character.HumanoidRootPart.CFrame)
	else
		return nil
	end
end

function LayerService:GetLayerInfo(index: number)
	return LayerInfo.Layers[index]
end

return LayerService
