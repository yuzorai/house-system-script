--[[
	HouseController
	Controls the Landlord menu and the owner's local furniture preview.
	The server makes every final ownership and placement decision.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local gui = script.Parent
local landlordPanel = gui:WaitForChild("LandlordPanel")
local buildPanel = gui:WaitForChild("BuildPanel")
local upgradePanel = gui:WaitForChild("HouseUpgradePanel")
local taxPanel = gui:WaitForChild("TaxPanel")
local Music = {}
Music.Panel = gui:WaitForChild("MusicPanel")
Music.Input = Music.Panel:WaitForChild("MusicAssetIdInput")
Music.SetButton = Music.Panel:WaitForChild("SetButton")
local Sign = {}
Sign.Panel = gui:WaitForChild("SignPanel")
Sign.Input = Sign.Panel:WaitForChild("SignTextInput")
Sign.SetButton = Sign.Panel:WaitForChild("SetButton")
local Visit = {}
Visit.Panel = gui:WaitForChild("PublicHousesPanel")
Visit.List = Visit.Panel:WaitForChild("HouseList")
Visit.RowTemplate = Visit.List:WaitForChild("HouseRowTemplate")
Visit.Status = Visit.Panel:WaitForChild("StatusLabel")
Visit.BackButton = Visit.Panel:WaitForChild("BackButton")
Visit.RefreshButton = Visit.Panel:WaitForChild("RefreshButton")
Visit.AccessButton = buildPanel:WaitForChild("AccessButton")
local taxWeeklyTaxLabel = taxPanel:WaitForChild("WeeklyTaxLabel")
local taxReserveLabel = taxPanel:WaitForChild("TaxReserveLabel")
local taxDescriptionLabel = taxPanel:WaitForChild("DescriptionLabel")
local payTaxButton = taxPanel:WaitForChild("PayTaxButton")
local addTaxReserveButton = taxPanel:WaitForChild("AddTaxReserveButton")
local taxExitButton = taxPanel:WaitForChild("ExitButton")
local stylesPanel = upgradePanel:WaitForChild("StylesPanel")
local styleList = stylesPanel:WaitForChild("StyleList")
local styleButtonTemplate = styleList:WaitForChild("StyleButtonTemplate")
local upgradeContent = upgradePanel:WaitForChild("ContentPanel")
local selectedStyleValue = upgradeContent:WaitForChild("SelectedStyle"):WaitForChild("Value")
local upgradeCostLabel = upgradeContent:WaitForChild("UpgradeCostLabel")
local weeklyTaxLabel = upgradeContent:WaitForChild("WeeklyTaxLabel")
local upgradeStatusLabel = upgradeContent:WaitForChild("StatusLabel")
local upgradeBackButton = upgradeContent:WaitForChild("BackButton")
local upgradeBuyButton = upgradeContent:WaitForChild("BuyButton")
local upgradeTable = upgradeContent:WaitForChild("UpgradeTable")
local upgradeRowTemplate = upgradeTable:WaitForChild("UpgradeRowTemplate")
local noUpgradesLabel = upgradeTable:WaitForChild("NoUpgradesLabel")
local upgradeRows = upgradeTable:WaitForChild("UpgradeRows")
local furnitureList = buildPanel:WaitForChild("FurnitureList")
local rowTemplate = furnitureList:WaitForChild("FurnitureRowTemplate")
local rotationAxisTitle = buildPanel:WaitForChild("RotationAxisTitle")
local rotationAxes = buildPanel:WaitForChild("RotationAxes")
local rotationTitle = buildPanel:WaitForChild("RotationTitle")
local rotationSteps = buildPanel:WaitForChild("RotationSteps")
local rotationStepDecreaseButton = rotationSteps:WaitForChild("StepDecreaseButton")
local rotationStepValue = rotationSteps:WaitForChild("StepValue")
local rotationStepIncreaseButton = rotationSteps:WaitForChild("StepIncreaseButton")
local rotateLeftButton = buildPanel:WaitForChild("RotateLeftButton")
local rotateRightButton = buildPanel:WaitForChild("RotateRightButton")
local placeButton = buildPanel:WaitForChild("PlaceButton")
local cancelButton = buildPanel:WaitForChild("CancelButton")
local moveButton = buildPanel:WaitForChild("MoveButton")
local storeButton = buildPanel:WaitForChild("StoreButton")
local statusLabel = buildPanel:WaitForChild("StatusLabel")
local furnitureCount = buildPanel:WaitForChild("FurnitureCount")
local toolbarGui = playerGui:WaitForChild("mainToolbar")
local buildToggleButton = toolbarGui:WaitForChild("Toolbar"):WaitForChild("BuildButton")

local closeRequested = gui:WaitForChild("CloseRequested")
local closedEvent = gui:WaitForChild("Closed")

local remotes = ReplicatedStorage:WaitForChild("HouseRemotes")
local openMenu = remotes:WaitForChild("OpenMenu")
local sessionState = remotes:WaitForChild("SessionState")
local actionResult = remotes:WaitForChild("ActionResult")
local requestEnter = remotes:WaitForChild("RequestEnter")
local requestExit = remotes:WaitForChild("RequestExit")
local requestHousePreview = remotes:WaitForChild("RequestHousePreview")
local housePreviewState = remotes:WaitForChild("HousePreviewState")
local requestExitHousePreview = remotes:WaitForChild("RequestExitHousePreview")
local requestPurchaseHouse = remotes:WaitForChild("RequestPurchaseHouse")
local housePurchaseResult = remotes:WaitForChild("HousePurchaseResult")
local getHousePurchaseCatalog = remotes:WaitForChild("GetHousePurchaseCatalog")
local requestPlace = remotes:WaitForChild("RequestPlace")
local requestMove = remotes:WaitForChild("RequestMove")
local requestStore = remotes:WaitForChild("RequestStore")
local requestSnapshot = remotes:WaitForChild("RequestSnapshot")
local FurnitureRemotes = {
	Interact = remotes:WaitForChild("RequestInteractFurniture"),
	Action = remotes:WaitForChild("RequestFurnitureFunctionAction"),
	Editor = remotes:WaitForChild("FurnitureFunctionEditor"),
	Result = remotes:WaitForChild("FurnitureFunctionResult"),
}
local VisitRemotes = {
	List = remotes:WaitForChild("GetPublicHouseList"),
	Request = remotes:WaitForChild("RequestVisitHouse"),
	Result = remotes:WaitForChild("VisitHouseResult"),
	SetAccess = remotes:WaitForChild("RequestSetHouseAccess"),
	AccessState = remotes:WaitForChild("HouseAccessState"),
}
local getHouseTaxStatus = remotes:WaitForChild("GetHouseTaxStatus")
local requestAddTaxReserve = remotes:WaitForChild("RequestAddTaxReserve")
local requestPayHouseTax = remotes:WaitForChild("RequestPayHouseTax")
local houseTaxState = remotes:WaitForChild("HouseTaxState")
local requestPurchaseHouseUpgrade = remotes:WaitForChild("RequestPurchaseHouseUpgrade")
local requestAddHousePreviewUpgrade = remotes:WaitForChild("RequestAddHousePreviewUpgrade")
local houseUpgradePurchaseResult = remotes:WaitForChild("HouseUpgradePurchaseResult")

local ItemRegistry = require(ReplicatedStorage:WaitForChild("ItemRegistry"))
local furnitureFolder = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Furnitures")

local GOLD = Color3.fromRGB(126, 100, 66)
local SELECTED_GOLD = Color3.fromRGB(160, 124, 58)
local GREEN = Color3.fromRGB(112, 210, 126)
local RED = Color3.fromRGB(235, 82, 75)
local GRAY = Color3.fromRGB(190, 190, 190)
local ROTATION_STEPS = {5, 10, 20, 30, 45, 90, 180}

local HouseTools = {
    Geometry = require(ReplicatedStorage:WaitForChild("HouseShared"):WaitForChild("HousePlacementGeometry")),
    Snapshot = require(ReplicatedStorage.HouseShared.HouseSnapshot),
    UI = require(gui:WaitForChild("HouseBuildTools")).new(buildPanel),
    History = remotes:WaitForChild("RequestMoveHistory"),
}
HouseTools.UI.FitViewport(camera)
local snapshot
local activeHouse
local activeSessionId
local activeRevision = 0
local placementIndex = {}
local selectedPlacementId
local selectedItemName
local selectedBoundsBox
local previewModel
local previewHighlight
local previewBoundsBox
local previewMode
local movingOriginal
local movingTransparency = {}
local rotationStep = 45
local rotationAxis = "Y"
local rotationDegrees = Vector3.zero
local lastPointer = Vector2.zero
local lastPosition
local lastSurfaceNormal
local lastValid = false
local pending = false
local buildModeOpen = false
local inventoryConnections = {}
local refreshQueued = false

local houseCatalog
local catalogByName = {}
local selectedHouseStyle
local previewActive = false
local previewPending = false
local purchasePending = false
local upgradePurchasePending = false
local previewUpgradeStage = 0
local toolbarEnabledBeforePreview = true
local styleButtonConnections = {}
local upgradeRowConnections = {}
local styleScroll
local taxStatus
local taxRequestPending = false
Music.PlacementId = nil
Music.Pending = false
Music.Players = {}
Music.SessionId = nil
Sign.PlacementId = nil
Sign.Pending = false
Visit.Pending = false
Visit.CanBuild = false
Visit.HouseAccess = "Private"

local function setStatus(message, kind)
	statusLabel.Text = message or ""
	if kind == "Good" then
		statusLabel.TextColor3 = GREEN
	elseif kind == "Bad" then
		statusLabel.TextColor3 = RED
	else
		statusLabel.TextColor3 = GRAY
	end
end

local function setInterfaceOpen(value)
	gui:SetAttribute("InterfaceOpen", value)
end

function Music.SetPending(value)
	Music.Pending = value == true
	Music.SetButton.Active = not Music.Pending
	Music.SetButton.AutoButtonColor = not Music.Pending
	Music.Input.TextEditable = not Music.Pending
	Music.SetButton.Text = Music.Pending and "SETTING..." or "SET"
end

function Music.CloseEditor()
	Music.Panel.Visible = false
	Music.PlacementId = nil
	Music.SetPending(false)
	Music.Input:ReleaseFocus()
	setInterfaceOpen(
		buildModeOpen
		or landlordPanel.Visible
		or upgradePanel.Visible
		or taxPanel.Visible
	)
end

function Sign.SetPending(value)
	Sign.Pending = value == true
	Sign.SetButton.Active = not Sign.Pending
	Sign.SetButton.AutoButtonColor = not Sign.Pending
	Sign.Input.TextEditable = not Sign.Pending
	Sign.SetButton.Text = Sign.Pending and "SETTING..." or "SET"
end

function Sign.CloseEditor()
	Sign.Panel.Visible = false
	Sign.PlacementId = nil
	Sign.SetPending(false)
	Sign.Input:ReleaseFocus()
	setInterfaceOpen(
		buildModeOpen
		or landlordPanel.Visible
		or upgradePanel.Visible
		or taxPanel.Visible
		or Music.Panel.Visible
		or Visit.Panel.Visible
	)
end

local function waitForMenuClose(screen)
	if not screen or screen == gui or screen:GetAttribute("InterfaceOpen") ~= true then
		return
	end
	local request = screen:FindFirstChild("CloseRequested")
	if request and request:IsA("BindableEvent") then
		request:Fire()
		local deadline = os.clock() + 1.75
		repeat
			task.wait()
		until screen:GetAttribute("InterfaceOpen") ~= true or os.clock() >= deadline
	else
		screen.Enabled = false
	end
end

local function closeOtherMenus()
	for _, name in ipairs({
		"WarehouseTemplate",
		"InventoryTemplate",
		"CharacterProfileGui",
		"ShopGui",
		"RepairKitGui",
	}) do
		waitForMenuClose(playerGui:FindFirstChild(name))
	end
end

local function closeLandlordMenu()
	if not landlordPanel.Visible then return end
	landlordPanel.Visible = false
	if not activeSessionId and not Visit.Panel.Visible then
		setInterfaceOpen(false)
		closedEvent:Fire()
	end
end

function Visit.SetStatus(text, kind)
	Visit.Status.Text = text or ""
	Visit.Status.TextColor3 = kind == "Bad" and RED or (kind == "Good" and GREEN or GRAY)
end

function Visit.SetPending(value)
	Visit.Pending = value == true
	Visit.RefreshButton.Active = not Visit.Pending
	Visit.RefreshButton.AutoButtonColor = not Visit.Pending
	Visit.BackButton.Active = true
	Visit.BackButton.AutoButtonColor = true
end

function Visit.ClearRows()
	for _, child in ipairs(Visit.List:GetChildren()) do
		if child:IsA("TextButton") and child ~= Visit.RowTemplate then
			child:Destroy()
		end
	end
end

function Visit.Refresh()
	if Visit.Pending then return end
	Visit.SetPending(true)
	Visit.SetStatus("Loading public houses...", nil)
	task.spawn(function()
		local ok, entries = pcall(VisitRemotes.List.InvokeServer, VisitRemotes.List)
		if not Visit.Panel.Visible then
			Visit.SetPending(false)
			return
		end
		Visit.ClearRows()
		if not ok or typeof(entries) ~= "table" then
			Visit.SetStatus("Could not load public houses. Try again.", "Bad")
			Visit.SetPending(false)
			return
		end
		for index, entry in ipairs(entries) do
			if typeof(entry) == "table"
				and typeof(entry.UserId) == "number"
				and typeof(entry.PlayerName) == "string"
				and typeof(entry.HouseName) == "string"
			then
				local row = Visit.RowTemplate:Clone()
				row.Name = "House_" .. tostring(entry.UserId)
				row.LayoutOrder = index
				row.Visible = true
				row.PlayerName.Text = entry.PlayerName
				row.HouseName.Text = entry.HouseName
				row.Parent = Visit.List
				row.Activated:Connect(function()
					if Visit.Pending then return end
					Visit.SetPending(true)
					Visit.SetStatus("Visiting " .. entry.PlayerName .. "'s house...", nil)
					VisitRemotes.Request:FireServer(entry.UserId)
				end)
			end
		end
		Visit.SetPending(false)
		Visit.SetStatus(#entries > 0 and "Choose a public house to visit." or "No public houses are available.", nil)
	end)
end

function Visit.Open()
	if player:GetAttribute("TradingInterfaceLocked") == true then return end
	task.spawn(function()
		closeOtherMenus()
		if player:GetAttribute("TradingInterfaceLocked") == true then return end
		landlordPanel.Visible = false
		Visit.Panel.Visible = true
		setInterfaceOpen(true)
		Visit.Refresh()
	end)
end

function Visit.Close(showLandlord)
	Visit.Panel.Visible = false
	Visit.SetPending(false)
	if showLandlord == true and not activeSessionId then
		landlordPanel.Visible = true
	end
	setInterfaceOpen(landlordPanel.Visible or buildModeOpen or upgradePanel.Visible or taxPanel.Visible or Music.Panel.Visible)
	if not landlordPanel.Visible and not activeSessionId then
		closedEvent:Fire()
	end
end

local function formatAmount(value)
	local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
	while true do
		local replaced
		text, replaced = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return text
end


local function setTaxPanelOpen(open, showLandlord)
	taxPanel.Visible = open
	if showLandlord ~= nil then
		landlordPanel.Visible = showLandlord
	end
	setInterfaceOpen(open or landlordPanel.Visible or buildModeOpen or upgradePanel.Visible)
	if not open and not landlordPanel.Visible and not buildModeOpen and not upgradePanel.Visible then
		closedEvent:Fire()
	end
end

local function formatTimeUntil(timestamp)
	local remaining = math.max(0, math.floor((tonumber(timestamp) or 0) - os.time()))
	local days = math.floor(remaining / 86400)
	local hours = math.floor((remaining % 86400) / 3600)
	if days > 0 then
		return ("%dd %dh"):format(days, hours)
	end
	local minutes = math.floor((remaining % 3600) / 60)
	return ("%dh %dm"):format(hours, minutes)
end

local function applyTaxStatus(nextStatus, message, kind)
	if typeof(nextStatus) == "table" then
		taxStatus = nextStatus
	end
	local state = taxStatus or {}
	local weeklyTax = math.max(0, math.floor(tonumber(state.WeeklyTax) or 0))
	local reserve = math.max(0, math.floor(tonumber(state.TaxReserve) or 0))
	local due = math.max(0, math.floor(tonumber(state.TaxDueAmount) or 0))
	taxWeeklyTaxLabel.Text = "Weekly Tax: " .. formatAmount(weeklyTax)
	taxReserveLabel.Text = "Tax Reserve: " .. formatAmount(reserve)

	local defaultMessage
	if state.Loaded == false then
		defaultMessage = "House tax data is still loading."
	elseif state.HasHouse ~= true then
		defaultMessage = "You don't have a house."
	elseif due > 0 then
		defaultMessage = ("Taxes due: %s %s. Pay them before entering your house."):format(
			formatAmount(due),
			state.Currency or "Imperial Credits"
		)
	elseif state.NextTaxDueAt then
		defaultMessage = "No tax is due. Next tax in " .. formatTimeUntil(state.NextTaxDueAt) .. "."
	else
		defaultMessage = "No tax is due."
	end
	taxDescriptionLabel.Text = message or defaultMessage
	if kind == "Bad" then
		taxDescriptionLabel.TextColor3 = RED
	elseif kind == "Good" then
		taxDescriptionLabel.TextColor3 = GREEN
	else
		taxDescriptionLabel.TextColor3 = GRAY
	end

	local canAdd = state.HasHouse == true and weeklyTax > 0 and not taxRequestPending
	local canPay = state.HasHouse == true and due > 0 and reserve >= due and not taxRequestPending
	addTaxReserveButton.Active = canAdd
	addTaxReserveButton.AutoButtonColor = canAdd
	payTaxButton.Active = canPay
	payTaxButton.AutoButtonColor = canPay
	addTaxReserveButton.Text = taxRequestPending and "Please wait..." or "Add to Tax Reserves"
	payTaxButton.Text = taxRequestPending and "Please wait..." or "Pay Taxes"
end

local function openTaxPanel()
	if taxRequestPending then return end
	task.spawn(function()
		closeOtherMenus()
		if player:GetAttribute("TradingInterfaceLocked") == true then return end
		setTaxPanelOpen(true, false)
		applyTaxStatus(nil, "Loading house tax information...", nil)
		local ok, nextStatus = pcall(getHouseTaxStatus.InvokeServer, getHouseTaxStatus)
		if taxPanel.Visible then
			if ok and typeof(nextStatus) == "table" then
				applyTaxStatus(nextStatus, nil, nil)
			else
				applyTaxStatus(nil, "House tax information is unavailable.", "Bad")
			end
		end
	end)
end

local function closeTaxPanel(reopenLandlord)
	taxRequestPending = false
	setTaxPanelOpen(false, reopenLandlord ~= false)
end

local function setUpgradeStatus(message, kind)
	upgradeStatusLabel.Text = message or ""
	if kind == "Good" then
		upgradeStatusLabel.TextColor3 = GREEN
	elseif kind == "Bad" then
		upgradeStatusLabel.TextColor3 = RED
	else
		upgradeStatusLabel.TextColor3 = GRAY
	end
end

local function ensureStyleScroll()
	if styleScroll and styleScroll.Parent then
		return styleScroll
	end
	styleScroll = styleList:FindFirstChild("StyleScroll")
	if not styleScroll then
		styleScroll = Instance.new("ScrollingFrame")
		styleScroll.Name = "StyleScroll"
		styleScroll.BackgroundTransparency = 1
		styleScroll.BorderSizePixel = 0
		styleScroll.Size = UDim2.fromScale(1, 1)
		styleScroll.CanvasSize = UDim2.fromOffset(0, 0)
		styleScroll.ScrollBarThickness = 4
		styleScroll.ScrollBarImageColor3 = GOLD
		styleScroll.ScrollingDirection = Enum.ScrollingDirection.Y
		styleScroll.ZIndex = styleList.ZIndex + 1
		styleScroll.Parent = styleList
	end
	return styleScroll
end

local function setUpgradeOpen(open, showLandlord)
	if open and not upgradePanel.Visible and toolbarGui:IsA("ScreenGui") then
		toolbarEnabledBeforePreview = toolbarGui.Enabled
	end
	upgradePanel.Visible = open
	upgradePanel:SetAttribute("BlocksHotbar", open)
	gui:SetAttribute("BlocksHotbar", open)
	if toolbarGui:IsA("ScreenGui") then
		if open then
			toolbarGui.Enabled = false
		else
			toolbarGui.Enabled = toolbarEnabledBeforePreview
		end
	else
		local toolbar = toolbarGui:FindFirstChild("Toolbar")
		if toolbar and toolbar:IsA("GuiObject") then
			toolbar.Visible = not open
		end
	end
	if showLandlord ~= nil then
		landlordPanel.Visible = showLandlord
	end
	setInterfaceOpen(open or landlordPanel.Visible or buildModeOpen)
	if not open and not landlordPanel.Visible and not buildModeOpen then
		closedEvent:Fire()
	end
end

local updateUpgradeSelection

local function rebuildUpgradeRows()
	for _, connection in ipairs(upgradeRowConnections) do
		connection:Disconnect()
	end
	table.clear(upgradeRowConnections)
	for _, child in ipairs(upgradeRows:GetChildren()) do
		if child:GetAttribute("GeneratedHouseUpgrade") == true then
			child:Destroy()
		end
	end

	local style = selectedHouseStyle and catalogByName[selectedHouseStyle]
	local upgrades = style and style.Upgrades or {}
	noUpgradesLabel.Visible = #upgrades == 0
	if #upgrades == 0 then
		noUpgradesLabel.Text = style and "No expansions available" or "Select a house style"
	end

	local ownedHouse = houseCatalog and houseCatalog.OwnedHouse
	local ownedStage = math.max(0, math.floor(tonumber(houseCatalog and houseCatalog.OwnedUpgradeStage) or 0))
	local selectedIsOwned = selectedHouseStyle ~= nil and selectedHouseStyle == ownedHouse
	local displayedStage = selectedIsOwned and ownedStage or previewUpgradeStage

	for index, upgrade in ipairs(upgrades) do
		local row = upgradeRowTemplate:Clone()
		row.Name = "Upgrade_" .. tostring(upgrade.Id)
		row.Visible = true
		row.Position = UDim2.fromOffset(7, 3 + (index - 1) * 30)
		row:SetAttribute("GeneratedHouseUpgrade", true)
		row.Parent = upgradeRows
		row.NameLabel.Text = tostring(upgrade.DisplayName or upgrade.Id)
		row.CostLabel.Text = formatAmount(upgrade.Cost)
		row.TaxLabel.Text = "0"

		local order = math.max(1, math.floor(tonumber(upgrade.Order) or index))
		local isOwned = selectedIsOwned and order <= ownedStage
		local isAdded = not selectedIsOwned and order <= previewUpgradeStage
		local isNext = order == displayedStage + 1
		local canAdd = previewActive
			and isNext
			and not previewPending
			and not purchasePending
			and not upgradePurchasePending

		local button = row.ActionButton
		if isOwned then
			button.Text = "Owned"
		elseif isAdded then
			button.Text = "Added"
		elseif isNext then
			button.Text = (previewPending or upgradePurchasePending) and "Adding..." or "Add"
		else
			local previous = upgrades[order - 1]
			button.Text = "Requires " .. tostring(previous and previous.DisplayName or ("Stage " .. tostring(order - 1)))
		end
		button.Active = canAdd
		button.AutoButtonColor = canAdd

		if canAdd then
			local upgradeId = upgrade.Id
			local displayName = upgrade.DisplayName or upgrade.Id
			table.insert(upgradeRowConnections, button.Activated:Connect(function()
				if upgradePurchasePending or purchasePending or previewPending then return end
				if selectedIsOwned then
					upgradePurchasePending = true
					setUpgradeStatus("Checking Imperial Credits for " .. tostring(displayName) .. "...", nil)
					updateUpgradeSelection()
					requestPurchaseHouseUpgrade:FireServer(selectedHouseStyle, upgradeId)
				else
					previewPending = true
					setUpgradeStatus("Adding " .. tostring(displayName) .. " to preview...", nil)
					updateUpgradeSelection()
					requestAddHousePreviewUpgrade:FireServer(selectedHouseStyle, upgradeId)
				end
			end))
		end
	end

	upgradeRows.CanvasSize = UDim2.fromOffset(0, math.max(upgradeRows.AbsoluteSize.Y, 6 + #upgrades * 30))
end

updateUpgradeSelection = function()
	local style = selectedHouseStyle and catalogByName[selectedHouseStyle]
	if style then
		selectedStyleValue.Text = tostring(style.DisplayName or selectedHouseStyle)
		local ownedHouse = houseCatalog and houseCatalog.OwnedHouse
		local ownedStage = math.max(0, math.floor(tonumber(houseCatalog and houseCatalog.OwnedUpgradeStage) or 0))
		local displayedStage = selectedHouseStyle == ownedHouse and ownedStage or previewUpgradeStage
		local totalCost = math.max(0, math.floor(tonumber(style.PurchaseCost) or 0))
		for index, upgrade in ipairs(style.Upgrades or {}) do
			local order = math.max(1, math.floor(tonumber(upgrade.Order) or index))
			if order <= displayedStage then
				totalCost += math.max(0, math.floor(tonumber(upgrade.Cost) or 0))
			end
		end
		upgradeCostLabel.Text = "Upgrade Cost: " .. formatAmount(totalCost)
		weeklyTaxLabel.Text = "Weekly Tax: " .. formatAmount(style.WeeklyTax)
	else
		selectedStyleValue.Text = "Unavailable"
		upgradeCostLabel.Text = "Upgrade Cost: --"
		weeklyTaxLabel.Text = "Weekly Tax: --"
	end

	local canBuy = previewActive
		and style ~= nil
		and not purchasePending
		and not previewPending
		and not upgradePurchasePending
	upgradeBuyButton.Active = canBuy
	upgradeBuyButton.AutoButtonColor = canBuy
	if purchasePending then
		upgradeBuyButton.Text = "Buying..."
	else
		upgradeBuyButton.Text = "Buy"
	end

	local scroll = ensureStyleScroll()
	for _, object in ipairs(scroll:GetChildren()) do
		if object:IsA("TextButton") and object:GetAttribute("GeneratedHouseStyle") == true then
			local selected = object:GetAttribute("TemplateName") == selectedHouseStyle
			object.BackgroundTransparency = selected and 0.35 or styleButtonTemplate.BackgroundTransparency
			local stroke = object:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = selected and SELECTED_GOLD or GOLD
			end
		end
	end
	rebuildUpgradeRows()
end

local function rebuildStyleList()
	for _, connection in ipairs(styleButtonConnections) do
		connection:Disconnect()
	end
	table.clear(styleButtonConnections)
	local scroll = ensureStyleScroll()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:GetAttribute("GeneratedHouseStyle") == true then
			child:Destroy()
		end
	end

	local styles = houseCatalog and houseCatalog.Styles or {}
	for index, style in ipairs(styles) do
		if typeof(style) == "table" and typeof(style.TemplateName) == "string" then
			catalogByName[style.TemplateName] = style
			local button = styleButtonTemplate:Clone()
			button.Name = "Style_" .. style.TemplateName
			button.Text = tostring(style.DisplayName or style.TemplateName)
			button.Visible = true
			button.Position = UDim2.fromOffset(10, 8 + (index - 1) * 26)
			button:SetAttribute("GeneratedHouseStyle", true)
			button:SetAttribute("TemplateName", style.TemplateName)
			button.Parent = scroll
			table.insert(styleButtonConnections, button.Activated:Connect(function()
				if previewPending or purchasePending or upgradePurchasePending or selectedHouseStyle == style.TemplateName then
					return
				end
				previewPending = true
				setUpgradeStatus("Loading " .. tostring(style.DisplayName or style.TemplateName) .. " preview...", nil)
				updateUpgradeSelection()
				requestHousePreview:FireServer(style.TemplateName)
			end))
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, math.max(styleList.AbsoluteSize.Y, 16 + #styles * 26))
	updateUpgradeSelection()
end

local function refreshHouseCatalog()
	local ok, catalog = pcall(getHousePurchaseCatalog.InvokeServer, getHousePurchaseCatalog)
	if not ok or typeof(catalog) ~= "table" or typeof(catalog.Styles) ~= "table" then
		setUpgradeStatus("House styles are unavailable.", "Bad")
		return false
	end
	houseCatalog = catalog
	table.clear(catalogByName)
	rebuildStyleList()
	return true
end

local function openHouseUpgrade()
	if previewPending or purchasePending or upgradePurchasePending then return end
	task.spawn(function()
		closeOtherMenus()
		if player:GetAttribute("TradingInterfaceLocked") == true then return end
		setUpgradeOpen(true, false)
		setUpgradeStatus("Loading house styles...", nil)
		if not refreshHouseCatalog() then return end
		local defaultStyle = houseCatalog.OwnedHouse or houseCatalog.DefaultStyle
		if typeof(defaultStyle) ~= "string" or not catalogByName[defaultStyle] then
			local firstStyle = houseCatalog.Styles[1]
			defaultStyle = firstStyle and firstStyle.TemplateName
		end
		if typeof(defaultStyle) ~= "string" or defaultStyle == "" then
			setUpgradeStatus("No house templates are available.", "Bad")
			return
		end
		previewPending = true
		setUpgradeStatus("Loading " .. defaultStyle .. " preview...", nil)
		updateUpgradeSelection()
		requestHousePreview:FireServer(defaultStyle)
	end)
end

local function closeHouseUpgrade()
	if purchasePending or upgradePurchasePending then return end
	if previewActive or previewPending or player:GetAttribute("HousePreviewActive") == true then
		previewPending = true
		setUpgradeStatus("Leaving house preview...", nil)
		updateUpgradeSelection()
		requestExitHousePreview:FireServer()
		task.delay(3, function()
			if previewPending and upgradePanel.Visible then
				previewPending = false
				previewActive = false
				setUpgradeOpen(false, true)
			end
		end)
	else
		previewPending = false
		setUpgradeOpen(false, true)
	end
end

local function findFurnitureTemplate(itemName)
	for _, object in ipairs(furnitureFolder:GetDescendants()) do
		if object.Name == itemName
			and (object:IsA("Model") or object:IsA("BasePart"))
			and object.Parent
			and object.Parent:IsA("Folder")
		then
			return object
		end
	end
	return nil
end

local function getVisibleParts(model)
	local parts = {}
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") and object.Transparency < 0.99 then
			table.insert(parts, object)
		end
	end
	return parts
end

local function getVisibleBounds(model)
	local minVector
	local maxVector
	for _, object in ipairs(getVisibleParts(model)) do
		local half = object.Size * 0.5
		for _, x in ipairs({-1, 1}) do
			for _, y in ipairs({-1, 1}) do
				for _, z in ipairs({-1, 1}) do
					local point = object.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					minVector = minVector and Vector3.new(
						math.min(minVector.X, point.X),
						math.min(minVector.Y, point.Y),
						math.min(minVector.Z, point.Z)
					) or point
					maxVector = maxVector and Vector3.new(
						math.max(maxVector.X, point.X),
						math.max(maxVector.Y, point.Y),
						math.max(maxVector.Z, point.Z)
					) or point
				end
			end
		end
	end
	if not minVector or not maxVector then return nil end
	return (minVector + maxVector) * 0.5, maxVector - minVector, minVector, maxVector
end

local function updateFurnitureBoundsBox(model, boundsBox)
	if not model or not model.Parent or not boundsBox then return end
	local pivot = model:GetPivot()
	local minVector
	local maxVector
	for _, object in ipairs(getVisibleParts(model)) do
		local half = object.Size * 0.5
		for _, x in ipairs({-1, 1}) do
			for _, y in ipairs({-1, 1}) do
				for _, z in ipairs({-1, 1}) do
					local worldPoint = object.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					local point = pivot:PointToObjectSpace(worldPoint)
					minVector = minVector and Vector3.new(
						math.min(minVector.X, point.X),
						math.min(minVector.Y, point.Y),
						math.min(minVector.Z, point.Z)
					) or point
					maxVector = maxVector and Vector3.new(
						math.max(maxVector.X, point.X),
						math.max(maxVector.Y, point.Y),
						math.max(maxVector.Z, point.Z)
					) or point
				end
			end
		end
	end
	if not minVector or not maxVector then
		boundsBox.Transparency = 1
		return
	end
	local center = (minVector + maxVector) * 0.5
	local size = maxVector - minVector + Vector3.new(0.12, 0.12, 0.12)
	boundsBox.Transparency = 0.82
	boundsBox.Size = Vector3.new(
		math.max(size.X, 0.12),
		math.max(size.Y, 0.12),
		math.max(size.Z, 0.12)
	)
	boundsBox.CFrame = pivot * CFrame.new(center)
end

local function createFurnitureBoundsBox(name)
	local boundsBox = Instance.new("Part")
	boundsBox.Name = name
	boundsBox.Anchored = true
	boundsBox.CanCollide = false
	boundsBox.CanTouch = false
	boundsBox.CanQuery = false
	boundsBox.CastShadow = false
	boundsBox.Color = Color3.new(1, 1, 1)
	boundsBox.Material = Enum.Material.SmoothPlastic
	boundsBox.Transparency = 0.82
	boundsBox.Size = Vector3.one
	boundsBox.Parent = workspace
	local boundsOutline = Instance.new("SelectionBox")
	boundsOutline.Name = "BoundsOutline"
	boundsOutline.Adornee = boundsBox
	boundsOutline.Color3 = Color3.new(1, 1, 1)
	boundsOutline.SurfaceTransparency = 1
	boundsOutline.Transparency = 0.2
	boundsOutline.LineThickness = 0.03
	boundsOutline.Parent = boundsBox
	return boundsBox
end

local function updatePreviewBoundsBox()
	updateFurnitureBoundsBox(previewModel, previewBoundsBox)
end

local function clearSelectedBoundsBox()
	if selectedBoundsBox then
		selectedBoundsBox:Destroy()
		selectedBoundsBox = nil
	end
end

local function updateSelectedBoundsBox()
	clearSelectedBoundsBox()
	if not buildModeOpen or previewModel or not selectedPlacementId then return end
	local entry = placementIndex[selectedPlacementId]
	local model = entry and entry.Model
	if not model or not model.Parent then return end
	selectedBoundsBox = createFurnitureBoundsBox("HouseFurnitureSelectedBounds")
	updateFurnitureBoundsBox(model, selectedBoundsBox)
end

local function cloneForPreview(template)
	local model
	if template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		model.Name = template.Name
		local part = template:Clone()
		part.Parent = model
		model.PrimaryPart = part
	end
	model.Name = "HouseFurniturePreview"
	model:SetAttribute("HouseFurniturePreview", true)
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("LuaSourceContainer")
			or object:IsA("ProximityPrompt")
			or object:IsA("ClickDetector")
			or object:IsA("TouchTransmitter")
		then
			object:Destroy()
		elseif object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Transparency = math.max(object.Transparency, 0.45)
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "PlacementHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0
	highlight.Parent = model
	model.Parent = workspace
	return model, highlight
end

local function restoreMovingOriginal()
	for part, transparency in pairs(movingTransparency) do
		if part.Parent then
			part.LocalTransparencyModifier = transparency
		end
	end
	table.clear(movingTransparency)
	movingOriginal = nil
end

local function updateActionButtons()
    HouseTools.UI.UndoButton.Active = not pending and snapshot ~= nil and snapshot.CanUndo == true
    HouseTools.UI.RedoButton.Active = not pending and snapshot ~= nil and snapshot.CanRedo == true
    HouseTools.UI.UndoButton.TextTransparency = HouseTools.UI.UndoButton.Active and 0 or 0.5
    HouseTools.UI.RedoButton.TextTransparency = HouseTools.UI.RedoButton.Active and 0 or 0.5
	local hasPreview = previewModel ~= nil
	local hasSelection = selectedPlacementId ~= nil and not hasPreview
	placeButton.Visible = hasPreview
	cancelButton.Visible = hasPreview or hasSelection
	moveButton.Visible = hasSelection
	storeButton.Visible = hasSelection
end

local function cancelPreview(clearSelection)
	HouseTools.UI.Reset()
	if clearSelection then
		clearSelectedBoundsBox()
	end
	if previewBoundsBox then
		previewBoundsBox:Destroy()
	end
	if previewModel then
		previewModel:Destroy()
	end
	previewBoundsBox = nil
	previewModel = nil
	previewHighlight = nil
	previewMode = nil
	lastPosition = nil
	lastSurfaceNormal = nil
	lastValid = false
	pending = false
	restoreMovingOriginal()
	if clearSelection then
		selectedPlacementId = nil
		selectedItemName = nil
	end
	updateActionButtons()
	if activeSessionId then
		setStatus(clearSelection and "Select furniture to begin." or "Placement cancelled.", nil)
	end
end

local function setBuildMode(open)
	buildModeOpen = open == true and activeSessionId ~= nil and Visit.CanBuild == true
	if buildModeOpen then
		Music.CloseEditor()
		Sign.CloseEditor()
	else
		cancelPreview(true)
	end
	buildPanel.Visible = buildModeOpen
	setInterfaceOpen(buildModeOpen or landlordPanel.Visible or Music.Panel.Visible or Sign.Panel.Visible or Visit.Panel.Visible)
end

local function toggleBuildMode()
	if pending or not activeSessionId or Visit.CanBuild ~= true or player:GetAttribute("TradingInterfaceLocked") == true then
		return
	end
	if buildModeOpen then
		setBuildMode(false)
		return
	end
	task.spawn(function()
		closeOtherMenus()
		if activeSessionId and player:GetAttribute("TradingInterfaceLocked") ~= true then
			setBuildMode(true)
		end
	end)
end

local function setStep(value)
	if typeof(value) ~= "number" then return end
	rotationStep = value
	rotationTitle.Text = "ROTATION STEP"
	rotationStepValue.Text = ("%d°"):format(value)
end

local function shiftRotationStep(direction)
	local currentIndex = table.find(ROTATION_STEPS, rotationStep) or 1
	local nextIndex = ((currentIndex - 1 + direction) % #ROTATION_STEPS) + 1
	setStep(ROTATION_STEPS[nextIndex])
end

local function setRotationAxis(axis)
	if axis ~= "X" and axis ~= "Y" and axis ~= "Z" then return end
	rotationAxis = axis
	rotationAxisTitle.Text = "ROTATION AXIS: " .. axis
	for _, object in ipairs(rotationAxes:GetChildren()) do
		if object:IsA("TextButton") then
			local selected = object:GetAttribute("RotationAxis") == axis
			local stroke = object:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = GOLD
				stroke.Thickness = 1.5
			end
			object.BorderColor3 = selected and SELECTED_GOLD or GOLD
			object.BorderSizePixel = selected and 3 or 1
			object.TextColor3 = selected and Color3.new(1, 1, 1) or GRAY
		end
	end
end

local function rotatePreview(direction)
	if not previewModel then
		setStatus("Select furniture or choose MOVE first.", "Bad")
		return
	end
	local amount = rotationStep * direction
	if rotationAxis == "X" then
		rotationDegrees = Vector3.new((rotationDegrees.X + amount) % 360, rotationDegrees.Y, rotationDegrees.Z)
	elseif rotationAxis == "Y" then
		rotationDegrees = Vector3.new(rotationDegrees.X, (rotationDegrees.Y + amount) % 360, rotationDegrees.Z)
	else
		rotationDegrees = Vector3.new(rotationDegrees.X, rotationDegrees.Y, (rotationDegrees.Z + amount) % 360)
	end
end

local getFurniturePlacementNormal

local function startPreview(itemName, mode, placementId)
	cancelPreview(false)
	clearSelectedBoundsBox()
	local template = findFurnitureTemplate(itemName)
	if not template then
		setStatus("That furniture template is unavailable.", "Bad")
		return
	end
	previewModel, previewHighlight = cloneForPreview(template)
	previewBoundsBox = createFurnitureBoundsBox("HouseFurniturePreviewBounds")
	updatePreviewBoundsBox()
	previewMode = mode
	selectedItemName = itemName
	selectedPlacementId = placementId
	rotationDegrees = Vector3.zero
	if mode == "Move" then
		local entry = placementIndex[placementId]
		movingOriginal = entry and entry.Model
		if movingOriginal then
			if getFurniturePlacementNormal(previewModel) == Vector3.yAxis then
				local x, y, z = movingOriginal:GetPivot():ToOrientation()
				rotationDegrees = Vector3.new(math.deg(x), math.deg(y), math.deg(z))
			else
				rotationDegrees = Vector3.zero
			end
			for _, part in ipairs(movingOriginal:GetDescendants()) do
				if part:IsA("BasePart") then
					movingTransparency[part] = part.LocalTransparencyModifier
					part.LocalTransparencyModifier = 0.85
				end
			end
		end
	end
	updateActionButtons()
	setStatus("X/Y/Z selects axis. R/T rotates; click to place.", nil)
end

local function pointInsideBounds(point)
	if not activeHouse then return false end
	local boundsFolder = activeHouse:FindFirstChild("PlacementBounds")
	if not boundsFolder then return false end
	for _, bound in ipairs(boundsFolder:GetChildren()) do
		if bound:IsA("BasePart") then
			local localPoint = bound.CFrame:PointToObjectSpace(point)
			local half = bound.Size * 0.5 + Vector3.new(0.2, 0.2, 0.2)
			if math.abs(localPoint.X) <= half.X
				and math.abs(localPoint.Y) <= half.Y
				and math.abs(localPoint.Z) <= half.Z
			then
				return true
			end
		end
	end
	return false
end

getFurniturePlacementNormal = function(model)
	if model:GetAttribute("HouseFunction") ~= "ItemDisplay" then
		return Vector3.yAxis
	end
	local pivot = model:GetPivot()
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("DisplaySurface") == true then
			local displayNormal = object:GetAttribute("DisplayNormal")
			if typeof(displayNormal) == "Vector3" and displayNormal.Magnitude > 0.001 then
				local worldNormal = object.CFrame:VectorToWorldSpace(displayNormal.Unit)
				local localNormal = pivot:VectorToObjectSpace(worldNormal)
				if localNormal.Magnitude > 0.001 then
					return localNormal.Unit
				end
			end
		end
	end
	return Vector3.yAxis
end

local function getAlignmentRotation(fromDirection, toDirection)
	local from = fromDirection.Unit
	local to = toDirection.Unit
	local dot = math.clamp(from:Dot(to), -1, 1)
	if dot > 0.999999 then
		return CFrame.identity
	end
	if dot < -0.999999 then
		local reference = math.abs(from:Dot(Vector3.xAxis)) < 0.9 and Vector3.xAxis or Vector3.yAxis
		return CFrame.fromAxisAngle(from:Cross(reference).Unit, math.pi)
	end
	local axis = from:Cross(to)
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function getSurfaceCFrame(position, normal, rotation, placementNormal)
	normal = normal.Unit
	local surfaceCFrame
	if normal.Y >= 0.999 then
		surfaceCFrame = CFrame.new(position)
	else
		local reference = math.abs(normal:Dot(Vector3.yAxis)) > 0.95 and Vector3.zAxis or Vector3.yAxis
		local right = reference:Cross(normal)
		if right.Magnitude < 0.001 then
			right = Vector3.xAxis
		end
		right = right.Unit
		local back = right:Cross(normal).Unit
		surfaceCFrame = CFrame.fromMatrix(position, right, normal, back)
	end
	local userRotation = CFrame.Angles(
		math.rad(rotation.X),
		math.rad(rotation.Y),
		math.rad(rotation.Z)
	)
	local alignment = getAlignmentRotation(placementNormal or Vector3.yAxis, Vector3.yAxis)
	return surfaceCFrame * userRotation * alignment
end

local function getVisibleProjectionRange(model, axis)
	local minimum = math.huge
	local maximum = -math.huge
	local found = false
	for _, object in ipairs(getVisibleParts(model)) do
		local half = object.Size * 0.5
		for _, x in ipairs({-1, 1}) do
			for _, y in ipairs({-1, 1}) do
				for _, z in ipairs({-1, 1}) do
					local corner = object.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					local projection = corner:Dot(axis)
					minimum = math.min(minimum, projection)
					maximum = math.max(maximum, projection)
					found = true
				end
			end
		end
	end
	if not found then return nil end
	return minimum, maximum
end

local function updatePreview(screenPosition)
    if not previewModel or not activeHouse or not camera then return end
    local tools = HouseTools.UI
    local ray = UserInputService:GetLastInputType() == Enum.UserInputType.Touch
        and camera:ViewportPointToRay(screenPosition.X, screenPosition.Y) or mouse.UnitRay
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local excluded = {previewModel}
    if previewBoundsBox then table.insert(excluded, previewBoundsBox) end
    for _, participant in ipairs(Players:GetPlayers()) do if participant.Character then table.insert(excluded, participant.Character) end end
    if movingOriginal then table.insert(excluded, movingOriginal) end
    local boundsFolder = activeHouse:FindFirstChild("PlacementBounds")
    if boundsFolder then table.insert(excluded, boundsFolder) end
    params.FilterDescendantsInstances = excluded
    params.IgnoreWater = true
    local result = tools.Frozen and tools.FixedHit or workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    if not tools.Frozen and result then tools.FixedHit = result end
    local valid = result and result.Instance and result.Instance:IsDescendantOf(activeHouse) and result.Instance.Name ~= "HouseSpawn"
    local reason = "Aim at a house or furniture surface."
    local cursorPosition
    if valid then
        local normal = result.Normal.Unit
        cursorPosition = HouseTools.Geometry.SnapSurface(result.Position, normal, activeHouse:GetPivot(), tools.Grid)
            + activeHouse:GetPivot():VectorToWorldSpace(tools.Offset)
        -- Resolve the adjusted cursor against the real surface before using it for preview or server input.
        local adjusted = workspace:Raycast(cursorPosition + normal * 2.5, -normal * 5, params)
        if not adjusted or not adjusted.Instance:IsDescendantOf(activeHouse) or (adjusted.Position - cursorPosition).Magnitude > 1.5 then
            valid = false
            reason = "The adjusted cursor needs a supporting house or furniture surface."
        else
            cursorPosition = adjusted.Position
            normal = adjusted.Normal.Unit
            previewModel:PivotTo(getSurfaceCFrame(cursorPosition, normal, rotationDegrees, getFurniturePlacementNormal(previewModel)))
            local center = getVisibleBounds(previewModel)
            local minimum = getVisibleProjectionRange(previewModel, normal)
            if center and minimum then
                local offset = cursorPosition - center
                previewModel:PivotTo(previewModel:GetPivot() + offset - normal * offset:Dot(normal)
                    + normal * (cursorPosition:Dot(normal) - minimum + 0.02))
                valid, reason = HouseTools.Geometry.ValidateModel(previewModel, boundsFolder, snapshot and snapshot.UpgradeStage or 0)
                if not pointInsideBounds(cursorPosition) then valid = false; reason = "The cursor is outside the unlocked build area." end
            else valid = false; reason = "Furniture has no visible geometry." end
            lastSurfaceNormal = normal
        end
    end
    updatePreviewBoundsBox()
    lastValid = valid == true
    lastPosition = cursorPosition
    if previewHighlight then
        previewHighlight.FillColor = lastValid and GREEN or RED
        previewHighlight.OutlineColor = lastValid and GREEN or RED
    end
    if not pending then
        setStatus(lastValid and "Valid placement. Press PLACE or click the surface." or (reason or "Invalid placement."), lastValid and "Good" or "Bad")
    end
end

local function clearRows()
	for _, child in ipairs(furnitureList:GetChildren()) do
		if child:IsA("TextButton") and child ~= rowTemplate then
			child:Destroy()
		end
	end
end

local function normalizeIcon(iconId)
	local ok, result = pcall(ItemRegistry.NormalizeIconId, iconId)
	return ok and result or ""
end

local function rebuildFurnitureList()
	clearRows()
	if Visit.CanBuild ~= true or not snapshot or typeof(snapshot.Furniture) ~= "table" then return end
	local shown = 0
	for index, entry in ipairs(snapshot.Furniture) do
		if (tonumber(entry.Available) or 0) > 0
            and (HouseTools.UI.Search == "" or string.find(string.lower(entry.Name), HouseTools.UI.Search, 1, true)) then
			shown += 1
			local row = rowTemplate:Clone()
			row.Name = "Furniture_" .. entry.Name
			row.LayoutOrder = index
			row.Visible = true
			row:SetAttribute("ItemName", entry.Name)
			row.ItemName.Text = entry.Name
			row.Quantity.Text = ("%dx"):format(entry.Available)
			local image = normalizeIcon(entry.IconId)
			row.Icon.Image = image
			row.Icon.Visible = image ~= ""
			row.IconFallback.Visible = image == ""
			row.Parent = furnitureList
			row.Activated:Connect(function()
				if pending or not activeSessionId or Visit.CanBuild ~= true then return end
				selectedPlacementId = nil
				startPreview(entry.Name, "New", nil)
			end)
		end
	end
	if shown == 0 then
		setStatus(HouseTools.UI.Search ~= "" and "No furniture matches your search." or "No available furniture is in your Inventory.", nil)
	end
end

HouseTools.UI.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    HouseTools.UI.Search = string.lower(HouseTools.UI.SearchBox.Text):match("^%s*(.-)%s*$")
    rebuildFurnitureList()
end)

local function findPlacedModel(placementId)
	if not activeHouse then return nil end
	local folder = activeHouse:FindFirstChild("PlacedFurniture") or activeHouse:FindFirstChild("PlacedFurniture_PhysicalRuntime")
	if not folder then return nil end
	for _, model in ipairs(folder:GetChildren()) do
		if model:GetAttribute("PlacementId") == placementId then
			return model
		end
	end
	return nil
end

function Music.FindSound(model)
	if not model then return nil end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Sound")
			and descendant.Name == "Sound"
			and descendant.Parent:IsA("BasePart")
		then
			return descendant
		end
	end
	return nil
end

function Music.Stop(entry)
	local sound = entry and entry.Sound
	if sound and sound.Parent then
		pcall(function()
			sound:Stop()
			sound.SoundId = ""
			sound.TimePosition = 0
		end)
	end
end

function Music.Clear()
	for _, entry in pairs(Music.Players) do
		Music.Stop(entry)
	end
	table.clear(Music.Players)
	Music.SessionId = nil
end

function Music.Sync(nextSnapshot)
	if typeof(nextSnapshot) ~= "table" or nextSnapshot.Active ~= true then
		Music.Clear()
		return
	end
	local sessionId = nextSnapshot.SessionId
	if Music.SessionId ~= sessionId then
		Music.Clear()
		Music.SessionId = sessionId
	end
	local desired = {}
	for _, placement in ipairs(nextSnapshot.Placements or {}) do
		local functionState = placement.FunctionState
		local musicState = typeof(functionState) == "table" and functionState.MusicPlayer or nil
		local soundId = typeof(musicState) == "table" and musicState.SoundId or nil
		if typeof(soundId) == "string" and string.match(soundId, "^%d+$") and tonumber(soundId) > 0 then
			local model = placement.Model or findPlacedModel(placement.PlacementId)
			local sound = Music.FindSound(model)
			if sound then
				desired[placement.PlacementId] = true
				local template = findFurnitureTemplate(placement.ItemName)
				local volume = math.clamp(tonumber(template and template:GetAttribute("MusicVolume")) or 0.5, 0, 1)
				local minDistance = math.max(1, tonumber(template and template:GetAttribute("MusicMinDistance")) or 5)
				local radius = math.max(minDistance, tonumber(template and template:GetAttribute("MusicRadius")) or 30)
				local current = Music.Players[placement.PlacementId]
				local unchanged = current
					and current.Sound == sound
					and current.SoundId == soundId
					and current.SessionId == sessionId
				sound.Looped = true
				sound.Volume = volume
				sound.RollOffMode = Enum.RollOffMode.InverseTapered
				sound.RollOffMinDistance = minDistance
				sound.RollOffMaxDistance = radius
				if not unchanged then
					Music.Stop(current)
					sound.SoundId = "rbxassetid://" .. soundId
					sound.TimePosition = 0
					pcall(function() sound:Play() end)
					Music.Players[placement.PlacementId] = {
						Sound = sound,
						SoundId = soundId,
						SessionId = sessionId,
					}
				end
			end
		end
	end
	for placementId, entry in pairs(Music.Players) do
		if not desired[placementId] then
			Music.Stop(entry)
			Music.Players[placementId] = nil
		end
	end
end

local Windows = {
	Parts = {},
	House = nil,
	Mode = nil,
}

function Windows.Clear()
	for part, state in pairs(Windows.Parts) do
		if part.Parent then
			part.LocalTransparencyModifier = state.LocalTransparencyModifier
			part.Material = state.Material
			part.Color = state.Color
			part.Transparency = state.Transparency
		end
		if state.Light then state.Light:Destroy() end
	end
	table.clear(Windows.Parts)
	Windows.House = nil
	Windows.Mode = nil
end

function Windows.GetGlassParts(house)
	local parts = {}
	if not house then return parts end
	for _, object in ipairs(house:GetDescendants()) do
		if object:IsA("BasePart") and object.Name == "Glass" then
			local ancestor = object.Parent
			local belongsToWindow = false
			while ancestor and ancestor ~= house do
				if ancestor:IsA("Model") and ancestor.Name == "Window" then belongsToWindow = true; break end
				ancestor = ancestor.Parent
			end
			if belongsToWindow then table.insert(parts, object) end
		end
	end
	return parts
end

function Windows.Sync(house, mode)
	if Windows.House == house and Windows.Mode == mode then return end
	Windows.Clear()
	if not house or (mode ~= "PhysicalInside" and mode ~= "VirtualGlow") then return end
	Windows.House = house
	Windows.Mode = mode
	local glowColor = house:GetAttribute("WindowGlowColor")
	if typeof(glowColor) ~= "Color3" then glowColor = Color3.fromRGB(255, 226, 145) end
	local brightness = math.max(0, tonumber(house:GetAttribute("WindowGlowBrightness")) or 1.5)
	for _, part in ipairs(Windows.GetGlassParts(house)) do
		local state = {
			LocalTransparencyModifier = part.LocalTransparencyModifier,
			Material = part.Material,
			Color = part.Color,
			Transparency = part.Transparency,
		}
		Windows.Parts[part] = state
		if mode == "PhysicalInside" then
			part.LocalTransparencyModifier = 1
		else
			part.LocalTransparencyModifier = 0
			part.Material = Enum.Material.Neon
			part.Color = glowColor
			part.Transparency = math.min(part.Transparency, 0.2)
			if brightness > 0 then
				local light = Instance.new("PointLight")
				light.Name = "LocalWindowGlow"
				light.Color = glowColor
				light.Brightness = brightness
				light.Range = 8
				light.Shadows = false
				light.Parent = part
				state.Light = light
			end
		end
	end
end

local function syncLocalPhysicalDoorPrompts(activePhysicalHouse)
	local folder = workspace:FindFirstChild("PhysicalHouses")
	if not folder then return end
	for _, object in ipairs(folder:GetDescendants()) do
		if object:IsA("ProximityPrompt") then
			local isCurrentHouse = activePhysicalHouse ~= nil and object:IsDescendantOf(activePhysicalHouse)
			if object.Name == "PhysicalHouseExitPrompt" then
				-- Exit is local to an occupant, so outside players never see or use it.
				object.Enabled = isCurrentHouse
			elseif object.Name == "PhysicalHouseDoorPrompt" then
				-- The outside Enter action is replaced by Exit while this client is inside.
				object.Enabled = not isCurrentHouse
			end
		end
	end
end

local function applySnapshot(nextSnapshot)
    if typeof(nextSnapshot) ~= "table" then return end
    local previousSnapshot = snapshot
    if nextSnapshot.Kind == "Delta" then
        if snapshot and snapshot.SessionId == nextSnapshot.SessionId and (snapshot.StreamSequence or 0) >= nextSnapshot.StreamSequence then return end
        local merged = HouseTools.Snapshot.Apply(snapshot, nextSnapshot)
        if not merged then
            if not HouseTools.Resyncing then
                HouseTools.Resyncing = true
                task.spawn(function()
                    local ok, full = pcall(requestSnapshot.InvokeServer, requestSnapshot, activeSessionId)
                    HouseTools.Resyncing = false
                    if ok and full then HouseTools.ApplySnapshot(full) end
                end)
            end
            return
        end
        nextSnapshot = merged
    elseif snapshot and nextSnapshot.Active == true and snapshot.SessionId == nextSnapshot.SessionId
        and (nextSnapshot.StreamSequence or 0) < (snapshot.StreamSequence or 0) then return end
    local previousSessionId = activeSessionId
    snapshot = nextSnapshot
    if previousSessionId ~= nextSnapshot.SessionId or nextSnapshot.Active ~= true then pending = false end
	landlordPanel.EnterHouseButton.Text = "Enter House"
	if nextSnapshot.Active ~= true then
		syncLocalPhysicalDoorPrompts(nil)
		Music.CloseEditor()
		Sign.CloseEditor()
		Music.Clear()
		Windows.Clear()
		cancelPreview(true)
		buildModeOpen = false
		Visit.CanBuild = false
		Visit.Panel.Visible = false
		buildToggleButton.Visible = false
		activeHouse = nil
		activeSessionId = nil
		activeRevision = 0
		placementIndex = {}
		buildPanel.Visible = false
		landlordPanel.Visible = false
		setInterfaceOpen(false)
		closedEvent:Fire()
		return
	end
	activeHouse = nextSnapshot.House
	syncLocalPhysicalDoorPrompts(nextSnapshot.IsPhysical == true and activeHouse or nil)
	Windows.Sync(activeHouse, nextSnapshot.IsPhysical == true and "PhysicalInside" or "VirtualGlow")
	activeSessionId = nextSnapshot.SessionId
	activeRevision = nextSnapshot.Revision or 0
	Visit.CanBuild = nextSnapshot.CanBuild == true
	Visit.HouseAccess = typeof(nextSnapshot.HouseAccess) == "string" and nextSnapshot.HouseAccess or "Private"
	Visit.AccessButton.Text = "ACCESS: " .. string.upper(Visit.HouseAccess)
	Visit.AccessButton.Visible = Visit.CanBuild
	Visit.AccessButton.Active = Visit.CanBuild
	Visit.AccessButton.AutoButtonColor = Visit.CanBuild
	Visit.Panel.Visible = false
	if previousSessionId ~= activeSessionId then
		Music.CloseEditor()
		Sign.CloseEditor()
		buildModeOpen = false
	end
	buildToggleButton.Visible = Visit.CanBuild
	if Visit.CanBuild ~= true then
		buildModeOpen = false
		cancelPreview(true)
	end
	placementIndex = {}
	for _, entry in ipairs(nextSnapshot.Placements or {}) do
        local localEntry = table.clone(entry)
        localEntry.Model = findPlacedModel(entry.PlacementId)
        placementIndex[entry.PlacementId] = localEntry
	end
	Music.Sync(nextSnapshot)
	if selectedPlacementId and not placementIndex[selectedPlacementId] then
		selectedPlacementId = nil
		selectedItemName = nil
	end
	if selectedPlacementId and not previewModel then
		updateSelectedBoundsBox()
	else
		clearSelectedBoundsBox()
	end
	landlordPanel.Visible = false
	buildPanel.Visible = buildModeOpen
	setInterfaceOpen(buildModeOpen or Music.Panel.Visible or Sign.Panel.Visible or Visit.Panel.Visible)
	furnitureCount.Text = ("PLACED: %d / %d"):format(
		#(nextSnapshot.Placements or {}),
		nextSnapshot.MaximumFurniture or 100
	)
    if not previousSnapshot or not HouseTools.Snapshot.Equal(previousSnapshot.Furniture, nextSnapshot.Furniture)
        or previousSessionId ~= activeSessionId or previousSnapshot.CanBuild ~= nextSnapshot.CanBuild then rebuildFurnitureList() end
    updateActionButtons()
end
HouseTools.ApplySnapshot = applySnapshot

local function selectPlaced(model)
	if previewModel or pending then return end
	local placementId = model and model:GetAttribute("PlacementId")
	local entry = placementId and placementIndex[placementId]
	if not entry then return end
	selectedPlacementId = placementId
	selectedItemName = entry.ItemName
	updateSelectedBoundsBox()
	updateActionButtons()
	setStatus(entry.ItemName .. " selected. Choose MOVE or STORE.", "Good")
end

local function isHouseGuiPoint(position)
	for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(position.X, position.Y)) do
		if object:IsDescendantOf(gui) and object.Visible then
			return true
		end
	end
	return false
end

local function confirmPreview()
	if pending or not previewModel then return end
	if not lastValid or not lastPosition or not lastSurfaceNormal then
		setStatus("Move the preview to a valid surface first.", "Bad")
		return
	end
	pending = true
	setStatus("Checking placement...", nil)
	if previewMode == "Move" then
		requestMove:FireServer(
			activeSessionId,
			activeRevision,
			selectedPlacementId,
			lastPosition,
			lastSurfaceNormal,
			rotationDegrees
		)
	else
		requestPlace:FireServer(
			activeSessionId,
			activeRevision,
			selectedItemName,
			lastPosition,
			lastSurfaceNormal,
			rotationDegrees
		)
	end
end

openMenu.OnClientEvent:Connect(function()
	if player:GetAttribute("TradingInterfaceLocked") == true then return end
	task.spawn(function()
		closeOtherMenus()
		if player:GetAttribute("TradingInterfaceLocked") == true then return end
		landlordPanel.Visible = true
		buildPanel.Visible = false
		taxPanel.Visible = false
		setInterfaceOpen(true)
	end)
end)

sessionState.OnClientEvent:Connect(applySnapshot)
HouseTools.UI.OnHistory = function(action)
    if pending or not buildModeOpen or not Visit.CanBuild or not activeSessionId then return end
    cancelPreview(false)
    pending = true
    updateActionButtons()
    setStatus("Checking " .. string.lower(action) .. "...", nil)
    HouseTools.History:FireServer(activeSessionId, activeRevision, action)
end


VisitRemotes.Result.OnClientEvent:Connect(function(success, message)
	Visit.SetPending(false)
	if success == true then
		Visit.Panel.Visible = false
		setInterfaceOpen(buildModeOpen or Music.Panel.Visible or Sign.Panel.Visible)
	else
		Visit.SetStatus(message or "That house is no longer available.", "Bad")
	end
end)

VisitRemotes.AccessState.OnClientEvent:Connect(function(success, access, message)
	if typeof(access) == "string" then
		Visit.HouseAccess = access
		Visit.AccessButton.Text = "ACCESS: " .. string.upper(access)
	end
	if success == false then
		setStatus(message or "Could not change house access.", "Bad")
	elseif message then
		setStatus(message, "Good")
	end
end)


FurnitureRemotes.Editor.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" or state.FunctionName ~= "MusicPlayer" then
		return
	end
	if state.Open ~= true then
		Music.CloseEditor()
		return
	end
	local placementId = state.PlacementId
	if not activeSessionId
		or typeof(placementId) ~= "string"
		or not placementIndex[placementId]
		or buildModeOpen
	then
		return
	end
	Sign.CloseEditor()
	Music.PlacementId = placementId
	Music.Input.Text = typeof(state.SoundId) == "string" and state.SoundId or ""
	Music.SetPending(false)
	Music.Panel.Visible = true
	setInterfaceOpen(true)
end)

FurnitureRemotes.Result.OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" or result.FunctionName ~= "MusicPlayer" then
		return
	end
	if Music.PlacementId and result.PlacementId == Music.PlacementId then
		Music.SetPending(false)
		if result.Success == true then
			Music.CloseEditor()
		end
	end
end)

FurnitureRemotes.Editor.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" or state.FunctionName ~= "EditableSign" then
		return
	end
	if state.Open ~= true then
		Sign.CloseEditor()
		return
	end
	local placementId = state.PlacementId
	if not activeSessionId
		or typeof(placementId) ~= "string"
		or not placementIndex[placementId]
		or buildModeOpen
	then
		return
	end
	Music.CloseEditor()
	Sign.PlacementId = placementId
	Sign.Input.Text = typeof(state.Text) == "string" and state.Text or ""
	Sign.SetPending(false)
	Sign.Panel.Visible = true
	setInterfaceOpen(true)
end)

FurnitureRemotes.Result.OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" or result.FunctionName ~= "EditableSign" then
		return
	end
	if Sign.PlacementId and result.PlacementId == Sign.PlacementId then
		Sign.SetPending(false)
		if result.Success == true then
			Sign.CloseEditor()
		end
	end
end)

actionResult.OnClientEvent:Connect(function(success, message, nextSnapshot)
	pending = false
	landlordPanel.EnterHouseButton.Text = "Enter House"
	if nextSnapshot then applySnapshot(nextSnapshot) end
	if success then
		cancelPreview(true)
		setStatus(message or "House updated.", "Good")
	else
		setStatus(message or "The house request was rejected.", "Bad")
	end
end)

housePreviewState.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	previewPending = false
	if state.Active == true and state.House then
		Windows.Sync(state.House, "VirtualGlow")
	elseif not snapshot or snapshot.Active ~= true then
		Windows.Clear()
	end
	if state.Active == true then
		previewActive = true
		previewUpgradeStage = math.max(0, math.floor(tonumber(state.PreviewUpgradeStage) or 0))
		if typeof(state.SelectedTemplate) == "string" then
			selectedHouseStyle = state.SelectedTemplate
		end
		if houseCatalog then
			houseCatalog.OwnedHouse = state.OwnedHouse
			houseCatalog.OwnedUpgradeStage = state.OwnedUpgradeStage or houseCatalog.OwnedUpgradeStage or 0
		end
		setUpgradeOpen(true, false)
		updateUpgradeSelection()
		if state.Success == false then
			setUpgradeStatus(state.Message or "The house preview could not be changed.", "Bad")
		elseif state.Message then
			setUpgradeStatus(state.Message, "Good")
		else
			setUpgradeStatus("Money must be in Warehouse.", nil)
		end
	elseif state.Success == false and upgradePanel.Visible and state.ReopenLandlord ~= true then
		previewActive = false
		previewUpgradeStage = 0
		updateUpgradeSelection()
		setUpgradeStatus(state.Message or "The house preview could not be opened.", "Bad")
	else
		previewActive = false
		previewUpgradeStage = 0
		purchasePending = false
		upgradePurchasePending = false
		setUpgradeOpen(false, state.ReopenLandlord == true)
	end
end)

