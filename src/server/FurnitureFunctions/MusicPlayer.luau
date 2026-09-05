local Players = game:GetService("Players")

local MusicPlayer = {}

local CLICK_COOLDOWN = 0.35
local ACTION_COOLDOWN = 0.5
local MAX_ASSET_ID_LENGTH = 20
local lastClickAt = setmetatable({}, {__mode = "k"})
local lastActionAt = setmetatable({}, {__mode = "k"})

local function trim(value)
	return string.match(value, "^%s*(.-)%s*$") or ""
end

local function sanitizeSoundId(value, allowEmpty)
	if typeof(value) ~= "string" then
		return nil, "Enter a numeric Music Asset ID"
	end
	value = trim(value)
	if value == "" then
		if allowEmpty then
			return ""
		end
		return nil, "Music Asset ID is empty"
	end
	if #value > MAX_ASSET_ID_LENGTH or not string.match(value, "^%d+$") then
		return nil, "Music Asset ID must contain numbers only"
	end
	local numeric = tonumber(value)
	if not numeric or numeric <= 0 then
		return nil, "Music Asset ID must be greater than 0"
	end
	return value
end

local function findEmitter(model)
	if not model then
		return nil, nil
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Sound") and descendant.Name == "Sound" and descendant.Parent:IsA("BasePart") then
			return descendant.Parent, descendant
		end
	end
	return nil, nil
end

local function validateOwnerAndDistance(context, player)
	if player ~= context.Owner or not player or player.Parent ~= Players then
		return false, "Only the house owner can edit this music player"
	end
	if not context.IsActive() then
		return false, "This music player is no longer active"
	end
	local emitter = findEmitter(context.Model)
	if not emitter then
		return false, "MusicPlayer furniture is missing its Sound"
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local maxDistance = math.max(1, tonumber(context.MaxDistance) or 8)
	if not root or (root.Position - emitter.Position).Magnitude > maxDistance + 2 then
		return false, "Move closer to the music player"
	end
	return true, nil, emitter
end

function MusicPlayer.SanitizeState(rawState)
	if typeof(rawState) ~= "table" or typeof(rawState.MusicPlayer) ~= "table" then
		return {}
	end
	local soundId = sanitizeSoundId(rawState.MusicPlayer.SoundId, true)
	if not soundId or soundId == "" then
		return {}
	end
	return {
		MusicPlayer = {
			SoundId = soundId,
		},
	}
end

function MusicPlayer.HandleOwnerClick(context, player)
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
	local musicState = typeof(state) == "table" and state.MusicPlayer or nil
	context.OpenEditor(player, {
		Open = true,
		FunctionName = "MusicPlayer",
		PlacementId = context.Record.PlacementId,
		SoundId = typeof(musicState) == "table" and musicState.SoundId or "",
	})
	return true
end

function MusicPlayer.HandleOwnerAction(context, player, action, payload)
	local valid, reason = validateOwnerAndDistance(context, player)
	if not valid then
		return false, reason
	end
	local now = os.clock()
	if (lastActionAt[player] or 0) + ACTION_COOLDOWN > now then
		return false, "Please wait before changing the music again"
	end
	lastActionAt[player] = now
	if action ~= "Set" then
		return false, "Unsupported music player action"
	end
	if typeof(payload) ~= "table" then
		return false, "Music request is invalid"
	end
	local soundId, soundError = sanitizeSoundId(payload.SoundId, true)
	if soundId == nil then
		return false, soundError
	end
	if soundId == "" then
		context.Record.FunctionState = {}
		context.OnChanged()
		return true, "Music cleared", {SoundId = ""}
	end
	context.Record.FunctionState = MusicPlayer.SanitizeState({
		MusicPlayer = {SoundId = soundId},
	})
	context.OnChanged()
	return true, "Music updated", {SoundId = soundId}
end

function MusicPlayer.Mount(context)
	local emitter, sound = findEmitter(context.Model)
	if not emitter or not sound then
		warn("[House] MusicPlayer furniture is missing a Sound parented to a BasePart:", context.Model:GetFullName())
		return nil
	end
	sound:Stop()
	sound.SoundId = ""
	sound.Looped = true
	local oldDetector = emitter:FindFirstChild("HouseMusicPlayerClick")
	if oldDetector then
		oldDetector:Destroy()
	end
	local detector = Instance.new("ClickDetector")
	detector.Name = "HouseMusicPlayerClick"
	detector.MaxActivationDistance = math.max(1, tonumber(context.MaxDistance) or 8)
	detector.Parent = emitter
	local connection = detector.MouseClick:Connect(function(player)
		MusicPlayer.HandleOwnerClick(context, player)
	end)
	return function()
		connection:Disconnect()
		if detector.Parent then
			detector:Destroy()
		end
		if sound.Parent then
			sound:Stop()
			sound.SoundId = ""
		end
	end
end

function MusicPlayer.Cleanup(context)
	local _, sound = findEmitter(context and context.Model)
	if sound then
		sound:Stop()
		sound.SoundId = ""
	end
end

return MusicPlayer
