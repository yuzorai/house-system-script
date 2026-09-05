-- Compact tools reuse the authored BuildPanel typography and borders.
local Tools = {}

function Tools.new(panel)
	local self = {Grid = 0, NudgeStep = 0.25, Offset = Vector3.zero, Frozen = false, FixedHit = nil, Search = ""}
	local donor = panel:WaitForChild("RotateLeftButton")
	local function button(parent, name, label, x, y, width, callback)
		local result = donor:Clone()
		result.Name, result.Text = name, label
		for _, obj in ipairs(result:GetDescendants()) do if obj:IsA("UIStroke") or obj:IsA("LuaSourceContainer") then obj:Destroy() end end
		result.Position = UDim2.fromOffset(x, y)
		result.Size = UDim2.fromOffset(width, 25)
		result.Visible = true
		result.Active = true
		result.BorderSizePixel = 1
		result.TextSize = math.min(donor.TextSize, 12)
		result.Parent = parent
		result.Activated:Connect(callback)
		return result
	end
	local search = Instance.new("TextBox")
	search.Name = "FurnitureSearch"
	search.Position = UDim2.fromOffset(16, 68)
	search.Size = UDim2.new(1, -32, 0, 26)
	search.FontFace, search.TextColor3 = donor.FontFace, donor.TextColor3
	search.BackgroundColor3, search.BackgroundTransparency = donor.BackgroundColor3, donor.BackgroundTransparency
	search.BorderColor3, search.BorderSizePixel = donor.BorderColor3, 1
	search.TextSize, search.PlaceholderText, search.Text = 13, "Search furniture...", ""
	search.ClearTextOnFocus = false
	search.Parent = panel
	self.SearchBox = search
	panel.FurnitureList.Position = UDim2.fromOffset(16, 100)
	panel.FurnitureList.Size = UDim2.new(1, -32, 0, 122)
	local positions = {RotationAxisTitle = 228, RotationAxes = 248, RotationTitle = 280,
		RotationSteps = 300, RotateLeftButton = 334, RotateRightButton = 334,
		PlaceButton = 370, CancelButton = 370, MoveButton = 408, StoreButton = 408, AccessButton = 446}
	for name, y in pairs(positions) do local obj = panel:FindFirstChild(name); if obj then obj.Position = UDim2.new(obj.Position.X.Scale, obj.Position.X.Offset, 0, y) end end
	local frame = Instance.new("Frame")
	frame.Name = "BuildTools"
	frame.BackgroundTransparency = 1
	frame.Position, frame.Size = UDim2.fromOffset(16, 486), UDim2.new(1, -32, 0, 130)
	frame.Parent = panel
	self.GridButton = button(frame, "GridButton", "GRID: OFF", 0, 0, 130, function()
		local values = {0, 0.25, 0.5, 1}
		self.Grid = values[((table.find(values, self.Grid) or 1) % #values) + 1]
		self.GridButton.Text = self.Grid == 0 and "GRID: OFF" or ("GRID: " .. self.Grid)
	end)
	self.FreezeButton = button(frame, "PrecisionButton", "LOCK CURSOR", 138, 0, 130, function()
		self.Frozen = not self.Frozen
		self.FreezeButton.Text = self.Frozen and "UNLOCK CURSOR" or "LOCK CURSOR"
		if not self.Frozen then self.FixedHit = nil; self.Offset = Vector3.zero end
	end)
	self.StepButton = button(frame, "NudgeStep", "NUDGE: 0.25", 0, 30, 268, function()
		local values = {0.05, 0.1, 0.25, 0.5, 1}
		self.NudgeStep = values[((table.find(values, self.NudgeStep) or 3) % #values) + 1]
		self.StepButton.Text = "NUDGE: " .. self.NudgeStep .. " (HOUSE AXES)"
	end)
	for index, axis in ipairs({Vector3.xAxis, Vector3.yAxis, Vector3.zAxis}) do
		for _, direction in ipairs({-1, 1}) do
			local axisName = ({"X", "Y", "Z"})[index]
			local column = (index - 1) * 2 + (direction == 1 and 1 or 0)
			button(frame, axisName .. (direction == 1 and "Plus" or "Minus"), axisName .. (direction == 1 and "+" or "-"), column * 45, 60, 42, function()
				self.Frozen = true
				self.FreezeButton.Text = "UNLOCK CURSOR"
				self.Offset += axis * direction * self.NudgeStep
			end)
		end
	end
	self.UndoButton = button(frame, "UndoButton", "UNDO MOVE", 0, 90, 130, function() if self.OnHistory then self.OnHistory("Undo") end end)
	self.RedoButton = button(frame, "RedoButton", "REDO MOVE", 138, 90, 130, function() if self.OnHistory then self.OnHistory("Redo") end end)
	panel.StatusLabel.Position = UDim2.fromOffset(16, 612)
	panel.StatusLabel.Size = UDim2.new(1, -32, 0, 54)
	panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, 678)
	local scale = panel:FindFirstChildWhichIsA("UIScale")
	if not scale then scale = Instance.new("UIScale"); scale.Name = "ResponsiveScale"; scale.Parent = panel end
	local maximum = scale.Scale
	function self.FitViewport(camera)
		if camera then scale.Scale = math.min(maximum, (camera.ViewportSize.Y - 32) / 678, (camera.ViewportSize.X - 32) / 300) end
	end
	function self.Reset()
		self.Offset, self.FixedHit, self.Frozen = Vector3.zero, nil, false
		self.FreezeButton.Text = "LOCK CURSOR"
	end
	return self
end

return Tools
