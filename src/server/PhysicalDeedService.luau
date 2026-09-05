--[[
	PhysicalDeedService
	Global, server-authoritative ownership registry for unique physical-house deeds.
	The item count remains in Inventory/Warehouse; this registry is the ownership lock.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemRegistry = require(ReplicatedStorage:WaitForChild("ItemRegistry"))

local PhysicalDeedService = {}

local STORE_NAME = "PhysicalHouseDeeds_v1"
local REGISTRY_KEY = "Registry"
local MESSAGE_TOPIC = "PhysicalHouseDeedsChanged_v1"
local CACHE_SECONDS = 8

local store = DataStoreService:GetDataStore(STORE_NAME)
local cache = nil
local cacheReadAt = 0

local changedEvent = script:FindFirstChild("Changed")
if not changedEvent then
	changedEvent = Instance.new("BindableEvent")
	changedEvent.Name = "Changed"
	changedEvent.Parent = script
end
PhysicalDeedService.Changed = changedEvent.Event

local relocationSources = {
	WarehouseDeposit = true,
	WarehouseWithdrawal = true,
	WarehouseRollback = true,
	TradeCommit = true,
	TradeRollback = true,
	DeedReconcile = true,
}

local removalSources = {
	WarehouseDeposit = true,
	WarehouseWithdrawal = true,
	TradeCommit = true,
	TradeRollback = true,
	AdminDeedRelease = true,
}

local function defaultRegistry()
	return {
		Version = 1,
		Revision = 0,
		Houses = {},
		Owners = {},
	}
end

local function sanitizeRegistry(raw)
	local result = defaultRegistry()
	if typeof(raw) ~= "table" then
		return result
	end
	result.Revision = math.max(0, math.floor(tonumber(raw.Revision) or 0))
	if typeof(raw.Houses) == "table" then
		for rawId, rawEntry in pairs(raw.Houses) do
			local id = tostring(rawId)
			if id ~= "" and typeof(rawEntry) == "table" then
				local ownerUserId = tonumber(rawEntry.OwnerUserId)
				result.Houses[id] = {
					OwnerUserId = ownerUserId and math.floor(ownerUserId) or nil,
					OwnerName = typeof(rawEntry.OwnerName) == "string" and rawEntry.OwnerName or nil,
					DeedItemName = typeof(rawEntry.DeedItemName) == "string" and rawEntry.DeedItemName or nil,
					TransactionId = typeof(rawEntry.TransactionId) == "string" and rawEntry.TransactionId or nil,
					PreviousOwnerUserId = tonumber(rawEntry.PreviousOwnerUserId),
					PreviousOwnerName = typeof(rawEntry.PreviousOwnerName) == "string" and rawEntry.PreviousOwnerName or nil,
					UpdatedAt = math.floor(tonumber(rawEntry.UpdatedAt) or 0),
				}
			end
		end
	end
	if typeof(raw.Owners) == "table" then
		for rawUserId, rawId in pairs(raw.Owners) do
			local userId = tostring(rawUserId)
			local id = tostring(rawId)
			if userId ~= "" and id ~= "" then
				result.Owners[userId] = id
			end
		end
	end
	return result
end

local function publishChange(reason, physicalHouseId, ownerUserId)
	pcall(function()
		MessagingService:PublishAsync(MESSAGE_TOPIC, {
			Reason = reason,
			PhysicalHouseId = physicalHouseId,
			OwnerUserId = ownerUserId,
			JobId = game.JobId,
			SentAt = os.time(),
		})
	end)
	changedEvent:Fire(reason, physicalHouseId, ownerUserId)
end

local function setCache(registry)
	cache = sanitizeRegistry(registry)
	cacheReadAt = os.clock()
	return cache
end

local function readRegistry(forceRefresh)
	if not forceRefresh and cache and os.clock() - cacheReadAt <= CACHE_SECONDS then
		return cache
	end
	local ok, data = pcall(function()
		return store:GetAsync(REGISTRY_KEY)
	end)
	if not ok then
		warn("[PhysicalDeedService] Registry read failed: " .. tostring(data))
		return nil, "The physical-property registry is unavailable"
	end
	return setCache(data)
end

local function updateRegistry(mutator)
	local callbackResult
	local ok, updated = pcall(function()
		return store:UpdateAsync(REGISTRY_KEY, function(raw)
			local registry = sanitizeRegistry(raw)
			local shouldWrite, result = mutator(registry)
			callbackResult = result
			if shouldWrite ~= true then
				return nil
			end
			registry.Version = 1
			registry.Revision += 1
			return registry
		end)
	end)
	if not ok then
		warn("[PhysicalDeedService] Registry update failed: " .. tostring(updated))
		return false, "The physical-property registry is unavailable"
	end
	if updated ~= nil then
		setCache(updated)
	else
		cacheReadAt = 0
	end
	if typeof(callbackResult) == "table" then
		return callbackResult.Success == true, callbackResult.Message, callbackResult
	end
	return false, "The deed request was rejected"
end

local function getDeedInfo(itemOrName)
	local item = typeof(itemOrName) == "Instance" and itemOrName or ItemRegistry.FindItem(itemOrName)
	if not item or item:GetAttribute("UniqueItemType") ~= "PhysicalHouseDeed" then
		return nil
	end
	local id = tostring(item:GetAttribute("PhysicalHouseId") or "")
	if id == "" then
		return nil
	end
	return item, id
end

local function getCount(folder, itemName)
	local value = folder and folder:FindFirstChild(itemName)
	return value and value:IsA("IntValue") and math.max(0, value.Value) or 0
end

local function setCount(folder, itemName, amount)
	if not folder then
		return false
	end
	local value = folder:FindFirstChild(itemName)
	if not value then
		value = Instance.new("IntValue")
		value.Name = itemName
		value.Parent = folder
	end
	if not value:IsA("IntValue") then
		value:Destroy()
		value = Instance.new("IntValue")
		value.Name = itemName
		value.Parent = folder
	end
	value.Value = math.max(0, math.floor(amount))
	return true
end

function PhysicalDeedService:IsDeed(itemOrName)
	return getDeedInfo(itemOrName) ~= nil
end

function PhysicalDeedService:GetPhysicalHouseId(itemOrName)
	local _, id = getDeedInfo(itemOrName)
	return id
end

function PhysicalDeedService:GetDeedItemName(physicalHouseId)
	local wantedId = tostring(physicalHouseId or "")
	for _, item in ipairs(ItemRegistry.GetItems()) do
		local _, id = getDeedInfo(item)
		if id == wantedId then
			return item.Name
		end
	end
	return nil
end

function PhysicalDeedService:GetOwnerAsync(physicalHouseId, forceRefresh)
	local id = tostring(physicalHouseId or "")
	if id == "" then
		return nil, "Physical house ID is required"
	end
	local registry, readError = readRegistry(forceRefresh == true)
	if not registry then
		return nil, readError
	end
	local entry = registry.Houses[id]
	if not entry or not entry.OwnerUserId then
		return nil
	end
	return table.clone(entry)
end

function PhysicalDeedService:GetPlayerDeedAsync(userId, forceRefresh)
	userId = tonumber(userId)
	if not userId then
		return nil, "User ID is required"
	end
	local registry, readError = readRegistry(forceRefresh == true)
	if not registry then
		return nil, readError
	end
	return registry.Owners[tostring(math.floor(userId))]
end

function PhysicalDeedService:PlayerOwnsAsync(player, itemOrName, forceRefresh)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player"
	end
	local item, id = getDeedInfo(itemOrName)
	if not item then
		return false, "That item is not a physical-house deed"
	end
	local ownedId, readError = self:GetPlayerDeedAsync(player.UserId, forceRefresh)
	if readError then
		return false, readError
	end
	return ownedId == id
end

function PhysicalDeedService:ClaimAsync(player, deedItemName, source)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "Invalid player"
	end
	local item, id = getDeedInfo(deedItemName)
	if not item then
		return false, "That item is not a valid physical-house deed"
	end
	local transactionId = "claim:" .. HttpService:GenerateGUID(false)
	local success, message = updateRegistry(function(registry)
		local userKey = tostring(player.UserId)
		local currentId = registry.Owners[userKey]
		local house = registry.Houses[id]
		if currentId then
			return false, {Success = false, Message = currentId == id and "You already own this deed" or "A player may own only one physical-house deed"}
		end
		if house and house.OwnerUserId then
			return false, {Success = false, Message = "That deed already belongs to another player"}
		end
		registry.Houses[id] = {
			OwnerUserId = player.UserId,
			OwnerName = player.Name,
			DeedItemName = item.Name,
			TransactionId = transactionId,
			UpdatedAt = os.time(),
		}
		registry.Owners[userKey] = id
		return true, {Success = true, Message = "Deed claimed"}
	end)
	if success then
		publishChange(source or "Claim", id, player.UserId)
		return true, transactionId
	end
	return false, message
end

function PhysicalDeedService:RollbackClaimAsync(transactionId)
	if typeof(transactionId) ~= "string" or transactionId == "" then
		return false, "Transaction ID is required"
	end
	local releasedId
	local success, message = updateRegistry(function(registry)
		for id, house in pairs(registry.Houses) do
			if house.TransactionId == transactionId and string.sub(transactionId, 1, 6) == "claim:" then
				if house.OwnerUserId then registry.Owners[tostring(house.OwnerUserId)] = nil end
				registry.Houses[id] = nil
				releasedId = id
				return true, {Success = true, Message = "Claim rolled back"}
			end
		end
		return false, {Success = false, Message = "Claim transaction is no longer active"}
	end)
	if success then publishChange("ClaimRollback", releasedId, nil) end
	return success, message
end

function PhysicalDeedService:AuthorizeAddAsync(player, itemOrName, amount, source, options)
	local item, id = getDeedInfo(itemOrName)
	if not item then
		return true
	end
	if amount ~= 1 then
		return false, "A physical-house deed must be granted exactly once"
	end
	options = typeof(options) == "table" and options or {}
	local ownedId, readError = self:GetPlayerDeedAsync(player.UserId, true)
	if readError then return false, readError end
	local inventory = player:FindFirstChild("MaterialInventory")
	local warehouse = player:FindFirstChild("WarehouseInventory")
	local existingCount = getCount(inventory, item.Name) + getCount(warehouse, item.Name)
	if ownedId == id then
		if existingCount == 0 and (relocationSources[tostring(source)] or options.AllowOwnedDeedAdd == true) then
			return true
		end
		return false, "That unique deed already exists for this player"
	elseif ownedId then
		return false, "A player may own only one physical-house deed"
	end
	local owner = self:GetOwnerAsync(id, true)
	if owner then
		return false, "That deed already belongs to another player"
	end
	local success, claimOrError = self:ClaimAsync(player, item.Name, source)
	if not success then return false, claimOrError end
	return true, nil, claimOrError
end

function PhysicalDeedService:CanRemove(player, itemOrName, amount, source, options)
	local item = getDeedInfo(itemOrName)
	if not item then return true end
	if amount ~= 1 then return false, "A physical-house deed can only move as one item" end
	options = typeof(options) == "table" and options or {}
	if removalSources[tostring(source)] or options.AllowDeedRemoval == true then
		return true
	end
	return false, "Physical-house deeds can only be moved, traded, or explicitly released by an administrator"
end

function PhysicalDeedService:TransferAsync(giver, recipient, deedItemName, transactionId)
	if typeof(giver) ~= "Instance" or not giver:IsA("Player") or typeof(recipient) ~= "Instance" or not recipient:IsA("Player") then
		return false, "Invalid trade players"
	end
	if giver == recipient then return false, "A deed cannot be traded to the same player" end
	local item, id = getDeedInfo(deedItemName)
	if not item then return false, "That item is not a physical-house deed" end
	transactionId = typeof(transactionId) == "string" and transactionId ~= "" and transactionId or ("trade:" .. HttpService:GenerateGUID(false))
	local success, message = updateRegistry(function(registry)
		local giverKey = tostring(giver.UserId)
		local recipientKey = tostring(recipient.UserId)
		local house = registry.Houses[id]
		if registry.Owners[giverKey] ~= id or not house or house.OwnerUserId ~= giver.UserId then
			return false, {Success = false, Message = "The giver no longer owns that deed"}
		end
		if registry.Owners[recipientKey] then
			return false, {Success = false, Message = "The recipient already owns a physical-house deed"}
		end
		if house.TransactionId == transactionId and house.OwnerUserId == recipient.UserId then
			return false, {Success = true, Message = "Transfer already completed"}
		end
		registry.Owners[giverKey] = nil
		registry.Owners[recipientKey] = id
		house.PreviousOwnerUserId = giver.UserId
		house.PreviousOwnerName = giver.Name
		house.OwnerUserId = recipient.UserId
		house.OwnerName = recipient.Name
		house.DeedItemName = item.Name
		house.TransactionId = transactionId
		house.UpdatedAt = os.time()
		return true, {Success = true, Message = "Deed transferred"}
	end)
	if success then publishChange("Transfer", id, recipient.UserId) end
	return success, message, transactionId, id
end

function PhysicalDeedService:RollbackTransferAsync(transactionId)
	if typeof(transactionId) ~= "string" or transactionId == "" then return false, "Transaction ID is required" end
	local rolledBackId, restoredOwner
	local success, message = updateRegistry(function(registry)
		for id, house in pairs(registry.Houses) do
			if house.TransactionId == transactionId and house.PreviousOwnerUserId then
				local currentKey = house.OwnerUserId and tostring(house.OwnerUserId) or nil
				if currentKey then registry.Owners[currentKey] = nil end
				restoredOwner = math.floor(house.PreviousOwnerUserId)
				registry.Owners[tostring(restoredOwner)] = id
				house.OwnerUserId = restoredOwner
				house.OwnerName = house.PreviousOwnerName
				house.PreviousOwnerUserId = nil
				house.PreviousOwnerName = nil
				house.TransactionId = "rollback:" .. transactionId
				house.UpdatedAt = os.time()
				rolledBackId = id
				return true, {Success = true, Message = "Deed transfer rolled back"}
			end
		end
		return false, {Success = false, Message = "Transfer transaction is no longer active"}
	end)
	if success then publishChange("TransferRollback", rolledBackId, restoredOwner) end
	return success, message
end

function PhysicalDeedService:ReleaseAsync(playerOrUserId, deedItemName, adminReason)
	local userId = typeof(playerOrUserId) == "Instance" and playerOrUserId.UserId or tonumber(playerOrUserId)
	if not userId then return false, "User ID is required" end
	local item, id = getDeedInfo(deedItemName)
	if not item then return false, "That item is not a physical-house deed" end
	local success, message = updateRegistry(function(registry)
		local userKey = tostring(math.floor(userId))
		local house = registry.Houses[id]
		if registry.Owners[userKey] ~= id or not house or house.OwnerUserId ~= userId then
			return false, {Success = false, Message = "That player does not own this deed"}
		end
		registry.Owners[userKey] = nil
		registry.Houses[id] = nil
		return true, {Success = true, Message = "Deed released"}
	end)
	if success then publishChange("AdminRelease:" .. tostring(adminReason or "Unspecified"), id, nil) end
	return success, message, id
end

function PhysicalDeedService:ReconcilePlayerAsync(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "Invalid player" end
	local inventory = player:FindFirstChild("MaterialInventory")
	local warehouse = player:FindFirstChild("WarehouseInventory")
	if not inventory or not warehouse then return false, "Inventory folders are unavailable" end

	local deedItems = {}
	for _, item in ipairs(ItemRegistry.GetItems()) do
		local _, id = getDeedInfo(item)
		if id then table.insert(deedItems, {Item = item, Id = id}) end
	end
	table.sort(deedItems, function(a, b) return a.Id < b.Id end)

	local ownedId, readError = self:GetPlayerDeedAsync(player.UserId, true)
	if readError then return false, readError end
	if not ownedId then
		for _, entry in ipairs(deedItems) do
			if getCount(inventory, entry.Item.Name) + getCount(warehouse, entry.Item.Name) > 0 then
				local claimed = self:ClaimAsync(player, entry.Item.Name, "LoadReconcile")
				if claimed then ownedId = entry.Id end
				break
			end
		end
	end

	local changed = false
	local ownedTemplateFound = false
	for _, entry in ipairs(deedItems) do
		local inventoryCount = getCount(inventory, entry.Item.Name)
		local warehouseCount = getCount(warehouse, entry.Item.Name)
		if entry.Id == ownedId then
			ownedTemplateFound = true
			if inventoryCount + warehouseCount == 0 then
				setCount(inventory, entry.Item.Name, 1)
				changed = true
			elseif inventoryCount > 0 then
				if inventoryCount ~= 1 then setCount(inventory, entry.Item.Name, 1); changed = true end
				if warehouseCount ~= 0 then setCount(warehouse, entry.Item.Name, 0); changed = true end
			else
				if warehouseCount ~= 1 then setCount(warehouse, entry.Item.Name, 1); changed = true end
			end
		else
			if inventoryCount ~= 0 then setCount(inventory, entry.Item.Name, 0); changed = true end
			if warehouseCount ~= 0 then setCount(warehouse, entry.Item.Name, 0); changed = true end
		end
	end
	if ownedId and not ownedTemplateFound then
		warn(("[PhysicalDeedService] Player %d owns physical house %s, but its deed template is missing"):format(player.UserId, ownedId))
		return false, "Owned deed template is missing"
	end
	if changed then
		print(("[PhysicalDeedService] Reconciled unique deed data for %s (%d)"):format(player.Name, player.UserId))
	end
	return true, changed, ownedId
end

pcall(function()
	MessagingService:SubscribeAsync(MESSAGE_TOPIC, function(message)
		local data = message.Data
		if typeof(data) == "table" and data.JobId ~= game.JobId then
			cacheReadAt = 0
			changedEvent:Fire(data.Reason, data.PhysicalHouseId, data.OwnerUserId)
		end
	end)
end)

return PhysicalDeedService

