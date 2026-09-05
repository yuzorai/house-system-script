local Service = {}
function Service.new(ctx)
local ReplicatedStorage, Workspace = game:GetService("ReplicatedStorage"), game:GetService("Workspace")
local Config, furnitureFolder = ctx.Config, ctx.FurnitureFolder
local FurnitureFunctionRegistry, isFiniteNumber = ctx.Registry, ctx.IsFiniteNumber
local Geometry = ctx.Geometry
local invalidSeatTemplateWarnings = setmetatable({}, {__mode = "k"})
local function isVisiblePart(part)
	return part:IsA("BasePart") and part.Transparency < 0.99
end

local function findFurnitureTemplate(itemName)
	if typeof(itemName) ~= "string" or itemName == "" then
		return nil
	end
	local found
	for _, object in ipairs(furnitureFolder:GetDescendants()) do
		if object.Name == itemName
			and (object:IsA("Model") or object:IsA("BasePart"))
			and object.Parent
			and object.Parent:IsA("Folder")
		then
			local hasVisiblePart = object:IsA("BasePart") and isVisiblePart(object)
			if object:IsA("Model") then
				for _, descendant in ipairs(object:GetDescendants()) do
					if isVisiblePart(descendant) then
						hasVisiblePart = true
						break
					end
				end
			end
			if hasVisiblePart then
				if found then
					warn(("[House] Multiple furniture templates are named %s. The first one is used."):format(itemName))
				end
				found = found or object
			end
		end
	end
	return found
end

local function findCraftedFurnitureRecord(player, itemName, recordId, requiredLocation)
	local folder = player and player:FindFirstChild("CraftedFurnitureRecords")
	if not folder then return nil end
	for _, record in ipairs(folder:GetChildren()) do
		if record:IsA("Folder")
			and record:GetAttribute("ItemName") == itemName
			and (not recordId or record.Name == recordId)
			and (not requiredLocation or record:GetAttribute("Location") == requiredLocation)
		then
			return record
		end
	end
	return nil
end

local function craftedFinishFromRecord(record)
	if not record then return nil end
	local wood1 = record:GetAttribute("Wood1Name")
	local wood2 = record:GetAttribute("Wood2Name")
	if typeof(wood1) ~= "string" and typeof(wood2) ~= "string" then return nil end
	return {
		Wood1Name = typeof(wood1) == "string" and wood1 or nil,
		Wood2Name = typeof(wood2) == "string" and wood2 or nil,
	}
end

local function craftedWoodColor(woodName)
	if typeof(woodName) ~= "string" then return nil end
	local items = ReplicatedStorage:FindFirstChild("Items")
	local woods = items and items:FindFirstChild("Wood")
	local wood = woods and woods:FindFirstChild(woodName)
	local hex = wood and wood:GetAttribute("CraftingColorHex")
	if typeof(hex) ~= "string" then return nil end
	hex = hex:gsub("#", "")
	if #hex ~= 6 then return nil end
	local red, green, blue = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	if not (red and green and blue) then return nil end
	local hue, saturation, value = Color3.fromRGB(red, green, blue):ToHSV()
	return Color3.fromHSV(hue, saturation * 0.65, value * 0.72)
end

local function partIsInsideGroup(part, root, groupName)
	local current = part.Parent
	while current and current ~= root do
		if current.Name == groupName then return true end
		current = current.Parent
	end
	return false
end

local function applyCraftedFurnitureFinish(model, finish)
	if typeof(finish) ~= "table" then return end
	local wood1Color = craftedWoodColor(finish.Wood1Name)
	local wood2Color = craftedWoodColor(finish.Wood2Name)
	if not wood1Color and not wood2Color then return end
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			if wood1Color and partIsInsideGroup(object, model, "Wood1") then
				object.Color = wood1Color
			elseif wood2Color and partIsInsideGroup(object, model, "Wood2") then
				object.Color = wood2Color
			end
		end
	end
end

local function sanitizeFurnitureClone(template)
	local model
	if template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		model.Name = template.Name
		local part = template:Clone()
		part.Parent = model
		model.PrimaryPart = part
	end
	model.Name = template.Name
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("LuaSourceContainer")
			or object:IsA("ProximityPrompt")
			or object:IsA("ClickDetector")
			or object:IsA("TouchTransmitter")
		then
			object:Destroy()
		elseif object:IsA("BasePart") then
			object.Anchored = true
			local isInvisibleSeat = object:IsA("Seat") and object.Transparency >= 0.99 and not object.CanCollide
			object.CanQuery = not isInvisibleSeat
			object.CanTouch = object:IsA("Seat")
			object.Massless = false
		end
	end
	return model
end

local function templateHasNativeSeat(template)
	if template and template:IsA("Seat") then
		return true
	end
	if template then
		for _, object in ipairs(template:GetDescendants()) do
			if object:IsA("Seat") then
				return true
			end
		end
	end
	return false
end