houseTaxState.OnClientEvent:Connect(function(nextStatus, success, message)
	taxRequestPending = false
	applyTaxStatus(nextStatus, message, success == false and "Bad" or (success == true and "Good" or nil))
end)

houseUpgradePurchaseResult.OnClientEvent:Connect(function(success, message, state)
	upgradePurchasePending = false
	if typeof(state) == "table" and houseCatalog then
		houseCatalog.OwnedHouse = state.OwnedHouse
		houseCatalog.OwnedUpgradeStage = state.OwnedUpgradeStage or 0
		previewUpgradeStage = math.max(0, math.floor(tonumber(state.PreviewUpgradeStage) or tonumber(state.OwnedUpgradeStage) or 0))
		if typeof(state.SelectedTemplate) == "string" then
			selectedHouseStyle = state.SelectedTemplate
		end
	end
	updateUpgradeSelection()
	setUpgradeStatus(
		message or (success and "House expansion purchased." or "The expansion purchase was rejected."),
		success and "Good" or "Bad"
	)
end)

housePurchaseResult.OnClientEvent:Connect(function(success, message, purchasedTemplate, purchasedUpgradeStage)
	purchasePending = false
	previewPending = false
	if success then
		local savedStage = math.max(0, math.floor(tonumber(purchasedUpgradeStage) or previewUpgradeStage))
		previewUpgradeStage = savedStage
		if houseCatalog then
			houseCatalog.OwnedHouse = purchasedTemplate or selectedHouseStyle
			houseCatalog.OwnedUpgradeStage = savedStage
		end
		updateUpgradeSelection()
	else
		setUpgradeStatus(message or "The house purchase was rejected.", "Bad")
		updateUpgradeSelection()
	end
end)

