-- One writer owns a house save. Visitors can read snapshots without claiming the owner's lease.
local Service = {}
Service.__index = Service

function Service.new(store, schema, config, dependencies)
	local deps = dependencies or {}
	return setmetatable({Store = store, Schema = schema, Config = config,
		Now = deps.Now or os.time, Wait = deps.Wait or task.wait,
		Guid = deps.Guid or function() return game:GetService("HttpService"):GenerateGUID(false) end,
		JobId = deps.JobId or game.JobId, Handles = {}}, Service)
end

function Service:Key(userId) return "Player_" .. tostring(userId) end
function Service:LiveLease(raw)
	local lease = typeof(raw) == "table" and raw.WriteLease
	return typeof(lease) == "table" and typeof(lease.ExpiresAt) == "number" and lease.ExpiresAt > self.Now() and lease or nil
end

function Service:Retry(callback)
	local lastError
	for attempt = 1, self.Config.SaveRetryAttempts or 4 do
		local ok, value = pcall(callback)
		if ok then return true, value end
		lastError = value
		if attempt < (self.Config.SaveRetryAttempts or 4) then self.Wait(math.min(2 ^ (attempt - 1), 4)) end
	end
	return false, tostring(lastError)
end

function Service:Acquire(userId)
	local id = self.Guid()
	local blocked = false
	local ok, raw = self:Retry(function()
		return self.Store:UpdateAsync(self:Key(userId), function(old)
			blocked = false
			local lease = self:LiveLease(old)
			if lease and lease.Id ~= id then blocked = true; return nil end
			local value = typeof(old) == "table" and table.clone(old) or self.Schema.Default()
			value.WriteLease = {Id = id, JobId = self.JobId, ExpiresAt = self.Now() + (self.Config.WriteLeaseSeconds or 120)}
			return value
		end)
	end)
	if not ok or blocked or typeof(raw) ~= "table" then return nil, blocked and "Your house is still saving in another server. Please try again shortly." or tostring(raw) end
	local handle = {Id = id, UserId = userId, Revision = raw.Revision or 0, ExpiresAt = raw.WriteLease.ExpiresAt}
	self.Handles[userId] = handle
	return self.Schema.Sanitize(raw), handle
end

function Service:Read(userId)
	local ok, raw = self:Retry(function() return self.Store:GetAsync(self:Key(userId)) end)
	if not ok then return nil, raw end
	local data = self.Schema.Sanitize(raw)
	return data, nil, self:LiveLease(raw) ~= nil
end

function Service:Write(userId, data, handle, release)
	if handle and (handle.Lost or handle.Busy) then return false, "House save is busy or its write lease expired." end
	if handle then handle.Busy = true end
	local expected = handle and handle.Revision or (data.Revision or 0)
	local snapshot = self.Schema.Serialize(data)
	snapshot.Revision = math.max(snapshot.Revision, expected + 1)
	local operationId = self.Guid()
	snapshot.LastWriteId = operationId
	local rejection
	local ok, result = self:Retry(function()
		return self.Store:UpdateAsync(self:Key(userId), function(old)
			rejection = nil
			if typeof(old) == "table" and old.LastWriteId == operationId then return old end
			local lease = self:LiveLease(old)
			if handle then
				if not lease or lease.Id ~= handle.Id then rejection = "LeaseLost"; return nil end
			elseif lease then rejection = "WriterActive"; return nil end
			if (typeof(old) == "table" and (old.Revision or 0) or 0) ~= expected then rejection = "RevisionConflict"; return nil end
			snapshot.WriteLease = handle and not release and {Id = handle.Id, JobId = self.JobId,
				ExpiresAt = self.Now() + (self.Config.WriteLeaseSeconds or 120)} or nil
			return snapshot
		end)
	end)
	if handle then handle.Busy = false end
	if not ok or rejection or typeof(result) ~= "table" or result.LastWriteId ~= operationId then
		if handle and (rejection == "LeaseLost" or rejection == "RevisionConflict") then handle.Lost = true end
		return false, rejection or tostring(result)
	end
	if handle then
		handle.Revision = result.Revision
		handle.ExpiresAt = result.WriteLease and result.WriteLease.ExpiresAt or 0
		if release then self.Handles[userId] = nil end
	end
	return true, result.Revision
end

function Service:Renew(handle)
	if not handle or handle.Lost or handle.Busy then return false end
	handle.Busy = true
	local denied = false
	local ok, result = self:Retry(function()
		return self.Store:UpdateAsync(self:Key(handle.UserId), function(old)
			denied = false
			local lease = self:LiveLease(old)
			if not lease or lease.Id ~= handle.Id then denied = true; return nil end
			local value = table.clone(old)
			value.WriteLease = {Id = handle.Id, JobId = self.JobId, ExpiresAt = self.Now() + (self.Config.WriteLeaseSeconds or 120)}
			return value
		end)
	end)
	handle.Busy = false
	if ok and not denied and typeof(result) == "table" then handle.ExpiresAt = result.WriteLease.ExpiresAt; return true end
	if denied or self.Now() >= handle.ExpiresAt then handle.Lost = true end
	return false
end

return Service
