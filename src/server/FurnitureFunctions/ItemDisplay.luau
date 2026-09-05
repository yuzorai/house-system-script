local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemRegistry = require(ReplicatedStorage:WaitForChild("ItemRegistry"))
local CraftedFinishRenderer = require(ReplicatedStorage:WaitForChild("CraftedFinishRenderer"))
local ArmorRecordService = require(ServerScriptService:WaitForChild("Equipment System"):WaitForChild("ArmorRecordService"))
local WeaponRecordService = require(ServerScriptService:WaitForChild("Equipment System"):WaitForChild("WeaponRecordService"))
local NotificationServer = require(ServerScriptService:WaitForChild("Notification System"):WaitForChild("NotificationServer"))

local ItemDisplay = {}

local ALLOWED_ITEM_TYPES = {
	Weapons = true,
	Tools = true,
	Equipment = true,
}

local VISUAL_ATTRIBUTE_NAMES = {
	"Crafted",
	"CraftedName",
	"ModelVariantId",
	"GunMetal1Name",
	"GunMetal2Name",
	"ArmorMetal1Name",
	"ArmorMetal2Name",
	"Tier",
}

local CLICK_COOLDOWN = 0.35
local lastClickAt = setmetatable({}, {__mode = "k"})
local warningUntil = setmetatable({}, {__mode = "k"})

local function notify(player, text)
	local now = os.clock()
	if now < (warningUntil[player] or 0) then
		return
	end
	warningUntil[player] = now + 3
	NotificationServer.Notify(player, {
		Title = "Item Display",
		Text = text,
		Duration = 3,
	})
end

local function copyVisualAttributes(source)
	local output = {}
	if not source then
		return output
	end
	for _, attributeName in ipairs(VISUAL_ATTRIBUTE_NAMES) do
		local value = source:GetAttribute(attributeName)
		local valueType = typeof(value)
		if valueType == "string" or valueType == "number" or valueType == "boolean" then
			output[attributeName] = value
		end
	end
	return output
end

local function sanitizeVisualAttributes(raw)
	local output = {}
	if typeof(raw) ~= "table" then
		return output
	end
	for _, attributeName in ipairs(VISUAL_ATTRIBUTE_NAMES) do
		local value = raw[attributeName]
		local valueType = typeof(value)
		if valueType == "string" or valueType == "number" or valueType == "boolean" then
			output[attributeName] = value
		end
	end
	return output
end

function ItemDisplay.SanitizeState(rawState)
	if typeof(rawState) ~= "table" or typeof(rawState.DisplayItem) ~= "table" then
		return {}
	end
	local rawItem = rawState.DisplayItem
	if typeof(rawItem.ItemName) ~= "string" or rawItem.ItemName == "" then
		return {}
	end
	local template = ItemRegistry.FindItem(rawItem.ItemName)
	local itemType = template and ItemRegistry.GetItemType(template)
	if not template or not ALLOWED_ITEM_TYPES[itemType] then
		return {}
	end
	local displayName = typeof(rawItem.DisplayName) == "string" and rawItem.DisplayName or rawItem.ItemName
	if #displayName > 100 then
		displayName = string.sub(displayName, 1, 100)
	end
	return {
		DisplayItem = {
			ItemName = template.Name,
			ItemType = itemType,
			DisplayName = displayName,
			VisualAttributes = sanitizeVisualAttributes(rawItem.VisualAttributes),
		},
	}
end

local function destroyDisplayedVisual(model)
	local existing = model and model:FindFirstChild("DisplayedItemVisual")
	if existing then
		existing:Destroy()
	end
end

local function sanitizeVisual(root)
	local objects = {root}
	for _, descendant in ipairs(root:GetDescendants()) do
		table.insert(objects, descendant)
	end
	for _, object in ipairs(objects) do
		if object ~= root and (
			object:IsA("LuaSourceContainer")
			or object:IsA("Sound")
			or object:IsA("ParticleEmitter")
			or object:IsA("Trail")
			or object:IsA("Beam")
			or object:IsA("Smoke")
			or object:IsA("Fire")
			or object:IsA("Sparkles")
			or object:IsA("Highlight")
			or object:IsA("BillboardGui")
			or object:IsA("SurfaceGui")
			or object:IsA("ProximityPrompt")
			or object:IsA("ClickDetector")
			or object:IsA("TouchTransmitter")
		) then
			object:Destroy()
		elseif object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Massless = true
		end
	end
end