landlordPanel.EnterHouseButton.Activated:Connect(function()
	if pending then return end
	pending = true
	landlordPanel.EnterHouseButton.Text = "Entering..."
	requestEnter:FireServer()
	task.delay(3, function()
		if pending and not activeSessionId then
			pending = false
			landlordPanel.EnterHouseButton.Text = "Enter House"
		end
	end)
end)
local exitButton = landlordPanel:WaitForChild("ExitButton")
exitButton.Activated:Connect(closeLandlordMenu)
landlordPanel:WaitForChild("UpgradeHouse").Activated:Connect(openHouseUpgrade)
landlordPanel:WaitForChild("TaxesButton").Activated:Connect(openTaxPanel)
landlordPanel:WaitForChild("VisitHouseButton").Activated:Connect(Visit.Open)
Visit.BackButton.Activated:Connect(function()
	Visit.Close(true)
end)
Visit.RefreshButton.Activated:Connect(Visit.Refresh)

taxExitButton.Activated:Connect(closeTaxPanel)
addTaxReserveButton.Activated:Connect(function()
	if taxRequestPending or not taxStatus or taxStatus.HasHouse ~= true then return end
	taxRequestPending = true
	applyTaxStatus(nil, "Adding one week of tax to your reserve...", nil)
	requestAddTaxReserve:FireServer()
end)
payTaxButton.Activated:Connect(function()
	if taxRequestPending or not taxStatus or taxStatus.HasHouse ~= true then return end
	taxRequestPending = true
	applyTaxStatus(nil, "Paying house taxes from your reserve...", nil)
	requestPayHouseTax:FireServer()
end)

