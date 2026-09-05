--[[
	HouseSystem
	Creates private house sessions and keeps furniture placement server-authoritative.
	House data is separate from the inventory save format.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local MessagingService = game:GetService("MessagingService")

local Config = require(script.Parent:WaitForChild("HouseConfig"))
local ItemRegistry = require(ReplicatedStorage:WaitForChild("ItemRegistry"))
local inventorySystem = ServerScriptService:WaitForChild("Inventory System")
local InventoryService = require(inventorySystem:WaitForChild("InventoryService"))
local WarehouseService = require(inventorySystem:WaitForChild("WarehouseService"))
local PhysicalDeedService = require(inventorySystem:WaitForChild("PhysicalDeedService"))
local NotificationServer = require(ServerScriptService:WaitForChild("Notification System"):WaitForChild("NotificationServer"))
local FurnitureFunctionRegistry = require(script.Parent:WaitForChild("FurnitureFunctions"):WaitForChild("Registry"))

local inventorySaveRequest = ServerScriptService
	:WaitForChild("Inventory System")
	:WaitForChild("InventoryDataStore")
	:WaitForChild("RequestImmediateSave")

local houseTemplates = ServerStorage:WaitForChild("HouseTemplates")
local physicalHouses = Workspace:WaitForChild("PhysicalHouses")
local furnitureFolder = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Furnitures")
local activeHouses = Workspace:WaitForChild("ActiveHouses")
local remotes = ReplicatedStorage:WaitForChild("HouseRemotes")

local openMenu = remotes:WaitForChild("OpenMenu")
local sessionState = remotes:WaitForChild("SessionState")
local actionResult = remotes:WaitForChild("ActionResult")
local requestEnter = remotes:WaitForChild("RequestEnter")
local requestPurchaseHouse = remotes:WaitForChild("RequestPurchaseHouse")
local housePurchaseResult = remotes:WaitForChild("HousePurchaseResult")
local getHousePurchaseCatalog = remotes:WaitForChild("GetHousePurchaseCatalog")
local requestHousePreview = remotes:WaitForChild("RequestHousePreview")
local housePreviewState = remotes:WaitForChild("HousePreviewState")
local requestExitHousePreview = remotes:WaitForChild("RequestExitHousePreview")
local requestExit = remotes:WaitForChild("RequestExit")
local getPublicHouseList = remotes:WaitForChild("GetPublicHouseList")
local requestVisitHouse = remotes:WaitForChild("RequestVisitHouse")
local visitHouseResult = remotes:WaitForChild("VisitHouseResult")
local requestSetHouseAccess = remotes:WaitForChild("RequestSetHouseAccess")
local houseAccessState = remotes:WaitForChild("HouseAccessState")
local requestPlace = remotes:WaitForChild("RequestPlace")
local requestMove = remotes:WaitForChild("RequestMove")
local requestStore = remotes:WaitForChild("RequestStore")
local requestSnapshot = remotes:WaitForChild("RequestSnapshot")
local requestInteractItemDisplay = remotes:WaitForChild("RequestInteractItemDisplay")
local requestInteractFurniture = remotes:WaitForChild("RequestInteractFurniture")
local requestFurnitureFunctionAction = remotes:WaitForChild("RequestFurnitureFunctionAction")
local furnitureFunctionEditor = remotes:WaitForChild("FurnitureFunctionEditor")
local furnitureFunctionResult = remotes:WaitForChild("FurnitureFunctionResult")
local getHouseTaxStatus = remotes:WaitForChild("GetHouseTaxStatus")
local requestAddTaxReserve = remotes:WaitForChild("RequestAddTaxReserve")
local requestPayHouseTax = remotes:WaitForChild("RequestPayHouseTax")
local houseTaxState = remotes:WaitForChild("HouseTaxState")
local requestPurchaseHouseUpgrade = remotes:WaitForChild("RequestPurchaseHouseUpgrade")
local requestAddHousePreviewUpgrade = remotes:WaitForChild("RequestAddHousePreviewUpgrade")
local houseUpgradePurchaseResult = remotes:WaitForChild("HouseUpgradePurchaseResult")

local houseStore = DataStoreService:GetDataStore(Config.DataStoreName)
local inventoryStore = DataStoreService:GetDataStore("MaterialInventory_v3")
local PHYSICAL_HOUSE_MESSAGE_TOPIC = "PhysicalHouseSnapshotsChanged_v1"
local caches = {}
local sessions = {}
local runtimeSessionsByOwnerId = {}
local runtimeSessionsByPhysicalId = {}
local validPhysicalHouses = {}
local previewSessions = {}
local usedCells = {}
local cooldowns = setmetatable({}, {__mode = "k"})
local taxOperationBusy = setmetatable({}, {__mode = "k"})
local upgradeOperationBusy = setmetatable({}, {__mode = "k"})
local furnitureWarningUntil = setmetatable({}, {__mode = "k"})
local invalidSeatTemplateWarnings = setmetatable({}, {__mode = "k"})
local registeredLandlords = setmetatable({}, {__mode = "k"})
local lastLandlordParts = setmetatable({}, {__mode = "k"})
local shuttingDown = false

local function notify(player, title, message)
	NotificationServer.Notify(player, {
		Title = title,
		Text = message,
		Duration = 3,
	})
end

local function notifyFurnitureWarning(player, title, message)
	local now = os.clock()
	if now < (furnitureWarningUntil[player] or 0) then
		return
	end
	furnitureWarningUntil[player] = now + 3
	notify(player, title, message)
end
local Modules = {}
Modules.Schema = require(script.Parent.HouseDataSchema).new(Config, FurnitureFunctionRegistry)
Modules.Data = require(script.Parent.HouseDataService).new(houseStore, Modules.Schema, Config)
Modules.Geometry = require(ReplicatedStorage:WaitForChild("HouseShared"):WaitForChild("HousePlacementGeometry"))
Modules.Snapshot = require(ReplicatedStorage.HouseShared.HouseSnapshot)
Modules.History = require(script.Parent.HouseMoveHistory)
Modules.Validator = require(script.Parent.HouseTemplateValidator)
Modules.Streams = setmetatable({}, {__mode = "k"})
Modules.Leaving = setmetatable({}, {__mode = "k"})
local isFiniteNumber = Modules.Schema.IsFiniteNumber
local encodeCFrame = Modules.Schema.EncodeCFrame
local decodeCFrame = Modules.Schema.DecodeCFrame
local defaultData = Modules.Schema.Default
local sanitizeLoadedData = Modules.Schema.Sanitize
local sanitizeTaxAmount = Modules.Schema.SanitizeTaxAmount
local sanitizeTimestamp = Modules.Schema.SanitizeTimestamp
local sanitizeHouseAccess = Modules.Schema.SanitizeAccess
local HOUSE_ACCESS_ORDER = Modules.Schema.AccessOrder
local HOUSE_ACCESS_SET = Modules.Schema.AccessSet

function Modules.SendState(player, state)
    local previous = Modules.Streams[player]
    if state.Active ~= true then
        Modules.Streams[player] = nil
        sessionState:FireClient(player, state)
        return
    end
    state.StreamSequence = previous and previous.SessionId == state.SessionId and previous.StreamSequence + 1 or 1
    local outgoing = previous and previous.SessionId == state.SessionId and Modules.Snapshot.Diff(previous, state) or state
    Modules.Streams[player] = state
    sessionState:FireClient(player, outgoing)
end

function Modules.WritableCache(player)
    local cache = caches[player]
    if cache and not cache.Closing and cache.Handle and not cache.Handle.Lost and os.time() < cache.Handle.ExpiresAt then return cache end
    return nil
end

local initializeTaxSchedule
local scheduleSave
local reconcilePhysicalSelection

local function loadPlayerData(player)
    player:SetAttribute("HouseDataLoaded", false)
    player:SetAttribute("HouseDataLoadFailed", false)
    local loaded, handle = Modules.Data:Acquire(player.UserId)
    if not loaded then
        warn("[House] Could not load " .. player.Name .. ": " .. tostring(handle))
        player:SetAttribute("HouseDataLoadFailed", true)
        return
    end
    if player.Parent ~= Players or shuttingDown then
        Modules.Data:Write(player.UserId, loaded, handle, true)
        return
    end
    caches[player] = {Data = loaded, Handle = handle, Dirty = false, SaveToken = 0, Saving = false}
    if loaded.HouseKind == "Physical" and reconcilePhysicalSelection then
        local ok, reason = reconcilePhysicalSelection(player)
        if not ok then warn("[PhysicalHouse] Reconciliation deferred: " .. tostring(reason)) end
    end
    initializeTaxSchedule(player)
    player:SetAttribute("HouseDataLoaded", true)
end

local function savePlayerData(player)
    local cache = caches[player]
    if not cache or cache.Handle.Lost then return false end
    local deadline = os.clock() + 18
    while cache.Saving or cache.Handle.Busy do
        if os.clock() >= deadline then return false end
        task.wait(0.05)
    end
    if not cache.Dirty then return true end
    cache.Saving = true
    local token = cache.SaveToken
    local ok, revision = Modules.Data:Write(player.UserId, cache.Data, cache.Handle)
    cache.Saving = false
    if ok then
        cache.Data.Revision = math.max(cache.Data.Revision, revision)
        if token == cache.SaveToken then cache.Dirty = false end
        if cache.Data.HouseKind == "Physical" and cache.Data.PhysicalHouseId then
            pcall(function()
                MessagingService:PublishAsync(PHYSICAL_HOUSE_MESSAGE_TOPIC, {
                    PhysicalHouseId = cache.Data.PhysicalHouseId, OwnerUserId = player.UserId,
                    Revision = revision, JobId = game.JobId})
            end)
        end
    else
        warn("[House] Save remains queued for " .. player.Name .. ": " .. tostring(revision))
    end
    if cache.Dirty and not cache.Closing and not cache.Handle.Lost then
        task.delay(2, function() if caches[player] == cache and cache.Dirty then savePlayerData(player) end end)
    end
    return ok and not cache.Dirty
end

function Modules.FlushPlayer(player, release, deadline)
    local cache = caches[player]
    if not cache then return true end
    deadline = deadline or os.clock() + 20
    repeat
        if cache.Handle.Lost then return false end
        if not cache.Saving and not cache.Handle.Busy then
            if cache.Dirty then savePlayerData(player) end
            if not cache.Dirty and not cache.Saving and not cache.Handle.Busy then
                if not release then return true end
                local ok = Modules.Data:Write(player.UserId, cache.Data, cache.Handle, true)
                if ok then return true end
            end
        end
        task.wait(0.05)
    until os.clock() >= deadline
    warn("[House] Final save is still pending for " .. player.UserId)
    return false
end

scheduleSave = function(player)
    local cache = caches[player]
    if not cache or cache.Closing or cache.Handle.Lost then return end
    cache.Dirty = true
    cache.Data.Revision += 1
    cache.SaveToken += 1
    if cache.SaveScheduled then return end
    cache.SaveScheduled = true
    local delaySeconds = cache.Data.HouseKind == "Physical" and (Config.PhysicalSaveDebounce or 0.5) or Config.SaveDebounce
    task.delay(delaySeconds, function()
        cache.SaveScheduled = false
        if caches[player] == cache and cache.Dirty and not cache.Closing then savePlayerData(player) end
    end)
end

Modules.Placement = require(script.Parent.HousePlacementService).new({Config = Config, FurnitureFolder = furnitureFolder,
    Registry = FurnitureFunctionRegistry, IsFiniteNumber = isFiniteNumber, Geometry = Modules.Geometry})
local isVisiblePart = Modules.Placement.isVisiblePart
local findFurnitureTemplate = Modules.Placement.findFurnitureTemplate
local findCraftedFurnitureRecord = Modules.Placement.findCraftedFurnitureRecord
local craftedFinishFromRecord = Modules.Placement.craftedFinishFromRecord
local craftedWoodColor = Modules.Placement.craftedWoodColor
local partIsInsideGroup = Modules.Placement.partIsInsideGroup
local applyCraftedFurnitureFinish = Modules.Placement.applyCraftedFurnitureFinish
local sanitizeFurnitureClone = Modules.Placement.sanitizeFurnitureClone
local templateHasNativeSeat = Modules.Placement.templateHasNativeSeat
local validateFurnitureTemplate = Modules.Placement.validateFurnitureTemplate
local isFurnitureOccupied = Modules.Placement.isFurnitureOccupied
local getVisibleBounds = Modules.Placement.getVisibleBounds
local boundsContainPoint = Modules.Placement.boundsContainPoint
local getFurniturePlacementNormal = Modules.Placement.getFurniturePlacementNormal
local getAlignmentRotation = Modules.Placement.getAlignmentRotation
local getSurfaceCFrame = Modules.Placement.getSurfaceCFrame
local getVisibleProjectionRange = Modules.Placement.getVisibleProjectionRange
local resolveSurface = Modules.Placement.resolveSurface
local preparePlacement = Modules.Placement.preparePlacement

local function validateHouseTemplate(template, warnInvalid)
	local valid = template
		and template:IsA("Model")
		and template:GetAttribute("House") == true
	local door = valid and template:FindFirstChild("Door")
	local doorIsContainer = door and (door:IsA("Model") or door:IsA("BasePart"))
	local spawn = doorIsContainer and door:FindFirstChild("HouseSpawn")
	local bounds = valid and template:FindFirstChild("PlacementBounds")
	local hasBound = false
	if bounds and bounds:IsA("Folder") then
		for _, child in ipairs(bounds:GetChildren()) do
			if child:IsA("BasePart") then
				hasBound = true
				break
			end
		end
	end
	valid = valid
		and doorIsContainer
		and spawn
		and spawn:IsA("BasePart")
		and bounds
		and bounds:IsA("Folder")
		and hasBound
	if not valid and warnInvalid and template and template:IsA("Model") then
		warn(("[House] Ignoring %s. It needs House=true, a Model or BasePart Door with HouseSpawn, and PlacementBounds."):format(template:GetFullName()))
	end
	return valid
end

Modules.Physical = require(script.Parent.PhysicalHouseService).new({PhysicalHouses = physicalHouses})
local validatePhysicalHouseTemplate = Modules.Physical.Validate
local getPhysicalHouse = Modules.Physical.Get
local function rebuildPhysicalHouseIndex(warnInvalid)
    validPhysicalHouses = Modules.Physical.Rebuild(warnInvalid)
    return validPhysicalHouses
end

local function getHouseTemplate(name)
	if typeof(name) ~= "string" or name == "" then return nil end
	local physicalId = string.match(name, "^Physical:(.+)$")
	if physicalId then
		local physical = getPhysicalHouse(physicalId)
		return physical, physical and "Physical" or nil, physical and physicalId or nil
	end
	local template = houseTemplates:FindFirstChild(name)
	if validateHouseTemplate(template, true) then return template, "Virtual", nil end
	return nil
end

local function getStyleKey(template)
	if template and template:GetAttribute("PhysicalHouse") == true then
		return "Physical:" .. tostring(template:GetAttribute("PhysicalHouseId"))
	end
	return template and template.Name or nil
end

local function getStyleDisplayName(template)
	if template and template:GetAttribute("PhysicalHouse") == true then
		local value = template:GetAttribute("DisplayName")
		return typeof(value) == "string" and value ~= "" and value
			or tostring(template:GetAttribute("Address") or template.Name)
	end
	return template and template.Name or "House"
end

local function getUpgradeDefinitions(template, warnInvalid)
	local folder = template and template:FindFirstChild("UpgradeDefinitions")
	if not folder then
		return {}
	end
	if not folder:IsA("Folder") then
		if warnInvalid then
			warn(("[House] %s.UpgradeDefinitions must be a Folder."):format(template:GetFullName()))
		end
		return {}
	end

	local definitions = {}
	local ids = {}
	local orders = {}
	for _, config in ipairs(folder:GetChildren()) do
		if config:IsA("Configuration") then
			local order = tonumber(config:GetAttribute("Order"))
			local blockerName = config:GetAttribute("BlockerName")
			local displayName = config:GetAttribute("DisplayName")
			local cost = tonumber(config:GetAttribute("Cost"))
			local valid = order
				and order == math.floor(order)
				and order >= 1
				and typeof(blockerName) == "string"
				and blockerName ~= ""
				and cost
				and cost == cost
				and cost > -math.huge
				and cost < math.huge
				and cost >= 0
				and not ids[config.Name]
				and not orders[order]
			if not valid then
				if warnInvalid then
					warn(("[House] Invalid upgrade definition %s. Check its Order, BlockerName, Cost, and unique ID."):format(config:GetFullName()))
				end
				return {}
			end
			ids[config.Name] = true
			orders[order] = true
			table.insert(definitions, {
				Id = config.Name,
				Order = order,
				DisplayName = typeof(displayName) == "string" and displayName ~= "" and displayName or config.Name,
				BlockerName = blockerName,
				Cost = math.floor(cost),
			})
		end
	end

	table.sort(definitions, function(a, b)
		return a.Order < b.Order
	end)
	for index, definition in ipairs(definitions) do
		if definition.Order ~= index then
			if warnInvalid then
				warn(("[House] %s upgrade orders must be contiguous from 1."):format(template:GetFullName()))
			end
			return {}
		end
	end
	return definitions
end

local function getPublicUpgradeDefinitions(template)
	local result = {}
	for _, definition in ipairs(getUpgradeDefinitions(template, false)) do
		table.insert(result, {
			Id = definition.Id,
			Order = definition.Order,
			DisplayName = definition.DisplayName,
			Cost = definition.Cost,
			BlockerName = definition.BlockerName,
		})
	end
	return result
end

local function applyUpgradeStage(house, template, stage)
	stage = math.max(0, math.floor(tonumber(stage) or 0))
	local blockerNames = {}
	for _, definition in ipairs(getUpgradeDefinitions(template, false)) do
		if definition.Order <= stage then
			blockerNames[definition.BlockerName] = true
		end
	end

	local toDestroy = {}
	for _, object in ipairs(house:GetDescendants()) do
		if blockerNames[object.Name] and (object:IsA("Model") or object:IsA("BasePart")) then
			local coveredByMatchingModel = false
			local ancestor = object.Parent
			while ancestor and ancestor ~= house do
				if ancestor:IsA("Model") and blockerNames[ancestor.Name] then
					coveredByMatchingModel = true
					break
				end
				ancestor = ancestor.Parent
			end
			if not coveredByMatchingModel then
				table.insert(toDestroy, object)
			end
		end
	end
	for _, object in ipairs(toDestroy) do
		object:Destroy()
	end
	house:SetAttribute("UpgradeStage", stage)
end

local function buildUpgradeState(player, selectedTemplate)
	local cache = caches[player]
	local ownedHouse = cache and cache.Data.SelectedHouse or nil
	local ownedStage = cache and cache.Data.UpgradeStage or 0
	return {
		OwnedHouse = ownedHouse,
		OwnedUpgradeStage = ownedStage,
		SelectedTemplate = selectedTemplate,
		PreviewUpgradeStage = selectedTemplate == ownedHouse and ownedStage or 0,
	}
end

local function playerHasPhysicalDeed(player, physicalHouseId, forceRefresh)
	local id = tostring(physicalHouseId or "")
	if id == "" or not player then return false, "Physical house ID is missing" end
	local ownedId, registryError = PhysicalDeedService:GetPlayerDeedAsync(player.UserId, forceRefresh == true)
	if registryError then return false, registryError end
	if ownedId ~= id then return false, "You do not own the deed for this physical house" end
	local deedName = PhysicalDeedService:GetDeedItemName(id)
	if not deedName then return false, "The matching deed template is unavailable" end
	local inventory = player:FindFirstChild("MaterialInventory")
	local warehouse = player:FindFirstChild("WarehouseInventory")
	local inventoryCount = inventory and inventory:FindFirstChild(deedName)
	local warehouseCount = warehouse and warehouse:FindFirstChild(deedName)
	local amount = (inventoryCount and inventoryCount:IsA("IntValue") and inventoryCount.Value or 0)
		+ (warehouseCount and warehouseCount:IsA("IntValue") and warehouseCount.Value or 0)
	if amount ~= 1 then return false, "Your unique deed data needs reconciliation" end
	return true, nil, deedName
end

local function makeCatalogStyle(template)
	local catalogOrder = tonumber(template:GetAttribute("CatalogOrder"))
	local key = getStyleKey(template)
	local isPhysical = template:GetAttribute("PhysicalHouse") == true
	return {
		TemplateName = key,
		DisplayName = getStyleDisplayName(template),
		HouseKind = isPhysical and "Physical" or "Virtual",
		PhysicalHouseId = isPhysical and tostring(template:GetAttribute("PhysicalHouseId")) or nil,
		Address = isPhysical and tostring(template:GetAttribute("Address")) or nil,
		PurchaseCost = isPhysical and 0 or math.max(0, math.floor(tonumber(template:GetAttribute("PurchaseCost")) or 0)),
		WeeklyTax = math.max(0, math.floor(tonumber(template:GetAttribute("WeeklyTax")) or 0)),
		CatalogOrder = catalogOrder and math.floor(catalogOrder) or nil,
		Upgrades = getPublicUpgradeDefinitions(template),
	}
end

local function getPurchaseCatalogStyles(player)
	local styles = {}
	for _, template in ipairs(houseTemplates:GetChildren()) do
		if validateHouseTemplate(template, false) then table.insert(styles, makeCatalogStyle(template)) end
	end
	if player and player:GetAttribute("InventoryDataLoaded") == true then
		-- Repairs deed copies created before the global registry existed, or copied in by an admin/import.
		local reconciled, reconcileError = PhysicalDeedService:ReconcilePlayerAsync(player)
		if not reconciled then
			warn("[PhysicalHouse] Could not reconcile deeds for " .. player.Name .. ": " .. tostring(reconcileError))
		end
		local ownedId = PhysicalDeedService:GetPlayerDeedAsync(player.UserId, true)
		local physical = ownedId and getPhysicalHouse(ownedId) or nil
		if physical then
			local hasDeed = playerHasPhysicalDeed(player, ownedId, false)
			if hasDeed then table.insert(styles, makeCatalogStyle(physical)) end
		end
	end
	table.sort(styles, function(a, b)
		if a.TemplateName == Config.DefaultHouse then return true end
		if b.TemplateName == Config.DefaultHouse then return false end
		local aOrder = a.CatalogOrder or math.huge
		local bOrder = b.CatalogOrder or math.huge
		if aOrder ~= bOrder then return aOrder < bOrder end
		return string.lower(a.DisplayName or a.TemplateName) < string.lower(b.DisplayName or b.TemplateName)
	end)
	return styles
end

Modules.Taxes = require(script.Parent.HouseTaxService).new({Config = Config, Caches = caches,
    GetHouseTemplate = getHouseTemplate, Notify = notify, ScheduleSave = scheduleSave, TaxState = houseTaxState})
local getWeeklyTaxForData = Modules.Taxes.GetWeeklyTax
local updateHouseTaxDue = Modules.Taxes.UpdateDue
initializeTaxSchedule = Modules.Taxes.Initialize
local buildTaxStatus = Modules.Taxes.BuildStatus
local sendTaxState = Modules.Taxes.SendState

local allocateCell, releaseCell

local function findPlacementRecord(cache, placementId)
	for index, record in ipairs(cache.Data.Placements) do
		if record.PlacementId == placementId then
			return record, index
		end
	end
	return nil
end

local function buildSnapshot(player)
	local session = sessions[player]
	if not session then
		return {Active = false}
	end
	local isOwner = session.OwnerUserId == player.UserId
	local placements = {}
	for placementId, entry in pairs(session.Placements) do
		table.insert(placements, {
			PlacementId = placementId,
			ItemName = entry.Record.ItemName,
			CFrame = entry.Model:GetPivot(),
			FunctionState = FurnitureFunctionRegistry.SerializeState(entry.Record.FunctionState),
		})
	end
	table.sort(placements, function(a, b)
		return a.PlacementId < b.PlacementId
	end)
	local furniture = {}
	if isOwner then
		for _, object in ipairs(furnitureFolder:GetDescendants()) do
			if (object:IsA("Model") or object:IsA("BasePart"))
				and object.Parent
				and object.Parent:IsA("Folder")
			then
				local amount = InventoryService:GetSpendableAmount(player, object.Name)
				table.insert(furniture, {
					Name = object.Name,
					Available = tonumber(amount) or 0,
					IconId = object:GetAttribute("IconId"),
				})
			end
		end
		table.sort(furniture, function(a, b)
			return a.Name:lower() < b.Name:lower()
		end)
	end
	return {
		Active = true,
        StreamSequence = Modules.Streams[player] and Modules.Streams[player].SessionId == session.Id and Modules.Streams[player].StreamSequence or 0,
        CanUndo = Modules.History.Peek(session, "Undo") ~= nil and isOwner,
        CanRedo = Modules.History.Peek(session, "Redo") ~= nil and isOwner,
		SessionId = session.Id,
		Revision = session.Revision,
		House = session.House,
		HouseName = session.HouseName,
		UpgradeStage = session.UpgradeStage,
		Placements = placements,
		Furniture = furniture,
		MaximumFurniture = Config.MaximumFurniture,
		Role = isOwner and "Owner" or "Visitor",
		CanBuild = isOwner,
		OwnerUserId = session.OwnerUserId,
		OwnerName = session.OwnerName or (session.Owner and session.Owner.Name) or ("User " .. tostring(session.OwnerUserId)),
		HouseAccess = sanitizeHouseAccess(session.Cache.Data.HouseAccess),
		HouseKind = session.HouseKind or "Virtual",
		PhysicalHouseId = session.PhysicalHouseId,
		IsPhysical = session.HouseKind == "Physical",
		IsPreview = false,
	}
end

local function sendSnapshot(player, resultMessage)
	local session = sessions[player]
	if not session then
		Modules.SendState(player, {Active = false})
		return
	end
	for participant in pairs(session.Participants) do
		if participant.Parent == Players then
			Modules.SendState(participant, buildSnapshot(participant))
		end
	end
	if resultMessage then
		actionResult:FireClient(player, true, resultMessage)
	end
end

local function teleportCharacter(player, targetCFrame)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	character:PivotTo(targetCFrame)
	return true
end

local function unseatPlayer(player)
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end
end

local endSession
local endPreview

local function getDoorPromptPart(door)
	if not door then
		return nil
	end
	if door:IsA("BasePart") then
		return door
	end
	local namedDoorPart = door:FindFirstChild("Door", true)
	if namedDoorPart and namedDoorPart:IsA("BasePart") then
		return namedDoorPart
	end
	for _, object in ipairs(door:GetDescendants()) do
		if object:IsA("BasePart") and object.Name ~= "HouseSpawn" then
			return object
		end
	end

	-- Backward compatibility: older templates such as ModularHouse contain only HouseSpawn.
	-- Create an invisible prompt anchor under Door instead of attaching the prompt to HouseSpawn.
	local spawn = door:FindFirstChild("HouseSpawn", true)
	if not spawn or not spawn:IsA("BasePart") then
		return nil
	end
	local anchor = door:FindFirstChild("DoorPromptAnchor")
	if anchor and not anchor:IsA("BasePart") then
		anchor:Destroy()
		anchor = nil
	end
	if not anchor then
		anchor = Instance.new("Part")
		anchor.Name = "DoorPromptAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.5, 0.5, 0.5)
		anchor.Parent = door
	end
	anchor.CFrame = spawn.CFrame
	return anchor
end

local function getPhysicalHouseExitCFrame(session)
	if not session or session.HouseKind ~= "Physical" or not session.House then
		return nil
	end
	local door = session.House:FindFirstChild("Door", true)
	if not door then
		return nil
	end

	-- Future physical houses can place HouseExit exactly where players should appear outside.
	local marker = door:FindFirstChild("HouseExit", true) or door:FindFirstChild("ExitSpawn", true)
	if marker then
		if marker:IsA("Attachment") then
			return marker.WorldCFrame * CFrame.new(0, 3, 0)
		end
		if marker:IsA("BasePart") then
			return marker.CFrame * CFrame.new(0, 3, 0)
		end
	end

	-- Existing physical houses do not need a marker: the door's forward face is outside.
	local doorPart = getDoorPromptPart(door)
	if doorPart then
		return doorPart.CFrame * CFrame.new(0, 3, -4)
	end
	return nil
end


local function ensureDoorExitPrompt(door, promptName, objectText)
	local doorPart = getDoorPromptPart(door)
	if not doorPart then
		return nil
	end
	local prompt = door:FindFirstChild(promptName, true)
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = promptName
	end
	prompt.ActionText = "Exit House"
	prompt.ObjectText = objectText or "House"
	prompt.MaxActivationDistance = Config.InteractionDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.5
	prompt.Enabled = true
	prompt.Parent = doorPart
	return prompt
end

local function attachExitPrompt(session)
	if session.ExitConnection then
		session.ExitConnection:Disconnect()
		session.ExitConnection = nil
	end
	local door = session.House:FindFirstChild("Door")
	local prompt = ensureDoorExitPrompt(door, "ExitHousePrompt", session.HouseName or "House")
	if not prompt then
		warn("[House] No prompt-bearing BasePart was found under Door in " .. session.House:GetFullName())
		return
	end
	session.ExitConnection = prompt.Triggered:Connect(function(triggeringPlayer)
		if session.Participants[triggeringPlayer] and sessions[triggeringPlayer] == session then
			endSession(triggeringPlayer, true, "Left house")
		end
	end)
end

local function placementFunctionContext(player, session, entry)
	local owner = session.Owner
	local template = findFurnitureTemplate(entry.Record.ItemName)
	if not template then return nil end
	return {
		Owner = owner,
		Session = session,
		Template = template,
		Model = entry.Model,
		Record = entry.Record,
		MaxDistance = Config.InteractionDistance,
		IsActive = function()
            if owner and not Modules.WritableCache(owner) then return false end
			local runtimeActive = owner and runtimeSessionsByOwnerId[owner.UserId] == session
				or (session.PhysicalHouseId and runtimeSessionsByPhysicalId[session.PhysicalHouseId] == session)
			return runtimeActive
				and session.Placements[entry.Record.PlacementId] == entry
				and entry.Model.Parent ~= nil
		end,
		OnChanged = function(message)
			if not owner then return end
			if runtimeSessionsByOwnerId[owner.UserId] ~= session
				or session.Placements[entry.Record.PlacementId] ~= entry
			then
				return
			end
			session.Revision += 1
			scheduleSave(owner)
			sendSnapshot(owner, message)
		end,
		OpenEditor = function(targetPlayer, state)
			if owner and targetPlayer == owner
				and sessions[owner] == session
				and session.Placements[entry.Record.PlacementId] == entry
			then
				furnitureFunctionEditor:FireClient(owner, state)
			end
		end,
	}
end

local function mountPlacementFunction(player, session, entry)
	FurnitureFunctionRegistry.Cleanup(entry)
	local context = placementFunctionContext(player, session, entry)
	if not context then
		return
	end
	entry.FunctionCleanup = FurnitureFunctionRegistry.Mount(context)
end

requestInteractItemDisplay.OnServerEvent:Connect(function(player, placementId)
	if typeof(placementId) ~= "string" then
		return
	end
	local session = sessions[player]
	local entry = session and session.Placements[placementId]
	if not entry then
		return
	end
	local context = placementFunctionContext(player, session, entry)
	if not context or FurnitureFunctionRegistry.GetFunctionName(context.Template) ~= "ItemDisplay" then
		return
	end
	FurnitureFunctionRegistry.HandleOwnerClick(context, player)
end)

requestInteractFurniture.OnServerEvent:Connect(function(player, placementId)
	if typeof(placementId) ~= "string" or #placementId > 100 then
		return
	end
	local session = sessions[player]
	local entry = session and session.Placements[placementId]
	if not entry then
		return
	end
	local context = placementFunctionContext(player, session, entry)
	if not context then
		return
	end
	local success, message = FurnitureFunctionRegistry.HandleOwnerClick(context, player)
	if success ~= true and typeof(message) == "string" and message ~= "" then
		furnitureFunctionResult:FireClient(player, {
			Success = false,
			FunctionName = FurnitureFunctionRegistry.GetFunctionName(context.Template),
			PlacementId = placementId,
			Message = message,
		})
		notifyFurnitureWarning(player, "Furniture", message)
	end
end)

requestFurnitureFunctionAction.OnServerEvent:Connect(function(player, placementId, functionName, action, payload)
	if typeof(placementId) ~= "string" or #placementId > 100
		or typeof(functionName) ~= "string" or #functionName > 50
		or typeof(action) ~= "string" or #action > 50
	then
		return
	end
	local session = sessions[player]
	local entry = session and session.Placements[placementId]
	if not entry then
		return
	end
	local context = placementFunctionContext(player, session, entry)
	if not context then
		return
	end
	local actualFunctionName = FurnitureFunctionRegistry.GetFunctionName(context.Template)
	if actualFunctionName ~= functionName then
		local message = "Furniture function does not match this placement"
		furnitureFunctionResult:FireClient(player, {
			Success = false,
			FunctionName = actualFunctionName,
			PlacementId = placementId,
			Message = message,
		})
		notifyFurnitureWarning(player, "Furniture", message)
		return
	end
	local success, message, state = FurnitureFunctionRegistry.HandleOwnerAction(context, player, action, payload)
	local result = {
		Success = success == true,
		FunctionName = actualFunctionName,
		PlacementId = placementId,
		Message = typeof(message) == "string" and message or "",
		State = typeof(state) == "table" and state or nil,
	}
	furnitureFunctionResult:FireClient(player, result)
	if result.Message ~= "" then
		local title = actualFunctionName == "MusicPlayer" and "Music Player" or "Furniture"
		if result.Success then
			notify(player, title, result.Message)
		else
			notifyFurnitureWarning(player, title, result.Message)
		end
	end
end)

local function restoreSavedPlacements(player, session)
	local cache = session.Cache or (player and caches[player])
	if not cache then return end
	for _, record in ipairs(cache.Data.Placements) do
		local template = findFurnitureTemplate(record.ItemName)
		local templateIsValid, validationError = validateFurnitureTemplate(template)
		local localCF = decodeCFrame(record.LocalCFrame)
		if template and templateIsValid and localCF then
			local model = sanitizeFurnitureClone(template)
			applyCraftedFurnitureFinish(model, record.CraftedFinish)
			model:PivotTo(session.House:GetPivot() * localCF)
			model.Name = "Placed_" .. record.ItemName
			model:SetAttribute("PlacementId", record.PlacementId)
			model:SetAttribute("OwnerUserId", session.OwnerUserId)
			model:SetAttribute("ItemName", record.ItemName)
			model.Parent = session.PlacedFolder
			session.Placements[record.PlacementId] = {
				Model = model,
				Record = record,
			}
			mountPlacementFunction(player, session, session.Placements[record.PlacementId])
		else
			local detail = not template and "its furniture template is missing"
				or (not templateIsValid and (validationError or "its seating template is invalid"))
				or "its saved placement is invalid"
			warn(("[House] Could not restore %s for %s because %s."):format(record.ItemName, session.OwnerName or (player and player.Name) or tostring(session.OwnerUserId), detail))
		end
	end
end

local LANDLORD_PART_NAME = "Landlord"
local LANDLORD_PROMPT_NAME = "EnterHousePrompt"
local LANDLORD_PROMPT_DISTANCE = 8
local LANDLORD_PROMPT_HOLD_DURATION = 0.5

local function getLegacyLandlordPart()
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.Name == "Landlord" then
			local root = child:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root
			end
		end
	end
	return nil
end

local function isRegisteredLandlordPart(part)
	return part and part:IsA("BasePart") and part:IsDescendantOf(Workspace) and registeredLandlords[part] ~= nil
end

local function getLandlordReturnCFrame(player)
	local part = lastLandlordParts[player]
	if not isRegisteredLandlordPart(part) then
		part = getLegacyLandlordPart()
	end
	if not part then
		return nil
	end
	local attachment = part:FindFirstChild("HouseReturnPoint")
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldCFrame * CFrame.new(0, 3, 0)
	end
	return part.CFrame * CFrame.new(0, 3, 0)
end

local function teleportToLandlordReturn(player)
	local returnCFrame = getLandlordReturnCFrame(player)
	if returnCFrame then
		teleportCharacter(player, returnCFrame)
	end
end

local function returnPlayerFromHouse(player, session)
	local exteriorCFrame = getPhysicalHouseExitCFrame(session)
	if exteriorCFrame and teleportCharacter(player, exteriorCFrame) then
		return
	end
	teleportToLandlordReturn(player)
end

local function isNearLandlord(player)
	local landlordPart = lastLandlordParts[player]
	if not isRegisteredLandlordPart(landlordPart) then
		return false
	end
	local characterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local prompt = registeredLandlords[landlordPart].Prompt
	return characterRoot
		and characterRoot:IsA("BasePart")
		and prompt
		and prompt:IsA("ProximityPrompt")
		and (characterRoot.Position - landlordPart.Position).Magnitude <= prompt.MaxActivationDistance + 2
end

Modules.Sessions = require(script.Parent.HouseSessionService).new({Config = Config, Caches = caches,
    Sessions = sessions, RuntimeSessions = runtimeSessionsByOwnerId, GetHouseTemplate = getHouseTemplate,
    ApplyUpgradeStage = applyUpgradeStage, ActiveHouses = activeHouses, Restore = restoreSavedPlacements,
    AttachExit = attachExitPrompt, EndSession = function(...) return endSession(...) end,
    Teleport = teleportCharacter, BuildSnapshot = buildSnapshot, SendState = Modules.SendState})
allocateCell, releaseCell = Modules.Sessions.allocateCell, Modules.Sessions.releaseCell
local getSessionSpawn = Modules.Sessions.getSessionSpawn
local createRuntimeSession = Modules.Sessions.createRuntimeSession
local addParticipantToSession = Modules.Sessions.addParticipantToSession
local joinRuntimeSession = Modules.Sessions.joinRuntimeSession

local function serializeHouseDataTable(data)
    return Modules.Schema.Serialize(data)
end

local function readHouseDataByUserId(userId)
    local owner = Players:GetPlayerByUserId(userId)
    if owner and caches[owner] then return caches[owner], owner end
    local data, reason, writerActive = Modules.Data:Read(userId)
    if not data then return nil, nil, "House data is unavailable: " .. tostring(reason) end
    return {Data = data, Dirty = false, Offline = true, WriterActive = writerActive}, nil
end

local function writeOfflineHouseData(userId, data)
    local ok, revision = Modules.Data:Write(userId, data)
    if not ok then return false, "House data changed or its owner is active in another server: " .. tostring(revision) end
    data.Revision = revision
    pcall(function()
        MessagingService:PublishAsync(PHYSICAL_HOUSE_MESSAGE_TOPIC, {PhysicalHouseId = data.PhysicalHouseId,
            OwnerUserId = userId, Revision = revision, JobId = game.JobId})
    end)
    return true
end

local function updateOfflineTaxDue(data)
	if not data or data.HouseKind ~= "Physical" or not data.PhysicalHouseId then return false end
	if data.TaxDueAmount > 0 then
		if data.NextTaxDueAt ~= nil then data.NextTaxDueAt = nil; return true end
		return false
	end
	local weeklyTax, template = getWeeklyTaxForData(data)
	if not template then return false end
	local now = os.time()
	if data.NextTaxDueAt == nil then
		data.NextTaxDueAt = now + Config.TaxIntervalSeconds
		return true
	elseif data.NextTaxDueAt <= now then
		data.NextTaxDueAt = nil
		if weeklyTax > 0 then data.TaxDueAmount = weeklyTax else data.NextTaxDueAt = now + Config.TaxIntervalSeconds end
		return true
	end
	return false
end

local function closePhysicalRuntimeSession(physicalHouseId, reason)
	local session = runtimeSessionsByPhysicalId[tostring(physicalHouseId or "")]
	if not session then return end
	local participants = {}
	for participant in pairs(session.Participants) do table.insert(participants, participant) end
	for _, participant in ipairs(participants) do endSession(participant, true, reason or "Physical house refreshed") end
end

local function getPhysicalEntryPermission(player, physicalHouseId)
	local id = tostring(physicalHouseId or "")
	local physical = getPhysicalHouse(id)
	if not physical then return false, "This physical house is unavailable" end
	local ownerRecord, ownerError = PhysicalDeedService:GetOwnerAsync(id, true)
	if ownerError then return false, ownerError end
	if not ownerRecord or not ownerRecord.OwnerUserId then return false, "This house is empty" end
	local ownerUserId = ownerRecord.OwnerUserId
	local ownerCache, ownerPlayer, dataError = readHouseDataByUserId(ownerUserId)
	if not ownerCache then return false, dataError or "This house is empty" end
	local data = ownerCache.Data
	if data.HouseKind ~= "Physical" or data.PhysicalHouseId ~= id or data.SelectedHouse ~= "Physical:" .. id then
		return false, "This house is empty"
	end
	if ownerPlayer then
		initializeTaxSchedule(ownerPlayer)
	elseif updateOfflineTaxDue(data) and not ownerCache.WriterActive then
		if not writeOfflineHouseData(ownerUserId, data) then return false, "This house is temporarily unavailable" end
	end
	if data.TaxDueAmount > 0 then return false, "This house is closed because its taxes are unpaid" end
	if player.UserId == ownerUserId then
		return true, nil, ownerRecord, ownerCache, ownerPlayer, physical
	end
	if sanitizeHouseAccess(data.HouseAccess) ~= "Public" then return false, "This house is private" end
	return true, nil, ownerRecord, ownerCache, ownerPlayer, physical
end

local function createPhysicalRuntimeSession(physicalHouseId, ownerRecord, ownerCache, ownerPlayer, physical)
	local id = tostring(physicalHouseId)
	local current = runtimeSessionsByPhysicalId[id]
	if current then
		if current.OwnerUserId == ownerRecord.OwnerUserId then
			if ownerPlayer then
				local nextCache = caches[ownerPlayer] or ownerCache
				local needsRefresh = sanitizeTaxAmount(current.Cache.Data.Revision) ~= sanitizeTaxAmount(nextCache.Data.Revision)
				current.OwnerName = ownerPlayer.Name
                if needsRefresh and Modules.ReconcilePlacements then
                    Modules.ReconcilePlacements(current, nextCache, ownerPlayer)
                else
                    current.Owner = ownerPlayer
                    current.Cache = nextCache
                    for _, entry in pairs(current.Placements) do mountPlacementFunction(ownerPlayer, current, entry) end
				end
			end
			return current
		end
		closePhysicalRuntimeSession(id, "Physical house ownership changed")
	end

	local oldFolder = physical:FindFirstChild("PlacedFurniture_PhysicalRuntime")
	if oldFolder then oldFolder:Destroy() end
	local placedFolder = Instance.new("Folder")
	placedFolder.Name = "PlacedFurniture_PhysicalRuntime"
	placedFolder.Parent = physical
	physical:SetAttribute("RuntimeHouse", true)
	physical:SetAttribute("RuntimeOwnerUserId", ownerRecord.OwnerUserId)
	local session = {
		Id = HttpService:GenerateGUID(false),
		Revision = 1,
		Owner = ownerPlayer,
		OwnerUserId = ownerRecord.OwnerUserId,
		OwnerName = ownerPlayer and ownerPlayer.Name or ownerRecord.OwnerName,
		Cache = ownerCache,
		House = physical,
		HouseName = "Physical:" .. id,
		HouseKind = "Physical",
		PhysicalHouseId = id,
		UpgradeStage = ownerCache.Data.UpgradeStage,
		CellIndex = nil,
		PlacedFolder = placedFolder,
		BoundsFolder = physical:FindFirstChild("PlacementBounds"),
		Placements = {},
		Participants = {},
		DeathConnections = {},
		DestroyHouseOnEnd = false,
	}
	runtimeSessionsByPhysicalId[id] = session
	runtimeSessionsByOwnerId[ownerRecord.OwnerUserId] = session
	restoreSavedPlacements(ownerPlayer, session)
	return session
end

local function enterPhysicalHouse(player, physicalHouseId, entrySource)
	local now = os.clock()
	local playerCooldowns = cooldowns[player] or {}
	cooldowns[player] = playerCooldowns
	if now - (playerCooldowns.PhysicalEntry or 0) < Config.GeneralRequestCooldown then return false, "Please wait before entering again" end
	playerCooldowns.PhysicalEntry = now
	if player:GetAttribute("TradingInterfaceLocked") == true then return false, "House access is locked while trading" end
	if previewSessions[player] then return false, "Leave the house preview before entering" end
	local allowed, reason, ownerRecord, ownerCache, ownerPlayer, physical = getPhysicalEntryPermission(player, physicalHouseId)
	if not allowed then return false, reason end
	local current = sessions[player]
	if current and current.HouseKind == "Physical" and current.PhysicalHouseId == tostring(physicalHouseId) then
		sendSnapshot(player)
		return true, "You are already inside this house"
	end
	if current then endSession(player, false, "Entering another house") end
	local runtime = createPhysicalRuntimeSession(physicalHouseId, ownerRecord, ownerCache, ownerPlayer, physical)
	local joined, joinError = joinRuntimeSession(player, runtime)
	if not joined then return false, joinError end
	local address = tostring(physical:GetAttribute("Address") or getStyleDisplayName(physical))
	return true, player.UserId == ownerRecord.OwnerUserId
		and ("Entered your physical house at " .. address)
		or ("Visiting " .. tostring(ownerRecord.OwnerName or ownerRecord.OwnerUserId) .. " at " .. address)
end

local function validateOwnerHouseEntry(player)
	if player:GetAttribute("InventoryDataLoaded") ~= true then
		return nil, "Inventory data is still loading"
	end
	if player:GetAttribute("HouseDataLoadFailed") == true then
		return nil, "House data could not be loaded. Rejoin before entering."
	end
	if player:GetAttribute("HouseDataLoaded") ~= true or not caches[player] then
		return nil, "House data is still loading"
	end
	local cache = caches[player]
	initializeTaxSchedule(player)
	if cache.Data.TaxDueAmount > 0 then
		return nil, ("You have %d %s in unpaid house taxes. Pay them before entering."):format(
			cache.Data.TaxDueAmount,
			Config.HouseCurrency
		)
	end
	if typeof(cache.Data.SelectedHouse) ~= "string" or cache.Data.SelectedHouse == "" then
		return nil, "You don’t have a house."
	end
	local _, houseKind, physicalHouseId = getHouseTemplate(cache.Data.SelectedHouse)
	if not houseKind then return nil, "The selected house template is unavailable" end
	if houseKind == "Physical" then
		local hasDeed, deedError = playerHasPhysicalDeed(player, physicalHouseId, true)
		if not hasDeed then return nil, deedError or "You no longer own the deed for this physical house" end
	end
	return cache
end

local function beginSession(player)
	if previewSessions[player] then
		actionResult:FireClient(player, false, "Leave the house preview before entering your owned house")
		return
	end
	if player:GetAttribute("TradingInterfaceLocked") == true then
		actionResult:FireClient(player, false, "House access is locked while trading")
		return
	end
	if not isNearLandlord(player) then
		actionResult:FireClient(player, false, "Move closer to the Landlord before entering")
		return
	end
	local current = sessions[player]
	if current and current.OwnerUserId == player.UserId then
		sendSnapshot(player)
		return
	end
	if current then
		endSession(player, false, "Joined owned house")
	end
	local cache, reason = validateOwnerHouseEntry(player)
	if not cache then
		actionResult:FireClient(player, false, reason)
		if reason == "You don’t have a house." then
			notify(player, "House Unavailable", reason)
		end
		return
	end
	if cache.Data.HouseKind == "Physical" and cache.Data.PhysicalHouseId then
		local entered, enterMessage = enterPhysicalHouse(player, cache.Data.PhysicalHouseId, "Landlord")
		if not entered then
			actionResult:FireClient(player, false, enterMessage)
			notify(player, "House Unavailable", enterMessage)
		else
			notify(player, "House Entered", enterMessage)
		end
		return
	end
	local session = runtimeSessionsByOwnerId[player.UserId]
	if not session then
		session, reason = createRuntimeSession(player)
		if not session then
			actionResult:FireClient(player, false, reason)
			return
		end
	end
	local joined, joinReason = joinRuntimeSession(player, session)
	if not joined then
		actionResult:FireClient(player, false, joinReason)
		return
	end
	notify(player, "House Entered", "Build mode is ready.")
end

endSession = function(player, returnToWorld, reason)
	local session = sessions[player]
	if not session then
		Modules.SendState(player, {Active = false, Reason = reason})
		return
	end
	sessions[player] = nil
	session.Participants[player] = nil
	player:SetAttribute("HouseSessionActive", false)
	player:SetAttribute("HouseSessionId", nil)
	local deathConnection = session.DeathConnections[player]
	if deathConnection then
		deathConnection:Disconnect()
		session.DeathConnections[player] = nil
	end
	unseatPlayer(player)
	if returnToWorld then
		returnPlayerFromHouse(player, session)
	end
	Modules.SendState(player, {Active = false, Reason = reason})
	if next(session.Participants) then return end
	if session.ExitConnection then session.ExitConnection:Disconnect() end
	for _, entry in pairs(session.Placements) do FurnitureFunctionRegistry.Cleanup(entry) end
	if not shuttingDown and session.Owner and caches[session.Owner] == session.Cache then savePlayerData(session.Owner) end
	if session.DestroyHouseOnEnd ~= false then
		if session.House then session.House:Destroy() end
	else
		if session.PlacedFolder then session.PlacedFolder:Destroy() end
		if session.House then
			session.House:SetAttribute("RuntimeHouse", nil)
			session.House:SetAttribute("RuntimeOwnerUserId", nil)
		end
		if session.PhysicalHouseId and runtimeSessionsByPhysicalId[session.PhysicalHouseId] == session then
			runtimeSessionsByPhysicalId[session.PhysicalHouseId] = nil
		end
	end
	releaseCell(session.CellIndex)
	if runtimeSessionsByOwnerId[session.OwnerUserId] == session then runtimeSessionsByOwnerId[session.OwnerUserId] = nil end
end

local function closeOwnerRuntimeSession(owner, reason)
	local session = runtimeSessionsByOwnerId[owner.UserId]
	if not session then
		return
	end
	if session.HouseKind == "Physical" then
		if sessions[owner] == session then endSession(owner, false, reason) end
		session.Owner = nil
		return
	end
	local participants = {}
	for participant in pairs(session.Participants) do table.insert(participants, participant) end
	for _, participant in ipairs(participants) do endSession(participant, true, reason) end
end

endPreview = function(player, returnToWorld, reason, reopenLandlord)
	local preview = previewSessions[player]
	if not preview then
		housePreviewState:FireClient(player, {
			Active = false,
			Reason = reason,
			ReopenLandlord = reopenLandlord == true,
		})
		return
	end
	previewSessions[player] = nil
	player:SetAttribute("HousePreviewActive", false)
	if preview.ExitConnection then preview.ExitConnection:Disconnect() end
	if preview.DeathConnection then preview.DeathConnection:Disconnect() end
	if returnToWorld then
		teleportToLandlordReturn(player)
	end
	if preview.House then preview.House:Destroy() end
	releaseCell(preview.CellIndex)
	housePreviewState:FireClient(player, {
		Active = false,
		Reason = reason,
		ReopenLandlord = reopenLandlord == true,
	})
end

local function sendPreviewError(player, message)
	local preview = previewSessions[player]
	housePreviewState:FireClient(player, {
		Active = preview ~= nil,
		Success = false,
		Message = message,
		SelectedTemplate = preview and preview.SelectedTemplate or nil,
		OwnedHouse = caches[player] and caches[player].Data.SelectedHouse or nil,
		OwnedUpgradeStage = caches[player] and caches[player].Data.UpgradeStage or 0,
		PreviewUpgradeStage = preview and preview.UpgradeStage or 0,
		House = preview and preview.House or nil,
		IsPreview = preview ~= nil,
	})
end

local function setPreviewHouse(player, preview, template, selectedTemplate)
	local house = template:Clone()
	house.Name = ("Preview_%s_%d"):format(template.Name, player.UserId)
	house:SetAttribute("RuntimeHouse", true)
	house:SetAttribute("PreviewHouse", true)
	house:SetAttribute("OwnerUserId", player.UserId)
	house:SetAttribute("HouseTemplate", selectedTemplate)
	house:SetAttribute("SourceHouseKind", template:GetAttribute("PhysicalHouse") == true and "Physical" or "Virtual")
	house:SetAttribute("PhysicalHouseId", template:GetAttribute("PhysicalHouse") == true and tostring(template:GetAttribute("PhysicalHouseId")) or nil)
	for _, object in ipairs(house:GetDescendants()) do
		if object:IsA("ProximityPrompt") and object.Name == "PhysicalHouseDoorPrompt" then object:Destroy() end
	end
	local upgradeState = buildUpgradeState(player, selectedTemplate)
	applyUpgradeStage(house, template, upgradeState.PreviewUpgradeStage)
	-- Keep the source house's authored orientation when it is moved into a preview cell.
	local authoredPivot = template:GetPivot()
	house:PivotTo(CFrame.new(preview.CellCFrame.Position) * authoredPivot.Rotation)
	house.Parent = activeHouses

	local door = house:FindFirstChild("Door")
	local spawn = door and door:FindFirstChild("HouseSpawn")
	if not spawn or not spawn:IsA("BasePart") or not teleportCharacter(player, spawn.CFrame * CFrame.new(0, 3, 0)) then
		house:Destroy()
		return false, "Could not move your character into the house preview"
	end

	if preview.ExitConnection then
		preview.ExitConnection:Disconnect()
		preview.ExitConnection = nil
	end
	local oldHouse = preview.House
	preview.House = house
	preview.SelectedTemplate = selectedTemplate
	preview.UpgradeStage = upgradeState.PreviewUpgradeStage
	-- Preview exits use the Door's visible prompt part; HouseSpawn is teleport-only.
	local oldPreviewPrompt = door:FindFirstChild("PreviewExitHousePrompt", true)
	if oldPreviewPrompt then oldPreviewPrompt:Destroy() end
	local prompt = ensureDoorExitPrompt(door, "ExitHousePrompt", "House Preview")
	if not prompt then
		house:Destroy()
		return false, "Could not create an exit prompt for this house preview"
	end
	preview.ExitConnection = prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer == player and previewSessions[player] == preview then
			endPreview(player, true, "Left house preview", true)
		end
	end)
	if oldHouse then oldHouse:Destroy() end
	return true
end

local function beginOrSwitchPreview(player, requestedTemplate)
	if player:GetAttribute("TradingInterfaceLocked") == true then
		sendPreviewError(player, "House previews are locked while trading")
		return
	end
	if sessions[player] then
		sendPreviewError(player, "Leave your current house before previewing another style")
		return
	end
	if typeof(requestedTemplate) ~= "string" or requestedTemplate == "" then
		sendPreviewError(player, "That house style is invalid")
		return
	end
	local template, houseKind, physicalHouseId = getHouseTemplate(requestedTemplate)
	if not template then
		sendPreviewError(player, "That house style is unavailable")
		return
	end
	if houseKind == "Physical" then
		local hasDeed, deedError = playerHasPhysicalDeed(player, physicalHouseId, true)
		if not hasDeed then
			sendPreviewError(player, deedError or "You do not own the matching physical-house deed")
			return
		end
	end

	local now = os.clock()
	local playerCooldowns = cooldowns[player] or {}
	cooldowns[player] = playerCooldowns
	if now - (playerCooldowns.Preview or 0) < Config.GeneralRequestCooldown then
		sendPreviewError(player, "Please wait before changing house styles")
		return
	end
	playerCooldowns.Preview = now

	local preview = previewSessions[player]
	if not preview then
		if not isNearLandlord(player) then
			sendPreviewError(player, "Move closer to the Landlord before previewing a house")
			return
		end
		if player:GetAttribute("InventoryDataLoaded") ~= true or player:GetAttribute("HouseDataLoaded") ~= true or not caches[player] then
			sendPreviewError(player, "Your data is still loading")
			return
		end
		local cellIndex, cellCFrame = allocateCell()
		preview = {
			Id = HttpService:GenerateGUID(false),
			Player = player,
			CellIndex = cellIndex,
			CellCFrame = cellCFrame,
		}
		previewSessions[player] = preview
		player:SetAttribute("HousePreviewActive", true)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			preview.DeathConnection = humanoid.Died:Connect(function()
				if previewSessions[player] == preview then
					endPreview(player, false, "House preview ended on death", false)
				end
			end)
		end
	end

	local changed, changeError = setPreviewHouse(player, preview, template, requestedTemplate)
	if not changed then
		endPreview(player, true, changeError, true)
		return
	end
	housePreviewState:FireClient(player, {
		Active = true,
		Success = true,
		SelectedTemplate = requestedTemplate,
		OwnedHouse = caches[player] and caches[player].Data.SelectedHouse or nil,
		OwnedUpgradeStage = caches[player] and caches[player].Data.UpgradeStage or 0,
		PreviewUpgradeStage = preview.UpgradeStage or 0,
		House = preview.House,
		IsPreview = true,
		SourceHouseKind = preview.House and preview.House:GetAttribute("SourceHouseKind") or "Virtual",
	})
end

local function validRequest(player, sessionId, revision, kind)
    local cache = caches[player]
    if not cache or cache.Closing or not cache.Handle or cache.Handle.Lost or os.time() >= cache.Handle.ExpiresAt then
        return nil, "Your house save is unavailable. Please rejoin before editing."
    end
	local session = sessions[player]
	if not session or session.Id ~= sessionId then
		return nil, "Invalid or expired house session"
	end
	if session.OwnerUserId ~= player.UserId then
		return nil, "Visitors cannot edit this house"
	end
	if revision ~= session.Revision then
		return nil, "House changed. The interface has been refreshed."
	end
	if player:GetAttribute("TradingInterfaceLocked") == true then
		return nil, "House editing is locked while trading"
	end
	local now = os.clock()
	local playerCooldowns = cooldowns[player] or {}
	cooldowns[player] = playerCooldowns
	local cooldown = (kind == "Place" or kind == "Move")
		and Config.PlacementRequestCooldown
		or Config.GeneralRequestCooldown
	if now - (playerCooldowns[kind] or 0) < cooldown then
		return nil, "Please wait before trying that again"
	end
	playerCooldowns[kind] = now
	return session
end

requestEnter.OnServerEvent:Connect(function(player)
	beginSession(player)
end)

local function getVisitPermission(visitor, owner)
	if not owner or owner.Parent ~= Players then
		return false, "That player is no longer available"
	end
	if visitor == owner then
		return false, "You cannot visit your own house from Public Houses"
	end
	if owner:GetAttribute("HouseDataLoaded") ~= true or owner:GetAttribute("HouseDataLoadFailed") == true then
		return false, "That house is still loading"
	end
	local cache = caches[owner]
	if not cache then
		return false, "That house is unavailable"
	end
	initializeTaxSchedule(owner)
	if cache.Data.TaxDueAmount > 0 then
		return false, "That house is closed because its taxes are unpaid"
	end
	if typeof(cache.Data.SelectedHouse) ~= "string" or cache.Data.SelectedHouse == "" then
		return false, "That player does not have a house"
	end
	if not getHouseTemplate(cache.Data.SelectedHouse) then
		return false, "That house template is unavailable"
	end
	local access = sanitizeHouseAccess(cache.Data.HouseAccess)
	if access == "Public" then
		return true
	end

	return false, "This house is private"
end

local function buildPublicHouseList(player)
	local results = {}
	if not isNearLandlord(player) or player:GetAttribute("TradingInterfaceLocked") == true then
		return results
	end
	for _, owner in ipairs(Players:GetPlayers()) do
		if owner ~= player
			and owner:GetAttribute("HouseDataLoaded") == true
			and owner:GetAttribute("HouseDataLoadFailed") ~= true
		then
			local cache = caches[owner]
			if cache and sanitizeHouseAccess(cache.Data.HouseAccess) == "Public" then
				initializeTaxSchedule(owner)
				if cache.Data.TaxDueAmount <= 0
					and typeof(cache.Data.SelectedHouse) == "string"
					and getHouseTemplate(cache.Data.SelectedHouse)
				then
					table.insert(results, {
						UserId = owner.UserId,
						PlayerName = owner.Name,
						DisplayName = owner.DisplayName,
						HouseName = cache.Data.SelectedHouse,
					})
				end
			end
		end
	end
	table.sort(results, function(a, b)
		return string.lower(a.PlayerName) < string.lower(b.PlayerName)
	end)
	return results
end

getPublicHouseList.OnServerInvoke = function(player)
	return buildPublicHouseList(player)
end

requestVisitHouse.OnServerEvent:Connect(function(player, ownerUserId)
	if typeof(ownerUserId) ~= "number" or ownerUserId ~= math.floor(ownerUserId) then
		return
	end
	if player:GetAttribute("TradingInterfaceLocked") == true then
		visitHouseResult:FireClient(player, false, "House access is locked while trading")
		return
	end
	if previewSessions[player] then
		visitHouseResult:FireClient(player, false, "Leave the house preview before visiting")
		return
	end
	if not isNearLandlord(player) then
		visitHouseResult:FireClient(player, false, "Move closer to the Landlord before visiting")
		return
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local allowed, reason = getVisitPermission(player, owner)
	if not allowed then
		visitHouseResult:FireClient(player, false, reason)
		notify(player, "House Visit Denied", reason)
		return
	end
	local ownerCache = caches[owner]
	if ownerCache and ownerCache.Data.HouseKind == "Physical" and ownerCache.Data.PhysicalHouseId then
		local entered, enterMessage = enterPhysicalHouse(player, ownerCache.Data.PhysicalHouseId, "LandlordPublicList")
		visitHouseResult:FireClient(player, entered, enterMessage)
		if entered then notify(player, "House Visit", enterMessage) else notify(player, "House Visit Denied", enterMessage) end
		return
	end
	local current = sessions[player]
	if current and current.Owner == owner then
		sendSnapshot(player)
		visitHouseResult:FireClient(player, true, "You are already visiting " .. owner.Name .. "'s house")
		return
	end
	if current then
		endSession(player, false, "Visiting another house")
	end
	local session = runtimeSessionsByOwnerId[owner.UserId]
	if not session then
		session, reason = createRuntimeSession(owner)
		if not session then
			visitHouseResult:FireClient(player, false, reason)
			return
		end
	end
	local joined, joinReason = joinRuntimeSession(player, session)
	if not joined then
		visitHouseResult:FireClient(player, false, joinReason)
		return
	end
	local message = ("Visiting %s's house."):format(owner.Name)
	visitHouseResult:FireClient(player, true, message)
	notify(player, "House Visit", message)
end)

requestSetHouseAccess.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	local cache = Modules.WritableCache(player)
	if not session or session.Owner ~= player or not cache then
		houseAccessState:FireClient(player, false, nil, "Only the house owner can change house access")
		return
	end
	if player:GetAttribute("TradingInterfaceLocked") == true then
		houseAccessState:FireClient(player, false, nil, "House access is locked while trading")
		return
	end
	local current = sanitizeHouseAccess(cache.Data.HouseAccess)
	local currentIndex = table.find(HOUSE_ACCESS_ORDER, current) or 1
	local nextAccess = HOUSE_ACCESS_ORDER[(currentIndex % #HOUSE_ACCESS_ORDER) + 1]
	local previous = cache.Data.HouseAccess
	cache.Data.HouseAccess = nextAccess
	scheduleSave(player)
	local saved = savePlayerData(player)
	if not saved then
		cache.Data.HouseAccess = previous
		scheduleSave(player)
		houseAccessState:FireClient(player, false, sanitizeHouseAccess(previous), "Could not save house access")
		return
	end
	sendSnapshot(player)
	houseAccessState:FireClient(player, true, nextAccess, "House access set to " .. string.upper(nextAccess))
	notify(player, "House Access", "House access set to " .. string.upper(nextAccess) .. ".")
end)

getHousePurchaseCatalog.OnServerInvoke = function(player)
	local cache = caches[player]
	local styles = getPurchaseCatalogStyles(player)
	local firstAvailableStyle = styles[1] and styles[1].TemplateName or nil
	return {
		Currency = Config.HouseCurrency,
		-- Never advertise a deleted DefaultHouse. The first ordered valid style is the preview fallback.
		DefaultStyle = firstAvailableStyle,
		OwnedHouse = cache and cache.Data.SelectedHouse or nil,
		OwnedUpgradeStage = cache and cache.Data.UpgradeStage or 0,
		Styles = styles,
	}
end


getHouseTaxStatus.OnServerInvoke = function(player)
	if player:GetAttribute("HouseDataLoaded") ~= true or not caches[player] then
		return {
			Loaded = false,
			Currency = Config.HouseCurrency,
		}
	end
	return buildTaxStatus(player)
end

local function canManageHouseTaxes(player)
	if player:GetAttribute("TradingInterfaceLocked") == true then
		return nil, "House taxes are locked while trading"
	end
	if player:GetAttribute("InventoryDataLoaded") ~= true or player:GetAttribute("HouseDataLoaded") ~= true then
		return nil, "Your data is still loading"
	end
	local cache = Modules.WritableCache(player)
	if not cache then
		return nil, "House data is unavailable"
	end
	initializeTaxSchedule(player)
	local status = buildTaxStatus(player)
	if not status.HasHouse then
		return nil, "You don't have a house"
	end
	return cache, status
end

requestAddTaxReserve.OnServerEvent:Connect(function(player)
	if taxOperationBusy[player] then
		sendTaxState(player, false, "Please wait for your previous tax request")
		return
	end
	local cache, statusOrMessage = canManageHouseTaxes(player)
	if not cache then
		sendTaxState(player, false, statusOrMessage)
		return
	end
	local status = statusOrMessage
	local amount = status.WeeklyTax
	if amount <= 0 then
		sendTaxState(player, false, "This house does not require a weekly tax")
		return
	end

	taxOperationBusy[player] = true
	local removed, removeError = WarehouseService:RemoveItem(player, Config.HouseCurrency, amount, "HouseTaxReserve")
	if not removed then
		taxOperationBusy[player] = nil
		sendTaxState(player, false, removeError or "Not enough Imperial Credits in Warehouse")
		return
	end

	cache.Data.TaxReserve += amount
	scheduleSave(player)
	local saved = savePlayerData(player)
	if not saved then
		cache.Data.TaxReserve -= amount
		scheduleSave(player)
		local refunded, refundError = WarehouseService:AddItem(player, Config.HouseCurrency, amount, "HouseTaxReserveRollback")
		if not refunded then
			warn(("[House] Could not roll back tax reserve for %s: %s"):format(player.Name, tostring(refundError)))
		end
		inventorySaveRequest:Fire(player)
		taxOperationBusy[player] = nil
		sendTaxState(player, false, "Could not save your tax reserve. Your credits were returned.")
		return
	end

	inventorySaveRequest:Fire(player)
	taxOperationBusy[player] = nil
	notify(player, "Tax Reserve", ("%d %s added to your tax reserve."):format(amount, Config.HouseCurrency))
	sendTaxState(player, true, ("Added %d %s to your tax reserve."):format(amount, Config.HouseCurrency))
end)

requestPayHouseTax.OnServerEvent:Connect(function(player)
	if taxOperationBusy[player] then
		sendTaxState(player, false, "Please wait for your previous tax request")
		return
	end
	local cache, statusOrMessage = canManageHouseTaxes(player)
	if not cache then
		sendTaxState(player, false, statusOrMessage)
		return
	end
	local status = statusOrMessage
	local amount = status.TaxDueAmount
	if amount <= 0 then
		sendTaxState(player, false, "You have no house tax due")
		return
	end
	if cache.Data.TaxReserve < amount then
		sendTaxState(player, false, "Your tax reserve does not have enough Imperial Credits")
		return
	end

	taxOperationBusy[player] = true
	local oldReserve = cache.Data.TaxReserve
	local oldDue = cache.Data.TaxDueAmount
	local oldNextDue = cache.Data.NextTaxDueAt
	cache.Data.TaxReserve -= amount
	cache.Data.TaxDueAmount = 0
	cache.Data.NextTaxDueAt = os.time() + Config.TaxIntervalSeconds
	scheduleSave(player)
	local saved = savePlayerData(player)
	if not saved then
		cache.Data.TaxReserve = oldReserve
		cache.Data.TaxDueAmount = oldDue
		cache.Data.NextTaxDueAt = oldNextDue
		scheduleSave(player)
		taxOperationBusy[player] = nil
		sendTaxState(player, false, "Could not save your tax payment. No tax payment was applied.")
		return
	end

	taxOperationBusy[player] = nil
	notify(player, "House Taxes Paid", ("Paid %d %s from your tax reserve."):format(amount, Config.HouseCurrency))
	sendTaxState(player, true, "House taxes paid. Your house entry is restored.")
end)

requestHousePreview.OnServerEvent:Connect(function(player, requestedTemplate)
	-- Supports clients that still have the old configured default cached after its template was removed.
	if requestedTemplate == Config.DefaultHouse and not getHouseTemplate(requestedTemplate) then
		local styles = getPurchaseCatalogStyles(player)
		requestedTemplate = styles[1] and styles[1].TemplateName or nil
	end
	beginOrSwitchPreview(player, requestedTemplate)
end)

requestExitHousePreview.OnServerEvent:Connect(function(player)
	if previewSessions[player] then
		endPreview(player, true, "Left house preview", true)
	end
end)

requestAddHousePreviewUpgrade.OnServerEvent:Connect(function(player, requestedTemplate, requestedUpgradeId)
	local preview = previewSessions[player]
	if player:GetAttribute("TradingInterfaceLocked") == true then
		sendPreviewError(player, "House expansions are locked while trading")
		return
	end
	if player:GetAttribute("InventoryDataLoaded") ~= true or player:GetAttribute("HouseDataLoaded") ~= true then
		sendPreviewError(player, "Your data is still loading")
		return
	end
	if typeof(requestedTemplate) ~= "string"
		or requestedTemplate == ""
		or typeof(requestedUpgradeId) ~= "string"
		or requestedUpgradeId == ""
	then
		sendPreviewError(player, "That expansion request is invalid")
		return
	end
	if not preview or preview.SelectedTemplate ~= requestedTemplate or not preview.House or not preview.House.Parent then
		sendPreviewError(player, "Preview that house style before adding an expansion")
		return
	end

	local cache = caches[player]
	if not cache then
		sendPreviewError(player, "House data is unavailable")
		return
	end
	if cache.Data.SelectedHouse == requestedTemplate then
		sendPreviewError(player, "Use the paid expansion option for your currently owned house")
		return
	end

	local template = getHouseTemplate(requestedTemplate)
	if not template then
		sendPreviewError(player, "That house style is unavailable")
		return
	end
	local definitions = getUpgradeDefinitions(template, true)
	local requestedDefinition
	for _, definition in ipairs(definitions) do
		if definition.Id == requestedUpgradeId then
			requestedDefinition = definition
			break
		end
	end
	if not requestedDefinition then
		sendPreviewError(player, "That expansion is unavailable")
		return
	end

	local currentStage = math.max(0, math.floor(tonumber(preview.UpgradeStage) or 0))
	if requestedDefinition.Order <= currentStage then
		sendPreviewError(player, requestedDefinition.DisplayName .. " is already added")
		return
	end
	if requestedDefinition.Order ~= currentStage + 1 then
		local nextDefinition = definitions[currentStage + 1]
		local requirement = nextDefinition and nextDefinition.DisplayName or ("Expansion " .. tostring(currentStage + 1))
		sendPreviewError(player, "Add " .. requirement .. " first")
		return
	end

	local now = os.clock()
	local playerCooldowns = cooldowns[player] or {}
	cooldowns[player] = playerCooldowns
	if now - (playerCooldowns.PreviewUpgrade or 0) < Config.GeneralRequestCooldown then
		sendPreviewError(player, "Please wait before adding another preview expansion")
		return
	end
	playerCooldowns.PreviewUpgrade = now

	applyUpgradeStage(preview.House, template, requestedDefinition.Order)
	preview.UpgradeStage = requestedDefinition.Order
	housePreviewState:FireClient(player, {
		Active = true,
		Success = true,
		Message = requestedDefinition.DisplayName .. " added to preview.",
		SelectedTemplate = template.Name,
		OwnedHouse = cache.Data.SelectedHouse,
		OwnedUpgradeStage = cache.Data.UpgradeStage,
		PreviewUpgradeStage = preview.UpgradeStage,
	})
end)

local function sendUpgradePurchaseResult(player, success, message, selectedTemplate)
	houseUpgradePurchaseResult:FireClient(
		player,
		success,
		message,
		buildUpgradeState(player, selectedTemplate)
	)
end

requestPurchaseHouseUpgrade.OnServerEvent:Connect(function(player, requestedTemplate, requestedUpgradeId)
	local preview = previewSessions[player]
	local selectedTemplate = preview and preview.SelectedTemplate or requestedTemplate
	if upgradeOperationBusy[player] then
		sendUpgradePurchaseResult(player, false, "Please wait for your previous expansion request", selectedTemplate)
		return
	end
	if player:GetAttribute("TradingInterfaceLocked") == true then
		sendUpgradePurchaseResult(player, false, "House expansions are locked while trading", selectedTemplate)
		return
	end
	if player:GetAttribute("InventoryDataLoaded") ~= true or player:GetAttribute("HouseDataLoaded") ~= true then
		sendUpgradePurchaseResult(player, false, "Your data is still loading", selectedTemplate)
		return
	end
	if typeof(requestedTemplate) ~= "string"
		or requestedTemplate == ""
		or typeof(requestedUpgradeId) ~= "string"
		or requestedUpgradeId == ""
	then
		sendUpgradePurchaseResult(player, false, "That expansion request is invalid", selectedTemplate)
		return
	end
	if not preview or preview.SelectedTemplate ~= requestedTemplate then
		sendUpgradePurchaseResult(player, false, "Preview your owned house before purchasing an expansion", selectedTemplate)
		return
	end

	local cache = Modules.WritableCache(player)
	if not cache then
		sendUpgradePurchaseResult(player, false, "House data is unavailable", requestedTemplate)
		return
	end
	if cache.Data.SelectedHouse ~= requestedTemplate then
		sendUpgradePurchaseResult(player, false, "Expansions can only be purchased for your currently owned house", requestedTemplate)
		return
	end

	initializeTaxSchedule(player)
	if cache.Data.TaxDueAmount > 0 then
		sendUpgradePurchaseResult(player, false, "Pay your outstanding house taxes before purchasing an expansion", requestedTemplate)
		return
	end

	local template = getHouseTemplate(requestedTemplate)
	if not template then
		sendUpgradePurchaseResult(player, false, "That house style is unavailable", requestedTemplate)
		return
	end
	local definitions = getUpgradeDefinitions(template, true)
	local requestedDefinition
	for _, definition in ipairs(definitions) do
		if definition.Id == requestedUpgradeId then
			requestedDefinition = definition
			break
		end
	end
	if not requestedDefinition then
		sendUpgradePurchaseResult(player, false, "That expansion is unavailable", requestedTemplate)
		return
	end

	local currentStage = cache.Data.UpgradeStage
	if requestedDefinition.Order <= currentStage then
		sendUpgradePurchaseResult(player, false, requestedDefinition.DisplayName .. " is already owned", requestedTemplate)
		return
	end
	if requestedDefinition.Order ~= currentStage + 1 then
		local previous = definitions[currentStage + 1]
		local requirement = previous and previous.DisplayName or ("Expansion " .. tostring(currentStage + 1))
		sendUpgradePurchaseResult(player, false, "Purchase " .. requirement .. " first", requestedTemplate)
		return
	end

	local now = os.clock()
	local playerCooldowns = cooldowns[player] or {}
	cooldowns[player] = playerCooldowns
	if now - (playerCooldowns.UpgradePurchase or 0) < Config.GeneralRequestCooldown then
		sendUpgradePurchaseResult(player, false, "Please wait before purchasing another expansion", requestedTemplate)
		return
	end
	playerCooldowns.UpgradePurchase = now
	upgradeOperationBusy[player] = true

	local cost = requestedDefinition.Cost
	if cost > 0 then
		local removed, removeError = WarehouseService:RemoveItem(
			player,
			Config.HouseCurrency,
			cost,
			"HouseExpansionPurchase"
		)
		if not removed then
			upgradeOperationBusy[player] = nil
			sendUpgradePurchaseResult(
				player,
				false,
				removeError or ("Not enough %s in Warehouse"):format(Config.HouseCurrency),
				requestedTemplate
			)
			return
		end
	end

	local oldStage = cache.Data.UpgradeStage
	cache.Data.UpgradeStage = requestedDefinition.Order
	scheduleSave(player)
	local saved = savePlayerData(player)
	if not saved then
		cache.Data.UpgradeStage = oldStage
		scheduleSave(player)
		if cost > 0 then
			local refunded, refundError = WarehouseService:AddItem(
				player,
				Config.HouseCurrency,
				cost,
				"HouseExpansionRefund"
			)
			if not refunded then
				warn(("[House] Could not refund %d %s to %s after expansion save failure: %s"):format(
					cost,
					Config.HouseCurrency,
					player.Name,
					tostring(refundError)
				))
			end
			inventorySaveRequest:Fire(player)
		end
		upgradeOperationBusy[player] = nil
		sendUpgradePurchaseResult(player, false, "Could not save the expansion. Your credits were returned.", requestedTemplate)
		return
	end

	if cost > 0 then
		inventorySaveRequest:Fire(player)
	end
	local activePreview = previewSessions[player]
	if activePreview == preview and preview.House and preview.House.Parent then
		applyUpgradeStage(preview.House, template, requestedDefinition.Order)
		preview.UpgradeStage = requestedDefinition.Order
	end
	upgradeOperationBusy[player] = nil

	local message = ("You purchased %s for %s"):format(requestedDefinition.DisplayName, requestedTemplate)
	sendUpgradePurchaseResult(player, true, message, requestedTemplate)
	notify(player, "House Expanded", message .. ".")
end)

requestPurchaseHouse.OnServerEvent:Connect(function(player, requestedTemplate)
	if player:GetAttribute("TradingInterfaceLocked") == true then
		housePurchaseResult:FireClient(player, false, "House access is locked while trading")
		return
	end
	if sessions[player] then
		housePurchaseResult:FireClient(player, false, "Leave your current house before buying another one")
		return
	end
	local preview = previewSessions[player]
	if not preview then
		housePurchaseResult:FireClient(player, false, "Start a house preview before buying")
		return
	end
	if typeof(requestedTemplate) ~= "string"
		or requestedTemplate == ""
		or preview.SelectedTemplate ~= requestedTemplate
	then
		housePurchaseResult:FireClient(player, false, "The selected style does not match your active preview")
		return
	end
	if player:GetAttribute("InventoryDataLoaded") ~= true or player:GetAttribute("HouseDataLoaded") ~= true then
		housePurchaseResult:FireClient(player, false, "Your data is still loading")
		return
	end

	local now = os.clock()
	local playerCooldowns = cooldowns[player] or {}
	cooldowns[player] = playerCooldowns
	if now - (playerCooldowns.Purchase or 0) < Config.GeneralRequestCooldown then
		housePurchaseResult:FireClient(player, false, "Please wait before buying")
		return
	end
	playerCooldowns.Purchase = now

	local cache = Modules.WritableCache(player)
	if not cache then
		housePurchaseResult:FireClient(player, false, "House data is unavailable")
		return
	end

	local template, houseKind, physicalHouseId = getHouseTemplate(requestedTemplate)
	if not template then
		housePurchaseResult:FireClient(player, false, "That house style is unavailable")
		return
	end
	if houseKind == "Physical" then
		local hasDeed, deedError = playerHasPhysicalDeed(player, physicalHouseId, true)
		if not hasDeed then
			housePurchaseResult:FireClient(player, false, deedError or "You do not own the matching physical-house deed")
			return
		end
	end
	initializeTaxSchedule(player)
	if cache.Data.TaxDueAmount > 0 then
		housePurchaseResult:FireClient(player, false, "Pay your outstanding house taxes before changing houses")
		return
	end
	local definitions = getUpgradeDefinitions(template, true)
	local selectedUpgradeStage = math.max(0, math.floor(tonumber(preview.UpgradeStage) or 0))
	-- A house that is already active cannot be bought again. The only allowed follow-up is a preview containing a new expansion.
	if cache.Data.SelectedHouse == requestedTemplate and selectedUpgradeStage <= cache.Data.UpgradeStage then
		housePurchaseResult:FireClient(player, false, "You already own this house. Add an available expansion before buying again.")
		return
	end
	if selectedUpgradeStage > #definitions then
		housePurchaseResult:FireClient(player, false, "The selected expansion package is no longer available")
		return
	end
	local houseCost = houseKind == "Physical"
		and 0
		or math.max(0, math.floor(tonumber(template:GetAttribute("PurchaseCost")) or 0))
	local expansionCost = 0
	for _, definition in ipairs(definitions) do
		if definition.Order <= selectedUpgradeStage then
			expansionCost += definition.Cost
		end
	end
	local cost = houseCost + expansionCost
	local replacingHouse = typeof(cache.Data.SelectedHouse) == "string" and cache.Data.SelectedHouse ~= ""

	if cost > 0 then
		local removed, removeError = WarehouseService:RemoveItem(player, Config.HouseCurrency, cost, "HousePurchase")
		if not removed then
			housePurchaseResult:FireClient(player, false, removeError or "Not enough Imperial Credits in warehouse")
			return
		end
	end

	local furnitureToStore = {}
	for _, placement in ipairs(cache.Data.Placements) do
		furnitureToStore[placement.ItemName] = (furnitureToStore[placement.ItemName] or 0) + 1
	end
	local storedFurniture = {}
	for itemName, amount in pairs(furnitureToStore) do
		local stored, storeError = WarehouseService:AddItem(player, itemName, amount, "HouseStyleReplacement")
		if not stored then
			for storedItem, storedAmount in pairs(storedFurniture) do
				local rolledBack, rollbackError = WarehouseService:RemoveItem(
					player,
					storedItem,
					storedAmount,
					"HouseStyleReplacementRollback"
				)
				if not rolledBack then
					warn(("[House] Could not roll back %d %s for %s: %s"):format(
						storedAmount,
						storedItem,
						player.Name,
						tostring(rollbackError)
					))
				end
			end
			if cost > 0 then
				local refunded, refundError = WarehouseService:AddItem(
					player,
					Config.HouseCurrency,
					cost,
					"HousePurchaseRefund"
				)
				if not refunded then
					warn(("[House] Could not refund %d %s to %s: %s"):format(
						cost,
						Config.HouseCurrency,
						player.Name,
						tostring(refundError)
					))
				end
			end
			inventorySaveRequest:Fire(player)
			housePurchaseResult:FireClient(
				player,
				false,
				storeError or "Placed furniture could not be returned to Warehouse"
			)
			return
		end
		storedFurniture[itemName] = amount
	end

	local previousPhysicalId = cache.Data.HouseKind == "Physical" and cache.Data.PhysicalHouseId or nil
	if previousPhysicalId then closePhysicalRuntimeSession(previousPhysicalId, "Physical house style changed") end
	cache.Data.SelectedHouse = requestedTemplate
	cache.Data.HouseKind = houseKind == "Physical" and "Physical" or "Virtual"
	cache.Data.PhysicalHouseId = houseKind == "Physical" and physicalHouseId or nil
	cache.Data.Placements = {}
	cache.Data.UpgradeStage = selectedUpgradeStage
	if previousPhysicalId and previousPhysicalId ~= physicalHouseId then
		pcall(function()
			MessagingService:PublishAsync(PHYSICAL_HOUSE_MESSAGE_TOPIC, {
				PhysicalHouseId = previousPhysicalId,
				OwnerUserId = player.UserId,
				Revision = cache.Data.Revision + 1,
				JobId = game.JobId,
				Reason = "StyleChanged",
			})
		end)
	end
	if not replacingHouse then
		cache.Data.TaxDueAmount = 0
		cache.Data.NextTaxDueAt = os.time() + Config.TaxIntervalSeconds
	end
	scheduleSave(player)
	savePlayerData(player)
	inventorySaveRequest:Fire(player)
	endPreview(player, true, "House purchased", true)
	local expansionSuffix = selectedUpgradeStage > 0
		and (" with %d expansion%s"):format(selectedUpgradeStage, selectedUpgradeStage == 1 and "" or "s")
		or ""
	local styleDisplayName = getStyleDisplayName(template)
	local message = replacingHouse
		and ("You replaced your house with %s%s"):format(styleDisplayName, expansionSuffix)
		or (houseKind == "Physical"
			and ("You activated %s%s"):format(styleDisplayName, expansionSuffix)
			or ("You bought the %s%s"):format(styleDisplayName, expansionSuffix))
	housePurchaseResult:FireClient(player, true, message, requestedTemplate, selectedUpgradeStage)
	notify(player, "House Purchased", message .. ".")
end)

requestExit.OnServerEvent:Connect(function(player, sessionId)
	local session = sessions[player]
	if session and session.Id == sessionId then
		endSession(player, true, "Left house")
	end
end)

requestPlace.OnServerEvent:Connect(function(player, sessionId, revision, itemName, desiredPosition, surfaceNormal, rotationDegrees)
	local session, requestError = validRequest(player, sessionId, revision, "Place")
	if not session then
		actionResult:FireClient(player, false, requestError, buildSnapshot(player))
		return
	end
	if #caches[player].Data.Placements >= Config.MaximumFurniture then
		actionResult:FireClient(player, false, "This house already has 100 furniture pieces", buildSnapshot(player))
		return
	end
	local template = findFurnitureTemplate(itemName)
	if not template then
		actionResult:FireClient(player, false, "That furniture template is unavailable", buildSnapshot(player))
		return
	end
	local available, amountError = InventoryService:GetSpendableAmount(player, itemName)
	if not available or available < 1 then
		actionResult:FireClient(player, false, amountError or "No unreserved copy is available", buildSnapshot(player))
		return
	end
	local craftedRecord = findCraftedFurnitureRecord(player, itemName, nil, "Inventory")
	local craftedFinish = craftedFinishFromRecord(craftedRecord)
	local model, finalCFrame, placementError = preparePlacement(session, template, desiredPosition, surfaceNormal, rotationDegrees)
	if not model then
		actionResult:FireClient(player, false, placementError, buildSnapshot(player))
		return
	end
	local removed, removeError = InventoryService:RemoveItem(player, itemName, 1, "HousePlacement")
	if not removed then
		model:Destroy()
		actionResult:FireClient(player, false, removeError, buildSnapshot(player))
		return
	end
	local placementId = HttpService:GenerateGUID(false)
	if craftedFinish then
		applyCraftedFurnitureFinish(model, craftedFinish)
		craftedRecord:SetAttribute("Location", "Placed")
		craftedRecord:SetAttribute("PlacementId", placementId)
	end
	local record = {
		PlacementId = placementId,
		ItemName = itemName,
		LocalCFrame = encodeCFrame(session.House:GetPivot():ToObjectSpace(finalCFrame)),
		FunctionState = {},
		CraftedRecordId = craftedRecord and craftedRecord.Name or nil,
		CraftedFinish = craftedFinish,
	}
	model.Name = "Placed_" .. itemName
	model:SetAttribute("PlacementId", placementId)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("ItemName", itemName)
	model.Parent = session.PlacedFolder
	table.insert(caches[player].Data.Placements, record)
	session.Placements[placementId] = {Model = model, Record = record}
	mountPlacementFunction(player, session, session.Placements[placementId])
	session.Revision += 1
	scheduleSave(player)
	inventorySaveRequest:Fire(player)
	sendSnapshot(player, itemName .. " placed")
end)

requestMove.OnServerEvent:Connect(function(player, sessionId, revision, placementId, desiredPosition, surfaceNormal, rotationDegrees)
	local session, requestError = validRequest(player, sessionId, revision, "Move")
	if not session then
		actionResult:FireClient(player, false, requestError, buildSnapshot(player))
		return
	end
	local entry = session.Placements[placementId]
	if not entry then
		actionResult:FireClient(player, false, "That furniture piece no longer exists", buildSnapshot(player))
		return
	end
	if isFurnitureOccupied(entry.Model) then
		actionResult:FireClient(player, false, "This furniture is occupied. Ask the player to stand up first.", buildSnapshot(player))
		return
	end
	local template = findFurnitureTemplate(entry.Record.ItemName)
	if not template then
		actionResult:FireClient(player, false, "That furniture template is unavailable", buildSnapshot(player))
		return
	end
	local model, finalCFrame, moveError = preparePlacement(session, template, desiredPosition, surfaceNormal, rotationDegrees, entry.Model)
	if not model then
		actionResult:FireClient(player, false, moveError, buildSnapshot(player))
		return
	end
	Modules.History.Record(session, placementId, entry.Model:GetPivot(), finalCFrame, Config.MoveHistoryLimit)
	entry.Model:PivotTo(finalCFrame)
	model:Destroy()
	entry.Record.LocalCFrame = encodeCFrame(session.House:GetPivot():ToObjectSpace(finalCFrame))
	session.Revision += 1
	scheduleSave(player)
	sendSnapshot(player, entry.Record.ItemName .. " moved")
end)

requestStore.OnServerEvent:Connect(function(player, sessionId, revision, placementId)
	local session, requestError = validRequest(player, sessionId, revision, "Store")
	if not session then
		actionResult:FireClient(player, false, requestError, buildSnapshot(player))
		return
	end
	local entry = session.Placements[placementId]
	if not entry then
		actionResult:FireClient(player, false, "That furniture piece no longer exists", buildSnapshot(player))
		return
	end
	if isFurnitureOccupied(entry.Model) then
		actionResult:FireClient(player, false, "This furniture is occupied. Ask the player to stand up first.", buildSnapshot(player))
		return
	end
	local added, addError = InventoryService:AddItem(player, entry.Record.ItemName, 1, "HouseStorage", {
		EnforceCapacity = false,
	})
	if not added then
		actionResult:FireClient(player, false, addError or "Furniture could not be returned", buildSnapshot(player))
		return
	end
	if entry.Record.CraftedRecordId then
		local craftedRecord = findCraftedFurnitureRecord(player, entry.Record.ItemName, entry.Record.CraftedRecordId)
		if craftedRecord then
			craftedRecord:SetAttribute("Location", "Inventory")
			craftedRecord:SetAttribute("PlacementId", nil)
		end
	end
	local _, recordIndex = findPlacementRecord(caches[player], placementId)
	if recordIndex then
		table.remove(caches[player].Data.Placements, recordIndex)
	end
	Modules.History.Remove(session, placementId)
	FurnitureFunctionRegistry.Cleanup(entry)
	entry.Model:Destroy()
	session.Placements[placementId] = nil
	session.Revision += 1
	scheduleSave(player)
	inventorySaveRequest:Fire(player)
	sendSnapshot(player, entry.Record.ItemName .. " returned to Inventory")
end)

Modules.HistoryRemote = remotes:FindFirstChild("RequestMoveHistory") or Instance.new("RemoteEvent")
Modules.HistoryRemote.Name = "RequestMoveHistory"
Modules.HistoryRemote.Parent = remotes
Modules.HistoryRemote.OnServerEvent:Connect(function(player, sessionId, revision, action)
    local session, reason = validRequest(player, sessionId, revision, "History")
    if not session or (action ~= "Undo" and action ~= "Redo") then
        actionResult:FireClient(player, false, reason or "Invalid history action", buildSnapshot(player))
        return
    end
    local item = Modules.History.Peek(session, action)
    local entry = item and session.Placements[item.PlacementId]
    if not entry then actionResult:FireClient(player, false, "There is no move to " .. string.lower(action), buildSnapshot(player)); return end
    if isFurnitureOccupied(entry.Model) then actionResult:FireClient(player, false, "This furniture is occupied.", buildSnapshot(player)); return end
    local expected = action == "Undo" and item.After or item.Before
    local actualComponents, expectedComponents = {entry.Model:GetPivot():GetComponents()}, {expected:GetComponents()}
    local matches = true
    for i, value in ipairs(actualComponents) do if math.abs(value - expectedComponents[i]) > 0.001 then matches = false; break end end
    if not matches then
        Modules.History.Remove(session, item.PlacementId)
        actionResult:FireClient(player, false, "That furniture changed. Its old move history was cleared.", buildSnapshot(player))
        return
    end
    local target = action == "Undo" and item.Before or item.After
    local template = findFurnitureTemplate(entry.Record.ItemName)
    if not template then actionResult:FireClient(player, false, "Furniture template is unavailable."); return end
    local probe = sanitizeFurnitureClone(template)
    probe:PivotTo(target)
    local fits, errorText = Modules.Geometry.ValidateModel(probe, session.BoundsFolder, session.UpgradeStage)
    probe:Destroy()
    if not fits then actionResult:FireClient(player, false, errorText, buildSnapshot(player)); return end
    entry.Model:PivotTo(target)
    entry.Record.LocalCFrame = encodeCFrame(session.House:GetPivot():ToObjectSpace(target))
    Modules.History.Commit(session, action)
    session.Revision += 1
    scheduleSave(player)
    sendSnapshot(player, action .. " move: " .. entry.Record.ItemName)
end)

requestSnapshot.OnServerInvoke = function(player, sessionId)
	local session = sessions[player]
	if not session or (sessionId and session.Id ~= sessionId) then
		return {Active = false}
	end
	return buildSnapshot(player)
end

local function returnTransferredFurnitureOffline(ownerUserId, placements, transactionId)
	local totals = {}
	for _, placement in ipairs(placements or {}) do
		if findFurnitureTemplate(placement.ItemName) then totals[placement.ItemName] = (totals[placement.ItemName] or 0) + 1 end
	end
	local ok, updateError = pcall(function()
		inventoryStore:UpdateAsync("Player_" .. tostring(ownerUserId), function(raw)
			raw = typeof(raw) == "table" and raw or {Version = 5, Materials = {}, Warehouse = {}}
			raw.Warehouse = typeof(raw.Warehouse) == "table" and raw.Warehouse or {}
			raw.WarehouseOrder = typeof(raw.WarehouseOrder) == "table" and raw.WarehouseOrder or {}
			raw.PhysicalDeedTransferReceipts = typeof(raw.PhysicalDeedTransferReceipts) == "table" and raw.PhysicalDeedTransferReceipts or {}
			if raw.PhysicalDeedTransferReceipts[transactionId] then return raw end
			local order = sanitizeTaxAmount(raw.WarehouseOrderCounter)
			for itemName, amount in pairs(totals) do
				raw.Warehouse[itemName] = math.clamp(sanitizeTaxAmount(raw.Warehouse[itemName]) + amount, 0, 2147483647)
				order += 1
				raw.WarehouseOrder[itemName] = order
			end
			raw.WarehouseOrderCounter = order
			raw.PhysicalDeedTransferReceipts[transactionId] = os.time()
			return raw
		end)
	end)
	if not ok then
		warn(("[PhysicalHouse] Could not return offline furniture for %d: %s"):format(ownerUserId, tostring(updateError)))
		return false, "Furniture could not be returned to the previous owner's Warehouse"
	end
	return true
end

local function clearTransferredPhysicalSelection(ownerUserId, physicalHouseId, transactionId)
	local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
	local cache = ownerPlayer and caches[ownerPlayer] or nil
	if cache and cache.Data.HouseKind == "Physical" and cache.Data.PhysicalHouseId == physicalHouseId then
		local stored = {}
		for _, placement in ipairs(cache.Data.Placements) do
			local added, addError = WarehouseService:AddItem(ownerPlayer, placement.ItemName, 1, "PhysicalDeedTransfer")
			if not added then
				for itemName, amount in pairs(stored) do WarehouseService:RemoveItem(ownerPlayer, itemName, amount, "PhysicalDeedTransferRollback") end
				return false, addError or "Furniture could not be returned to Warehouse"
			end
			stored[placement.ItemName] = (stored[placement.ItemName] or 0) + 1
		end
		cache.Data.SelectedHouse = nil
		cache.Data.HouseKind = "Virtual"
		cache.Data.PhysicalHouseId = nil
		cache.Data.Placements = {}
		cache.Data.UpgradeStage = 0
		cache.Data.TaxDueAmount = 0
		cache.Data.NextTaxDueAt = nil
		scheduleSave(ownerPlayer)
		if not savePlayerData(ownerPlayer) then return false, "Previous owner house data could not be saved" end
		inventorySaveRequest:Fire(ownerPlayer)
		return true
	end

	local offlineCache, _, readError = readHouseDataByUserId(ownerUserId)
	if not offlineCache then return false, readError end
	local data = offlineCache.Data
	if data.HouseKind ~= "Physical" or data.PhysicalHouseId ~= physicalHouseId then return true end
	local returned, returnError = returnTransferredFurnitureOffline(ownerUserId, data.Placements, transactionId)
	if not returned then return false, returnError end
	data.SelectedHouse = nil
	data.HouseKind = "Virtual"
	data.PhysicalHouseId = nil
	data.Placements = {}
	data.UpgradeStage = 0
	data.TaxDueAmount = 0
	data.NextTaxDueAt = nil
	return writeOfflineHouseData(ownerUserId, data)
end

reconcilePhysicalSelection = function(player)
	local cache = caches[player]
	if not cache or cache.Data.HouseKind ~= "Physical" or not cache.Data.PhysicalHouseId then return true end
	local registeredId, registryError = PhysicalDeedService:GetPlayerDeedAsync(player.UserId, true)
	if registryError then return false, registryError end
	if registeredId == cache.Data.PhysicalHouseId then return true end
	local deadline = os.clock() + 15
	while player.Parent and player:GetAttribute("InventoryDataLoaded") ~= true and os.clock() < deadline do task.wait(0.1) end
	if player:GetAttribute("InventoryDataLoaded") ~= true or player:GetAttribute("InventoryDataLoadFailed") == true then
		return false, "Inventory data is unavailable for furniture reconciliation"
	end
	return clearTransferredPhysicalSelection(
		player.UserId,
		cache.Data.PhysicalHouseId,
		"reconcile:" .. HttpService:GenerateGUID(false)
	)
end

local transferHandler = script.Parent:FindFirstChild("HandlePhysicalDeedTransfer")
if not transferHandler then
	transferHandler = Instance.new("BindableFunction")
	transferHandler.Name = "HandlePhysicalDeedTransfer"
	transferHandler.Parent = script.Parent
end
transferHandler.OnInvoke = function(previousOwnerUserId, newOwnerUserId, physicalHouseId, transactionId)
	physicalHouseId = tostring(physicalHouseId or "")
	if physicalHouseId == "" then return false, "Physical house ID is missing" end
	closePhysicalRuntimeSession(physicalHouseId, "Physical house ownership changed")
	if tonumber(previousOwnerUserId) and tonumber(previousOwnerUserId) > 0 then
		local cleared, clearError = clearTransferredPhysicalSelection(
			math.floor(tonumber(previousOwnerUserId)),
			physicalHouseId,
			tostring(transactionId or HttpService:GenerateGUID(false))
		)
		if not cleared then return false, clearError end
	end
	return true
end

function Modules.ReconcilePlacements(session, nextCache, owner)
    local desired = {}
    for _, record in ipairs(nextCache.Data.Placements) do desired[record.PlacementId] = record end
    local ownerChanged = session.Owner ~= owner
    for id, entry in pairs(session.Placements) do
        local record = desired[id]
        if not record or record.ItemName ~= entry.Record.ItemName then
            FurnitureFunctionRegistry.Cleanup(entry)
            entry.Model:Destroy()
            session.Placements[id] = nil
            Modules.History.Remove(session, id)
        end
    end
    session.Cache = nextCache
    session.Owner = owner
    session.UpgradeStage = nextCache.Data.UpgradeStage
    for id, record in pairs(desired) do
        local entry = session.Placements[id]
        if entry and entry.Model.Parent then
            local moved = not Modules.Snapshot.Equal(entry.Record.LocalCFrame, record.LocalCFrame)
            local functionChanged = not Modules.Snapshot.Equal(entry.Record.FunctionState, record.FunctionState)
            local finishChanged = not Modules.Snapshot.Equal(entry.Record.CraftedFinish, record.CraftedFinish)
            if moved then
                if isFurnitureOccupied(entry.Model) then
                    for _, seat in ipairs(entry.Model:GetDescendants()) do
                        if seat:IsA("Seat") and seat.Occupant then seat.Occupant.Sit = false end
                    end
                end
                entry.Model:PivotTo(session.House:GetPivot() * decodeCFrame(record.LocalCFrame))
                Modules.History.Remove(session, id)
            end
            if finishChanged then applyCraftedFurnitureFinish(entry.Model, record.CraftedFinish) end
            -- Preserve the Record table captured by the handler's active context.
            if entry.Record ~= record then
                for key in pairs(entry.Record) do entry.Record[key] = nil end
                for key, value in pairs(record) do entry.Record[key] = value end
            end
            desired[id] = entry.Record
            local template = findFurnitureTemplate(record.ItemName)
            if functionChanged or (ownerChanged and FurnitureFunctionRegistry.GetFunctionName(template) ~= "Seat") then
                mountPlacementFunction(owner, session, entry)
            end
        else
            local template = findFurnitureTemplate(record.ItemName)
            local valid = validateFurnitureTemplate(template)
            local localCF = decodeCFrame(record.LocalCFrame)
            if valid and localCF then
                local model = sanitizeFurnitureClone(template)
                applyCraftedFurnitureFinish(model, record.CraftedFinish)
                model:PivotTo(session.House:GetPivot() * localCF)
                model.Name = "Placed_" .. record.ItemName
                model:SetAttribute("PlacementId", id)
                model:SetAttribute("OwnerUserId", session.OwnerUserId)
                model:SetAttribute("ItemName", record.ItemName)
                model.Parent = session.PlacedFolder
                entry = {Model = model, Record = record}
                session.Placements[id] = entry
                mountPlacementFunction(owner, session, entry)
            end
        end
    end
    for i, record in ipairs(nextCache.Data.Placements) do
        nextCache.Data.Placements[i] = desired[record.PlacementId] or record
    end
end

local function refreshPhysicalRuntimeSession(physicalHouseId)
	local id = tostring(physicalHouseId or "")
	local session = runtimeSessionsByPhysicalId[id]
	if not session then return end
	local ownerRecord = PhysicalDeedService:GetOwnerAsync(id, true)
	if not ownerRecord or ownerRecord.OwnerUserId ~= session.OwnerUserId then
		closePhysicalRuntimeSession(id, "Physical house ownership changed")
		return
	end
	local refreshedCache, ownerPlayer = readHouseDataByUserId(ownerRecord.OwnerUserId)
	if not refreshedCache then closePhysicalRuntimeSession(id, "Physical house data became unavailable"); return end
	local data = refreshedCache.Data
	if data.HouseKind ~= "Physical" or data.PhysicalHouseId ~= id or data.SelectedHouse ~= "Physical:" .. id or data.TaxDueAmount > 0 then
		closePhysicalRuntimeSession(id, data.TaxDueAmount > 0 and "Physical house closed for unpaid taxes" or "Physical house is no longer active")
		return
	end
	if sanitizeTaxAmount(data.Revision) == sanitizeTaxAmount(session.Cache.Data.Revision) then return end
    Modules.ReconcilePlacements(session, refreshedCache, ownerPlayer)
	session.OwnerName = ownerPlayer and ownerPlayer.Name or ownerRecord.OwnerName
	session.Revision += 1
	for participant in pairs(session.Participants) do
		if participant.Parent == Players then Modules.SendState(participant, buildSnapshot(participant)) end
	end
end

PhysicalDeedService.Changed:Connect(function(_, physicalHouseId)
	if not physicalHouseId then return end
	physicalHouseId = tostring(physicalHouseId)
	task.defer(closePhysicalRuntimeSession, physicalHouseId, "Physical house ownership changed")
	for player, preview in pairs(previewSessions) do
		if preview.SelectedTemplate == "Physical:" .. physicalHouseId then
			task.defer(endPreview, player, true, "Physical deed ownership changed", true)
		end
	end
end)

pcall(function()
	MessagingService:SubscribeAsync(PHYSICAL_HOUSE_MESSAGE_TOPIC, function(message)
		local data = message.Data
		if typeof(data) == "table" and data.JobId ~= game.JobId and data.PhysicalHouseId then
			task.spawn(refreshPhysicalRuntimeSession, tostring(data.PhysicalHouseId))
		end
	end)
end)

local physicalPromptConnections = setmetatable({}, {__mode = "k"})

local function clearPhysicalDoorPrompts(model)
	local connections = physicalPromptConnections[model]
	if connections then
		for _, connection in ipairs(connections) do connection:Disconnect() end
		physicalPromptConnections[model] = nil
	end
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("ProximityPrompt") and (object.Name == "PhysicalHouseDoorPrompt" or object.Name == "PhysicalHouseExitPrompt") then
			object:Destroy()
		end
	end
end

local function setupPhysicalHouseDoor(model)
	clearPhysicalDoorPrompts(model)
	if not validatePhysicalHouseTemplate(model, true) then return end
	local id = tostring(model:GetAttribute("PhysicalHouseId"))
	if getPhysicalHouse(id) ~= model then return end
	local door = model:FindFirstChild("Door")
	local doorPart = door and (door:IsA("BasePart") and door or door:FindFirstChild("Door", true))
	local spawn = door and door:FindFirstChild("HouseSpawn", true)
	if not doorPart or not doorPart:IsA("BasePart") then doorPart = door and door:FindFirstChildWhichIsA("BasePart", true) end
	if not doorPart then warn("[PhysicalHouse] No prompt-bearing Door part found in " .. model:GetFullName()); return end
	if not spawn or not spawn:IsA("BasePart") then warn("[PhysicalHouse] No interior HouseSpawn found in " .. model:GetFullName()); return end

	-- Physical glass is opaque for every client by default. The occupant's client locally reveals it after entering.
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") and object.Name == "Glass" then
			object.Transparency = 0
			object.Material = Enum.Material.SmoothPlastic
		end
	end

	local function enterFromPhysicalDoor(player)
		local active = sessions[player]
		if active and active.HouseKind == "Physical" and active.PhysicalHouseId == id then
			return
		end
		local entered, message = enterPhysicalHouse(player, id, "MapDoor")
		if entered then
			notify(player, "House Entered", message)
		else
			notify(player, message == "This house is empty" and "Empty House" or "House Unavailable", message)
		end
	end

	local enterPrompt = Instance.new("ProximityPrompt")
	enterPrompt.Name = "PhysicalHouseDoorPrompt"
	enterPrompt.ActionText = "Enter House"
	enterPrompt.ObjectText = tostring(model:GetAttribute("Address"))
	enterPrompt.MaxActivationDistance = Config.InteractionDistance
	enterPrompt.RequiresLineOfSight = false
	enterPrompt.HoldDuration = 0
	enterPrompt.Parent = doorPart

	-- Both prompts attach to Door. HouseSpawn remains only the interior teleport target.
	local exitPrompt = ensureDoorExitPrompt(door, "PhysicalHouseExitPrompt", tostring(model:GetAttribute("Address")))
	if not exitPrompt then
		warn("[PhysicalHouse] No prompt-bearing Door part found in " .. model:GetFullName())
		enterPrompt:Destroy()
		return
	end
	-- The client enables this only while its player occupies this exact physical house.
	exitPrompt.Enabled = false

	physicalPromptConnections[model] = {
		enterPrompt.Triggered:Connect(enterFromPhysicalDoor),
		exitPrompt.Triggered:Connect(function(player)
			local active = sessions[player]
			if active and active.HouseKind == "Physical" and active.PhysicalHouseId == id then
				endSession(player, true, "Left physical house")
			end
		end),
	}
end

local function rebuildAndSetupPhysicalHouses()
	rebuildPhysicalHouseIndex(true)
	for id, runtime in pairs(table.clone(runtimeSessionsByPhysicalId)) do
		if validPhysicalHouses[id] ~= runtime.House then closePhysicalRuntimeSession(id, "Physical house configuration became invalid") end
	end
	for player, preview in pairs(previewSessions) do
		local previewId = typeof(preview.SelectedTemplate) == "string" and string.match(preview.SelectedTemplate, "^Physical:(.+)$") or nil
		if previewId and not validPhysicalHouses[previewId] then endPreview(player, true, "Physical house configuration became invalid", true) end
	end
	for _, model in ipairs(physicalHouses:GetChildren()) do
		if model:IsA("Model") then setupPhysicalHouseDoor(model) end
	end
end

physicalHouses.ChildAdded:Connect(function()
	task.defer(rebuildAndSetupPhysicalHouses)
end)
physicalHouses.ChildRemoved:Connect(function(child)
	local id = child:GetAttribute("PhysicalHouseId")
	if id then
		id = tostring(id)
		closePhysicalRuntimeSession(id, "Physical house was removed")
		for player, preview in pairs(previewSessions) do
			if preview.SelectedTemplate == "Physical:" .. id then endPreview(player, true, "Physical house was removed", true) end
		end
	end
	task.defer(rebuildAndSetupPhysicalHouses)
end)

local deedTemplatesFolder = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Deeds")
deedTemplatesFolder.ChildAdded:Connect(function() task.defer(rebuildAndSetupPhysicalHouses) end)
deedTemplatesFolder.ChildRemoved:Connect(function() task.defer(rebuildAndSetupPhysicalHouses) end)

local unregisterLandlordPart

local function isGenericLandlordPart(part)
	return part
		and part:IsA("BasePart")
		and part:IsDescendantOf(Workspace)
		and part.Name == LANDLORD_PART_NAME
end

local function configureLandlordPrompt(part)
	local prompt = part:FindFirstChild(LANDLORD_PROMPT_NAME)
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = LANDLORD_PROMPT_NAME
		prompt.Parent = part
	end
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Landlord"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = LANDLORD_PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = LANDLORD_PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	return prompt
end

local function isNearLandlordPart(player, part, prompt)
	local characterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return characterRoot
		and characterRoot:IsA("BasePart")
		and part
		and part:IsA("BasePart")
		and prompt
		and prompt:IsA("ProximityPrompt")
		and (characterRoot.Position - part.Position).Magnitude <= prompt.MaxActivationDistance + 2
end

local function openLandlordMenu(player, part)
	local entry = registeredLandlords[part]
	if not entry or not isNearLandlordPart(player, part, entry.Prompt) then
		return
	end
	if player:GetAttribute("TradingInterfaceLocked") == true then
		notify(player, "House Unavailable", "House access is locked while trading.")
		return
	end
	lastLandlordParts[player] = part
	openMenu:FireClient(player)
end

unregisterLandlordPart = function(part)
	local entry = registeredLandlords[part]
	if not entry then
		return
	end
	registeredLandlords[part] = nil
	for _, connection in ipairs(entry.Connections) do
		connection:Disconnect()
	end
	for player, activePart in pairs(lastLandlordParts) do
		if activePart == part then
			lastLandlordParts[player] = nil
		end
	end
end

local function registerLandlordPart(part, isLegacy)
	if (not isLegacy and not isGenericLandlordPart(part))
		or not part
		or not part:IsA("BasePart")
		or not part:IsDescendantOf(Workspace)
		or registeredLandlords[part]
	then
		return
	end

	local prompt = configureLandlordPrompt(part)
	local entry = {Prompt = prompt, Legacy = isLegacy == true, Connections = {}}
	registeredLandlords[part] = entry

	table.insert(entry.Connections, prompt.Triggered:Connect(function(player)
		openLandlordMenu(player, part)
	end))
	if not isLegacy then
		table.insert(entry.Connections, part:GetPropertyChangedSignal("Name"):Connect(function()
			if not isGenericLandlordPart(part) then
				unregisterLandlordPart(part)
			end
		end))
	end
	table.insert(entry.Connections, prompt.AncestryChanged:Connect(function()
		if prompt:IsDescendantOf(part) or not part:IsDescendantOf(Workspace) then
			return
		end
		task.defer(function()
			if registeredLandlords[part] == entry and part:IsDescendantOf(Workspace) then
				unregisterLandlordPart(part)
				registerLandlordPart(part, isLegacy)
			end
		end)
	end))
end

local legacyLandlordPart = getLegacyLandlordPart()
if legacyLandlordPart then
	registerLandlordPart(legacyLandlordPart, true)
else
	warn("[House] Legacy Workspace.Landlord.HumanoidRootPart was not found.")
end
for _, instance in ipairs(Workspace:GetDescendants()) do
	if isGenericLandlordPart(instance) then
		registerLandlordPart(instance, false)
	end
end
Workspace.DescendantAdded:Connect(function(instance)
	if isGenericLandlordPart(instance) then
		task.defer(registerLandlordPart, instance, false)
	end
end)
Workspace.DescendantRemoving:Connect(function(instance)
	if registeredLandlords[instance] then
		unregisterLandlordPart(instance)
	end
end)

houseTemplates.ChildAdded:Connect(function(child)
	task.defer(function()
		validateHouseTemplate(child, true)
		if child:IsA("Model") then
			getUpgradeDefinitions(child, true)
		end
	end)
end)

houseTemplates.ChildRemoved:Connect(function(child)
	if not child:IsA("Model") then return end
	local affectedOwners = {}
	for _, session in pairs(runtimeSessionsByOwnerId) do
		if session.HouseName == child.Name then
			table.insert(affectedOwners, session.Owner)
		end
	end
	for _, owner in ipairs(affectedOwners) do
		closeOwnerRuntimeSession(owner, "House template was removed")
	end
	for player, preview in pairs(previewSessions) do
		if preview.SelectedTemplate == child.Name then
			endPreview(player, true, "House preview template was removed", true)
		end
	end
end)

local function setupPlayer(player)
	task.spawn(loadPlayerData, player)
	task.spawn(function()
		while player.Parent and not shuttingDown do
			task.wait(Config.TaxCheckInterval)
			if caches[player] and initializeTaxSchedule(player) then
				sendTaxState(player, true, "Your house tax status was updated.")
			end
		end
	end)
	player:GetAttributeChangedSignal("TradingInterfaceLocked"):Connect(function()
		if player:GetAttribute("TradingInterfaceLocked") == true then
			if sessions[player] then
				endSession(player, true, "House session closed while trading")
			end
			if previewSessions[player] then
				endPreview(player, true, "House preview closed while trading", false)
			end
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	closeOwnerRuntimeSession(player, "House owner left")
	endSession(player, false, "Player left")
	endPreview(player, false, "Player left", false)
	Modules.Leaving[player] = true
    local cache = caches[player]
    if cache then cache.Closing = true end
    local saved = Modules.FlushPlayer(player, true)
    if saved then caches[player] = nil; Modules.Leaving[player] = nil end
    Modules.Streams[player] = nil
	cooldowns[player] = nil
	taxOperationBusy[player] = nil
	upgradeOperationBusy[player] = nil
	lastLandlordParts[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

rebuildAndSetupPhysicalHouses()
Modules.Validator.Report(houseTemplates, physicalHouses, furnitureFolder, ReplicatedStorage.Items:FindFirstChild("Deeds"), FurnitureFunctionRegistry)
local validateSetup = script.Parent:FindFirstChild("ValidateHouseSetup") or Instance.new("BindableFunction")
validateSetup.Name = "ValidateHouseSetup"
validateSetup.Parent = script.Parent
validateSetup.OnInvoke = function()
    return Modules.Validator.Report(houseTemplates, physicalHouses, furnitureFolder, ReplicatedStorage.Items:FindFirstChild("Deeds"), FurnitureFunctionRegistry)
end

for _, template in ipairs(houseTemplates:GetChildren()) do
	validateHouseTemplate(template, true)
	if template:IsA("Model") then
		getUpgradeDefinitions(template, true)
	end
end

task.spawn(function()
	while not shuttingDown do
		task.wait(60)
		for physicalHouseId, runtime in pairs(runtimeSessionsByPhysicalId) do
			if next(runtime.Participants) then
				local refreshed = readHouseDataByUserId(runtime.OwnerUserId)
				if refreshed and sanitizeTaxAmount(refreshed.Data.Revision) ~= sanitizeTaxAmount(runtime.Cache.Data.Revision) then
					task.spawn(refreshPhysicalRuntimeSession, physicalHouseId)
				end
			end
		end
	end
end)

task.spawn(function()
    while not shuttingDown do
        task.wait(Config.SaveMaintenanceInterval or 30)
        for player, cache in pairs(caches) do
            task.spawn(function()
                if cache.Closing then
                    if Modules.FlushPlayer(player, true) then caches[player] = nil; Modules.Leaving[player] = nil end
                elseif cache.Dirty then
                    savePlayerData(player)
                elseif not cache.Saving then
                    Modules.Data:Renew(cache.Handle)
                end
                if cache.Handle and cache.Handle.Lost and player.Parent == Players then
                    player:SetAttribute("HouseDataLoaded", false)
                    player:SetAttribute("HouseDataLoadFailed", true)
                    closeOwnerRuntimeSession(player, "House save ownership changed")
                end
            end)
        end
    end
end)

game:BindToClose(function()
	shuttingDown = true
	local runtimeList, seenRuntime = {}, {}
	for _, runtime in pairs(runtimeSessionsByOwnerId) do
		if not seenRuntime[runtime] then seenRuntime[runtime] = true; table.insert(runtimeList, runtime) end
	end
	for _, runtime in ipairs(runtimeList) do
		local participants = {}
		for participant in pairs(runtime.Participants) do table.insert(participants, participant) end
		for _, participant in ipairs(participants) do endSession(participant, false, "Server closing") end
	end
	for player in pairs(previewSessions) do
		endPreview(player, false, "Server closing", false)
	end
    local remaining = 0
    local deadline = os.clock() + 24
    for player, cache in pairs(caches) do
        cache.Closing = true
        remaining += 1
        task.spawn(function()
            Modules.FlushPlayer(player, true, deadline)
            remaining -= 1
        end)
    end
    while remaining > 0 and os.clock() < deadline do task.wait(0.05) end
end)

print("[House] NC2 private house and furniture placement system ready.")

