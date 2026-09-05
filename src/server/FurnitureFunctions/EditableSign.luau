local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local moderationConfig = script.Parent.Parent:WaitForChild("SignModeration")
local blockedTermsFolder = moderationConfig:WaitForChild("BlockedTerms")

local EditableSign = {}

local CLICK_COOLDOWN = 0.35
local ACTION_COOLDOWN = 0.5
local MAX_TEXT_LENGTH = 140
local lastClickAt = setmetatable({}, {__mode = "k"})
local lastActionAt = setmetatable({}, {__mode = "k"})

local function normalizeText(value)
	if typeof(value) ~= "string" then
		return nil, "Enter text for the sign"
	end
	value = string.gsub(value, "\r\n", "\n")
	value = string.gsub(value, "\r", "\n")
	value = string.gsub(value, "[%z\1-\8\11\12\14-\31\127]", "")
	local length = utf8.len(value)
	if not length then
		return nil, "Sign text contains invalid characters"
	end
	if length > MAX_TEXT_LENGTH then
		return nil, ("Sign text cannot be longer than %d characters"):format(MAX_TEXT_LENGTH)
	end
	return value
end

local function isWordCharacter(character)
	return character ~= "" and string.match(character, "[%a%d]") ~= nil
end

local function getBlockedTerms()
	local terms = {}
	for _, entry in ipairs(blockedTermsFolder:GetChildren()) do
		if entry:IsA("StringValue") then
			local value = string.lower(entry.Value)
			if value ~= "" and #value <= 80 then
				table.insert(terms, value)
			end
		end
	end
	table.sort(terms, function(left, right)
		return #left > #right
	end)
	return terms
end