upgradeBackButton.Activated:Connect(closeHouseUpgrade)
upgradeBuyButton.Activated:Connect(function()
	if purchasePending or upgradePurchasePending or previewPending or not previewActive or not selectedHouseStyle then
		return
	end
	purchasePending = true
	setUpgradeStatus("Checking Imperial Credits in Warehouse...", nil)
	updateUpgradeSelection()
	requestPurchaseHouse:FireServer(selectedHouseStyle)
end)


for _, object in ipairs(rotationAxes:GetChildren()) do
	if object:IsA("TextButton") then
		object.Activated:Connect(function()
			setRotationAxis(object:GetAttribute("RotationAxis"))
		end)
	end
end

rotationStepDecreaseButton.Activated:Connect(function()
	shiftRotationStep(-1)
end)
rotationStepIncreaseButton.Activated:Connect(function()
	shiftRotationStep(1)
end)

setStep(rotationStep)
setRotationAxis("Y")
buildToggleButton.Activated:Connect(toggleBuildMode)
rotateLeftButton.Activated:Connect(function() rotatePreview(-1) end)
rotateRightButton.Activated:Connect(function() rotatePreview(1) end)
placeButton.Activated:Connect(confirmPreview)
cancelButton.Activated:Connect(function() cancelPreview(true) end)
moveButton.Activated:Connect(function()
	if not selectedPlacementId or not selectedItemName then return end
	startPreview(selectedItemName, "Move", selectedPlacementId)
end)
storeButton.Activated:Connect(function()
	if pending or not selectedPlacementId or Visit.CanBuild ~= true then return end
	pending = true
	setStatus("Returning furniture to Inventory...", nil)
	requestStore:FireServer(activeSessionId, activeRevision, selectedPlacementId)
end)

