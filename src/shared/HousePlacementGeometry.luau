-- Shared by the build preview and the server. Every visible part must fit in the unlocked volume.
local Geometry = {}
local SIGNS = {-1, 1}
local TOLERANCE = 0.03

local function corners(cf, size)
	local result = {}
	for _, x in ipairs(SIGNS) do for _, y in ipairs(SIGNS) do for _, z in ipairs(SIGNS) do
		table.insert(result, cf:PointToWorldSpace(size * Vector3.new(x, y, z) * 0.5))
	end end end
	return result
end

function Geometry.GetVolumes(folder, stage)
	local volumes = {}
	for _, part in ipairs(folder and folder:GetChildren() or {}) do
		if part:IsA("BasePart") and (tonumber(part:GetAttribute("RequiredUpgradeStage")) or 0) <= (stage or 0) then
			table.insert(volumes, {CFrame = part.CFrame, Half = part.Size * 0.5 + Vector3.one * TOLERANCE})
		end
	end
	return volumes
end

local function inside(volume, point)
	local p = volume.CFrame:PointToObjectSpace(point)
	local h = volume.Half
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

function Geometry.ContainsPoint(volumes, point)
	for _, volume in ipairs(volumes) do if inside(volume, point) then return true end end
	return false
end

-- Splitting proves that each sub-box belongs to a room. Testing only the outer corners
-- would incorrectly accept a box bridging an outside gap between two rooms.
local function covered(cf, size, volumes, budget, depth)
	budget[1] -= 1
	if budget[1] < 0 then return false end
	local points = corners(cf, size)
	for _, volume in ipairs(volumes) do
		local all = true
		for _, p in ipairs(points) do if not inside(volume, p) then all = false; break end end
		if all then return true end
	end
	for _, p in ipairs(points) do if not Geometry.ContainsPoint(volumes, p) then return false end end
	if not Geometry.ContainsPoint(volumes, cf.Position) then return false end
	if depth >= 18 then return false end
	local axis = size.X >= size.Y and size.X >= size.Z and Vector3.xAxis
		or (size.Y >= size.Z and Vector3.yAxis or Vector3.zAxis)
	local length = size:Dot(axis)
	if length <= 0.015 then return false end
	local halfSize = size - axis * length * 0.5
	local offset = axis * length * 0.25
	return covered(cf * CFrame.new(-offset), halfSize, volumes, budget, depth + 1)
		and covered(cf * CFrame.new(offset), halfSize, volumes, budget, depth + 1)
end

function Geometry.ContainsBox(cf, size, volumes)
	return covered(cf, size, volumes, {8192}, 0)
end

function Geometry.ValidateModel(model, folder, stage)
	local volumes = Geometry.GetVolumes(folder, stage)
	if #volumes == 0 then return false, "This house has no unlocked build area." end
	local found = false
	local parts = model:GetDescendants()
	if model:IsA("BasePart") then table.insert(parts, model) end
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and part.Transparency < 0.99 then
			found = true
			if not Geometry.ContainsBox(part.CFrame, part.Size, volumes) then
				return false, "Keep the entire furniture inside an unlocked room."
			end
		end
	end
	if found then return true end
	return false, "Furniture has no visible geometry."
end

function Geometry.SnapSurface(point, normal, origin, step)
	if not step or step <= 0 then return point end
	local reference = math.abs(normal:Dot(origin.UpVector)) < 0.9 and origin.UpVector or origin.RightVector
	local right = reference:Cross(normal).Unit
	local up = normal:Cross(right).Unit
	local relative = point - origin.Position
	local x = math.round(relative:Dot(right) / step) * step
	local y = math.round(relative:Dot(up) / step) * step
	return origin.Position + right * x + up * y + normal * relative:Dot(normal)
end

return Geometry