local function ensureVisibleVisual(root)
	local fallbackPart
	local objects = {root}
	for _, descendant in ipairs(root:GetDescendants()) do
		table.insert(objects, descendant)
	end
	for _, object in ipairs(objects) do
		if object:IsA("BasePart") then
			fallbackPart = fallbackPart or object
			if object.Transparency < 0.98 then
				return
			end
		end
	end
	if fallbackPart then
		-- Some outfit inventory templates are intentionally invisible data carriers.
		-- Their authored root still supplies useful display bounds, so expose only the
		-- sanitized cosmetic clone as a neutral fabric preview.
		fallbackPart.Transparency = 0
		fallbackPart.Material = Enum.Material.Fabric
	end
end

local function getLocalBounds(model, referenceCFrame)
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 0.98 then
			local half = part.Size * 0.5
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local worldPoint = part.CFrame:PointToWorldSpace(Vector3.new(
							half.X * x,
							half.Y * y,
							half.Z * z
						))
						local point = referenceCFrame:PointToObjectSpace(worldPoint)
						minimum = Vector3.new(
							math.min(minimum.X, point.X),
							math.min(minimum.Y, point.Y),
							math.min(minimum.Z, point.Z)
						)
						maximum = Vector3.new(
							math.max(maximum.X, point.X),
							math.max(maximum.Y, point.Y),
							math.max(maximum.Z, point.Z)
						)
						found = true
					end
				end
			end
		end
	end
	return found and minimum or nil, found and maximum or nil
end

local function getProjectionMinimum(minimum, maximum, axis)
	local result = math.huge
	for x = 0, 1 do
		for y = 0, 1 do
			for z = 0, 1 do
				local point = Vector3.new(
					x == 0 and minimum.X or maximum.X,
					y == 0 and minimum.Y or maximum.Y,
					z == 0 and minimum.Z or maximum.Z
				)
				result = math.min(result, point:Dot(axis))
			end
		end
	end
	return result
end

local AUTO_ROTATIONS = {
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(0, math.rad(90), 0),
	CFrame.Angles(0, math.rad(180), 0),
	CFrame.Angles(0, math.rad(270), 0),
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(math.rad(90), math.rad(90), 0),
	CFrame.Angles(math.rad(90), math.rad(180), 0),
	CFrame.Angles(math.rad(90), math.rad(270), 0),
	CFrame.Angles(math.rad(-90), 0, 0),
	CFrame.Angles(math.rad(-90), math.rad(90), 0),
	CFrame.Angles(math.rad(-90), math.rad(180), 0),
	CFrame.Angles(math.rad(-90), math.rad(270), 0),
	CFrame.Angles(0, 0, math.rad(90)),
	CFrame.Angles(0, math.rad(90), math.rad(90)),
	CFrame.Angles(0, math.rad(180), math.rad(90)),
	CFrame.Angles(0, math.rad(270), math.rad(90)),
	CFrame.Angles(0, 0, math.rad(-90)),
	CFrame.Angles(0, math.rad(90), math.rad(-90)),
	CFrame.Angles(0, math.rad(180), math.rad(-90)),
	CFrame.Angles(0, math.rad(270), math.rad(-90)),
}

local function getRequestedDisplayRotation(template)
	local explicit = template:GetAttribute("HouseDisplayRotation")
	if typeof(explicit) == "Vector3" or typeof(explicit) == "CFrame" then
		return explicit
	end
	if ArmorRecordService.IsArmor(template) then
		local equipOffset = template:GetAttribute("EquipOffset")
		if typeof(equipOffset) ~= "CFrame" then
			equipOffset = CFrame.identity
		end
		return CFrame.Angles(0, math.rad(90), 0) * equipOffset.Rotation
	end
	return nil
end

local function chooseRotation(holder, surface, availableHeight, availableWidth, explicitRotation)
	local candidates
	if typeof(explicitRotation) == "CFrame" then
		candidates = {explicitRotation.Rotation}
	elseif typeof(explicitRotation) == "Vector3" then
		candidates = {
			CFrame.fromOrientation(
				math.rad(explicitRotation.X),
				math.rad(explicitRotation.Y),
				math.rad(explicitRotation.Z)
			),
		}
	else
		candidates = AUTO_ROTATIONS
	end

	local bestRotation
	local bestMinimum
	local bestMaximum
	local bestFit = -math.huge
	local bestDepth = math.huge
	for _, candidate in ipairs(candidates) do
		holder:PivotTo(surface.CFrame * candidate)
		local minimum, maximum = getLocalBounds(holder, surface.CFrame)
		if minimum and maximum then
			local size = maximum - minimum
			local fit = math.min(
				1,
				availableHeight / math.max(size.Y, 0.001),
				availableWidth / math.max(size.Z, 0.001)
			)
			if size.X < bestDepth - 0.0001
				or (math.abs(size.X - bestDepth) <= 0.0001 and fit > bestFit)
			then
				bestRotation = candidate
				bestMinimum = minimum
				bestMaximum = maximum
				bestFit = fit
				bestDepth = size.X
			end
		end
	end
	return bestRotation, bestMinimum, bestMaximum, bestFit