Visit.AccessButton.Activated:Connect(function()
	if Visit.CanBuild ~= true or not activeSessionId then return end
	VisitRemotes.SetAccess:FireServer()
end)

Music.SetButton.Activated:Connect(function()
	if Music.Pending or not activeSessionId or not Music.PlacementId then
		return
	end
	local placementId = Music.PlacementId
	Music.SetPending(true)
	FurnitureRemotes.Action:FireServer(
		placementId,
		"MusicPlayer",
		"Set",
		{SoundId = Music.Input.Text}
	)
	task.delay(5, function()
		if Music.Pending and Music.PlacementId == placementId then
			Music.SetPending(false)
		end
	end)
end)

Sign.SetButton.Activated:Connect(function()
	if Sign.Pending or not activeSessionId or not Sign.PlacementId then
		return
	end
	local placementId = Sign.PlacementId
	Sign.SetPending(true)
	FurnitureRemotes.Action:FireServer(
		placementId,
		"EditableSign",
		"Set",
		{Text = Sign.Input.Text}
	)
	task.delay(5, function()
		if Sign.Pending and Sign.PlacementId == placementId then
			Sign.SetPending(false)
		end
	end)
end)

closeRequested.Event:Connect(function()
	if Visit.Panel.Visible then
		Visit.Close(true)
	elseif Music.Panel.Visible then
		Music.CloseEditor()
	elseif Sign.Panel.Visible then
		Sign.CloseEditor()
	elseif upgradePanel.Visible then
		closeHouseUpgrade()
	elseif taxPanel.Visible then
		closeTaxPanel()
	elseif landlordPanel.Visible then
		closeLandlordMenu()
	elseif buildModeOpen then
		setBuildMode(false)
		closedEvent:Fire()
	else
		closedEvent:Fire()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		lastPointer = input.Position
	end
end)

