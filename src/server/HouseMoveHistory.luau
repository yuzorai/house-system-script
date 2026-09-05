-- History contains trusted transforms only; replay never grants or removes inventory items.
local History = {}

function History.Record(session, placementId, before, after, limit)
	if before == after then return end
	session.MoveHistory = session.MoveHistory or {Undo = {}, Redo = {}}
	local state = session.MoveHistory
	table.clear(state.Redo)
	table.insert(state.Undo, {PlacementId = placementId, Before = before, After = after})
	while #state.Undo > (limit or 40) do table.remove(state.Undo, 1) end
end

function History.Peek(session, action)
	local state = session.MoveHistory
	local stack = state and state[action]
	return stack and stack[#stack]
end

function History.Commit(session, action)
	local state = session.MoveHistory
	local item = table.remove(state[action])
	if item then table.insert(state[action == "Undo" and "Redo" or "Undo"], item) end
end

function History.Remove(session, placementId)
	for _, stack in pairs(session.MoveHistory or {}) do
		for i = #stack, 1, -1 do if stack[i].PlacementId == placementId then table.remove(stack, i) end end
	end
end

return History
