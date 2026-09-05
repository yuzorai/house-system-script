local Registry = {}

local handlers = {}

function Registry.Register(functionName, handler)
	if typeof(functionName) ~= "string" or functionName == "" or typeof(handler) ~= "table" then
		error("Furniture function registration is invalid")
	end
	handlers[functionName] = handler
end

function Registry.GetFunctionName(template)
	if not template then
		return "None"
	end
	local value = template:GetAttribute("HouseFunction")
	return typeof(value) == "string" and value ~= "" and value or "None"
end

local function mergeState(target, source)
	if typeof(source) ~= "table" then
		return target
	end
	for key, value in pairs(source) do
		target[key] = value
	end
	return target
end

function Registry.SanitizeState(rawState, template)
	local functionName = template and Registry.GetFunctionName(template) or nil
	if functionName then
		local handler = handlers[functionName]
		if handler and handler.SanitizeState then
			return handler.SanitizeState(rawState)
		end
		return {}
	end
	local result = {}
	for _, handler in pairs(handlers) do
		if handler.SanitizeState then
			mergeState(result, handler.SanitizeState(rawState))
		end
	end
	return result
end

function Registry.SerializeState(state, template)
	function Registry.HasHandler(name)
    return name == "None" or handlers[name] ~= nil
end
Registry.Register("Seat", require(script.Parent:WaitForChild("Seat")))
return Registry.SanitizeState(state, template)
end

function Registry.Mount(context)
	local functionName = Registry.GetFunctionName(context and context.Template)
	local handler = handlers[functionName]
	if not handler or not handler.Mount then
		return nil
	end
	return handler.Mount(context)
end

function Registry.HandleOwnerClick(context, player)
	local functionName = Registry.GetFunctionName(context and context.Template)
	local handler = handlers[functionName]
	if not handler or not handler.HandleOwnerClick then
		return false
	end
	return handler.HandleOwnerClick(context, player)
end

function Registry.HandleOwnerAction(context, player, action, payload)
	local functionName = Registry.GetFunctionName(context and context.Template)
	local handler = handlers[functionName]
	if not handler or not handler.HandleOwnerAction then
		return false, "This furniture does not support that action"
	end
	return handler.HandleOwnerAction(context, player, action, payload)
end

function Registry.Cleanup(entry)
	if not entry then
		return
	end
	local cleanup = entry.FunctionCleanup
	entry.FunctionCleanup = nil
	if typeof(cleanup) == "function" then
		local ok, cleanupError = pcall(cleanup)
		if not ok then
			warn("[House] Furniture function cleanup failed:", cleanupError)
		end
	end
end

Registry.Register("ItemDisplay", require(script.Parent:WaitForChild("ItemDisplay")))
Registry.Register("MusicPlayer", require(script.Parent:WaitForChild("MusicPlayer")))
Registry.Register("EditableSign", require(script.Parent:WaitForChild("EditableSign")))

function Registry.HasHandler(name)
    return name == "None" or handlers[name] ~= nil
end
Registry.Register("Seat", require(script.Parent:WaitForChild("Seat")))
return Registry