local function validateFurnitureTemplate(template)
	if not template then
		return false, "That furniture template is unavailable"
	end
	if FurnitureFunctionRegistry.GetFunctionName(template) ~= "Seat" then
		return true
	end
	if templateHasNativeSeat(template) then
		return true
	end
	if not invalidSeatTemplateWarnings[template] then
		invalidSeatTemplateWarnings[template] = true
		warn(("[House] Seating furniture %s is missing a native Roblox Seat and cannot be placed."):format(template:GetFullName()))
	end
	return false, "This seating furniture template is missing a Roblox Seat"
end

local function isFurnitureOccupied(model)
	if not model then
		return false
	end
	if model:IsA("Seat") and model.Occupant then
		return true
	end
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("Seat") and object.Occupant then
			return true
		end
	end
	return false
end

local function getVisibleBounds(model)
	local minVector
	local maxVector
	for _, object in ipairs(model:GetDescendants()) do
		if isVisiblePart(object) then
			local half = object.Size * 0.5
			for _, x in ipairs({-1, 1}) do
				for _, y in ipairs({-1, 1}) do
					for _, z in ipairs({-1, 1}) do
						local point = object.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						minVector = minVector and Vector3.new(
							math.min(minVector.X, point.X),
							math.min(minVector.Y, point.Y),
							math.min(minVector.Z, point.Z)
						) or point
						maxVector = maxVector and Vector3.new(
							math.max(maxVector.X, point.X),
							math.max(maxVector.Y, point.Y),
							math.max(maxVector.Z, point.Z)
						) or point
					end
				end
			end
		end
	end
	if not minVector or not maxVector then
		return nil
	end
	return (minVector + maxVector) * 0.5, maxVector - minVector, minVector, maxVector
end

local function boundsContainPoint(boundsFolder, point, upgradeStage)
	upgradeStage = math.max(0, math.floor(tonumber(upgradeStage) or 0))
	for _, bound in ipairs(boundsFolder:GetChildren()) do
		if bound:IsA("BasePart") then
			local requiredStage = math.max(0, math.floor(tonumber(bound:GetAttribute("RequiredUpgradeStage")) or 0))
			if requiredStage <= upgradeStage then
				local localPoint = bound.CFrame:PointToObjectSpace(point)
				local half = bound.Size * 0.5 + Vector3.new(0.2, 0.2, 0.2)
				if math.abs(localPoint.X) <= half.X
					and math.abs(localPoint.Y) <= half.Y
					and math.abs(localPoint.Z) <= half.Z
				then
					return true
				end
			end
		end
	end
	return false
end

local function getFurniturePlacementNormal(model)
	if model:GetAttribute("HouseFunction") ~= "ItemDisplay" then
		return Vector3.yAxis
	end
	local pivot = model:GetPivot()
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("DisplaySurface") == true then
			local displayNormal = object:GetAttribute("DisplayNormal")
			if typeof(displayNormal) == "Vector3" and displayNormal.Magnitude > 0.001 then
				local worldNormal = object.CFrame:VectorToWorldSpace(displayNormal.Unit)
				local localNormal = pivot:VectorToObjectSpace(worldNormal)
				if localNormal.Magnitude > 0.001 then
					return localNormal.Unit
				end
			end
		end
	end
	return Vector3.yAxis
end

local function getAlignmentRotation(fromDirection, toDirection)
	local from = fromDirection.Unit
	local to = toDirection.Unit
	local dot = math.clamp(from:Dot(to), -1, 1)
	if dot > 0.999999 then
		return CFrame.identity
	end
	if dot < -0.999999 then
		local reference = math.abs(from:Dot(Vector3.xAxis)) < 0.9 and Vector3.xAxis or Vector3.yAxis
		return CFrame.fromAxisAngle(from:Cross(reference).Unit, math.pi)
	end
	local axis = from:Cross(to)
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function getSurfaceCFrame(position, normal, rotation, placementNormal)
	normal = normal.Unit
	local surfaceCFrame
	if normal.Y >= 0.999 then
		surfaceCFrame = CFrame.new(position)
	else
		local reference = math.abs(normal:Dot(Vector3.yAxis)) > 0.95 and Vector3.zAxis or Vector3.yAxis
		local right = reference:Cross(normal)
		if right.Magnitude < 0.001 then
			right = Vector3.xAxis
		end
		right = right.Unit
		local back = right:Cross(normal).Unit
		surfaceCFrame = CFrame.fromMatrix(position, right, normal, back)
	end
	local userRotation = CFrame.Angles(
		math.rad(rotation.X),
		math.rad(rotation.Y),
		math.rad(rotation.Z)
	)
	local alignment = getAlignmentRotation(placementNormal or Vector3.yAxis, Vector3.yAxis)
	return surfaceCFrame * userRotation * alignment
end

local function getVisibleProjectionRange(model, axis)
	local minimum = math.huge
	local maximum = -math.huge
	local found = false
	for _, object in ipairs(model:GetDescendants()) do
		if isVisiblePart(object) then
			local half = object.Size * 0.5
			for _, x in ipairs({-1, 1}) do
				for _, y in ipairs({-1, 1}) do
					for _, z in ipairs({-1, 1}) do
						local corner = object.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						local projection = corner:Dot(axis)
						minimum = math.min(minimum, projection)
						maximum = math.max(maximum, projection)
						found = true
					end
				end
			end
		end
	end
	if not found then return nil end
	return minimum, maximum