function Music.GetPlacementFromTarget(target)
	local current = target
	while current and current ~= activeHouse do
		local placementId = current:GetAttribute("PlacementId")
		if typeof(placementId) == "string" and placementId ~= "" then
			return placementId
		end
		current = current.Parent
	end
	return nil
end

function Music.RequestInteraction(position)
	if not activeSessionId or buildModeOpen or isHouseGuiPoint(position) then
		return false
	end
	local target = mouse.Target
	if not target then
		return false
	end
	local placementId = Music.GetPlacementFromTarget(target)
	local entry = placementId and placementIndex[placementId]
	local template = entry and findFurnitureTemplate(entry.ItemName)
	local functionName = template and template:GetAttribute("HouseFunction")
	if functionName == "ItemDisplay" then
		if target:GetAttribute("DisplaySurface") ~= true then
			return false
		end
	elseif functionName == "MusicPlayer" then
		local sound = target:FindFirstChild("Sound")
		if not sound or not sound:IsA("Sound") then
			return false
		end
	elseif functionName == "EditableSign" then
		local surface = target:FindFirstChildWhichIsA("SurfaceGui")
		if not surface or not surface:FindFirstChildWhichIsA("TextLabel", true) then
			return false
		end
	else
		return false
	end
	FurnitureRemotes.Interact:FireServer(placementId)
	return true
