-- Read-only setup report. Developers can invoke ValidateHouseSetup after adding content.
local Validator = {}

function Validator.Report(houses, physicalHouses, furniture, deeds, registry, quiet)
	local report = {Errors = {}, Warnings = {}, Checked = 0}
	local function issue(list, object, code, detail)
		table.insert(list, {Path = object:GetFullName(), Code = code, Message = detail})
	end
	local function checkHouse(model, physical)
		if not model:IsA("Model") then return end
		report.Checked += 1
		local rootAttribute = physical and "PhysicalHouse" or "House"
		if model:GetAttribute(rootAttribute) ~= true then issue(report.Errors, model, "HOUSE_ATTRIBUTE", rootAttribute .. " must be Boolean true.") end
		local door = model:FindFirstChild("Door")
		if not door or not (door:IsA("Model") or door:IsA("BasePart")) then
			issue(report.Errors, model, "DOOR_MISSING", "Add a Door Model or BasePart.")
		else
			local spawn = door:FindFirstChild("HouseSpawn", true)
			if not spawn or not spawn:IsA("BasePart") then issue(report.Errors, door, "SPAWN_MISSING", "Add a BasePart named HouseSpawn.") end
			local anchor = door:IsA("BasePart") and door or nil
			for _, part in ipairs(door:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "HouseSpawn" then anchor = part; break end
			end
			if not anchor then issue(report.Warnings, door, "DOOR_ANCHOR", "Add a door BasePart or DoorPromptAnchor. The legacy spawn fallback will be used meanwhile.") end
		end
		local bounds = model:FindFirstChild("PlacementBounds")
		local count = 0
		if bounds and bounds:IsA("Folder") then
			for _, bound in ipairs(bounds:GetChildren()) do
				if bound:IsA("BasePart") then
					count += 1
					local stage = bound:GetAttribute("RequiredUpgradeStage")
					if stage ~= nil and (typeof(stage) ~= "number" or stage < 0 or stage % 1 ~= 0) then
						issue(report.Errors, bound, "BOUND_STAGE", "RequiredUpgradeStage must be a non-negative integer.")
					end
				end
			end
		end
		if count == 0 then issue(report.Errors, model, "BOUNDS_MISSING", "PlacementBounds must be a Folder with at least one BasePart covering the room interior.") end
		for _, object in ipairs(model:GetDescendants()) do
			if object:IsA("Model") and object.Name == "Window" then
				local glass = object:FindFirstChild("Glass", true)
				if not glass or not glass:IsA("BasePart") then issue(report.Errors, object, "WINDOW_GLASS", "Window needs a BasePart named Glass.") end
			end
		end
	end
	for _, model in ipairs(houses:GetChildren()) do checkHouse(model, false) end
	local ids, addresses, deedIds = {}, {}, {}
	for _, model in ipairs(physicalHouses:GetChildren()) do
		if model:IsA("Model") then
			checkHouse(model, true)
			local id, address = model:GetAttribute("PhysicalHouseId"), model:GetAttribute("Address")
			if typeof(id) ~= "string" or id == "" then issue(report.Errors, model, "PHYSICAL_ID", "PhysicalHouseId must be a nonempty String.")
			else ids[id] = ids[id] or {}; table.insert(ids[id], model) end
			if typeof(address) ~= "string" or address == "" then issue(report.Errors, model, "ADDRESS", "Address must be a nonempty String.")
			else address = string.lower(address); addresses[address] = addresses[address] or {}; table.insert(addresses[address], model) end
		end
	end
	for _, deed in ipairs(deeds and deeds:GetChildren() or {}) do
		local id = deed:GetAttribute("PhysicalHouseId")
		if typeof(id) == "string" and deed:GetAttribute("UniqueItemType") == "PhysicalHouseDeed" then deedIds[id] = (deedIds[id] or 0) + 1 end
	end
	for id, models in pairs(ids) do
		for _, model in ipairs(models) do
			if #models > 1 then issue(report.Errors, model, "DUPLICATE_ID", "PhysicalHouseId " .. id .. " is used by multiple properties.") end
			if deedIds[id] ~= 1 then issue(report.Errors, model, "DEED_MAPPING", "Expected exactly one deed for ID " .. id .. "; found " .. tostring(deedIds[id] or 0) .. ".") end
		end
	end
	for _, models in pairs(addresses) do
		if #models > 1 then for _, model in ipairs(models) do issue(report.Errors, model, "DUPLICATE_ADDRESS", "Address is used by another property.") end end
	end
	for _, item in ipairs(furniture:GetDescendants()) do
		if (item:IsA("Model") or item:IsA("BasePart")) and item.Parent:IsA("Folder") then
			local name = registry.GetFunctionName(item)
			if name ~= "None" and not registry.HasHandler(name) then issue(report.Errors, item, "UNKNOWN_FUNCTION", "HouseFunction '" .. name .. "' has no registered handler.") end
			if name == "Seat" and not item:IsA("Seat") and not item:FindFirstChildWhichIsA("Seat", true) then issue(report.Errors, item, "SEAT_MISSING", "Add at least one real Roblox Seat.") end
			if name == "MusicPlayer" then
				local valid = false
				for _, sound in ipairs(item:GetDescendants()) do if sound:IsA("Sound") and sound.Name == "Sound" and sound.Parent:IsA("BasePart") then valid = true end end
				if not valid then issue(report.Errors, item, "MUSIC_SOUND", "Add a Sound named Sound beneath a BasePart.") end
			elseif name == "EditableSign" then
				local valid = false
				for _, surface in ipairs(item:GetDescendants()) do if surface:IsA("SurfaceGui") and surface:FindFirstChildWhichIsA("TextLabel", true) then valid = true end end
				if not valid then issue(report.Errors, item, "SIGN_LABEL", "Add a SurfaceGui containing a TextLabel.") end
			end
		end
	end
	if not quiet then
		for _, items in ipairs({report.Errors, report.Warnings}) do
			for _, entry in ipairs(items) do warn("[HouseSetup][" .. entry.Code .. "] " .. entry.Path .. ": " .. entry.Message) end
		end
		print(("[HouseSetup] Checked %d houses: %d errors, %d warnings."):format(report.Checked, #report.Errors, #report.Warnings))
	end
	return report
end

return Validator
