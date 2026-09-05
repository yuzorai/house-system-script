local SeatHandler = {}

local function getSeats(root)
	local seats = {}
	if not root then
		return seats
	end
	if root:IsA("Seat") then
		table.insert(seats, root)
	end
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("Seat") then
			table.insert(seats, object)
		end
	end
	return seats
end

function SeatHandler.SanitizeState()
	return {}
end

function SeatHandler.Mount(context)
	local seats = getSeats(context and context.Model)
	if #seats == 0 then
		warn("[House] Seat furniture was mounted without a native Roblox Seat:", context and context.Template and context.Template:GetFullName() or "unknown template")
		return nil
	end

	for _, seat in ipairs(seats) do
		seat.Disabled = false
		seat.CanTouch = true
	end

	return function()
		for _, seat in ipairs(seats) do
			local occupant = seat.Occupant
			if occupant and occupant.Parent then
				occupant.Sit = false
			end
		end
	end
end

return SeatHandler