local function censorConfiguredTerms(text)
	local replacement = moderationConfig:GetAttribute("ReplacementCharacter")
	if typeof(replacement) ~= "string" or replacement == "" then
		replacement = "#"
	end
	replacement = string.sub(replacement, 1, 1)
	local lowered = string.lower(text)
	local maskedBytes = {}
	for _, term in ipairs(getBlockedTerms()) do
		local searchFrom = 1
		while true do
			local startAt, endAt = string.find(lowered, term, searchFrom, true)
			if not startAt then
				break
			end
			local before = startAt > 1 and string.sub(lowered, startAt - 1, startAt - 1) or ""
			local after = endAt < #lowered and string.sub(lowered, endAt + 1, endAt + 1) or ""
			if not isWordCharacter(before) and not isWordCharacter(after) then
				for byteIndex = startAt, endAt do
					maskedBytes[byteIndex] = true
				end
			end
			searchFrom = endAt + 1
		end
	end
	if not next(maskedBytes) then
		return text, false
	end
	local output = table.create(#text)
	for byteIndex = 1, #text do
		output[byteIndex] = maskedBytes[byteIndex] and replacement or string.sub(text, byteIndex, byteIndex)
	end
	return table.concat(output), true
end

local function findTextLabels(model)
	local labels = {}
	if not model then
		return labels
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			for _, child in ipairs(descendant:GetDescendants()) do
				if child:IsA("TextLabel") then
					table.insert(labels, child)
				end
			end
		end
	end
	return labels
end

local function findDisplayParts(model)
	local parts = {}
	local seen = {}
	local function check(candidate)
		if not candidate:IsA("BasePart") or seen[candidate] then
			return
		end
		for _, child in ipairs(candidate:GetChildren()) do
			if child:IsA("SurfaceGui") and child:FindFirstChildWhichIsA("TextLabel", true) then
				seen[candidate] = true
				table.insert(parts, candidate)
				return
			end
		end
	end
	if model:IsA("BasePart") then
		check(model)
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		check(descendant)
	end
	return parts
end

local function getCurrentText(model)
	local labels = findTextLabels(model)
	return labels[1] and labels[1].Text or ""
end

local function applyText(model, rawState)
	if typeof(rawState) ~= "table" or typeof(rawState.EditableSign) ~= "table" then
		return
	end
	local text = rawState.EditableSign.Text
	if typeof(text) ~= "string" then
		return
	end
	for _, label in ipairs(findTextLabels(model)) do
		label.Text = text
	end
end

local function validateOwnerAndDistance(context, player)
	if player ~= context.Owner or not player or player.Parent ~= Players then
		return false, "Only the house owner can edit this sign"
	end
	if not context.IsActive() then
		return false, "This sign is no longer active"
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local maxDistance = math.max(1, tonumber(context.MaxDistance) or 8)
	if not root then
		return false, "Move closer to the sign"
	end
	local closestDistance
	for _, part in ipairs(findDisplayParts(context.Model)) do
		local distance = (root.Position - part.Position).Magnitude
		if not closestDistance or distance < closestDistance then
			closestDistance = distance
		end
	end
	if not closestDistance then
		return false, "EditableSign furniture is missing SurfaceGui.TextLabel"
	end
	if closestDistance > maxDistance + 2 then
		return false, "Move closer to the sign"
	end
	return true
end

local function filterForHouse(text, player)
	if text == "" then
		return "", nil, false
	end
	local censoredText, wasCensored = censorConfiguredTerms(text)
	local filterOk, filterResult = pcall(function()
		return TextService:FilterStringAsync(censoredText, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not filterOk or not filterResult then
		return nil, "Could not filter sign text. Please try again"
	end
	local resultOk, filteredText = pcall(function()
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if not resultOk or typeof(filteredText) ~= "string" then
		return nil, "Could not filter sign text. Please try again"
	end
	local normalizedText, normalizeError = normalizeText(filteredText)
	if normalizedText == nil then
		return nil, normalizeError
	end
	local finalText, RobloxCensored = censorConfiguredTerms(normalizedText)
	return finalText, nil, wasCensored or RobloxCensored
end

function EditableSign.SanitizeState(rawState)
	if typeof(rawState) ~= "table" or typeof(rawState.EditableSign) ~= "table" then
		return {}
	end
	local text = normalizeText(rawState.EditableSign.Text)
	if text == nil then
		return {}
	end
	text = censorConfiguredTerms(text)
	return {
		EditableSign = {
			Text = text,
		},
	}
end

function EditableSign.HandleOwnerClick(context, player)
	local valid, reason = validateOwnerAndDistance(context, player)
	if not valid then
		return false, reason
	end
	local now = os.clock()
	if (lastClickAt[player] or 0) + CLICK_COOLDOWN > now then
		return false
	end
	lastClickAt[player] = now
	local state = context.Record.FunctionState
	local saved = typeof(state) == "table" and state.EditableSign or nil
	context.OpenEditor(player, {
		Open = true,
		FunctionName = "EditableSign",
		PlacementId = context.Record.PlacementId,
		Text = typeof(saved) == "table" and typeof(saved.Text) == "string" and saved.Text or getCurrentText(context.Model),
	})
	return true
end

function EditableSign.HandleOwnerAction(context, player, action, payload)
	local valid, reason = validateOwnerAndDistance(context, player)
	if not valid then
		return false, reason
	end
	local now = os.clock()
	if (lastActionAt[player] or 0) + ACTION_COOLDOWN > now then
		return false, "Please wait before changing the sign again"
	end
	lastActionAt[player] = now
	if action ~= "Set" then
		return false, "Unsupported sign action"
	end
	if typeof(payload) ~= "table" then
		return false, "Sign request is invalid"
	end
	local text, textError = normalizeText(payload.Text)
	if text == nil then
		return false, textError
	end
	local filteredText, filterError, wasCensored = filterForHouse(text, player)
	if filteredText == nil then
		return false, filterError
	end
	context.Record.FunctionState = EditableSign.SanitizeState({
		EditableSign = {
			Text = filteredText,
		},
	})
	applyText(context.Model, context.Record.FunctionState)
	context.OnChanged()
	local message = filteredText == "" and "Sign cleared" or (wasCensored and "Sign updated (text censored)" or "Sign updated")
	return true, message, {Text = filteredText}
end

function EditableSign.Mount(context)
	local parts = findDisplayParts(context.Model)
	if #parts == 0 then
		warn("[House] EditableSign furniture is missing a BasePart with SurfaceGui.TextLabel:", context.Model:GetFullName())
		return nil
	end
	applyText(context.Model, context.Record.FunctionState)
	local connections = {}
	local detectors = {}
	for _, part in ipairs(parts) do
		local oldDetector = part:FindFirstChild("HouseEditableSignClick")
		if oldDetector then
			oldDetector:Destroy()
		end
		local detector = Instance.new("ClickDetector")
		detector.Name = "HouseEditableSignClick"
		detector.MaxActivationDistance = math.max(1, tonumber(context.MaxDistance) or 8)
		detector.Parent = part
		table.insert(detectors, detector)
		table.insert(connections, detector.MouseClick:Connect(function(player)
			EditableSign.HandleOwnerClick(context, player)
		end))
	end
	return function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		for _, detector in ipairs(detectors) do
			if detector.Parent then
				detector:Destroy()
			end
		end
	end
end

return EditableSign

