-- Small state patches share the existing SessionState remote; full state remains the recovery path.
local Snapshot = {}

function Snapshot.Equal(a, b)
	if typeof(a) ~= typeof(b) then return false end
	if typeof(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not Snapshot.Equal(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

function Snapshot.Diff(previous, current)
	local delta = {Kind = "Delta", Active = true, SessionId = current.SessionId,
		BaseSequence = previous.StreamSequence, StreamSequence = current.StreamSequence,
		Changes = {}, Removed = {}, Placements = {}, RemovedPlacements = {}}
	for key, value in pairs(current) do
		if key ~= "Placements" and not Snapshot.Equal(value, previous[key]) then delta.Changes[key] = value end
	end
	for key in pairs(previous) do
		if key ~= "Placements" and current[key] == nil then table.insert(delta.Removed, key) end
	end
	local old, new = {}, {}
	for _, entry in ipairs(previous.Placements or {}) do old[entry.PlacementId] = entry end
	for _, entry in ipairs(current.Placements or {}) do
		new[entry.PlacementId] = true
		if not Snapshot.Equal(entry, old[entry.PlacementId]) then table.insert(delta.Placements, entry) end
	end
	for id in pairs(old) do if not new[id] then table.insert(delta.RemovedPlacements, id) end end
	return delta
end

function Snapshot.Apply(previous, delta)
	if not previous or previous.SessionId ~= delta.SessionId or previous.StreamSequence ~= delta.BaseSequence then
		return nil, "Resync"
	end
	local nextState = table.clone(previous)
	for key, value in pairs(delta.Changes or {}) do nextState[key] = value end
	for _, key in ipairs(delta.Removed or {}) do nextState[key] = nil end
	nextState.StreamSequence = delta.StreamSequence
	local entries = {}
	for _, entry in ipairs(previous.Placements or {}) do entries[entry.PlacementId] = entry end
	for _, id in ipairs(delta.RemovedPlacements or {}) do entries[id] = nil end
	for _, entry in ipairs(delta.Placements or {}) do entries[entry.PlacementId] = entry end
	nextState.Placements = {}
	for _, entry in pairs(entries) do table.insert(nextState.Placements, entry) end
	table.sort(nextState.Placements, function(a, b) return a.PlacementId < b.PlacementId end)
	return nextState
end

return Snapshot
