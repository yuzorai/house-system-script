local Service = {}
function Service.new(ctx)
local physicalHouses = ctx.PhysicalHouses
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local validPhysicalHouses = {}
local function validatePhysicalHouseTemplate(model, warnInvalid)
	local id = model and tostring(model:GetAttribute("PhysicalHouseId") or "") or ""
	local address = model and model:GetAttribute("Address") or nil
	local door = model and model:FindFirstChild("Door")
	local doorIsContainer = door and (door:IsA("Model") or door:IsA("BasePart"))
	local spawn = doorIsContainer and door:FindFirstChild("HouseSpawn", true)
	local bounds = model and model:FindFirstChild("PlacementBounds")
	local hasBound = false
	if bounds and bounds:IsA("Folder") then
		for _, child in ipairs(bounds:GetChildren()) do
			if child:IsA("BasePart") then hasBound = true; break end
		end
	end
	local windowCount = 0
	local malformedWindow = false
	if model then
		for _, object in ipairs(model:GetDescendants()) do
			if object:IsA("Model") and object.Name == "Window" then
				windowCount += 1
				local glass = object:FindFirstChild("Glass", true)
				if not glass or not glass:IsA("BasePart") then malformedWindow = true end
			end
		end
	end
	local valid = model and model:IsA("Model")
		and model:GetAttribute("PhysicalHouse") == true
		and id ~= ""
		and typeof(address) == "string" and address ~= ""
		and doorIsContainer and spawn and spawn:IsA("BasePart")
		and bounds and bounds:IsA("Folder") and hasBound
		and windowCount > 0 and not malformedWindow
	if not valid and warnInvalid and model and model:IsA("Model") then
		warn(("[PhysicalHouse] Disabled %s. It needs PhysicalHouse=true, a string PhysicalHouseId/Address, Door.HouseSpawn, PlacementBounds, and Window models containing Glass parts."):format(model:GetFullName()))
	end
	return valid
end

local function rebuildPhysicalHouseIndex(warnInvalid)
	local rebuilt, duplicateIds = {}, {}
	for _, model in ipairs(physicalHouses:GetChildren()) do
		if validatePhysicalHouseTemplate(model, warnInvalid) then
			local id = tostring(model:GetAttribute("PhysicalHouseId"))
			if rebuilt[id] or duplicateIds[id] then
				warn(("[PhysicalHouse] Duplicate PhysicalHouseId %s disables every model using that ID."):format(id))
				rebuilt[id] = nil
				duplicateIds[id] = true
			else
				rebuilt[id] = model
			end
		end
	end
	validPhysicalHouses = {}
	for id, model in pairs(rebuilt) do
		if model and not duplicateIds[id] then validPhysicalHouses[id] = model end
	end

	local addressIds = {}
	for id, model in pairs(table.clone(validPhysicalHouses)) do
		local normalizedAddress = string.lower(tostring(model:GetAttribute("Address")))
		local existingId = addressIds[normalizedAddress]
		if existingId then
			warn(("[PhysicalHouse] Duplicate address %s disables physical houses %s and %s."):format(tostring(model:GetAttribute("Address")), existingId, id))
			validPhysicalHouses[existingId] = nil
			validPhysicalHouses[id] = nil
		else
			addressIds[normalizedAddress] = id
		end
	end

	local deedCounts = {}
	local deedFolder = ReplicatedStorage:FindFirstChild("Items") and ReplicatedStorage.Items:FindFirstChild("Deeds")
	if deedFolder then
		for _, deed in ipairs(deedFolder:GetChildren()) do
			local deedId = tostring(deed:GetAttribute("PhysicalHouseId") or "")
			local validDeed = (deed:IsA("BasePart") or deed:IsA("Model"))
				and deed:GetAttribute("UniqueItemType") == "PhysicalHouseDeed"
				and deedId ~= ""
				and deed:GetAttribute("Tradable") == true
				and deed:GetAttribute("HotbarSection") == "None"
			if validDeed then deedCounts[deedId] = (deedCounts[deedId] or 0) + 1
			elseif warnInvalid then warn("[PhysicalHouse] Invalid deed template: " .. deed:GetFullName()) end
		end
	end
	for id in pairs(table.clone(validPhysicalHouses)) do
		if deedCounts[id] ~= 1 then
			warn(("[PhysicalHouse] Physical house %s requires exactly one valid deed template; found %d."):format(id, deedCounts[id] or 0))
			validPhysicalHouses[id] = nil
		end
	end
	return validPhysicalHouses
end

local function getPhysicalHouse(physicalHouseId)
	local id = tostring(physicalHouseId or "")
	local model = validPhysicalHouses[id]
	if model and model.Parent == physicalHouses and validatePhysicalHouseTemplate(model, false) then
		return model
	end
	rebuildPhysicalHouseIndex(false)
	return validPhysicalHouses[id]
end


return {Validate = validatePhysicalHouseTemplate, Rebuild = rebuildPhysicalHouseIndex, Get = getPhysicalHouse}
end
return Service
