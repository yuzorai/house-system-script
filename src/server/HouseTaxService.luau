local Service = {}
function Service.new(ctx)
local Config, caches, getHouseTemplate = ctx.Config, ctx.Caches, ctx.GetHouseTemplate
local notify, scheduleSave, houseTaxState = ctx.Notify, ctx.ScheduleSave, ctx.TaxState
local function getWeeklyTaxForData(data)
	local template = getHouseTemplate(data and data.SelectedHouse)
	if not template then
		return 0, nil
	end
	return math.max(0, math.floor(tonumber(template:GetAttribute("WeeklyTax")) or 0)), template
end

local function updateHouseTaxDue(player)
	local cache = caches[player]
	if not cache then
		return false
	end
	local data = cache.Data
	if typeof(data.SelectedHouse) ~= "string" or data.SelectedHouse == "" then
		return false
	end

	local weeklyTax, template = getWeeklyTaxForData(data)
	if not template then
		return false
	end

	local changed = false
	if data.TaxDueAmount > 0 then
		if data.NextTaxDueAt ~= nil then
			data.NextTaxDueAt = nil
			changed = true
		end
		return changed
	end

	local now = os.time()
	if data.NextTaxDueAt == nil then
		data.NextTaxDueAt = now + Config.TaxIntervalSeconds
		changed = true
	elseif data.NextTaxDueAt <= now then
		data.NextTaxDueAt = nil
		if weeklyTax > 0 then
			data.TaxDueAmount = weeklyTax
			notify(player, "House Taxes Due", ("Pay %d %s before entering your house."):format(weeklyTax, Config.HouseCurrency))
		else
			data.NextTaxDueAt = now + Config.TaxIntervalSeconds
		end
		changed = true
	end
	return changed
end

local initializeTaxSchedule
initializeTaxSchedule = function(player)
	local changed = updateHouseTaxDue(player)
	if changed then
		scheduleSave(player)
	end
	return changed
end

local function buildTaxStatus(player)
	local cache = caches[player]
	if not cache then
		return {
			Loaded = false,
			Currency = Config.HouseCurrency,
		}
	end
	initializeTaxSchedule(player)
	local data = cache.Data
	local weeklyTax, template = getWeeklyTaxForData(data)
	local hasHouse = typeof(data.SelectedHouse) == "string" and data.SelectedHouse ~= "" and template ~= nil
	return {
		Loaded = true,
		HasHouse = hasHouse,
		HouseName = data.SelectedHouse,
		Currency = Config.HouseCurrency,
		WeeklyTax = weeklyTax,
		TaxReserve = data.TaxReserve,
		TaxDueAmount = data.TaxDueAmount,
		NextTaxDueAt = data.NextTaxDueAt,
		HouseEntryBlocked = data.TaxDueAmount > 0,
	}
end

local function sendTaxState(player, success, message)
	houseTaxState:FireClient(player, buildTaxStatus(player), success, message)
end


return {GetWeeklyTax = getWeeklyTaxForData, UpdateDue = updateHouseTaxDue, Initialize = initializeTaxSchedule,
    BuildStatus = buildTaxStatus, SendState = sendTaxState}
end
return Service