end

local function renderDisplay(context)
	destroyDisplayedVisual(context.Model)
	local state = context.Record.FunctionState
	local displayItem = typeof(state) == "table" and state.DisplayItem or nil
	if typeof(displayItem) ~= "table" then
		return
	end

	local template = ItemRegistry.FindItem(displayItem.ItemName)
	local surface = context.Model:FindFirstChild("DisplaySurface", true)
	if not template or not surface or not surface:IsA("BasePart") then
		return
	end

	local ok, visual = pcall(function()
		return template:Clone()
	end)
	if not ok or not visual then
		warn("[House] Could not clone displayed item", displayItem.ItemName)
		return
	end
	sanitizeVisual(visual)
	ensureVisibleVisual(visual)

	local holder = Instance.new("Model")
	holder.Name = "DisplayedItemVisual"
	visual.Name = "SourceVisual"
	visual.Parent = holder
	holder.Parent = context.Model

	local attributes = displayItem.VisualAttributes or {}
	CraftedFinishRenderer.ApplyGunFinish(visual, attributes)
	CraftedFinishRenderer.ApplyArmorFinish(visual, attributes)
	CraftedFinishRenderer.CopyRecordAttributes(attributes, holder)

	local padding = math.max(0, tonumber(context.Model:GetAttribute("DisplayPadding")) or 0.12)
	local availableHeight = math.max(0.05, surface.Size.Y - padding * 2)
	local availableWidth = math.max(0.05, surface.Size.Z - padding * 2)
	local rotationCFrame, minimum, maximum, fitScale = chooseRotation(
		holder,
		surface,
		availableHeight,
		availableWidth,
		getRequestedDisplayRotation(template)
	)
	if not rotationCFrame or not minimum or not maximum then
		holder:Destroy()
		return
	end
	local customScale = tonumber(template:GetAttribute("HouseDisplayScale"))
	if not customScale or customScale ~= customScale then
		customScale = 1
	end
	customScale = math.clamp(customScale, 0.05, 1)
	local finalScale = math.min(1, fitScale * customScale)
	if finalScale < 0.999 then
		local scaled, scaleError = pcall(function()
			holder:ScaleTo(finalScale)
		end)
		if not scaled then
			warn("[House] Could not scale displayed item:", scaleError)
		end
	end

	holder:PivotTo(surface.CFrame * rotationCFrame)
	minimum, maximum = getLocalBounds(holder, surface.CFrame)
	if not minimum or not maximum then
		holder:Destroy()
		return
	end

	local normal = surface:GetAttribute("DisplayNormal")
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 0.9 then
		normal = Vector3.new(-1, 0, 0)
	else
		normal = normal.Unit
	end
	local center = (minimum + maximum) * 0.5
	local minimumProjection = getProjectionMinimum(minimum, maximum, normal)
	local depthOffset = math.max(0, tonumber(context.Model:GetAttribute("DisplayDepthOffset")) or 0.05)
	local surfaceHalfDepth = math.abs(normal.X) * surface.Size.X * 0.5
		+ math.abs(normal.Y) * surface.Size.Y * 0.5
		+ math.abs(normal.Z) * surface.Size.Z * 0.5
	local tangentCorrection = -center + normal * center:Dot(normal)
	local itemOffset = template:GetAttribute("HouseDisplayOffset")
	if typeof(itemOffset) ~= "Vector3" then
		itemOffset = Vector3.zero
	end
	local localShift = normal * (surfaceHalfDepth + depthOffset - minimumProjection)
		+ tangentCorrection
		+ itemOffset
	holder:PivotTo(holder:GetPivot() + surface.CFrame:VectorToWorldSpace(localShift))
end

