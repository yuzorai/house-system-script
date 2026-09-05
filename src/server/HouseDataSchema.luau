local Schema = {}
function Schema.new(Config, FurnitureFunctionRegistry)
local function isFiniteNumber(value)
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
		and math.abs(value) < 1000000
end

local function encodeCFrame(cf)
	return {cf:GetComponents()}
end

local function decodeCFrame(data)
	if typeof(data) ~= "table" or #data ~= 12 then
		return nil
	end
	for _, value in ipairs(data) do
		if not isFiniteNumber(value) then
			return nil
		end
	end
	local ok, cf = pcall(CFrame.new, table.unpack(data))
	return ok and cf or nil
end

local HOUSE_ACCESS_ORDER = {"Private", "Public"}
local HOUSE_ACCESS_SET = {
	Private = true,
	Public = true,
}

local function sanitizeHouseAccess(value)
	return typeof(value) == "string" and HOUSE_ACCESS_SET[value] and value or "Private"
end

local function defaultData()
	return {
		Version = Config.DataVersion,
		SelectedHouse = nil,
		HouseKind = "Virtual",
		PhysicalHouseId = nil,
		Revision = 0,
		Placements = {},
		TaxReserve = 0,
		TaxDueAmount = 0,
		NextTaxDueAt = nil,
		UpgradeStage = 0,
		HouseAccess = "Private",
	}
end

local function sanitizeTaxAmount(value)
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function sanitizeTimestamp(value)
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	value = math.floor(value)
	if value < 0 or value > 4102444800 then
		return nil
	end
	return value
end

local function sanitizeLoadedData(raw)
	if typeof(raw) ~= "table" then
		return defaultData()
	end
	local result = defaultData()
	if typeof(raw.SelectedHouse) == "string" and raw.SelectedHouse ~= "" then
		result.SelectedHouse = raw.SelectedHouse
	end
	local rawPhysicalId = typeof(raw.PhysicalHouseId) == "string" and raw.PhysicalHouseId or nil
	if not rawPhysicalId and typeof(result.SelectedHouse) == "string" then
		rawPhysicalId = string.match(result.SelectedHouse, "^Physical:(.+)$")
	end
	if (raw.HouseKind == "Physical" or (typeof(result.SelectedHouse) == "string" and string.match(result.SelectedHouse, "^Physical:")))
		and rawPhysicalId and rawPhysicalId ~= ""
	then
		result.HouseKind = "Physical"
		result.PhysicalHouseId = rawPhysicalId
		result.SelectedHouse = "Physical:" .. rawPhysicalId
	else
		result.HouseKind = "Virtual"
		result.PhysicalHouseId = nil
	end
	result.Revision = sanitizeTaxAmount(raw.Revision)
	result.TaxReserve = sanitizeTaxAmount(raw.TaxReserve)
	result.TaxDueAmount = sanitizeTaxAmount(raw.TaxDueAmount)
	result.NextTaxDueAt = sanitizeTimestamp(raw.NextTaxDueAt)
	result.UpgradeStage = sanitizeTaxAmount(raw.UpgradeStage)
	result.HouseAccess = sanitizeHouseAccess(raw.HouseAccess)
	if result.TaxDueAmount > 0 then
		result.NextTaxDueAt = nil
	end
	if typeof(raw.Placements) == "table" then
		for _, placement in ipairs(raw.Placements) do
			if typeof(placement) == "table"
				and typeof(placement.PlacementId) == "string"
				and placement.PlacementId ~= ""
				and typeof(placement.ItemName) == "string"
				and placement.ItemName ~= ""
				and decodeCFrame(placement.LocalCFrame)
			then
				table.insert(result.Placements, {
					PlacementId = placement.PlacementId,
					ItemName = placement.ItemName,
					LocalCFrame = table.clone(placement.LocalCFrame),
					FunctionState = FurnitureFunctionRegistry.SanitizeState(placement.FunctionState),
					CraftedRecordId = typeof(placement.CraftedRecordId) == "string" and placement.CraftedRecordId or nil,
					CraftedFinish = typeof(placement.CraftedFinish) == "table" and {
						Wood1Name = typeof(placement.CraftedFinish.Wood1Name) == "string" and placement.CraftedFinish.Wood1Name or nil,
						Wood2Name = typeof(placement.CraftedFinish.Wood2Name) == "string" and placement.CraftedFinish.Wood2Name or nil,
					} or nil,
				})
			else
				warn("[House] Skipped one malformed saved furniture placement.")
			end
		end
	end
	return result
end


return {Default = defaultData, Sanitize = sanitizeLoadedData, Serialize = sanitizeLoadedData,
    EncodeCFrame = encodeCFrame, DecodeCFrame = decodeCFrame, IsFiniteNumber = isFiniteNumber,
    SanitizeTaxAmount = sanitizeTaxAmount, SanitizeTimestamp = sanitizeTimestamp,
    SanitizeAccess = sanitizeHouseAccess, AccessOrder = HOUSE_ACCESS_ORDER, AccessSet = HOUSE_ACCESS_SET}
end
return Schema