end

local function resolveSurface(session, desiredPosition, requestedNormal, ignoredModel)
	local surfaceNormal = requestedNormal.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {session.BoundsFolder}
	for participant in pairs(session.Participants or {}) do
		if participant.Character then
			table.insert(excluded, participant.Character)
		end
	end
	if ignoredModel then
		table.insert(excluded, ignoredModel)
	end
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	local startPoint = desiredPosition + surfaceNormal * 2.5
	local result = Workspace:Raycast(startPoint, -surfaceNormal * 5, params)
	if not result
		or not result.Instance
		or not result.Instance:IsDescendantOf(session.House)
		or result.Instance.Name == "HouseSpawn"
		or result.Normal.Unit:Dot(surfaceNormal) < 0.75
		or (result.Position - desiredPosition).Magnitude > 1.5
	then
		return nil, "Furniture needs a valid house or furniture surface"
	end
	return result
end

local function preparePlacement(session, template, desiredPosition, surfaceNormal, requestedRotation, ignoredModel)
	local templateIsValid, templateError = validateFurnitureTemplate(template)
	if not templateIsValid then
		return nil, nil, templateError
	end
	if typeof(desiredPosition) ~= "Vector3"
		or typeof(surfaceNormal) ~= "Vector3"
		or not isFiniteNumber(desiredPosition.X)
		or not isFiniteNumber(desiredPosition.Y)
		or not isFiniteNumber(desiredPosition.Z)
		or not isFiniteNumber(surfaceNormal.X)
		or not isFiniteNumber(surfaceNormal.Y)
		or not isFiniteNumber(surfaceNormal.Z)
		or surfaceNormal.Magnitude < 0.9
	then
		return nil, nil, "Invalid placement values"
	end

	local rotation
	if typeof(requestedRotation) == "Vector3"
		and isFiniteNumber(requestedRotation.X)
		and isFiniteNumber(requestedRotation.Y)
		and isFiniteNumber(requestedRotation.Z)
	then
		rotation = requestedRotation
	elseif isFiniteNumber(requestedRotation) then
		rotation = Vector3.new(0, requestedRotation, 0)
	else
		return nil, nil, "Invalid rotation values"
	end
	rotation = Vector3.new(
		((rotation.X % 360) + 360) % 360,
		((rotation.Y % 360) + 360) % 360,
		((rotation.Z % 360) + 360) % 360
	)

	surfaceNormal = surfaceNormal.Unit
	local surfaceResult, surfaceError = resolveSurface(session, desiredPosition, surfaceNormal, ignoredModel)
	if not surfaceResult then
		return nil, nil, surfaceError
	end
	surfaceNormal = surfaceResult.Normal.Unit
	if not boundsContainPoint(session.BoundsFolder, surfaceResult.Position, session.UpgradeStage) then
		return nil, nil, "The placement cursor must stay inside the house build area"
	end
	local model = sanitizeFurnitureClone(template)
	local placementNormal = getFurniturePlacementNormal(model)
	model:PivotTo(getSurfaceCFrame(surfaceResult.Position, surfaceNormal, rotation, placementNormal))
	local center, size, minVector = getVisibleBounds(model)
	local minimumProjection = getVisibleProjectionRange(model, surfaceNormal)
	if not center or not minimumProjection then
		model:Destroy()
		return nil, nil, "Furniture has no visible geometry"
	end
	local cursorOffset = surfaceResult.Position - center
	local tangentOffset = cursorOffset - surfaceNormal * cursorOffset:Dot(surfaceNormal)
	local surfaceOffset = surfaceNormal * (
		surfaceResult.Position:Dot(surfaceNormal) - minimumProjection + 0.02
	)
	model:PivotTo(model:GetPivot() + tangentOffset + surfaceOffset)
	local fits, reason = Geometry.ValidateModel(model, session.BoundsFolder, session.UpgradeStage)
    if not fits then model:Destroy(); return nil, nil, reason end
    return model, model:GetPivot()
end


return {
isVisiblePart = isVisiblePart,
findFurnitureTemplate = findFurnitureTemplate,
findCraftedFurnitureRecord = findCraftedFurnitureRecord,
craftedFinishFromRecord = craftedFinishFromRecord,
craftedWoodColor = craftedWoodColor,
partIsInsideGroup = partIsInsideGroup,
applyCraftedFurnitureFinish = applyCraftedFurnitureFinish,
sanitizeFurnitureClone = sanitizeFurnitureClone,
templateHasNativeSeat = templateHasNativeSeat,
validateFurnitureTemplate = validateFurnitureTemplate,
isFurnitureOccupied = isFurnitureOccupied,
getVisibleBounds = getVisibleBounds,
boundsContainPoint = boundsContainPoint,
getFurniturePlacementNormal = getFurniturePlacementNormal,
getAlignmentRotation = getAlignmentRotation,
getSurfaceCFrame = getSurfaceCFrame,
getVisibleProjectionRange = getVisibleProjectionRange,
resolveSurface = resolveSurface,
preparePlacement = preparePlacement,
}
end
return Service