local function readSlotThree(player)
	local quickSlots = player:FindFirstChild("QuickSlots")
	local slot = quickSlots and quickSlots:FindFirstChild("Slot3")
	if not slot or not slot:IsA("StringValue") then
		return nil, "Toolbar slot 3 is unavailable"
	end
	if slot.Value == "" then
		return {}
	end

	local template = ItemRegistry.FindItem(slot.Value)
	local itemType = template and ItemRegistry.GetItemType(template)
	if not template or not ALLOWED_ITEM_TYPES[itemType] then
		return nil, "Slot 3 must contain a Weapon, Tool, or Equipment item"
	end
	local inventory = player:FindFirstChild("MaterialInventory")
	local count = inventory and inventory:FindFirstChild(template.Name)
	if not count or not count:IsA("IntValue") or count.Value <= 0 then
		return nil, "The slot 3 item is no longer in Inventory"
	end

	local itemId = slot:GetAttribute("ItemId")
	local record
	if ItemRegistry.IsWeapon(template) then
		record = typeof(itemId) == "string" and WeaponRecordService.GetById(player, itemId) or nil
		if not record
			or record:GetAttribute("ItemName") ~= template.Name
			or record:GetAttribute("Location") ~= "Inventory"
			or (tonumber(record:GetAttribute("QuickSlot")) or 0) ~= 3
			or record:GetAttribute("Broken") == true
		then
			return nil, "The exact slot 3 weapon or tool is unavailable"
		end
	elseif ArmorRecordService.IsArmor(template) then
		record = typeof(itemId) == "string" and ArmorRecordService.GetById(player, itemId) or nil
		if not record
			or record:GetAttribute("ItemName") ~= template.Name
			or record:GetAttribute("Location") ~= "Inventory"
			or record:GetAttribute("Broken") == true
			or (tonumber(record:GetAttribute("CurrentDurability")) or 0) <= 0
		then
			return nil, "The exact slot 3 equipment item is unavailable"
		end
	end

	local displayName = record and record:GetAttribute("CraftedName") or template.Name
	return {
		DisplayItem = {
			ItemName = template.Name,
			ItemType = itemType,
			DisplayName = typeof(displayName) == "string" and displayName or template.Name,
			VisualAttributes = copyVisualAttributes(record or template),
		},
	}
end

function ItemDisplay.HandleOwnerClick(context, player)
	if player ~= context.Owner or player.Parent ~= Players then
		return false
	end
	if not context.IsActive() then
		return false
	end
	local surface = context.Model:FindFirstChild("DisplaySurface", true)
	if not surface or not surface:IsA("BasePart") then
		return false
	end
	local maxDistance = math.max(1, tonumber(context.MaxDistance) or 12)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - surface.Position).Magnitude > maxDistance + 2 then
		notify(player, "Move closer to the item display")
		return false
	end
	local now = os.clock()
	if (lastClickAt[player] or 0) + CLICK_COOLDOWN > now then
		return false
	end
	lastClickAt[player] = now

	local newState, stateError = readSlotThree(player)
	if not newState then
		notify(player, stateError or "The slot 3 item cannot be displayed")
		return false
	end
	context.Record.FunctionState = ItemDisplay.SanitizeState(newState)
	renderDisplay(context)
	local message = context.Record.FunctionState.DisplayItem
		and (context.Record.FunctionState.DisplayItem.DisplayName .. " copied to display")
		or "Item display cleared"
	context.OnChanged(message)
	return true
end

function ItemDisplay.Mount(context)
	local surface = context.Model:FindFirstChild("DisplaySurface", true)
	if not surface or not surface:IsA("BasePart") then
		warn("[House] ItemDisplay furniture is missing DisplaySurface:", context.Model:GetFullName())
		return nil
	end

	renderDisplay(context)
	local oldDetector = surface:FindFirstChild("HouseItemDisplayClick")
	if oldDetector then
		oldDetector:Destroy()
	end
	local detector = Instance.new("ClickDetector")
	detector.Name = "HouseItemDisplayClick"
	detector.MaxActivationDistance = math.max(1, tonumber(context.MaxDistance) or 12)
	detector.Parent = surface

	local connection = detector.MouseClick:Connect(function(player)
		ItemDisplay.HandleOwnerClick(context, player)
	end)

	return function()
		connection:Disconnect()
		if detector.Parent then
			detector:Destroy()
		end
	end
end

function ItemDisplay.Cleanup(context)
	destroyDisplayedVisual(context and context.Model)
end

return ItemDisplay