end
Music.InputCaptured = false
function Music.HandleAction(_, inputState, input)
	if inputState == Enum.UserInputState.Begin then
		if UserInputService:GetFocusedTextBox() then
			Music.InputCaptured = false
			return Enum.ContextActionResult.Pass
		end
		local pointerPosition = input.UserInputType == Enum.UserInputType.Touch
			and Vector2.new(input.Position.X, input.Position.Y)
			or UserInputService:GetMouseLocation()
		Music.InputCaptured = Music.RequestInteraction(pointerPosition)
		return Music.InputCaptured and Enum.ContextActionResult.Sink
			or Enum.ContextActionResult.Pass
	end
	if Music.InputCaptured then
		if inputState == Enum.UserInputState.End
			or inputState == Enum.UserInputState.Cancel
		then
			Music.InputCaptured = false
		end
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindActionAtPriority(
	"HouseFurnitureInteract",
	Music.HandleAction,
	false,
	Enum.ContextActionPriority.High.Value + 100,
	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.Touch
)

local function handleWorldClick(position)
	if not activeSessionId or not buildModeOpen or isHouseGuiPoint(position) then return end
	if previewModel then
		updatePreview(position)
		confirmPreview()
		return
	end

	local object = mouse.Target
	while object and object ~= activeHouse do
		if object:GetAttribute("PlacementId") then
			selectPlaced(object)
			break
		end
		object = object.Parent
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Escape and Music.Panel.Visible then
		Music.CloseEditor()
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and Sign.Panel.Visible then
		Sign.CloseEditor()
		return
	end
	if not activeSessionId then return end
