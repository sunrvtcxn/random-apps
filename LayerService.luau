local LayerService = {}

LayerService.__index = LayerService

local HttpService = game:GetService('HttpService')
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

local chunk_size = 64
local cell_size = chunk_size / 64
local resolution = 32
local frequency = 1
local amplification = 7

local RNGSeed = Random.new()
local GenerationSeed = RNGSeed:NextInteger(0, 100000000000)

local render_distance = 15

LayerService.CurrentLayer = 1

function LayerService:SetLayer(NewLayer)
	LayerService.CurrentLayer = NewLayer
	GenerationSeed = RNGSeed:NextInteger(0, 100000000000)

	if LayerInfo.Layers[LayerService.CurrentLayer].GrassColor then
		Terrain:SetMaterialColor(Enum.Material.Grass, LayerInfo.Layers[LayerService.CurrentLayer].GrassColor)
	end
end

function LayerService:CreateChunk(CenterCf: CFrame?)
	task.wait()
	local self = setmetatable({}, LayerService)
	self.Id = HttpService:GenerateGUID(false)

	if not CenterCf then
		CenterCf = CFrame.new(0, 0, 0)
	end

	local CenterPart = Instance.new('Part')
	CenterPart.Name = self.Id
	CenterPart.Anchored = true
	CenterPart.Size = Vector3.new(chunk_size * 2, 50, chunk_size * 2)
	CenterPart.Transparency = 1
	CenterPart.CanCollide = false
	CenterPart.CastShadow = false
	CenterPart.CFrame = CenterCf
	CenterPart.Parent = workspace.Chunks
	self.CenterPart = CenterPart
	Chunks[self.Id] = self

	local Targets = {}
	local LayerFactors = LayerInfo.Layers[LayerService.CurrentLayer].LayerFactors

	if LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Natural' then

		task.desynchronize()

		for x = -chunk_size, chunk_size do
			for z = -chunk_size, chunk_size do

				local height = 2

				if not table.find(LayerFactors, 'Flat') then
					height = math.noise((x + CenterCf.X)/resolution*frequency, (z + CenterCf.Z)/resolution*frequency, GenerationSeed % 100000 * 0.01258 * 0.01952) * amplification
				end

				table.insert(Targets, CFrame.new(x * cell_size, height, z * cell_size) * CenterCf)
			end
		end

		task.synchronize()

		for _, v in pairs(Targets) do
			Terrain:FillBlock(v, Vector3.new(cell_size, cell_size, cell_size), Enum.Material.Grass)
		end

	elseif LayerInfo.Layers[LayerService.CurrentLayer].GenerationType == 'Predefined' then
		local Variations = LayerInfo.Layers[LayerService.CurrentLayer].PredefinedVariations:GetChildren()
		local Selection: Model = Variations[RNGSeed:NextInteger(1, #Variations)]:Clone()
		Selection.Parent = CenterPart
		Selection:PivotTo(CenterCf)
	end

	local pos = CenterCf:PointToWorldSpace()

	for _, v in pairs(LayerInfo.Layers[LayerService.CurrentLayer].LayerEvents) do
		if RNGSeed:NextInteger(1, 100) <= v.Chance then
			local RandomPosition = Vector3.new(RNGSeed:NextInteger(-math.floor(pos.X), math.floor(pos.X)), 3, RNGSeed:NextInteger(-math.floor(pos.Z), math.floor(pos.Z)))
			local asset: Model = v.Asset:Clone()
			CollectionService:AddTag(asset, asset.Name)
			asset:PivotTo(CFrame.new(RandomPosition))
			asset.Parent = self.CenterPart
		end
	end

	for _,v in pairs(LayerInfo.Layers[LayerService.CurrentLayer].Enemies) do
		if RNGSeed:NextInteger(1, 100) <= v.Chance then
			local RandomPosition = Vector3.new(RNGSeed:NextInteger(-math.floor(pos.X), math.floor(pos.X)), 3, RNGSeed:NextInteger(-math.floor(pos.Z), math.floor(pos.Z)))
			ReplicatedStorage.Events.Environment.SpawnEnemy:Fire(LayerInfo.Layers[LayerService.CurrentLayer].Enemies[RNGSeed:NextInteger(1, #LayerInfo.Layers[LayerService.CurrentLayer].Enemies)].Model, RandomPosition)
		end
	end

	print(`LayerService - finished preparing Chunk {self.Id}`)

	return self
end

function LayerService:DeleteChunk(id: string)
	if Chunks[id] then
		LayerService:WipeChunkEnemies(Chunks[id].Id)
		Terrain:FillBlock(Chunks[id].CenterPart.CFrame, Chunks[id].CenterPart.Size + Vector3.new(4, 4, 4), Enum.Material.Air)
		Chunks[id].CenterPart:Destroy()
		Chunks[id] = nil
	end

	print(`LayerService - finished deleting Chunk {id}`)
end

function LayerService:GetAvailableAdjacentCFrames(id: string)
	local results = {}
	local targets = {
		left = Chunks[id].CenterPart.CFrame * CFrame.new(0, 0, -chunk_size * 2),
		front = Chunks[id].CenterPart.CFrame * CFrame.new(chunk_size * 2, 0, 0),
		right = Chunks[id].CenterPart.CFrame * CFrame.new(0, 0, chunk_size * 2),
		back = Chunks[id].CenterPart.CFrame * CFrame.new(-chunk_size * 2, 0, 0),
		back_left = Chunks[id].CenterPart.CFrame * CFrame.new(-chunk_size * 2, 0, -chunk_size * 2),
		back_right = Chunks[id].CenterPart.CFrame * CFrame.new(-chunk_size * 2, 0, chunk_size * 2),
		front_left = Chunks[id].CenterPart.CFrame * CFrame.new(chunk_size * 2, 0, -chunk_size * 2),
		front_right = Chunks[id].CenterPart.CFrame * CFrame.new(chunk_size * 2, 0, chunk_size * 2)
	}

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
	for _, Chunk in pairs(Chunks) do
		local Preserve = false

		for _, Player in Players:GetPlayers() do
			if (Chunk.CenterPart.CFrame.Position - Player.Character.HumanoidRootPart.Position).Magnitude < chunk_size * (render_distance * 1.3) then
				Preserve = true
				break
			end
		end

		if Preserve == false then
			LayerService:DeleteChunk(Chunk.Id)
		end
	end
end

function LayerService:WipeAllChunks()
	for _, v in pairs(Chunks) do
		LayerService:DeleteChunk(v.Id)
	end
end

--// Gonna have to unfortunately declare already a variable which receives +1 each time there is a chunk
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
	local targets = workspace:GetPartBoundsInBox(Chunks[id].CenterPart.CFrame, Vector3.new(chunk_size, chunk_size, chunk_size))
	local results = {}

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
		return true
	else
		return false
	end
end

function LayerService:GetPlayerChunk(player: Player)
	if player.Character then
		return LayerService:GetChunkFromCFrame(player.Character.HumanoidRootPart.CFrame)
	else
		return nil
	end
end

return LayerService
