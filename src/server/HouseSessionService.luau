local Service = {}
function Service.new(ctx)
local Config, caches, sessions, runtimeSessionsByOwnerId = ctx.Config, ctx.Caches, ctx.Sessions, ctx.RuntimeSessions
local usedCells = {}
local getHouseTemplate, applyUpgradeStage = ctx.GetHouseTemplate, ctx.ApplyUpgradeStage
local HttpService = game:GetService("HttpService")
local activeHouses = ctx.ActiveHouses
local restoreSavedPlacements, attachExitPrompt, endSession = ctx.Restore, ctx.AttachExit, ctx.EndSession
local teleportCharacter, buildSnapshot = ctx.Teleport, ctx.BuildSnapshot
local Modules = {SendState = ctx.SendState}
local function allocateCell()
	local index = 1
	while usedCells[index] do
		index += 1
	end
	usedCells[index] = true
	local zeroIndex = index - 1
	local column = zeroIndex % Config.CellsPerRow
	local row = math.floor(zeroIndex / Config.CellsPerRow)
	local position = Config.HouseOrigin + Vector3.new(column * Config.CellSpacing, 0, row * Config.CellSpacing)
	return index, CFrame.new(position)
end

local function releaseCell(index)
	if index then
		usedCells[index] = nil
	end
end

local function getSessionSpawn(session)
	local door = session.House and session.House:FindFirstChild("Door")
	local spawn = door and door:FindFirstChild("HouseSpawn", true)
	return spawn and spawn:IsA("BasePart") and spawn or nil
end

local function createRuntimeSession(owner)
	local cache = caches[owner]
	if not cache then
		return nil, "House data is unavailable"
	end
	local data = cache.Data
	local template = getHouseTemplate(data.SelectedHouse)
	if not template then
		return nil, "The selected house template is unavailable"
	end
	local cellIndex, cellCFrame = allocateCell()
	local house = template:Clone()
	house.Name = ("%s_%d"):format(template.Name, owner.UserId)
	house:SetAttribute("RuntimeHouse", true)
	house:SetAttribute("OwnerUserId", owner.UserId)
	house:SetAttribute("HouseTemplate", template.Name)
	local upgradeStage = data.UpgradeStage
	applyUpgradeStage(house, template, upgradeStage)
	house:PivotTo(cellCFrame)
	house.Parent = activeHouses
	local placedFolder = Instance.new("Folder")
	placedFolder.Name = "PlacedFurniture"
	placedFolder.Parent = house
	local session = {
		Id = HttpService:GenerateGUID(false),
		Revision = 1,
		Owner = owner,
		OwnerUserId = owner.UserId,
		OwnerName = owner.Name,
		Cache = cache,
		House = house,
		HouseName = template.Name,
		HouseKind = "Virtual",
		PhysicalHouseId = nil,
		DestroyHouseOnEnd = true,
		UpgradeStage = upgradeStage,
		CellIndex = cellIndex,
		PlacedFolder = placedFolder,
		BoundsFolder = house:FindFirstChild("PlacementBounds"),
		Placements = {},
		Participants = {},
		DeathConnections = {},
	}
	runtimeSessionsByOwnerId[owner.UserId] = session
	restoreSavedPlacements(owner, session)
	attachExitPrompt(session)
	return session
end

local function addParticipantToSession(player, session)
	sessions[player] = session
	session.Participants[player] = true
	player:SetAttribute("HouseSessionActive", true)
	player:SetAttribute("HouseSessionId", session.Id)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		session.DeathConnections[player] = humanoid.Died:Connect(function()
			if sessions[player] == session then
				endSession(player, false, "House session ended on death")
			end
		end)
	end
end

local function joinRuntimeSession(player, session)
	-- Repair the virtual exit prompt for reused runtime clones before the player is teleported in.
	if session.HouseKind ~= "Physical" then
		attachExitPrompt(session)
	end
	addParticipantToSession(player, session)
	local spawn = getSessionSpawn(session)
	if not spawn or not teleportCharacter(player, spawn.CFrame * CFrame.new(0, 3, 0)) then
		endSession(player, false, "Could not enter house")
		return false, "Could not move your character into the house"
	end
	Modules.SendState(player, buildSnapshot(player))
	return true
end


return {
allocateCell = allocateCell,
releaseCell = releaseCell,
getSessionSpawn = getSessionSpawn,
createRuntimeSession = createRuntimeSession,
addParticipantToSession = addParticipantToSession,
joinRuntimeSession = joinRuntimeSession,
}
end
return Service