if input.KeyCode == Enum.KeyCode.B then
		if gameProcessed or UserInputService:GetFocusedTextBox() then return end
		toggleBuildMode()
		return
	end
	if not buildModeOpen then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handleWorldClick(UserInputService:GetMouseLocation())
		return
	elseif input.UserInputType == Enum.UserInputType.Touch then
		handleWorldClick(Vector2.new(input.Position.X, input.Position.Y))
		return
	end

	if gameProcessed or UserInputService:GetFocusedTextBox() then return end
    local control = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
    if control and input.KeyCode == Enum.KeyCode.Z then HouseTools.UI.OnHistory("Undo"); return end
    if control and input.KeyCode == Enum.KeyCode.Y then HouseTools.UI.OnHistory("Redo"); return end
	if input.KeyCode == Enum.KeyCode.X then
		setRotationAxis("X")
	elseif input.KeyCode == Enum.KeyCode.Y then
		setRotationAxis("Y")
	elseif input.KeyCode == Enum.KeyCode.Z then
		setRotationAxis("Z")
	elseif input.KeyCode == Enum.KeyCode.R then
		rotatePreview(-1)
	elseif input.KeyCode == Enum.KeyCode.T then
		rotatePreview(1)
	elseif input.KeyCode == Enum.KeyCode.Escape and previewModel then
		cancelPreview(true)
	end
end)

RunService.RenderStepped:Connect(function()
	if previewModel then
		local position = UserInputService.TouchEnabled and lastPointer.Magnitude > 0
			and lastPointer
			or UserInputService:GetMouseLocation()
        if (HouseTools.UI.Frozen or not isHouseGuiPoint(position)) and os.clock() - (HouseTools.LastPreview or 0) >= 1 / 30 then
            HouseTools.LastPreview = os.clock()
            updatePreview(position)
        end
	end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        if snapshot and snapshot.Active == true then
            for id, entry in pairs(placementIndex) do if not entry.Model or not entry.Model.Parent then entry.Model = findPlacedModel(id) end end
            Music.Sync(snapshot)
        end
    end
end)

local function requestRefresh()
	if refreshQueued or not activeSessionId then return end
	refreshQueued = true
	task.delay(0.15, function()
		refreshQueued = false
		if not activeSessionId then return end
		local ok, nextSnapshot = pcall(requestSnapshot.InvokeServer, requestSnapshot, activeSessionId)
		if ok and nextSnapshot then applySnapshot(nextSnapshot) end
	end)
end

local function bindInventory()
	for _, connection in ipairs(inventoryConnections) do connection:Disconnect() end
	table.clear(inventoryConnections)
	local inventory = player:FindFirstChild("MaterialInventory")
	if not inventory then return end
	local function bindCount(count)
		if count:IsA("IntValue") then
			table.insert(inventoryConnections, count:GetPropertyChangedSignal("Value"):Connect(requestRefresh))
		end
	end
	for _, count in ipairs(inventory:GetChildren()) do bindCount(count) end
	table.insert(inventoryConnections, inventory.ChildAdded:Connect(function(child)
		bindCount(child)
		requestRefresh()
	end))
	table.insert(inventoryConnections, inventory.ChildRemoved:Connect(requestRefresh))
end

player.ChildAdded:Connect(function(child)
	if child.Name == "MaterialInventory" then bindInventory() end
end)
furnitureFolder.DescendantAdded:Connect(requestRefresh)
furnitureFolder.DescendantRemoving:Connect(requestRefresh)
player:GetAttributeChangedSignal("TradingInterfaceLocked"):Connect(function()
	if player:GetAttribute("TradingInterfaceLocked") == true then
		if Music.Panel.Visible then
			Music.CloseEditor()
		end
		if Sign.Panel.Visible then
			Sign.CloseEditor()
		end
		if Visit.Panel.Visible then
			Visit.Close(false)
		end
		if taxPanel.Visible then
			closeTaxPanel(false)
		else
			closeLandlordMenu()
		end
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
    HouseTools.UI.FitViewport(camera)
end)
RunService.Heartbeat:Connect(function()
    if camera and HouseTools.Viewport ~= camera.ViewportSize then HouseTools.Viewport = camera.ViewportSize; HouseTools.UI.FitViewport(camera) end
end)

setStep(45)
cancelPreview(true)
landlordPanel.Visible = false
buildPanel.Visible = false
upgradePanel.Visible = false
taxPanel.Visible = false
Visit.Panel.Visible = false
Visit.BackButton.Active = true
Visit.BackButton.AutoButtonColor = true
Music.Panel.Visible = false
Music.SetPending(false)
Sign.Panel.Visible = false
Sign.SetPending(false)
upgradePanel:SetAttribute("BlocksHotbar", false)
gui:SetAttribute("BlocksHotbar", false)
styleButtonTemplate.Visible = false
upgradeRowTemplate.Visible = false
noUpgradesLabel.Visible = false
buildToggleButton.Visible = false
Visit.AccessButton.Active = true
Visit.AccessButton.AutoButtonColor = true
setInterfaceOpen(false)
bindInventory()

