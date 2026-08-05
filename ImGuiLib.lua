local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Theme = {
	Background = Color3.fromRGB(15, 15, 18),
	BackgroundTransparency = 0.15,
	Header = Color3.fromRGB(35, 69, 108),
	HeaderHover = Color3.fromRGB(48, 88, 136),
	HeaderActive = Color3.fromRGB(28, 55, 86),
	SectionHeader = Color3.fromRGB(30, 50, 75),
	Element = Color3.fromRGB(28, 28, 32),
	ElementHover = Color3.fromRGB(45, 45, 55),
	ElementActive = Color3.fromRGB(55, 55, 70),
	Accent = Color3.fromRGB(41, 74, 122),
	Grabber = Color3.fromRGB(66, 115, 180),
	GrabberHover = Color3.fromRGB(85, 140, 210),
	Text = Color3.fromRGB(240, 240, 240),
	SubText = Color3.fromRGB(160, 160, 165),
	Border = Color3.fromRGB(50, 50, 60),
	SeparatorLine = Color3.fromRGB(50, 50, 60),
	Disabled = Color3.fromRGB(90, 90, 100),
	Font = Enum.Font.RobotoMono,
	TextSize = 12,
	ItemSpacing = 4,
	IndentSpacing = 12,
	GrabberWidth = 10,
}

local Library = {}
Library.__index = Library
Library.Windows = {}
Library.ToolWindows = {}
Library.Flags = {}
Library.RegisteredKeybinds = {}
Library.ConfigFolder = "ImGuiConfigs"
Library.AutoSaveEnabled = false
Library.CurrentConfig = nil
Library.IDStack = {}
Library.ZIndexCounter = 100

-- Global connection registry, used by Library:Unload() to fully tear down
-- the module-level (non window-scoped) UserInputService connections.
Library.Connections = {}

local function track(conn)
	table.insert(Library.Connections, conn)
	return conn
end

-- Keybind Kayıt Kaydı
function Library:RegisterKeybind(name, getKeyFn, setKeyFn)
	local entry = {
		Name = name,
		GetKey = getKeyFn,
		SetKey = setKeyFn
	}
	table.insert(Library.RegisteredKeybinds, entry)
	return entry
end

-- ID Stack System
function Library:PushID(id)
	table.insert(Library.IDStack, tostring(id))
end

function Library:PopID()
	table.remove(Library.IDStack)
end

function Library:GetID(label)
	if #Library.IDStack == 0 then return tostring(label) end
	return table.concat(Library.IDStack, "/") .. "/" .. tostring(label)
end

-- Z-Index Management
function Library:GetNextZIndex()
	Library.ZIndexCounter = Library.ZIndexCounter + 1
	return Library.ZIndexCounter
end

function Library:BringToFront(window)
	if window and window.Main then
		window.Main.ZIndex = Library:GetNextZIndex()
	end
end

-- ============================================================
-- Helper Functions & Executor Support
-- ============================================================
local function getParentGui()
	if typeof(gethui) == "function" then
		local ok, res = pcall(gethui)
		if ok and res then return res end
	end
	if typeof(gethiddenui) == "function" then
		local ok, res = pcall(gethiddenui)
		if ok and res then return res end
	end
	return PlayerGui
end

local function stroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Theme.Border
	s.Thickness = thickness or 1
	s.Parent = inst
	return s
end

local function flexify(inst, widthScale)
	if widthScale then
		inst.Size = UDim2.new(widthScale, 0, 1, 0)
	else
		local f = Instance.new("UIFlexItem")
		f.FlexMode = Enum.UIFlexMode.Fill
		f.Parent = inst
		inst.Size = UDim2.new(0, 0, 1, 0)
	end
end

local function formatValue(format, v)
	if type(format) == "function" then return format(v) end
	if type(format) == "string" then return string.format(format, v) end
	return tostring(v)
end

-- Markdown -> RichText parsing
local function escapeRich(s)
	s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return s
end

local function parseMarkdownLine(line)
	local headerLevel = 0
	local content = line

	if line:match("^###%s+") then
		headerLevel = 3
		content = line:match("^###%s+(.*)$")
	elseif line:match("^##%s+") then
		headerLevel = 2
		content = line:match("^##%s+(.*)$")
	elseif line:match("^#%s+") then
		headerLevel = 1
		content = line:match("^#%s+(.*)$")
	end

	content = escapeRich(content)
	content = content:gsub("%*%*(.-)%*%*", "<b>%1</b>")
	content = content:gsub("%*(.-)%*", "<i>%1</i>")
	content = content:gsub("`(.-)`", "<font face=\"RobotoMono\">%1</font>")

	if headerLevel == 1 then
		content = "<font size=\"20\"><b>" .. content .. "</b></font>"
	elseif headerLevel == 2 then
		content = "<font size=\"17\"><b>" .. content .. "</b></font>"
	elseif headerLevel == 3 then
		content = "<font size=\"14\"><b>" .. content .. "</b></font>"
	end

	return content
end

local function markdownToRichText(text)
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, parseMarkdownLine(line))
	end
	return table.concat(lines, "\n")
end

local function getScreenGui()
	local parent = getParentGui()
	local existing = parent:FindFirstChild("ImGuiLibrary")
	if existing then return existing end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ImGuiLibrary"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	return gui
end

-- Every user-supplied callback in the library is routed through this so a
-- broken callback from a consumer script can never freeze/crash the menu.
local function safeCall(fn, ...)
	if not fn then return end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[ImGuiLibrary] Callback error: " .. tostring(err))
	end
	return ok
end

-- ============================================================
-- imgui-notify Tarzı Bildirim Sistemi
-- ============================================================
local NotifyContainer = Instance.new("Frame")
NotifyContainer.Name = "NotifyContainer"
NotifyContainer.Size = UDim2.new(0, 220, 0, 0)
NotifyContainer.Position = UDim2.new(1, -10, 1, -10)
NotifyContainer.AnchorPoint = Vector2.new(1, 1)
NotifyContainer.BackgroundTransparency = 1
NotifyContainer.ZIndex = 99999
NotifyContainer.Parent = getScreenGui()

local NotifyLayout = Instance.new("UIListLayout")
NotifyLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
NotifyLayout.Padding = UDim.new(0, 4)
NotifyLayout.Parent = NotifyContainer

function Library:Notify(title, message, duration, notifyType)
	duration = duration or 3
	notifyType = notifyType or "info"

	local typeColors = {
		info = Color3.fromRGB(41, 74, 122),
		success = Color3.fromRGB(40, 140, 60),
		warning = Color3.fromRGB(180, 130, 30),
		error = Color3.fromRGB(180, 40, 40)
	}
	local accentColor = typeColors[notifyType] or typeColors.info

	local Card = Instance.new("Frame")
	Card.Size = UDim2.new(1, 0, 0, 0)
	Card.AutomaticSize = Enum.AutomaticSize.Y
	Card.BackgroundColor3 = Theme.Background
	Card.BorderSizePixel = 0
	Card.Parent = NotifyContainer
	stroke(Card, Theme.Border)

	local LeftBar = Instance.new("Frame")
	LeftBar.Size = UDim2.new(0, 3, 1, 0)
	LeftBar.BackgroundColor3 = accentColor
	LeftBar.BorderSizePixel = 0
	LeftBar.Parent = Card

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 8)
	Pad.PaddingRight = UDim.new(0, 6)
	Pad.PaddingTop = UDim.new(0, 6)
	Pad.PaddingBottom = UDim.new(0, 6)
	Pad.Parent = Card

	local Layout = Instance.new("UIListLayout")
	Layout.Padding = UDim.new(0, 2)
	Layout.Parent = Card

	local TitleLbl = Instance.new("TextLabel")
	TitleLbl.Size = UDim2.new(1, 0, 0, 14)
	TitleLbl.BackgroundTransparency = 1
	TitleLbl.Font = Theme.Font
	TitleLbl.TextSize = 11
	TitleLbl.TextColor3 = Theme.Text
	TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	TitleLbl.Text = title or "Notification"
	TitleLbl.Parent = Card

	if message and message ~= "" then
		local MsgLbl = Instance.new("TextLabel")
		MsgLbl.Size = UDim2.new(1, 0, 0, 0)
		MsgLbl.AutomaticSize = Enum.AutomaticSize.Y
		MsgLbl.BackgroundTransparency = 1
		MsgLbl.Font = Theme.Font
		MsgLbl.TextSize = 10
		MsgLbl.TextColor3 = Theme.SubText
		MsgLbl.TextXAlignment = Enum.TextXAlignment.Left
		MsgLbl.TextWrapped = true
		MsgLbl.Text = message
		MsgLbl.Parent = Card
	end

	task.delay(duration, function()
		if Card and Card.Parent then
			TS:Create(Card, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
			task.wait(0.3)
			Card:Destroy()
		end
	end)
end

-- ============================================================
-- Onay Diyaloğu Modal Penceresi (Confirm Modal)
-- ============================================================
function Library:ConfirmModal(title, text, onConfirm, onCancel)
	local Catcher = Instance.new("TextButton")
	Catcher.Size = UDim2.new(1, 0, 1, 0)
	Catcher.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	Catcher.BackgroundTransparency = 0.5
	Catcher.Text = ""
	Catcher.AutoButtonColor = false
	Catcher.ZIndex = 10000
	Catcher.Parent = getScreenGui()

	local Modal = Instance.new("Frame")
	Modal.Size = UDim2.new(0, 260, 0, 0)
	Modal.AutomaticSize = Enum.AutomaticSize.Y
	Modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	Modal.AnchorPoint = Vector2.new(0.5, 0.5)
	Modal.BackgroundColor3 = Theme.Background
	Modal.BorderSizePixel = 0
	Modal.ZIndex = 10001
	Modal.Parent = Catcher
	stroke(Modal, Theme.Border)

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 10)
	Pad.PaddingRight = UDim.new(0, 10)
	Pad.PaddingTop = UDim.new(0, 8)
	Pad.PaddingBottom = UDim.new(0, 8)
	Pad.Parent = Modal

	local Layout = Instance.new("UIListLayout")
	Layout.Padding = UDim.new(0, 8)
	Layout.Parent = Modal

	local TitleLbl = Instance.new("TextLabel")
	TitleLbl.Size = UDim2.new(1, 0, 0, 18)
	TitleLbl.BackgroundTransparency = 1
	TitleLbl.Font = Theme.Font
	TitleLbl.TextSize = 12
	TitleLbl.TextColor3 = Theme.Text
	TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	TitleLbl.Text = title or "Confirm"
	TitleLbl.ZIndex = 10002
	TitleLbl.Parent = Modal

	local MsgLbl = Instance.new("TextLabel")
	MsgLbl.Size = UDim2.new(1, 0, 0, 0)
	MsgLbl.AutomaticSize = Enum.AutomaticSize.Y
	MsgLbl.BackgroundTransparency = 1
	MsgLbl.Font = Theme.Font
	MsgLbl.TextSize = 11
	MsgLbl.TextColor3 = Theme.SubText
	MsgLbl.TextXAlignment = Enum.TextXAlignment.Left
	MsgLbl.TextWrapped = true
	MsgLbl.Text = text or "Are you sure?"
	MsgLbl.ZIndex = 10002
	MsgLbl.Parent = Modal

	local BtnRow = Instance.new("Frame")
	BtnRow.Size = UDim2.new(1, 0, 0, 22)
	BtnRow.BackgroundTransparency = 1
	BtnRow.ZIndex = 10002
	BtnRow.Parent = Modal

	local BtnLayout = Instance.new("UIListLayout")
	BtnLayout.FillDirection = Enum.FillDirection.Horizontal
	BtnLayout.Padding = UDim.new(0, 6)
	BtnLayout.Parent = BtnRow

	local YesBtn = Instance.new("TextButton")
	YesBtn.Size = UDim2.new(0.5, -3, 1, 0)
	YesBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
	YesBtn.BorderSizePixel = 0
	YesBtn.Text = "Evet / Sil"
	YesBtn.Font = Theme.Font
	YesBtn.TextSize = 11
	YesBtn.TextColor3 = Theme.Text
	YesBtn.ZIndex = 10003
	YesBtn.Parent = BtnRow
	stroke(YesBtn, Theme.Border)

	local NoBtn = Instance.new("TextButton")
	NoBtn.Size = UDim2.new(0.5, -3, 1, 0)
	NoBtn.BackgroundColor3 = Theme.Element
	NoBtn.BorderSizePixel = 0
	NoBtn.Text = "İptal"
	NoBtn.Font = Theme.Font
	NoBtn.TextSize = 11
	NoBtn.TextColor3 = Theme.Text
	NoBtn.ZIndex = 10003
	NoBtn.Parent = BtnRow
	stroke(NoBtn, Theme.Border)

	YesBtn.MouseButton1Click:Connect(function()
		Catcher:Destroy()
		safeCall(onConfirm)
	end)

	NoBtn.MouseButton1Click:Connect(function()
		Catcher:Destroy()
		safeCall(onCancel)
	end)
end

-- Global Tooltip Manager
local TooltipFrame = Instance.new("TextLabel")
TooltipFrame.Name = "ImGuiTooltip"
TooltipFrame.Size = UDim2.new(0, 0, 0, 18)
TooltipFrame.AutomaticSize = Enum.AutomaticSize.X
TooltipFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
TooltipFrame.BorderSizePixel = 0
TooltipFrame.Font = Theme.Font
TooltipFrame.TextSize = 11
TooltipFrame.TextColor3 = Theme.Text
TooltipFrame.Visible = false
TooltipFrame.ZIndex = 9999
TooltipFrame.Parent = getScreenGui()
stroke(TooltipFrame, Theme.Border)

local TooltipPad = Instance.new("UIPadding")
TooltipPad.PaddingLeft = UDim.new(0, 6)
TooltipPad.PaddingRight = UDim.new(0, 6)
TooltipPad.Parent = TooltipFrame

track(UIS.InputChanged:Connect(function(input)
	if TooltipFrame.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
		TooltipFrame.Position = UDim2.new(0, input.Position.X + 12, 0, input.Position.Y + 12)
	end
end))

local function bindTooltip(target, text)
	if not target then return end
	local inst = target
	if type(target) == "table" then
		inst = target.Instance or target.Holder or target.Widget
	end

	if not inst or typeof(inst) ~= "Instance" or not inst:IsA("GuiObject") then
		return
	end

	inst.MouseEnter:Connect(function()
		TooltipFrame.Text = text
		TooltipFrame.Position = UDim2.new(0, UIS:GetMouseLocation().X + 12, 0, UIS:GetMouseLocation().Y + 12)
		TooltipFrame.Visible = true
	end)
	inst.MouseLeave:Connect(function()
		TooltipFrame.Visible = false
	end)
end

-- Overlay Layer & Popups
local OverlayLayer = Instance.new("Frame")
OverlayLayer.Name = "OverlayLayer"
OverlayLayer.Size = UDim2.new(1, 0, 1, 0)
OverlayLayer.BackgroundTransparency = 1
OverlayLayer.ZIndex = 5000
OverlayLayer.Parent = getScreenGui()

local ActivePopup = nil

local function closeActivePopup()
	if ActivePopup then
		local popup = ActivePopup
		ActivePopup = nil
		if popup.onClose then safeCall(popup.onClose) end
		if popup.catcher then popup.catcher:Destroy() end
		if popup.panel then popup.panel:Destroy() end
	end
end

-- Sürükleme (Drag) Sistemi
local function makeDraggable(handles, target)
	if type(handles) ~= "table" then handles = {handles} end
	local dragging = false
	local dragStart, startPos
	local moveConn, endConn

	local function stopDrag()
		dragging = false
		if moveConn then moveConn:Disconnect(); moveConn = nil end
		if endConn then endConn:Disconnect(); endConn = nil end
	end

	local function startDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			closeActivePopup()
			stopDrag()
			dragging = true
			dragStart = input.Position
			startPos = target.Position

			moveConn = UIS.InputChanged:Connect(function(moveInput)
				if dragging and (moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch) then
					local delta = moveInput.Position - dragStart
					target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
				end
			end)

			endConn = UIS.InputEnded:Connect(function(endInput)
				if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
					stopDrag()
				end
			end)
		end
	end

	for _, handle in ipairs(handles) do
		handle.InputBegan:Connect(startDrag)
	end
end

local function openOverlayPanel(anchor, height, buildFn, onClose, overrideWidth)
	closeActivePopup()

	local catcher = Instance.new("TextButton")
	catcher.Size = UDim2.new(1, 0, 1, 0)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.ZIndex = OverlayLayer.ZIndex
	catcher.Parent = OverlayLayer

	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = Theme.Background
	panel.BorderSizePixel = 0
	panel.ZIndex = OverlayLayer.ZIndex + 1
	panel.Parent = OverlayLayer
	stroke(panel, Theme.Border)

	local absPos = anchor.AbsolutePosition
	local absSize = anchor.AbsoluteSize
	local screenSize = OverlayLayer.AbsoluteSize
	local panelWidth = overrideWidth or absSize.X

	local posX = absPos.X
	local posY = absPos.Y + absSize.Y + 2
	if posY + height > screenSize.Y then
		posY = absPos.Y - height - 2
	end
	if posX + panelWidth > screenSize.X then
		posX = math.max(0, screenSize.X - panelWidth)
	end

	panel.Position = UDim2.new(0, posX, 0, posY)
	panel.Size = UDim2.new(0, panelWidth, 0, height)

	catcher.MouseButton1Click:Connect(function()
		closeActivePopup()
	end)

	buildFn(panel)

	ActivePopup = { catcher = catcher, panel = panel, onClose = onClose }
end

local function attachContextMenu(inst, itemsFn)
	if not inst or typeof(inst) ~= "Instance" then return end

	inst.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

		local items = itemsFn and itemsFn() or nil
		if not items or #items == 0 then return end

		closeActivePopup()

		local mousePos = UIS:GetMouseLocation()
		local screenSize = OverlayLayer.AbsoluteSize
		local menuWidth, menuHeight = 150, (#items * 20) + 6

		local catcher = Instance.new("TextButton")
		catcher.Size = UDim2.new(1, 0, 1, 0)
		catcher.BackgroundTransparency = 1
		catcher.Text = ""
		catcher.AutoButtonColor = false
		catcher.ZIndex = OverlayLayer.ZIndex
		catcher.Parent = OverlayLayer

		local panel = Instance.new("Frame")
		panel.BackgroundColor3 = Theme.Background
		panel.BorderSizePixel = 0
		panel.ZIndex = OverlayLayer.ZIndex + 1
		panel.Size = UDim2.new(0, menuWidth, 0, menuHeight)
		panel.Position = UDim2.new(
			0, math.min(mousePos.X, screenSize.X - menuWidth),
			0, math.min(mousePos.Y, screenSize.Y - menuHeight)
		)
		panel.Parent = OverlayLayer
		stroke(panel, Theme.Border)

		local Pad = Instance.new("UIPadding")
		Pad.PaddingTop = UDim.new(0, 3)
		Pad.PaddingLeft = UDim.new(0, 3)
		Pad.PaddingRight = UDim.new(0, 3)
		Pad.Parent = panel

		local Layout = Instance.new("UIListLayout")
		Layout.Padding = UDim.new(0, 2)
		Layout.Parent = panel

		for _, item in ipairs(items) do
			local Btn = Instance.new("TextButton")
			Btn.Size = UDim2.new(1, 0, 0, 18)
			Btn.BackgroundColor3 = Theme.Element
			Btn.BorderSizePixel = 0
			Btn.Text = item.Text
			Btn.Font = Theme.Font
			Btn.TextSize = 11
			Btn.TextColor3 = Theme.Text
			Btn.TextXAlignment = Enum.TextXAlignment.Left
			Btn.ZIndex = OverlayLayer.ZIndex + 2
			Btn.Parent = panel

			local IPad = Instance.new("UIPadding")
			IPad.PaddingLeft = UDim.new(0, 6)
			IPad.Parent = Btn

			Btn.MouseEnter:Connect(function()
				if Btn.BackgroundColor3 ~= Theme.Accent then
					Btn.BackgroundColor3 = Theme.ElementHover
				end
			end)
			Btn.MouseLeave:Connect(function()
				if Btn.BackgroundColor3 ~= Theme.Accent then
					Btn.BackgroundColor3 = Theme.Element
				end
			end)
			Btn.MouseButton1Click:Connect(function()
				if item.PreventClose then
					safeCall(item.Callback, Btn)
				else
					closeActivePopup()
					safeCall(item.Callback, Btn)
				end
			end)
		end

		catcher.MouseButton1Click:Connect(function() closeActivePopup() end)

		ActivePopup = { catcher = catcher, panel = panel, onClose = function()
			for _, item in ipairs(items) do
				if item.OnClose then safeCall(item.OnClose) end
			end
		end }
	end)
end

local function hasFileApi()
	return writefile and readfile and isfile and isfolder and makefolder
end

local function ensureFolder()
	if hasFileApi() and not isfolder(Library.ConfigFolder) then
		makefolder(Library.ConfigFolder)
	end
end

local function registerFlag(flag, getSet)
	if not flag then return end
	Library.Flags[Library:GetID(flag)] = getSet
end

local function pushAutoSave()
	if Library.AutoSaveEnabled and Library.CurrentConfig then
		Library:SaveConfig(Library.CurrentConfig)
	end
end

function Library:SaveConfig(name)
	if not hasFileApi() then return false end
	ensureFolder()
	local data = {}
	for flag, obj in pairs(Library.Flags) do
		data[flag] = obj.Get()
	end
	writefile(Library.ConfigFolder .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	Library:Notify("Config Saved", name .. ".json kaydedildi.", 3, "success")
	return true
end

function Library:LoadConfig(name)
	if not hasFileApi() then return false end
	local path = Library.ConfigFolder .. "/" .. name .. ".json"
	if not isfile(path) then return false end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if not ok then return false end
	for flag, value in pairs(data) do
		if Library.Flags[flag] then
			Library.Flags[flag].Set(value)
		end
	end
	Library.CurrentConfig = name
	Library:Notify("Config Loaded", name .. ".json yüklendi.", 3, "info")
	return true
end

function Library:ListConfigs()
	if not hasFileApi() or not listfiles then return {} end
	ensureFolder()
	local list = {}
	for _, file in ipairs(listfiles(Library.ConfigFolder)) do
		local name = file:match("([^/\\]+)%.json$")
		if name then table.insert(list, name) end
	end
	return list
end

function Library:SetAutoSave(enabled, name)
	Library.AutoSaveEnabled = enabled
	if name then Library.CurrentConfig = name end
end

local ActiveSlider = nil

track(UIS.InputChanged:Connect(function(input)
	if ActiveSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		ActiveSlider.Update(input.Position.X)
	end
end))

track(UIS.InputEnded:Connect(function(input)
	if ActiveSlider and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		ActiveSlider.Release()
		ActiveSlider = nil
	end
end))

local KeybindToggles = {}

track(UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	for _, entry in ipairs(KeybindToggles) do
		if entry.Key == input.KeyCode then
			entry.Toggle()
		end
	end
end))

-- Helper: Add Dependency API & Dynamic Element Deletion API
local function attachDependencyAPI(holder, api, flag)
	api.Instance = holder
	api.Holder = holder

	local isDisabled = false

	function api.SetDisabled(disabled)
		isDisabled = disabled
		for _, child in ipairs(holder:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("TextBox") or child:IsA("TextButton") then
				child.TextTransparency = disabled and 0.5 or 0
			end
			if child:IsA("GuiButton") or child:IsA("TextBox") or child:IsA("Frame") then
				child.Active = not disabled
			end
		end
	end

	function api.DependsOn(parentWidget, expectedValue)
		if type(expectedValue) == "nil" then expectedValue = true end
		local function update()
			local current = parentWidget.Get()
			api.SetDisabled(current ~= expectedValue)
		end
		if parentWidget.OnChanged then
			parentWidget.OnChanged(update)
		end
		update()
		return api
	end

	function api.Destroy()
		if flag and Library.Flags[flag] then
			Library.Flags[flag] = nil
		end
		if holder and typeof(holder) == "Instance" then
			holder:Destroy()
		end
	end
	api.Remove = api.Destroy

	return api
end

-- ============================================================
-- Widget Builders
-- ============================================================

local function buildLabel(container, text)
	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, 18)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.SubText
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = container

	local api = attachDependencyAPI(Label, {})
	return Label, api
end

local function buildMarkdown(container, text)
	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, 0)
	Label.AutomaticSize = Enum.AutomaticSize.Y
	Label.BackgroundTransparency = 1
	Label.RichText = true
	Label.TextWrapped = true
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextYAlignment = Enum.TextYAlignment.Top
	Label.Text = markdownToRichText(text)
	Label.Parent = container

	local api = attachDependencyAPI(Label, {
		SetText = function(newText) Label.Text = markdownToRichText(newText) end
	})
	return Label, api
end

local function buildSeparator(container, text)
	local Row = Instance.new("Frame")
	Row.Size = UDim2.new(1, 0, 0, text and 18 or 8)
	Row.BackgroundTransparency = 1
	Row.Parent = container

	local Layout = Instance.new("UIListLayout")
	Layout.FillDirection = Enum.FillDirection.Horizontal
	Layout.SortOrder = Enum.SortOrder.LayoutOrder
	Layout.VerticalAlignment = Enum.VerticalAlignment.Center
	Layout.Padding = UDim.new(0, 6)
	Layout.Parent = Row

	local Line = Instance.new("Frame")
	Line.LayoutOrder = 2
	Line.BackgroundColor3 = Theme.SeparatorLine
	Line.BorderSizePixel = 0
	Line.Parent = Row

	if text then
		local Label = Instance.new("TextLabel")
		Label.LayoutOrder = 1
		Label.AutomaticSize = Enum.AutomaticSize.X
		Label.Size = UDim2.new(0, 0, 1, 0)
		Label.BackgroundTransparency = 1
		Label.Font = Theme.Font
		Label.TextSize = Theme.TextSize
		Label.TextColor3 = Theme.SubText
		Label.TextXAlignment = Enum.TextXAlignment.Left
		Label.Text = text
		Label.Parent = Row

		Line.Size = UDim2.new(0, 24, 0, 1)
	else
		Line.Size = UDim2.new(0, 0, 0, 1)
		flexify(Line)
	end

	return attachDependencyAPI(Row, {})
end

local function buildButton(container, text, callback)
	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 0, 22)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text
	Btn.Font = Theme.Font
	Btn.TextSize = Theme.TextSize
	Btn.TextColor3 = Theme.Text
	Btn.Parent = container
	stroke(Btn, Theme.Border)

	Btn.MouseEnter:Connect(function() Btn.BackgroundColor3 = Theme.ElementHover end)
	Btn.MouseLeave:Connect(function() Btn.BackgroundColor3 = Theme.Element end)
	Btn.MouseButton1Down:Connect(function() Btn.BackgroundColor3 = Theme.ElementActive end)
	Btn.MouseButton1Up:Connect(function() Btn.BackgroundColor3 = Theme.ElementHover end)

	Btn.MouseButton1Click:Connect(function()
		safeCall(callback)
	end)

	local api = attachDependencyAPI(Btn, {})
	return Btn, api
end

local function buildCheckbox(container, text, default, callback, flag, bindEnabled)
	if bindEnabled == nil then bindEnabled = true end
	local state = default or false
	local defaultVal = state
	local onChangedCallbacks = {}
	local bindKey = nil
	local listeningBind = false
	local bindConn = nil

	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 20)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.Parent = container

	local Box = Instance.new("Frame")
	Box.Size = UDim2.new(0, 14, 0, 14)
	Box.Position = UDim2.new(0, 0, 0.5, -7)
	Box.BackgroundColor3 = state and Theme.Accent or Theme.Element
	Box.BorderSizePixel = 0
	Box.Active = false
	Box.Parent = Holder
	stroke(Box, Theme.Border)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -20, 1, 0)
	Label.Position = UDim2.new(0, 20, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Active = false
	Label.Parent = Holder

	local function setState(v, fromUser)
		state = v
		Box.BackgroundColor3 = state and Theme.Accent or Theme.Element
		safeCall(callback, state)
		for _, cb in ipairs(onChangedCallbacks) do safeCall(cb, state) end
		if fromUser then pushAutoSave() end
	end

	Holder.MouseButton1Click:Connect(function()
		setState(not state, true)
	end)

	local keybindEntry = { Key = nil, Toggle = function() setState(not state, true) end }
	table.insert(KeybindToggles, keybindEntry)

	local function setBindKey(k)
		bindKey = k
		keybindEntry.Key = k
	end

	Library:RegisterKeybind("Toggle: " .. text, function() return bindKey end, function(k) setBindKey(k) end)

	attachContextMenu(Holder, function()
		local items = {{Text = "Reset to Default", Callback = function() setState(defaultVal, true) end}}
		if bindEnabled then
			table.insert(items, {
				Text = "Bind Key: " .. (bindKey and bindKey.Name or "None"),
				PreventClose = true,
				OnClose = function()
					if bindConn then bindConn:Disconnect(); bindConn = nil end
					listeningBind = false
				end,
				Callback = function(btn)
					if listeningBind then return end
					listeningBind = true
					if btn then
						btn.Text = "Bind Key: Tuşa basın..."
						btn.BackgroundColor3 = Theme.Accent
					end

					if bindConn then bindConn:Disconnect() end
					bindConn = UIS.InputBegan:Connect(function(bindInput)
						if bindInput.UserInputType == Enum.UserInputType.Keyboard then
							if bindInput.KeyCode == Enum.KeyCode.Escape then
								listeningBind = false
								if btn and btn.Parent then
									btn.Text = "Bind Key: " .. (bindKey and bindKey.Name or "None")
									btn.BackgroundColor3 = Theme.Element
								end
								if bindConn then bindConn:Disconnect(); bindConn = nil end
								task.delay(0.1, closeActivePopup)
								return
							end

							setBindKey(bindInput.KeyCode)
							listeningBind = false
							if btn and btn.Parent then
								btn.Text = "Bind Key: " .. bindInput.KeyCode.Name
								btn.BackgroundColor3 = Theme.Element
							end
							if bindConn then bindConn:Disconnect(); bindConn = nil end
							task.delay(0.2, closeActivePopup)
						elseif bindInput.UserInputType == Enum.UserInputType.MouseButton1 then
							listeningBind = false
							if btn and btn.Parent then
								btn.Text = "Bind Key: " .. (bindKey and bindKey.Name or "None")
								btn.BackgroundColor3 = Theme.Element
							end
							if bindConn then bindConn:Disconnect(); bindConn = nil end
						end
					end)
				end
			})
			if bindKey then
				table.insert(items, {Text = "Unbind Key", Callback = function() setBindKey(nil) end})
			end
		end
		return items
	end)

	registerFlag(flag, {Get = function() return state end, Set = function(v) setState(v, false) end})
	if callback then safeCall(callback, state) end

	local api = attachDependencyAPI(Holder, {
		Set = function(v) setState(v, false) end,
		Get = function() return state end,
		OnChanged = function(cb) table.insert(onChangedCallbacks, cb) end,
		SetBindKey = function(k) setBindKey(k) end,
		GetBindKey = function() return bindKey end
	}, flag)

	return Holder, api
end

local function buildSlider(container, text, min, max, default, callback, flag, decimals, scrollable)
	min = min or 0
	max = max or 100
	decimals = decimals or 0
	local mult = 10 ^ decimals
	local value = default or min
	local defaultVal = value

	local function roundVal(v)
		if decimals > 0 then
			return math.floor(v * mult + 0.5) / mult
		else
			return math.floor(v + 0.5)
		end
	end

	local function fmt(v)
		if decimals > 0 then
			return string.format("%." .. decimals .. "f", v)
		end
		return tostring(v)
	end

	value = roundVal(value)

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Track = Instance.new("Frame")
	Track.Size = UDim2.new(1, 0, 1, 0)
	Track.BackgroundColor3 = Theme.Element
	Track.BorderSizePixel = 0
	Track.Active = true
	Track.Parent = Holder
	stroke(Track, Theme.Border)

	local grabWidth = Theme.GrabberWidth or 10
	local rel = (value - min) / math.max(1e-9, max - min)

	local Fill = Instance.new("Frame")
	Fill.Size = UDim2.new(rel, 0, 1, 0)
	Fill.BackgroundColor3 = Theme.Accent
	Fill.BackgroundTransparency = 0.5
	Fill.BorderSizePixel = 0
	Fill.Parent = Track

	local Grabber = Instance.new("Frame")
	Grabber.Size = UDim2.new(0, grabWidth, 1, 0)
	Grabber.Position = UDim2.new(rel, -rel * grabWidth, 0, 0)
	Grabber.BackgroundColor3 = Theme.Grabber
	Grabber.BorderSizePixel = 0
	Grabber.ZIndex = 3
	Grabber.Parent = Track
	stroke(Grabber, Theme.Border)

	local ValueLabel = Instance.new("TextLabel")
	ValueLabel.Size = UDim2.new(1, -8, 1, 0)
	ValueLabel.Position = UDim2.new(0, 4, 0, 0)
	ValueLabel.BackgroundTransparency = 1
	ValueLabel.Text = text .. ": " .. fmt(value)
	ValueLabel.Font = Theme.Font
	ValueLabel.TextSize = Theme.TextSize
	ValueLabel.TextColor3 = Theme.Text
	ValueLabel.TextXAlignment = Enum.TextXAlignment.Left
	ValueLabel.ZIndex = 4
	ValueLabel.Parent = Track

	local THROTTLE = 0.05
	local lastFire = 0

	local function applyVisual()
		grabWidth = Theme.GrabberWidth or 10
		local r = (value - min) / math.max(1e-9, max - min)
		Fill.Size = UDim2.new(r, 0, 1, 0)
		Grabber.Size = UDim2.new(0, grabWidth, 1, 0)
		Grabber.Position = UDim2.new(r, -r * grabWidth, 0, 0)
		ValueLabel.Text = text .. ": " .. fmt(value)
	end

	local function fireCallback()
		lastFire = os.clock()
		safeCall(callback, value)
	end

	local function apply(v, forceFire)
		value = math.clamp(roundVal(v), min, max)
		applyVisual()
		if forceFire or (os.clock() - lastFire) >= THROTTLE then
			fireCallback()
		end
	end

	local function setFromX(x)
		local r = math.clamp((x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
		apply(min + (max - min) * r)
	end

	-- Ctrl + Click ile Elle Değer Girişi (Iconic ImGui)
	Track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then
				ValueLabel.Visible = false
				local InputBox = Instance.new("TextBox")
				InputBox.Size = UDim2.new(1, -8, 1, 0)
				InputBox.Position = UDim2.new(0, 4, 0, 0)
				InputBox.BackgroundTransparency = 1
				InputBox.Text = fmt(value)
				InputBox.Font = Theme.Font
				InputBox.TextSize = Theme.TextSize
				InputBox.TextColor3 = Theme.Text
				InputBox.TextXAlignment = Enum.TextXAlignment.Left
				InputBox.ZIndex = 5
				InputBox.Parent = Track

				InputBox:CaptureFocus()

				local function commit()
					local num = tonumber(InputBox.Text)
					if num then
						apply(num, true)
						pushAutoSave()
					end
					InputBox:Destroy()
					ValueLabel.Visible = true
				end

				InputBox.FocusLost:Connect(function()
					commit()
				end)
				return
			end

			setFromX(input.Position.X)
			ActiveSlider = { Update = setFromX, Release = function() fireCallback(); pushAutoSave() end }
		end
	end)

	-- Scroll Bitişikte Ana Menü Scroll Çakışması Fix
	if scrollable then
		local hovering = false
		local parentScroll = nil
		Track.MouseEnter:Connect(function()
			hovering = true
			parentScroll = Track:FindFirstAncestorOfClass("ScrollingFrame")
			if parentScroll then
				parentScroll.ScrollingEnabled = false
			end
		end)
		Track.MouseLeave:Connect(function()
			hovering = false
			if parentScroll then
				parentScroll.ScrollingEnabled = true
			end
		end)
		local step = decimals > 0 and (1 / mult) or 1
		track(UIS.InputChanged:Connect(function(input)
			if hovering and input.UserInputType == Enum.UserInputType.MouseWheel then
				apply(value + (input.Position.Z > 0 and step or -step), true)
				pushAutoSave()
			end
		end))
	end

	attachContextMenu(Track, function()
		return {{Text = "Reset to Default", Callback = function() apply(defaultVal, true); pushAutoSave() end}}
	end)

	registerFlag(flag, {Get = function() return value end, Set = function(v) apply(v, true) end})
	if callback then safeCall(callback, value) end

	local api = attachDependencyAPI(Holder, {
		Set = function(v) apply(v, true) end,
		Get = function() return value end
	}, flag)
	return api
end

local function buildRangeSlider(container, text, min, max, defaultLow, defaultHigh, callback, flag)
	min, max = min or 0, max or 100
	local valLow = defaultLow or min
	local valHigh = defaultHigh or max
	local defLow, defHigh = valLow, valHigh

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Track = Instance.new("Frame")
	Track.Size = UDim2.new(1, 0, 1, 0)
	Track.BackgroundColor3 = Theme.Element
	Track.BorderSizePixel = 0
	Track.Active = true
	Track.Parent = Holder
	stroke(Track, Theme.Border)

	local grabWidth = Theme.GrabberWidth or 8
	local rLow = (valLow - min) / math.max(1e-9, max - min)
	local rHigh = (valHigh - min) / math.max(1e-9, max - min)

	local Fill = Instance.new("Frame")
	Fill.Position = UDim2.new(rLow, 0, 0, 0)
	Fill.Size = UDim2.new(rHigh - rLow, 0, 1, 0)
	Fill.BackgroundColor3 = Theme.Accent
	Fill.BackgroundTransparency = 0.4
	Fill.BorderSizePixel = 0
	Fill.Parent = Track

	local GrabberLow = Instance.new("Frame")
	GrabberLow.Size = UDim2.new(0, grabWidth, 1, 0)
	GrabberLow.Position = UDim2.new(rLow, -rLow * grabWidth, 0, 0)
	GrabberLow.BackgroundColor3 = Theme.Grabber
	GrabberLow.BorderSizePixel = 0
	GrabberLow.ZIndex = 3
	GrabberLow.Parent = Track
	stroke(GrabberLow, Theme.Border)

	local GrabberHigh = Instance.new("Frame")
	GrabberHigh.Size = UDim2.new(0, grabWidth, 1, 0)
	GrabberHigh.Position = UDim2.new(rHigh, -rHigh * grabWidth, 0, 0)
	GrabberHigh.BackgroundColor3 = Theme.Grabber
	GrabberHigh.BorderSizePixel = 0
	GrabberHigh.ZIndex = 3
	GrabberHigh.Parent = Track
	stroke(GrabberHigh, Theme.Border)

	local ValueLabel = Instance.new("TextLabel")
	ValueLabel.Size = UDim2.new(1, -8, 1, 0)
	ValueLabel.Position = UDim2.new(0, 4, 0, 0)
	ValueLabel.BackgroundTransparency = 1
	ValueLabel.Text = text .. ": [" .. tostring(valLow) .. " - " .. tostring(valHigh) .. "]"
	ValueLabel.Font = Theme.Font
	ValueLabel.TextSize = Theme.TextSize
	ValueLabel.TextColor3 = Theme.Text
	ValueLabel.TextXAlignment = Enum.TextXAlignment.Left
	ValueLabel.ZIndex = 4
	ValueLabel.Parent = Track

	local function apply()
		grabWidth = Theme.GrabberWidth or 8
		rLow = (valLow - min) / math.max(1e-9, max - min)
		rHigh = (valHigh - min) / math.max(1e-9, max - min)
		Fill.Position = UDim2.new(rLow, 0, 0, 0)
		Fill.Size = UDim2.new(rHigh - rLow, 0, 1, 0)
		GrabberLow.Size = UDim2.new(0, grabWidth, 1, 0)
		GrabberHigh.Size = UDim2.new(0, grabWidth, 1, 0)
		GrabberLow.Position = UDim2.new(rLow, -rLow * grabWidth, 0, 0)
		GrabberHigh.Position = UDim2.new(rHigh, -rHigh * grabWidth, 0, 0)
		ValueLabel.Text = text .. ": [" .. tostring(valLow) .. " - " .. tostring(valHigh) .. "]"
		safeCall(callback, valLow, valHigh)
	end

	local activeKnob = nil
	Track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local mouseX = input.Position.X
			local trackX = Track.AbsolutePosition.X
			local trackW = Track.AbsoluteSize.X
			local r = math.clamp((mouseX - trackX) / trackW, 0, 1)
			local clickedVal = math.floor(min + (max - min) * r)

			if math.abs(clickedVal - valLow) < math.abs(clickedVal - valHigh) then
				activeKnob = "low"
				valLow = math.min(clickedVal, valHigh)
			else
				activeKnob = "high"
				valHigh = math.max(clickedVal, valLow)
			end
			apply()

			local function updateDrag(x)
				local rel = math.clamp((x - trackX) / trackW, 0, 1)
				local v = math.floor(min + (max - min) * rel)
				if activeKnob == "low" then
					valLow = math.min(v, valHigh)
				else
					valHigh = math.max(v, valLow)
				end
				apply()
			end

			ActiveSlider = { Update = updateDrag, Release = pushAutoSave }
		end
	end)

	attachContextMenu(Track, function()
		return {{Text = "Reset to Default", Callback = function()
			valLow, valHigh = defLow, defHigh
			apply()
			pushAutoSave()
		end}}
	end)

	registerFlag(flag, {
		Get = function() return {low = valLow, high = valHigh} end,
		Set = function(v)
			valLow, valHigh = v.low or min, v.high or max
			apply()
		end
	})
	if callback then safeCall(callback, valLow, valHigh) end

	local api = attachDependencyAPI(Holder, {
		Set = function(l, h) valLow, valHigh = l, h; apply() end,
		Get = function() return valLow, valHigh end
	}, flag)
	return api
end

local function buildKnob(container, text, values, defaultIndex, callback, flag, size)
	values = values or {"1", "2", "3"}
	size = size or 32
	local index = math.clamp(defaultIndex or 1, 1, #values)
	local defaultIdx = index

	local knobRadius = size / 2
	local totalHeight = math.max(size + 8, 26)

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, totalHeight)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local KnobFrame = Instance.new("Frame")
	KnobFrame.Size = UDim2.new(0, size + 16, 0, totalHeight)
	KnobFrame.Position = UDim2.new(0, 0, 0, 0)
	KnobFrame.BackgroundTransparency = 1
	KnobFrame.Parent = Holder

	local Dial = Instance.new("Frame")
	Dial.Size = UDim2.new(0, size, 0, size)
	Dial.Position = UDim2.new(0, 8, 0.5, -knobRadius)
	Dial.BackgroundColor3 = Theme.Element
	Dial.BorderSizePixel = 0
	Dial.Active = true
	Dial.Parent = KnobFrame
	stroke(Dial, Theme.Border)

	local DialCorner = Instance.new("UICorner")
	DialCorner.CornerRadius = UDim.new(1, 0)
	DialCorner.Parent = Dial

	local Pointer = Instance.new("Frame")
	Pointer.Size = UDim2.new(0, 2, 0, math.floor(knobRadius - 3))
	Pointer.AnchorPoint = Vector2.new(0.5, 1)
	Pointer.Position = UDim2.new(0.5, 0, 0.5, 0)
	Pointer.BackgroundColor3 = Theme.Grabber
	Pointer.BorderSizePixel = 0
	Pointer.Parent = Dial

	local Ticks = {}
	local count = #values
	local ANGLE_MIN = -135
	local ANGLE_MAX = 135

	for i = 1, count do
		local frac = (count > 1) and ((i - 1) / (count - 1)) or 0.5
		local angleDeg = ANGLE_MIN + (frac * (ANGLE_MAX - ANGLE_MIN))
		local angleRad = math.rad(angleDeg)

		local dist = knobRadius + 4
		local offsetX = math.sin(angleRad) * dist
		local offsetY = -math.cos(angleRad) * dist

		local Tick = Instance.new("Frame")
		Tick.Size = UDim2.new(0, 3, 0, 3)
		Tick.AnchorPoint = Vector2.new(0.5, 0.5)
		Tick.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
		Tick.BackgroundColor3 = (i == index) and Theme.Grabber or Theme.SeparatorLine
		Tick.BorderSizePixel = 0
		Tick.Parent = Dial

		local TickCorner = Instance.new("UICorner")
		TickCorner.CornerRadius = UDim.new(1, 0)
		TickCorner.Parent = Tick

		table.insert(Ticks, Tick)
	end

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -(size + 20), 1, 0)
	Label.Position = UDim2.new(0, size + 20, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local function apply()
		index = math.clamp(index, 1, #values)
		local currentVal = values[index]
		Label.Text = text .. ": " .. tostring(currentVal)

		local frac = (count > 1) and ((index - 1) / (count - 1)) or 0.5
		local angleDeg = ANGLE_MIN + (frac * (ANGLE_MAX - ANGLE_MIN))
		Pointer.Rotation = angleDeg

		for i, tick in ipairs(Ticks) do
			tick.BackgroundColor3 = (i == index) and Theme.Grabber or Theme.SeparatorLine
			tick.Size = (i == index) and UDim2.new(0, 4, 0, 4) or UDim2.new(0, 3, 0, 3)
		end

		safeCall(callback, currentVal, index)
		pushAutoSave()
	end

	local startX, startIndex
	Dial.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			startX = input.Position.X
			startIndex = index

			local function updateDrag(x)
				local delta = x - startX
				local stepChange = math.floor(delta / 14)
				index = math.clamp(startIndex + stepChange, 1, #values)
				apply()
			end

			ActiveSlider = { Update = updateDrag, Release = pushAutoSave }
		end
	end)

	attachContextMenu(Dial, function()
		return {{Text = "Reset to Default", Callback = function() index = defaultIdx; apply() end}}
	end)

	registerFlag(flag, {
		Get = function() return {index = index, value = values[index]} end,
		Set = function(v)
			if type(v) == "table" then index = v.index or 1 else index = tonumber(v) or 1 end
			apply()
		end
	})

	apply()

	local api = attachDependencyAPI(Holder, {
		Set = function(i) index = i; apply() end,
		Get = function() return values[index], index end
	}, flag)
	return Holder, api
end

local function buildTextbox(container, text, default, placeholder, callback, flag)
	local value = default or ""
	local defaultVal = value
	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Box = Instance.new("TextBox")
	Box.Size = UDim2.new(1, 0, 1, 0)
	Box.BackgroundColor3 = Theme.Element
	Box.BorderSizePixel = 0
	Box.Text = value
	Box.PlaceholderText = placeholder or text
	Box.ClearTextOnFocus = false
	Box.Font = Theme.Font
	Box.TextSize = Theme.TextSize
	Box.TextColor3 = Theme.Text
	Box.PlaceholderColor3 = Theme.SubText
	Box.TextXAlignment = Enum.TextXAlignment.Left
	Box.Parent = Holder
	stroke(Box, Theme.Border)

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 6)
	Pad.Parent = Box

	Box.FocusLost:Connect(function(enterPressed)
		value = Box.Text
		safeCall(callback, value, enterPressed)
		pushAutoSave()
	end)

	attachContextMenu(Box, function()
		return {{Text = "Reset to Default", Callback = function()
			value = defaultVal
			Box.Text = defaultVal
			safeCall(callback, value, false)
			pushAutoSave()
		end}}
	end)

	registerFlag(flag, {Get = function() return value end, Set = function(v) value = v; Box.Text = v end})

	local api = attachDependencyAPI(Holder, {
		Set = function(v) value = v; Box.Text = v end,
		Get = function() return value end
	}, flag)
	return api
end

local function buildNumberInput(container, text, min, max, default, step, callback, flag)
	min = min or 0
	max = max or 100
	step = step or 1
	local value = math.clamp(default or min, min, max)
	local defaultVal = value

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -72, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local MinusBtn = Instance.new("TextButton")
	MinusBtn.Size = UDim2.new(0, 18, 1, 0)
	MinusBtn.Position = UDim2.new(1, -68, 0, 0)
	MinusBtn.BackgroundColor3 = Theme.Element
	MinusBtn.BorderSizePixel = 0
	MinusBtn.Text = "-"
	MinusBtn.Font = Theme.Font
	MinusBtn.TextSize = Theme.TextSize
	MinusBtn.TextColor3 = Theme.Text
	MinusBtn.Parent = Holder
	stroke(MinusBtn, Theme.Border)

	local Box = Instance.new("TextBox")
	Box.Size = UDim2.new(0, 32, 1, 0)
	Box.Position = UDim2.new(1, -49, 0, 0)
	Box.BackgroundColor3 = Theme.Element
	Box.BorderSizePixel = 0
	Box.Text = tostring(value)
	Box.Font = Theme.Font
	Box.TextSize = Theme.TextSize
	Box.TextColor3 = Theme.Text
	Box.ClearTextOnFocus = false
	Box.TextXAlignment = Enum.TextXAlignment.Center
	Box.Parent = Holder
	stroke(Box, Theme.Border)

	local PlusBtn = Instance.new("TextButton")
	PlusBtn.Size = UDim2.new(0, 18, 1, 0)
	PlusBtn.Position = UDim2.new(1, -18, 0, 0)
	PlusBtn.BackgroundColor3 = Theme.Element
	PlusBtn.BorderSizePixel = 0
	PlusBtn.Text = "+"
	PlusBtn.Font = Theme.Font
	PlusBtn.TextSize = Theme.TextSize
	PlusBtn.TextColor3 = Theme.Text
	PlusBtn.Parent = Holder
	stroke(PlusBtn, Theme.Border)

	local function apply(v, fromUser)
		value = math.clamp(math.floor(v + 0.5), min, max)
		Box.Text = tostring(value)
		safeCall(callback, value)
		if fromUser then pushAutoSave() end
	end

	MinusBtn.MouseButton1Click:Connect(function() apply(value - step, true) end)
	PlusBtn.MouseButton1Click:Connect(function() apply(value + step, true) end)

	MinusBtn.MouseEnter:Connect(function() MinusBtn.BackgroundColor3 = Theme.ElementHover end)
	MinusBtn.MouseLeave:Connect(function() MinusBtn.BackgroundColor3 = Theme.Element end)
	PlusBtn.MouseEnter:Connect(function() PlusBtn.BackgroundColor3 = Theme.ElementHover end)
	PlusBtn.MouseLeave:Connect(function() PlusBtn.BackgroundColor3 = Theme.Element end)

	Box.FocusLost:Connect(function()
		local num = tonumber(Box.Text)
		if num then
			apply(num, true)
		else
			Box.Text = tostring(value)
		end
	end)

	attachContextMenu(Holder, function()
		return {{Text = "Reset to Default", Callback = function() apply(defaultVal, true) end}}
	end)

	registerFlag(flag, {Get = function() return value end, Set = function(v) apply(v, false) end})
	if callback then safeCall(callback, value) end

	local api = attachDependencyAPI(Holder, {
		Set = function(v) apply(v, false) end,
		Get = function() return value end
	}, flag)
	return api
end

local function buildProgressBar(container, text, min, max, default, format)
	min = min or 0
	max = max or 100
	local value = default or min

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 20)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Track = Instance.new("Frame")
	Track.Size = UDim2.new(1, 0, 1, 0)
	Track.BackgroundColor3 = Theme.Element
	Track.BorderSizePixel = 0
	Track.Parent = Holder
	stroke(Track, Theme.Border)

	local Fill = Instance.new("Frame")
	Fill.BackgroundColor3 = Theme.Accent
	Fill.BackgroundTransparency = 0.35
	Fill.BorderSizePixel = 0
	Fill.Parent = Track

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -8, 1, 0)
	Label.Position = UDim2.new(0, 4, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.ZIndex = 2
	Label.Parent = Track

	local function apply(v)
		value = math.clamp(v, min, max)
		local r = (value - min) / math.max(1e-9, max - min)
		Fill.Size = UDim2.new(r, 0, 1, 0)
		if format then
			Label.Text = text .. ": " .. formatValue(format, value)
		else
			Label.Text = text .. ": " .. tostring(value)
		end
	end

	apply(value)

	local api = attachDependencyAPI(Holder, {
		Set = function(v) apply(v) end,
		Get = function() return value end
	})
	return api
end

local function buildColorpicker(container, text, default, callback, flag, defaultAlpha)
	local color = default or Color3.fromRGB(255, 255, 255)
	local alpha = (defaultAlpha ~= nil) and defaultAlpha or 1
	local defaultVal = color
	local defaultAlphaVal = alpha
	local isOpen = false

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, -26, 1, 0)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text
	Btn.Font = Theme.Font
	Btn.TextSize = Theme.TextSize
	Btn.TextColor3 = Theme.Text
	Btn.TextXAlignment = Enum.TextXAlignment.Left
	Btn.Parent = Holder
	stroke(Btn, Theme.Border)

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 6)
	Pad.Parent = Btn

	local Swatch = Instance.new("TextButton")
	Swatch.Size = UDim2.new(0, 22, 1, 0)
	Swatch.Position = UDim2.new(1, -22, 0, 0)
	Swatch.BackgroundColor3 = color
	Swatch.BackgroundTransparency = 1 - alpha
	Swatch.BorderSizePixel = 0
	Swatch.Text = ""
	Swatch.AutoButtonColor = false
	Swatch.Parent = Holder
	stroke(Swatch, Theme.Border)

	local function closePanel()
		isOpen = false
	end

	local function toHex(c)
		return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end

	local hexBoxRef = nil
	local alphaLblRef = nil

	local function setColor(c, a, fromUser)
		color = c
		alpha = math.clamp(a or alpha, 0, 1)
		Swatch.BackgroundColor3 = color
		Swatch.BackgroundTransparency = 1 - alpha
		if hexBoxRef then hexBoxRef.Text = toHex(color) end
		if alphaLblRef then alphaLblRef.Text = "A: " .. math.floor(alpha * 255 + 0.5) end
		safeCall(callback, color, alpha)
		if fromUser then pushAutoSave() end
	end

	local function openPanel()
		isOpen = true
		openOverlayPanel(Holder, 122, function(panel)
			local Pad2 = Instance.new("UIPadding")
			Pad2.PaddingLeft = UDim.new(0, 6)
			Pad2.PaddingRight = UDim.new(0, 6)
			Pad2.PaddingTop = UDim.new(0, 6)
			Pad2.PaddingBottom = UDim.new(0, 6)
			Pad2.Parent = panel

			local Layout = Instance.new("UIListLayout")
			Layout.Padding = UDim.new(0, 4)
			Layout.Parent = panel

			local r, g, b = math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)

			local function makeChannelSlider(label, initial, onChange, isAlpha)
				local Row = Instance.new("Frame")
				Row.Size = UDim2.new(1, 0, 0, 18)
				Row.BackgroundTransparency = 1
				Row.Parent = panel

				local CTrack = Instance.new("Frame")
				CTrack.Size = UDim2.new(1, 0, 1, 0)
				CTrack.BackgroundColor3 = Theme.Element
				CTrack.BorderSizePixel = 0
				CTrack.Active = true
				CTrack.Parent = Row
				stroke(CTrack, Theme.Border)

				local CFill = Instance.new("Frame")
				CFill.Size = UDim2.new(initial / 255, 0, 1, 0)
				CFill.BackgroundColor3 = Theme.Accent
				CFill.BackgroundTransparency = 0.5
				CFill.BorderSizePixel = 0
				CFill.Parent = CTrack

				local CLbl = Instance.new("TextLabel")
				CLbl.Size = UDim2.new(1, -6, 1, 0)
				CLbl.Position = UDim2.new(0, 3, 0, 0)
				CLbl.BackgroundTransparency = 1
				CLbl.Font = Theme.Font
				CLbl.TextSize = 11
				CLbl.TextColor3 = Theme.Text
				CLbl.TextXAlignment = Enum.TextXAlignment.Left
				CLbl.Text = label .. ": " .. initial
				CLbl.ZIndex = 2
				CLbl.Parent = CTrack

				if isAlpha then alphaLblRef = CLbl end

				local function setFromX(x)
					local rel = math.clamp((x - CTrack.AbsolutePosition.X) / CTrack.AbsoluteSize.X, 0, 1)
					local v = math.floor(rel * 255)
					CFill.Size = UDim2.new(rel, 0, 1, 0)
					CLbl.Text = label .. ": " .. v
					onChange(v)
				end

				CTrack.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						setFromX(input.Position.X)
						ActiveSlider = { Update = setFromX, Release = pushAutoSave }
					end
				end)
			end

			makeChannelSlider("R", r, function(v)
				r = v
				setColor(Color3.fromRGB(r, g, b), alpha, true)
			end)
			makeChannelSlider("G", g, function(v)
				g = v
				setColor(Color3.fromRGB(r, g, b), alpha, true)
			end)
			makeChannelSlider("B", b, function(v)
				b = v
				setColor(Color3.fromRGB(r, g, b), alpha, true)
			end)
			makeChannelSlider("A", math.floor(alpha * 255), function(v)
				setColor(color, v / 255, true)
			end, true)

			local HexRow = Instance.new("Frame")
			HexRow.Size = UDim2.new(1, 0, 0, 18)
			HexRow.BackgroundTransparency = 1
			HexRow.Parent = panel

			local HexBox = Instance.new("TextBox")
			HexBox.Size = UDim2.new(1, 0, 1, 0)
			HexBox.BackgroundColor3 = Theme.Element
			HexBox.BorderSizePixel = 0
			HexBox.Text = toHex(color)
			HexBox.Font = Theme.Font
			HexBox.TextSize = 11
			HexBox.TextColor3 = Theme.Text
			HexBox.ClearTextOnFocus = false
			HexBox.Parent = HexRow
			stroke(HexBox, Theme.Border)
			hexBoxRef = HexBox

			HexBox.FocusLost:Connect(function()
				local hex = HexBox.Text:gsub("#", "")
				if #hex == 6 and hex:match("^%x+$") then
					local nr = tonumber(hex:sub(1, 2), 16)
					local ng = tonumber(hex:sub(3, 4), 16)
					local nb = tonumber(hex:sub(5, 6), 16)
					r, g, b = nr, ng, nb
					setColor(Color3.fromRGB(nr, ng, nb), alpha, true)
				else
					HexBox.Text = toHex(color)
				end
			end)
		end, closePanel, 180)
	end

	Btn.MouseButton1Click:Connect(function()
		if isOpen then closeActivePopup() else openPanel() end
	end)
	Swatch.MouseButton1Click:Connect(function()
		if isOpen then closeActivePopup() else openPanel() end
	end)

	attachContextMenu(Btn, function()
		return {{Text = "Reset to Default", Callback = function() setColor(defaultVal, defaultAlphaVal, true) end}}
	end)

	registerFlag(flag, {
		Get = function() return {Color = color, Alpha = alpha} end,
		Set = function(v)
			if typeof(v) == "table" then
				setColor(v.Color, v.Alpha, false)
			else
				setColor(v, alpha, false)
			end
		end
	})
	if callback then safeCall(callback, color, alpha) end

	local api = attachDependencyAPI(Holder, {
		Set = function(v, a) setColor(v, a, false) end,
		Get = function() return color, alpha end
	}, flag)
	return api
end

local function buildColorpickerCompact(container, text, default, callback, flag, defaultAlpha)
	local color = default or Color3.fromRGB(255, 255, 255)
	local alpha = (defaultAlpha ~= nil) and defaultAlpha or 1
	local defaultVal, defaultAlphaVal = color, alpha

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0, 60, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local Swatch = Instance.new("TextButton")
	Swatch.Size = UDim2.new(0, 18, 0, 18)
	Swatch.Position = UDim2.new(0, 62, 0.5, -9)
	Swatch.BackgroundColor3 = color
	Swatch.BackgroundTransparency = 1 - alpha
	Swatch.BorderSizePixel = 0
	Swatch.Text = ""
	Swatch.AutoButtonColor = false
	Swatch.Parent = Holder
	stroke(Swatch, Theme.Border)

	local boxes = {}
	local function makeBox(idx, xOff, initVal)
		local Box = Instance.new("TextBox")
		Box.Size = UDim2.new(0, 30, 1, 0)
		Box.Position = UDim2.new(0, xOff, 0, 0)
		Box.BackgroundColor3 = Theme.Element
		Box.BorderSizePixel = 0
		Box.Text = tostring(initVal)
		Box.Font = Theme.Font
		Box.TextSize = 11
		Box.TextColor3 = Theme.Text
		Box.ClearTextOnFocus = false
		Box.TextXAlignment = Enum.TextXAlignment.Center
		Box.Parent = Holder
		stroke(Box, Theme.Border)
		boxes[idx] = Box
		return Box
	end

	local r, g, b = math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)
	makeBox(1, 86, r)
	makeBox(2, 118, g)
	makeBox(3, 150, b)
	makeBox(4, 182, math.floor(alpha * 255))

	local function refreshVisual()
		Swatch.BackgroundColor3 = color
		Swatch.BackgroundTransparency = 1 - alpha
		boxes[1].Text = tostring(math.floor(color.R * 255))
		boxes[2].Text = tostring(math.floor(color.G * 255))
		boxes[3].Text = tostring(math.floor(color.B * 255))
		boxes[4].Text = tostring(math.floor(alpha * 255))
	end

	local function setColor(c, a, fromUser)
		color = c
		alpha = math.clamp(a or alpha, 0, 1)
		refreshVisual()
		safeCall(callback, color, alpha)
		if fromUser then pushAutoSave() end
	end

	local function onBoxChanged(idx)
		boxes[idx].FocusLost:Connect(function()
			local num = tonumber(boxes[idx].Text)
			if not num then refreshVisual() return end
			num = math.clamp(math.floor(num), 0, 255)
			if idx == 4 then
				setColor(color, num / 255, true)
				return
			end
			local cr, cg, cb = math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)
			if idx == 1 then cr = num
			elseif idx == 2 then cg = num
			elseif idx == 3 then cb = num end
			setColor(Color3.fromRGB(cr, cg, cb), alpha, true)
		end)
	end
	for i = 1, 4 do onBoxChanged(i) end

	attachContextMenu(Holder, function()
		return {{Text = "Reset to Default", Callback = function() setColor(defaultVal, defaultAlphaVal, true) end}}
	end)

	registerFlag(flag, {
		Get = function() return {Color = color, Alpha = alpha} end,
		Set = function(v)
			if typeof(v) == "table" then setColor(v.Color, v.Alpha, false)
			else setColor(v, alpha, false) end
		end
	})
	if callback then safeCall(callback, color, alpha) end

	local api = attachDependencyAPI(Holder, {
		Set = function(v, a) setColor(v, a, false) end,
		Get = function() return color, alpha end
	}, flag)
	return api
end

local function buildKeybind(container, text, default, callback, flag)
	local key = default
	local defaultVal = key
	local listening = false

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -70, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(0, 64, 1, 0)
	Btn.Position = UDim2.new(1, -64, 0, 0)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Font = Theme.Font
	Btn.TextSize = Theme.TextSize
	Btn.TextColor3 = Theme.Text
	Btn.Text = key and key.Name or "None"
	Btn.Parent = Holder
	stroke(Btn, Theme.Border)

	local conn = nil

	local function setKey(k, fromUser)
		key = k
		Btn.Text = key and key.Name or "None"
		safeCall(callback, key)
		if fromUser then pushAutoSave() end
	end

	Library:RegisterKeybind("Keybind: " .. text, function() return key end, function(k) setKey(k, true) end)

	Btn.MouseButton1Click:Connect(function()
		if listening then return end
		listening = true
		Btn.Text = "..."
		Btn.BackgroundColor3 = Theme.ElementActive

		conn = UIS.InputBegan:Connect(function(input, gpe)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				setKey(input.KeyCode, true)
				listening = false
				Btn.BackgroundColor3 = Theme.Element
				if conn then conn:Disconnect(); conn = nil end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				listening = false
				Btn.Text = key and key.Name or "None"
				Btn.BackgroundColor3 = Theme.Element
				if conn then conn:Disconnect(); conn = nil end
			end
		end)
	end)

	attachContextMenu(Btn, function()
		return {
			{Text = "Reset to Default", Callback = function() setKey(defaultVal, true) end},
			{Text = "Unbind", Callback = function() setKey(nil, true) end},
		}
	end)

	registerFlag(flag, {
		Get = function() return key end,
		Set = function(v) setKey(v, false) end
	})

	local api = attachDependencyAPI(Holder, {
		Set = function(v) setKey(v, false) end,
		Get = function() return key end
	}, flag)
	return api
end

local function buildSearchableOptionList(panel, options, isSelectedFn, onPickFn, closeOnPick)
	local ListLayout = Instance.new("UIListLayout")
	ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ListLayout.Parent = panel

	local hasSearch = #options > 4

	local ScrollFrame = Instance.new("ScrollingFrame")
	ScrollFrame.Size = UDim2.new(1, 0, 1, hasSearch and -24 or 0)
	ScrollFrame.Position = UDim2.new(0, 0, 0, hasSearch and 24 or 0)
	ScrollFrame.BackgroundTransparency = 1
	ScrollFrame.BorderSizePixel = 0
	ScrollFrame.ScrollBarThickness = 4
	ScrollFrame.ScrollBarImageColor3 = Theme.Border
	ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	ScrollFrame.Parent = panel

	local ScrollLayout = Instance.new("UIListLayout")
	ScrollLayout.Parent = ScrollFrame

	local optionBtns = {}

	if hasSearch then
		local SearchBox = Instance.new("TextBox")
		SearchBox.Size = UDim2.new(1, -8, 0, 18)
		SearchBox.Position = UDim2.new(0, 4, 0, 3)
		SearchBox.BackgroundColor3 = Theme.Element
		SearchBox.BorderSizePixel = 0
		SearchBox.PlaceholderText = "Filtrele..."
		SearchBox.Text = ""
		SearchBox.Font = Theme.Font
		SearchBox.TextSize = 11
		SearchBox.TextColor3 = Theme.Text
		SearchBox.PlaceholderColor3 = Theme.SubText
		SearchBox.ClearTextOnFocus = false
		SearchBox.Parent = panel
		stroke(SearchBox, Theme.Border)

		SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local query = SearchBox.Text:lower()
			for opt, optBtn in pairs(optionBtns) do
				optBtn.Visible = (query == "" or tostring(opt):lower():find(query, 1, true) ~= nil)
			end
		end)
	end

	for _, opt in ipairs(options) do
		local OptBtn = Instance.new("TextButton")
		OptBtn.Size = UDim2.new(1, 0, 0, 20)
		OptBtn.BackgroundColor3 = isSelectedFn(opt) and Theme.Accent or Theme.Element
		OptBtn.BorderSizePixel = 0
		OptBtn.Text = tostring(opt)
		OptBtn.Font = Theme.Font
		OptBtn.TextSize = Theme.TextSize
		OptBtn.TextColor3 = Theme.Text
		OptBtn.TextXAlignment = Enum.TextXAlignment.Left
		OptBtn.Parent = ScrollFrame

		local OPad = Instance.new("UIPadding")
		OPad.PaddingLeft = UDim.new(0, 6)
		OPad.Parent = OptBtn

		optionBtns[opt] = OptBtn

		OptBtn.MouseEnter:Connect(function()
			if not isSelectedFn(opt) then OptBtn.BackgroundColor3 = Theme.ElementHover end
		end)
		OptBtn.MouseLeave:Connect(function()
			OptBtn.BackgroundColor3 = isSelectedFn(opt) and Theme.Accent or Theme.Element
		end)

		OptBtn.MouseButton1Click:Connect(function()
			onPickFn(opt)
			OptBtn.BackgroundColor3 = isSelectedFn(opt) and Theme.Accent or Theme.Element
			if closeOnPick then closeActivePopup() end
		end)
	end
end

local function buildMultiDropdown(container, text, options, defaults, callback, flag)
	local selected = {}
	for _, v in ipairs(defaults or {}) do selected[v] = true end
	local defaultSelected = {}
	for k, v in pairs(selected) do defaultSelected[k] = v end
	local currentOptions = options
	local isOpen = false

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 1, 0)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text .. ": ..."
	Btn.Font = Theme.Font
	Btn.TextSize = Theme.TextSize
	Btn.TextColor3 = Theme.Text
	Btn.TextXAlignment = Enum.TextXAlignment.Left
	Btn.Parent = Holder
	stroke(Btn, Theme.Border)

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 6)
	Pad.Parent = Btn

	local function refreshLabel()
		local names = {}
		for _, opt in ipairs(currentOptions) do
			if selected[opt] then table.insert(names, tostring(opt)) end
		end
		Btn.Text = text .. ": " .. (#names > 0 and table.concat(names, ", ") or "None")
	end
	refreshLabel()

	local function closePanel()
		isOpen = false
	end

	local function openPanel()
		isOpen = true
		local hasSearch = #currentOptions > 4
		local panelHeight = math.min(#currentOptions * 20 + (hasSearch and 24 or 0), 160)

		openOverlayPanel(Btn, panelHeight, function(panel)
			buildSearchableOptionList(panel, currentOptions, function(opt) return selected[opt] end, function(opt)
				selected[opt] = not selected[opt] or nil
				refreshLabel()
				safeCall(callback, selected)
				pushAutoSave()
			end, false)
		end, closePanel)
	end

	Btn.MouseButton1Click:Connect(function()
		if isOpen then
			closeActivePopup()
		else
			openPanel()
		end
	end)

	attachContextMenu(Btn, function()
		return {{Text = "Reset to Default", Callback = function()
			selected = {}
			for k, v in pairs(defaultSelected) do selected[k] = v end
			refreshLabel()
			safeCall(callback, selected)
			pushAutoSave()
		end}}
	end)

	registerFlag(flag, {
		Get = function() return selected end,
		Set = function(v)
			selected = v
			refreshLabel()
		end
	})
	if callback then safeCall(callback, selected) end

	local api = attachDependencyAPI(Holder, {
		Set = function(v) selected = v; refreshLabel() end,
		Refresh = function(newOptions)
			currentOptions = newOptions
			refreshLabel()
		end,
	}, flag)
	return api
end

local function buildDropdown(container, text, options, default, callback, flag)
	local selected = default or options[1]
	local defaultVal = selected
	local currentOptions = options
	local isOpen = false

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 1, 0)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text .. ": " .. tostring(selected)
	Btn.Font = Theme.Font
	Btn.TextSize = Theme.TextSize
	Btn.TextColor3 = Theme.Text
	Btn.TextXAlignment = Enum.TextXAlignment.Left
	Btn.Parent = Holder
	stroke(Btn, Theme.Border)

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 6)
	Pad.Parent = Btn

	local function selectOption(opt, fromUser)
		selected = opt
		Btn.Text = text .. ": " .. tostring(selected)
		safeCall(callback, opt)
		if fromUser then pushAutoSave() end
	end

	local function closePanel()
		isOpen = false
	end

	local function openPanel()
		isOpen = true
		local hasSearch = #currentOptions > 4
		local panelHeight = math.min(#currentOptions * 20 + (hasSearch and 24 or 0), 160)

		openOverlayPanel(Btn, panelHeight, function(panel)
			buildSearchableOptionList(panel, currentOptions, function(opt) return opt == selected end, function(opt)
				selectOption(opt, true)
			end, true)
		end, closePanel)
	end

	Btn.MouseButton1Click:Connect(function()
		if isOpen then
			closeActivePopup()
		else
			openPanel()
		end
	end)

	attachContextMenu(Btn, function()
		return {{Text = "Reset to Default", Callback = function() selectOption(defaultVal, true) end}}
	end)

	registerFlag(flag, {Get = function() return selected end, Set = function(v) selectOption(v, false) end})
	if callback then safeCall(callback, selected) end

	local api = attachDependencyAPI(Holder, {
		Set = function(v) selectOption(v, false) end,
		Get = function() return selected end,
		Refresh = function(newOptions)
			currentOptions = newOptions
			selectOption(newOptions[1], false)
		end
	}, flag)
	return api
end

local function buildSelectable(container, text, defaultSelected, callback)
	local state = defaultSelected or false

	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 0, 20)
	Btn.BackgroundColor3 = state and Theme.Accent or Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text
	Btn.Font = Theme.Font
	Btn.TextSize = Theme.TextSize
	Btn.TextColor3 = Theme.Text
	Btn.TextXAlignment = Enum.TextXAlignment.Left
	Btn.Parent = container

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 6)
	Pad.Parent = Btn

	Btn.MouseEnter:Connect(function()
		if not state then Btn.BackgroundColor3 = Theme.ElementHover end
	end)
	Btn.MouseLeave:Connect(function()
		Btn.BackgroundColor3 = state and Theme.Accent or Theme.Element
	end)

	Btn.MouseButton1Click:Connect(function()
		state = not state
		Btn.BackgroundColor3 = state and Theme.Accent or Theme.Element
		safeCall(callback, state)
	end)

	local api = attachDependencyAPI(Btn, {
		Set = function(v)
			state = v
			Btn.BackgroundColor3 = state and Theme.Accent or Theme.Element
		end,
		Get = function() return state end
	})
	return api
end

local RadioGroups = {}

local function buildRadioButton(container, text, active, callback, group)
	local state = active or false

	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 20)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.Parent = container

	local Outer = Instance.new("Frame")
	Outer.Size = UDim2.new(0, 14, 0, 14)
	Outer.Position = UDim2.new(0, 0, 0.5, -7)
	Outer.BackgroundColor3 = Theme.Element
	Outer.BorderSizePixel = 0
	Outer.Active = false
	Outer.Parent = Holder
	stroke(Outer, Theme.Border)

	local Dot = Instance.new("Frame")
	Dot.Size = UDim2.new(0, 6, 0, 6)
	Dot.Position = UDim2.new(0.5, -3, 0.5, -3)
	Dot.BackgroundColor3 = Theme.Accent
	Dot.BorderSizePixel = 0
	Dot.Visible = state
	Dot.Active = false
	Dot.Parent = Outer

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -20, 1, 0)
	Label.Position = UDim2.new(0, 20, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Active = false
	Label.Parent = Holder

	local function setState(v)
		state = v
		Dot.Visible = state
		safeCall(callback, state)
	end

	local api = { Set = function(v) setState(v) end, Get = function() return state end }

	if group then
		RadioGroups[group] = RadioGroups[group] or {}
		table.insert(RadioGroups[group], api)
	end

	Holder.MouseButton1Click:Connect(function()
		if state then return end
		if group and RadioGroups[group] then
			for _, other in ipairs(RadioGroups[group]) do
				if other ~= api then other.Set(false) end
			end
		end
		setState(true)
	end)

	return attachDependencyAPI(Holder, api)
end

local function buildSplitterFrames(container, ratio, height)
	ratio = math.clamp(ratio or 0.5, 0.1, 0.9)
	height = height or 160

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, height)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local LeftPane = Instance.new("Frame")
	LeftPane.Size = UDim2.new(ratio, -3, 1, 0)
	LeftPane.Position = UDim2.new(0, 0, 0, 0)
	LeftPane.BackgroundTransparency = 1
	LeftPane.Parent = Holder

	local Divider = Instance.new("Frame")
	Divider.Size = UDim2.new(0, 4, 1, 0)
	Divider.Position = UDim2.new(ratio, -2, 0, 0)
	Divider.BackgroundColor3 = Theme.SeparatorLine
	Divider.BorderSizePixel = 0
	Divider.Active = true
	Divider.Parent = Holder

	local RightPane = Instance.new("Frame")
	RightPane.Size = UDim2.new(1 - ratio, -3, 1, 0)
	RightPane.Position = UDim2.new(ratio, 4, 0, 0)
	RightPane.BackgroundTransparency = 1
	RightPane.Parent = Holder

	local function layoutPane(pane)
		local Pad = Instance.new("UIPadding")
		Pad.PaddingRight = UDim.new(0, 2)
		Pad.Parent = pane
		local Layout = Instance.new("UIListLayout")
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.Padding = UDim.new(0, Theme.ItemSpacing or 4)
		Layout.Parent = pane
	end
	layoutPane(LeftPane)
	layoutPane(RightPane)

	local dragging = false
	Divider.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)

	track(UIS.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
		end
	end))

	track(UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local relX = math.clamp((input.Position.X - Holder.AbsolutePosition.X) / Holder.AbsoluteSize.X, 0.1, 0.9)
			LeftPane.Size = UDim2.new(relX, -3, 1, 0)
			Divider.Position = UDim2.new(relX, -2, 0, 0)
			RightPane.Size = UDim2.new(1 - relX, -3, 1, 0)
			RightPane.Position = UDim2.new(relX, 4, 0, 0)
		end
	end))

	Divider.MouseEnter:Connect(function() Divider.BackgroundColor3 = Theme.Grabber end)
	Divider.MouseLeave:Connect(function() Divider.BackgroundColor3 = Theme.SeparatorLine end)

	return LeftPane, RightPane
end

-- ============================================================
-- Section / Tree / Row / Group Builders
-- ============================================================

local function buildSectionHeader(container, title, opts)
	opts = opts or {}
	local collapsed = opts.Collapsed or false

	local SectionFrame = Instance.new("Frame")
	SectionFrame.Size = UDim2.new(1, 0, 0, 0)
	SectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	SectionFrame.BackgroundTransparency = 1
	SectionFrame.Parent = container

	local SectionLayout = Instance.new("UIListLayout")
	SectionLayout.FillDirection = Enum.FillDirection.Vertical
	SectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	SectionLayout.Padding = UDim.new(0, 2)
	SectionLayout.Parent = SectionFrame

	local Header = Instance.new("TextButton")
	Header.LayoutOrder = 1
	Header.Size = UDim2.new(1, 0, 0, 20)
	Header.BackgroundColor3 = Theme.SectionHeader
	Header.BorderSizePixel = 0
	Header.Text = ""
	Header.AutoButtonColor = false
	Header.Parent = SectionFrame
	stroke(Header, Theme.Border)

	local HeaderLayout = Instance.new("UIListLayout")
	HeaderLayout.FillDirection = Enum.FillDirection.Horizontal
	HeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	HeaderLayout.Padding = UDim.new(0, 4)
	HeaderLayout.Parent = Header

	local Arrow = Instance.new("TextLabel")
	Arrow.Size = UDim2.new(0, 14, 1, 0)
	Arrow.BackgroundTransparency = 1
	Arrow.Font = Theme.Font
	Arrow.TextSize = 11
	Arrow.TextColor3 = Theme.Text
	Arrow.Text = collapsed and "▶" or "▼"
	Arrow.Active = false
	Arrow.Parent = Header

	local TitleLbl = Instance.new("TextLabel")
	TitleLbl.Size = UDim2.new(1, -20, 1, 0)
	TitleLbl.BackgroundTransparency = 1
	TitleLbl.Font = Theme.Font
	TitleLbl.TextSize = Theme.TextSize
	TitleLbl.TextColor3 = Theme.Text
	TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	TitleLbl.Text = title
	TitleLbl.Active = false
	TitleLbl.Parent = Header

	local Content = Instance.new("Frame")
	Content.LayoutOrder = 2
	Content.Size = UDim2.new(1, 0, 0, 0)
	Content.AutomaticSize = Enum.AutomaticSize.Y
	Content.BackgroundTransparency = 1
	Content.Visible = not collapsed
	Content.Parent = SectionFrame

	local ContentPad = Instance.new("UIPadding")
	ContentPad.PaddingLeft = UDim.new(0, Theme.IndentSpacing or 12)
	ContentPad.PaddingTop = UDim.new(0, 4)
	ContentPad.PaddingBottom = UDim.new(0, 4)
	ContentPad.Parent = Content

	local ContentLayout = Instance.new("UIListLayout")
	ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ContentLayout.Padding = UDim.new(0, Theme.ItemSpacing or 4)
	ContentLayout.Parent = Content

	Header.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		Content.Visible = not collapsed
		Arrow.Text = collapsed and "▶" or "▼"
	end)

	return Content
end

local function buildTree(container, title)
	local collapsed = true

	local TreeFrame = Instance.new("Frame")
	TreeFrame.Size = UDim2.new(1, 0, 0, 0)
	TreeFrame.AutomaticSize = Enum.AutomaticSize.Y
	TreeFrame.BackgroundTransparency = 1
	TreeFrame.Parent = container

	local TreeLayout = Instance.new("UIListLayout")
	TreeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	TreeLayout.Padding = UDim.new(0, 2)
	TreeLayout.Parent = TreeFrame

	local Header = Instance.new("TextButton")
	Header.LayoutOrder = 1
	Header.Size = UDim2.new(1, 0, 0, 18)
	Header.BackgroundTransparency = 1
	Header.Text = ""
	Header.Parent = TreeFrame

	local HeaderLayout = Instance.new("UIListLayout")
	HeaderLayout.FillDirection = Enum.FillDirection.Horizontal
	HeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	HeaderLayout.Padding = UDim.new(0, 4)
	HeaderLayout.Parent = Header

	local Arrow = Instance.new("TextLabel")
	Arrow.Size = UDim2.new(0, 12, 1, 0)
	Arrow.BackgroundTransparency = 1
	Arrow.Font = Theme.Font
	Arrow.TextSize = 10
	Arrow.TextColor3 = Theme.SubText
	Arrow.Text = "▶"
	Arrow.Active = false
	Arrow.Parent = Header

	local TitleLbl = Instance.new("TextLabel")
	TitleLbl.Size = UDim2.new(1, -16, 1, 0)
	TitleLbl.BackgroundTransparency = 1
	TitleLbl.Font = Theme.Font
	TitleLbl.TextSize = Theme.TextSize
	TitleLbl.TextColor3 = Theme.Text
	TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	TitleLbl.Text = title
	TitleLbl.Active = false
	TitleLbl.Parent = Header

	local Content = Instance.new("Frame")
	Content.LayoutOrder = 2
	Content.Size = UDim2.new(1, 0, 0, 0)
	Content.AutomaticSize = Enum.AutomaticSize.Y
	Content.BackgroundTransparency = 1
	Content.Visible = false
	Content.Parent = TreeFrame

	local ContentPad = Instance.new("UIPadding")
	ContentPad.PaddingLeft = UDim.new(0, Theme.IndentSpacing or 14)
	ContentPad.Parent = Content

	local ContentLayout = Instance.new("UIListLayout")
	ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ContentLayout.Padding = UDim.new(0, Theme.ItemSpacing or 4)
	ContentLayout.Parent = Content

	Header.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		Content.Visible = not collapsed
		Arrow.Text = collapsed and "▶" or "▼"
	end)

	return Content
end

local function buildRow(container, height, gap)
	local RowFrame = Instance.new("Frame")
	RowFrame.Size = UDim2.new(1, 0, 0, height or 22)
	RowFrame.BackgroundTransparency = 1
	RowFrame.Parent = container

	local RowLayout = Instance.new("UIListLayout")
	RowLayout.FillDirection = Enum.FillDirection.Horizontal
	RowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	RowLayout.Padding = UDim.new(0, gap or 6)
	RowLayout.Parent = RowFrame

	local Row = {}

	function Row:AddText(text, widthScale)
		local Label, api = buildLabel(RowFrame, text)
		flexify(Label, widthScale)
		return api
	end

	function Row:AddCheckbox(text, default, callback, flag, widthScale, bindEnabled)
		local Holder, api = buildCheckbox(RowFrame, text, default, callback, flag, bindEnabled)
		flexify(Holder, widthScale)
		return api
	end

	function Row:AddButton(text, callback, widthScale)
		local Btn, api = buildButton(RowFrame, text, callback)
		flexify(Btn, widthScale)
		return api
	end

	function Row:AddSlider(text, min, max, default, callback, flag, widthScale, decimals, scrollable)
		local api = buildSlider(RowFrame, text, min, max, default, callback, flag, decimals, scrollable)
		flexify(api.Instance, widthScale)
		return api
	end

	function Row:AddKnob(text, values, defaultIndex, callback, flag, size, widthScale)
		local holder, api = buildKnob(RowFrame, text, values, defaultIndex, callback, flag, size)
		flexify(holder, widthScale)
		return api
	end

	return Row
end

-- Scope Construction
local function buildScope(container)
	local Scope = {}

	function Scope:Clear()
		for _, child in ipairs(container:GetChildren()) do
			if not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end

	function Scope:AddLabel(text)
		local _, api = buildLabel(container, text)
		return api
	end
	function Scope:AddMarkdown(text)
		local _, api = buildMarkdown(container, text)
		return api
	end
	function Scope:AddSeparator(text) return buildSeparator(container, text) end
	function Scope:AddButton(text, callback)
		local _, api = buildButton(container, text, callback)
		return api
	end
	function Scope:AddCheckbox(text, default, callback, flag, bindEnabled)
		local _, api = buildCheckbox(container, text, default, callback, flag, bindEnabled)
		return api
	end
	function Scope:AddToggle(text, default, callback, flag, bindEnabled)
		local _, api = buildCheckbox(container, text, default, callback, flag, bindEnabled)
		return api
	end
	function Scope:AddSlider(text, min, max, default, callback, flag, decimals, scrollable)
		return buildSlider(container, text, min, max, default, callback, flag, decimals, scrollable)
	end
	function Scope:AddRangeSlider(text, min, max, defaultLow, defaultHigh, callback, flag)
		return buildRangeSlider(container, text, min, max, defaultLow, defaultHigh, callback, flag)
	end
	function Scope:AddKnob(text, values, defaultIndex, callback, flag, size)
		local _, api = buildKnob(container, text, values, defaultIndex, callback, flag, size)
		return api
	end
	function Scope:AddTextbox(text, default, placeholder, callback, flag)
		return buildTextbox(container, text, default, placeholder, callback, flag)
	end
	function Scope:AddNumberInput(text, min, max, default, step, callback, flag)
		return buildNumberInput(container, text, min, max, default, step, callback, flag)
	end
	function Scope:AddKeybind(text, default, callback, flag)
		return buildKeybind(container, text, default, callback, flag)
	end
	function Scope:AddProgressBar(text, min, max, default, format)
		return buildProgressBar(container, text, min, max, default, format)
	end
	function Scope:AddColorpicker(text, default, callback, flag, defaultAlpha)
		return buildColorpicker(container, text, default, callback, flag, defaultAlpha)
	end
	function Scope:AddColorpickerCompact(text, default, callback, flag, defaultAlpha)
		return buildColorpickerCompact(container, text, default, callback, flag, defaultAlpha)
	end
	function Scope:AddMultiDropdown(text, options, defaults, callback, flag)
		return buildMultiDropdown(container, text, options, defaults, callback, flag)
	end
	function Scope:AddDropdown(text, options, default, callback, flag)
		return buildDropdown(container, text, options, default, callback, flag)
	end
	function Scope:AddSelectable(text, defaultSelected, callback)
		return buildSelectable(container, text, defaultSelected, callback)
	end
	function Scope:AddRadioButton(text, active, callback, group)
		return buildRadioButton(container, text, active, callback, group)
	end
	function Scope:AddRow(height, gap)
		return buildRow(container, height, gap)
	end
	function Scope:AddSplitter(ratio, height)
		local left, right = buildSplitterFrames(container, ratio, height)
		return buildScope(left), buildScope(right)
	end
	function Scope:PushID(id)
		Library:PushID(id)
	end
	function Scope:PopID()
		Library:PopID()
	end

	-- Sub-Tabs Özelliği
	function Scope:AddSubTabs(tabNames)
		local SubTabsHolder = Instance.new("Frame")
		SubTabsHolder.Size = UDim2.new(1, 0, 0, 0)
		SubTabsHolder.AutomaticSize = Enum.AutomaticSize.Y
		SubTabsHolder.BackgroundTransparency = 1
		SubTabsHolder.Parent = container

		local SubTabsLayout = Instance.new("UIListLayout")
		SubTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		SubTabsLayout.Padding = UDim.new(0, 4)
		SubTabsLayout.Parent = SubTabsHolder

		local HeaderBar = Instance.new("Frame")
		HeaderBar.Size = UDim2.new(1, 0, 0, 20)
		HeaderBar.BackgroundTransparency = 1
		HeaderBar.Parent = SubTabsHolder

		local HeaderLayout = Instance.new("UIListLayout")
		HeaderLayout.FillDirection = Enum.FillDirection.Horizontal
		HeaderLayout.Padding = UDim.new(0, 4)
		HeaderLayout.Parent = HeaderBar

		local PagesFrame = Instance.new("Frame")
		PagesFrame.Size = UDim2.new(1, 0, 0, 0)
		PagesFrame.AutomaticSize = Enum.AutomaticSize.Y
		PagesFrame.BackgroundTransparency = 1
		PagesFrame.Parent = SubTabsHolder

		local subScopes = {}
		local tabBtns = {}
		local subPages = {}

		local function selectSubTab(name)
			for tabName, page in pairs(subPages) do
				page.Visible = (tabName == name)
				if tabBtns[tabName] then
					tabBtns[tabName].BackgroundColor3 = (tabName == name) and Theme.Accent or Theme.Element
					tabBtns[tabName].TextColor3 = (tabName == name) and Theme.Text or Theme.SubText
				end
			end
		end

		for i, name in ipairs(tabNames) do
			local Btn = Instance.new("TextButton")
			Btn.Size = UDim2.new(0, 60, 1, 0)
			Btn.BackgroundColor3 = Theme.Element
			Btn.BorderSizePixel = 0
			Btn.Text = name
			Btn.Font = Theme.Font
			Btn.TextSize = 11
			Btn.TextColor3 = Theme.SubText
			Btn.Parent = HeaderBar
			stroke(Btn, Theme.Border)
			tabBtns[name] = Btn

			local Page = Instance.new("Frame")
			Page.Size = UDim2.new(1, 0, 0, 0)
			Page.AutomaticSize = Enum.AutomaticSize.Y
			Page.BackgroundTransparency = 1
			Page.Visible = (i == 1)
			Page.Parent = PagesFrame

			local PageLayout = Instance.new("UIListLayout")
			PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
			PageLayout.Padding = UDim.new(0, Theme.ItemSpacing or 4)
			PageLayout.Parent = Page

			subPages[name] = Page
			subScopes[name] = buildScope(Page)

			Btn.MouseButton1Click:Connect(function()
				selectSubTab(name)
			end)
		end

		selectSubTab(tabNames[1])
		return subScopes
	end

	function Scope:AddSubTab(name)
		local subTabs = Scope:AddSubTabs({name})
		return subTabs[name]
	end

	function Scope:AddSection(title, opts)
		local Content = buildSectionHeader(container, title, opts)
		return buildScope(Content)
	end
	function Scope:AddTree(title)
		local Content = buildTree(container, title)
		return buildScope(Content)
	end
	function Scope:AddGroup()
		local GroupFrame = Instance.new("Frame")
		GroupFrame.Size = UDim2.new(1, 0, 0, 0)
		GroupFrame.AutomaticSize = Enum.AutomaticSize.Y
		GroupFrame.BackgroundTransparency = 1
		GroupFrame.Parent = container

		local GroupLayout = Instance.new("UIListLayout")
		GroupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		GroupLayout.Padding = UDim.new(0, Theme.ItemSpacing or 4)
		GroupLayout.Parent = GroupFrame

		return buildScope(GroupFrame)
	end
	function Scope:AddTooltip(inst, text)
		bindTooltip(inst, text)
	end

	function Scope:AddTabSearchBox(placeholder)
		local BoxFrame = Instance.new("Frame")
		BoxFrame.Size = UDim2.new(1, 0, 0, 22)
		BoxFrame.BackgroundTransparency = 1
		BoxFrame.LayoutOrder = -9999
		BoxFrame.Parent = container

		local Box = Instance.new("TextBox")
		Box.Size = UDim2.new(1, 0, 1, 0)
		Box.BackgroundColor3 = Theme.Element
		Box.BorderSizePixel = 0
		Box.PlaceholderText = placeholder or "Tab içinde ara..."
		Box.Text = ""
		Box.Font = Theme.Font
		Box.TextSize = Theme.TextSize
		Box.TextColor3 = Theme.Text
		Box.PlaceholderColor3 = Theme.SubText
		Box.ClearTextOnFocus = false
		Box.Parent = BoxFrame
		stroke(Box, Theme.Border)

		local Pad = Instance.new("UIPadding")
		Pad.PaddingLeft = UDim.new(0, 6)
		Pad.Parent = Box

		Box:GetPropertyChangedSignal("Text"):Connect(function()
			local query = Box.Text:lower()
			for _, child in ipairs(container:GetChildren()) do
				if child ~= BoxFrame and not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
					if query == "" then
						child.Visible = true
					else
						local match = false
						for _, desc in ipairs(child:GetDescendants()) do
							if (desc:IsA("TextLabel") or desc:IsA("TextBox") or desc:IsA("TextButton")) and desc.Text ~= "" then
								if desc.Text:lower():find(query, 1, true) then
									match = true
									break
								end
							end
						end
						child.Visible = match
					end
				end
			end
		end)

		return BoxFrame
	end

	return Scope
end

-- ============================================================
-- Window & MenuBar API
-- ============================================================

function Library:CreateWindow(title, pos, size, opts)
	opts = opts or {}
	local noMenuBar = opts.NoMenuBar or false

	local screenGui = getScreenGui()
	local offset = #Library.Windows * 20

	local Window = {}
	Window.Categories = {}
	Window.Collapsed = false

	local Main = Instance.new("Frame")
	Main.Name = title
	Main.Size = size or UDim2.new(0, 320, 0, 380)
	Main.Position = pos or UDim2.new(0, 80 + offset, 0, 80 + offset)
	Main.BackgroundColor3 = Theme.Background
	Main.BackgroundTransparency = Theme.BackgroundTransparency
	Main.BorderSizePixel = 0
	Main.ZIndex = Library:GetNextZIndex()
	Main.Parent = screenGui
	stroke(Main, Theme.Border)
	Window.Main = Main

	Main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Library:BringToFront(Window)
		end
	end)

	local TitleBar = Instance.new("Frame")
	TitleBar.Name = "TitleBar"
	TitleBar.Size = UDim2.new(1, 0, 0, 22)
	TitleBar.BackgroundColor3 = Theme.Header
	TitleBar.BorderSizePixel = 0
	TitleBar.Parent = Main

	local CollapseBtn = Instance.new("TextButton")
	CollapseBtn.Size = UDim2.new(0, 18, 1, 0)
	CollapseBtn.Position = UDim2.new(0, 2, 0, 0)
	CollapseBtn.BackgroundTransparency = 1
	CollapseBtn.Text = "▼"
	CollapseBtn.Font = Theme.Font
	CollapseBtn.TextSize = 11
	CollapseBtn.TextColor3 = Theme.Text
	CollapseBtn.Parent = TitleBar

	local TitleLabel = Instance.new("TextLabel")
	TitleLabel.BackgroundTransparency = 1
	TitleLabel.Size = UDim2.new(1, -24, 1, 0)
	TitleLabel.Position = UDim2.new(0, 22, 0, 0)
	TitleLabel.Font = Theme.Font
	TitleLabel.TextSize = 12
	TitleLabel.TextColor3 = Theme.Text
	TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	TitleLabel.Text = title
	TitleLabel.Parent = TitleBar

	local MenuBar = Instance.new("Frame")
	MenuBar.Name = "MenuBar"
	MenuBar.Size = UDim2.new(1, 0, 0, 18)
	MenuBar.Position = UDim2.new(0, 0, 0, 22)
	MenuBar.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	MenuBar.BorderSizePixel = 0
	MenuBar.Parent = Main
	stroke(MenuBar, Theme.Border)

	local MenuBarLayout = Instance.new("UIListLayout")
	MenuBarLayout.FillDirection = Enum.FillDirection.Horizontal
	MenuBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	MenuBarLayout.Padding = UDim.new(0, 2)
	MenuBarLayout.Parent = MenuBar

	local MenuBarPad = Instance.new("UIPadding")
	MenuBarPad.PaddingLeft = UDim.new(0, 4)
	MenuBarPad.Parent = MenuBar

	local Body = Instance.new("Frame")
	Body.Name = "Body"
	Body.Size = UDim2.new(1, 0, 1, -40)
	Body.Position = UDim2.new(0, 0, 0, 40)
	Body.BackgroundTransparency = 1
	Body.ClipsDescendants = true
	Body.Parent = Main

	function Window:SetMenuBarVisible(visible)
		MenuBar.Visible = visible
		if visible then
			Body.Size = UDim2.new(1, 0, 1, -40)
			Body.Position = UDim2.new(0, 0, 0, 40)
		else
			Body.Size = UDim2.new(1, 0, 1, -22)
			Body.Position = UDim2.new(0, 0, 0, 22)
		end
	end

	Window:SetMenuBarVisible(not noMenuBar)

	local Tabs = Instance.new("Frame")
	Tabs.Name = "Tabs"
	Tabs.Size = UDim2.new(1, -8, 0, 22)
	Tabs.Position = UDim2.new(0, 4, 0, 4)
	Tabs.BackgroundTransparency = 1
	Tabs.Parent = Body

	local TabsLayout = Instance.new("UIListLayout")
	TabsLayout.FillDirection = Enum.FillDirection.Horizontal
	TabsLayout.Padding = UDim.new(0, 2)
	TabsLayout.Parent = Tabs

	local Pages = Instance.new("Frame")
	Pages.Name = "Pages"
	Pages.Size = UDim2.new(1, -8, 1, -32)
	Pages.Position = UDim2.new(0, 4, 0, 28)
	Pages.BackgroundTransparency = 1
	Pages.Parent = Body

	local fullSize = Main.Size
	CollapseBtn.MouseButton1Click:Connect(function()
		Window.Collapsed = not Window.Collapsed
		if Window.Collapsed then
			CollapseBtn.Text = "▶"
			TS:Create(Main, TweenInfo.new(0.15), {Size = UDim2.new(fullSize.X.Scale, fullSize.X.Offset, 0, 22)}):Play()
		else
			CollapseBtn.Text = "▼"
			TS:Create(Main, TweenInfo.new(0.15), {Size = fullSize}):Play()
		end
	end)

	makeDraggable({ TitleBar }, Main)

	local ResizeHandle = Instance.new("Frame")
	ResizeHandle.Size = UDim2.new(0, 12, 0, 12)
	ResizeHandle.Position = UDim2.new(1, -12, 1, -12)
	ResizeHandle.BackgroundTransparency = 1
	ResizeHandle.Parent = Main
	ResizeHandle.ZIndex = 20

	local ResizeIcon = Instance.new("TextLabel")
	ResizeIcon.Size = UDim2.new(1, 0, 1, 0)
	ResizeIcon.BackgroundTransparency = 1
	ResizeIcon.Text = "◢"
	ResizeIcon.Font = Theme.Font
	ResizeIcon.TextSize = 10
	ResizeIcon.TextColor3 = Theme.SubText
	ResizeIcon.Parent = ResizeHandle

	local resizing = false
	local resizeStart, startSize
	local MIN_SIZE = Vector2.new(200, 120)

	ResizeHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if Window.Collapsed then return end
			resizing = true
			resizeStart = input.Position
			startSize = Main.Size
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then resizing = false end
			end)
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - resizeStart
			local newX = math.max(MIN_SIZE.X, startSize.X.Offset + delta.X)
			local newY = math.max(MIN_SIZE.Y, startSize.Y.Offset + delta.Y)
			Main.Size = UDim2.new(0, newX, 0, newY)
			fullSize = Main.Size
		end
	end)

	local function addMenuItem(name, callback)
		local MenuBtn = Instance.new("TextButton")
		MenuBtn.Size = UDim2.new(0, 50, 1, 0)
		MenuBtn.BackgroundTransparency = 1
		MenuBtn.Text = name
		MenuBtn.Font = Theme.Font
		MenuBtn.TextSize = 11
		MenuBtn.TextColor3 = Theme.Text
		MenuBtn.Parent = MenuBar

		MenuBtn.MouseEnter:Connect(function() MenuBtn.TextColor3 = Theme.Grabber end)
		MenuBtn.MouseLeave:Connect(function() MenuBtn.TextColor3 = Theme.Text end)
		MenuBtn.MouseButton1Click:Connect(function()
			safeCall(callback, MenuBtn)
		end)
		return MenuBtn
	end

	addMenuItem("Menu", function() end)
	addMenuItem("Examples", function() end)

	addMenuItem("Tools", function(anchorBtn)
		openOverlayPanel(anchorBtn, 62, function(panel)
			local ListLayout = Instance.new("UIListLayout")
			ListLayout.Parent = panel

			local function makeToolOpt(text, fn)
				local OptBtn = Instance.new("TextButton")
				OptBtn.Size = UDim2.new(1, 0, 0, 20)
				OptBtn.BackgroundColor3 = Theme.Element
				OptBtn.BorderSizePixel = 0
				OptBtn.Text = text
				OptBtn.Font = Theme.Font
				OptBtn.TextSize = 11
				OptBtn.TextColor3 = Theme.Text
				OptBtn.TextXAlignment = Enum.TextXAlignment.Left
				OptBtn.Parent = panel

				local OPad = Instance.new("UIPadding")
				OPad.PaddingLeft = UDim.new(0, 6)
				OPad.Parent = OptBtn

				OptBtn.MouseEnter:Connect(function() OptBtn.BackgroundColor3 = Theme.Accent end)
				OptBtn.MouseLeave:Connect(function() OptBtn.BackgroundColor3 = Theme.Element end)
				OptBtn.MouseButton1Click:Connect(function()
					closeActivePopup()
					fn()
				end)
			end

			makeToolOpt("Config Settings", function()
				if Library.ToolWindows.Config and Library.ToolWindows.Config.Main and Library.ToolWindows.Config.Main.Parent then
					Library.ToolWindows.Config:Destroy()
					Library.ToolWindows.Config = nil
				else
					Library.ToolWindows.Config = Library:CreateConfigWindow()
				end
			end)

			makeToolOpt("Style Editor", function()
				if Library.ToolWindows.Style and Library.ToolWindows.Style.Main and Library.ToolWindows.Style.Main.Parent then
					Library.ToolWindows.Style:Destroy()
					Library.ToolWindows.Style = nil
				else
					Library.ToolWindows.Style = Library:CreateStyleEditorWindow()
				end
			end)

			makeToolOpt("Keybind List", function()
				if Library.ToolWindows.Keybinds and Library.ToolWindows.Keybinds.Main and Library.ToolWindows.Keybinds.Main.Parent then
					Library.ToolWindows.Keybinds:Destroy()
					Library.ToolWindows.Keybinds = nil
				else
					Library.ToolWindows.Keybinds = Library:CreateKeybindListWindow()
				end
			end)
		end, nil, 130)
	end)

	function Window:AddCategory(name)
		local TabBtn = Instance.new("TextButton")
		TabBtn.Size = UDim2.new(0, 70, 1, 0)
		TabBtn.BackgroundColor3 = Theme.Element
		TabBtn.BorderSizePixel = 0
		TabBtn.Text = name
		TabBtn.Font = Theme.Font
		TabBtn.TextSize = 11
		TabBtn.TextColor3 = Theme.SubText
		TabBtn.Parent = Tabs
		stroke(TabBtn, Theme.Border)

		local Page = Instance.new("ScrollingFrame")
		Page.Size = UDim2.new(1, 0, 1, 0)
		Page.BackgroundTransparency = 1
		Page.BorderSizePixel = 0
		Page.ScrollBarThickness = 6
		Page.ScrollBarImageColor3 = Theme.Border
		Page.ScrollBarImageTransparency = 0.2
		Page.CanvasSize = UDim2.new(0, 0, 0, 0)
		Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		Page.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		Page.Visible = false
		Page.Parent = Pages

		local PagePad = Instance.new("UIPadding")
		PagePad.PaddingRight = UDim.new(0, 4)
		PagePad.Parent = Page

		local Layout = Instance.new("UIListLayout")
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.Padding = UDim.new(0, Theme.ItemSpacing or 4)
		Layout.Parent = Page

		local function select()
			for _, c in ipairs(Window.Categories) do
				c.Page.Visible = false
				c.TabBtn.BackgroundColor3 = Theme.Element
				c.TabBtn.TextColor3 = Theme.SubText
			end
			Page.Visible = true
			TabBtn.BackgroundColor3 = Theme.Accent
			TabBtn.TextColor3 = Theme.Text
		end

		TabBtn.MouseButton1Click:Connect(select)

		local Category = buildScope(Page)
		Category.Page = Page
		Category.TabBtn = TabBtn
		table.insert(Window.Categories, Category)

		if #Window.Categories == 1 then select() end

		return Category
	end

	local function collectSearchIndex()
		local results = {}
		for _, cat in ipairs(Window.Categories) do
			for _, desc in ipairs(cat.Page:GetDescendants()) do
				if (desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox"))
					and desc.Text ~= "" and desc.Text ~= "..." then
					table.insert(results, {Text = desc.Text, Category = cat, Instance = desc})
				end
			end
		end
		return results
	end

	local function openCommandPalette()
		local Catcher = Instance.new("TextButton")
		Catcher.Size = UDim2.new(1, 0, 1, 0)
		Catcher.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		Catcher.BackgroundTransparency = 0.4
		Catcher.Text = ""
		Catcher.AutoButtonColor = false
		Catcher.ZIndex = 20000
		Catcher.Parent = getScreenGui()

		local Panel = Instance.new("Frame")
		Panel.Size = UDim2.new(0, 280, 0, 220)
		Panel.Position = UDim2.new(0.5, 0, 0.35, 0)
		Panel.AnchorPoint = Vector2.new(0.5, 0.5)
		Panel.BackgroundColor3 = Theme.Background
		Panel.BorderSizePixel = 0
		Panel.ZIndex = 20001
		Panel.Parent = Catcher
		stroke(Panel, Theme.Border)

		local Pad = Instance.new("UIPadding")
		Pad.PaddingLeft = UDim.new(0, 6)
		Pad.PaddingRight = UDim.new(0, 6)
		Pad.PaddingTop = UDim.new(0, 6)
		Pad.PaddingBottom = UDim.new(0, 6)
		Pad.Parent = Panel

		local Layout = Instance.new("UIListLayout")
		Layout.Padding = UDim.new(0, 4)
		Layout.Parent = Panel

		local SearchBox = Instance.new("TextBox")
		SearchBox.Size = UDim2.new(1, 0, 0, 22)
		SearchBox.BackgroundColor3 = Theme.Element
		SearchBox.BorderSizePixel = 0
		SearchBox.PlaceholderText = "Widget ara... (" .. title .. ")"
		SearchBox.Text = ""
		SearchBox.Font = Theme.Font
		SearchBox.TextSize = Theme.TextSize
		SearchBox.TextColor3 = Theme.Text
		SearchBox.PlaceholderColor3 = Theme.SubText
		SearchBox.ClearTextOnFocus = false
		SearchBox.ZIndex = 20002
		SearchBox.Parent = Panel
		stroke(SearchBox, Theme.Border)

		local ResultsFrame = Instance.new("ScrollingFrame")
		ResultsFrame.Size = UDim2.new(1, 0, 1, -26)
		ResultsFrame.BackgroundTransparency = 1
		ResultsFrame.BorderSizePixel = 0
		ResultsFrame.ScrollBarThickness = 4
		ResultsFrame.ScrollBarImageColor3 = Theme.Border
		ResultsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		ResultsFrame.ZIndex = 20002
		ResultsFrame.Parent = Panel

		local ResultsLayout = Instance.new("UIListLayout")
		ResultsLayout.Padding = UDim.new(0, 2)
		ResultsLayout.Parent = ResultsFrame

		local function close()
			Catcher:Destroy()
		end
		Catcher.MouseButton1Click:Connect(close)

		local function jumpTo(result)
			close()
			for _, c in ipairs(Window.Categories) do
				local isTarget = (c == result.Category)
				c.Page.Visible = isTarget
				c.TabBtn.BackgroundColor3 = isTarget and Theme.Accent or Theme.Element
				c.TabBtn.TextColor3 = isTarget and Theme.Text or Theme.SubText
			end
			task.wait()
			local target = result.Instance
			pcall(function()
				local page = result.Category.Page
				local targetY = target.AbsolutePosition.Y - page.AbsolutePosition.Y + page.CanvasPosition.Y - 20
				page.CanvasPosition = Vector2.new(0, math.max(0, targetY))
			end)
			local flashTarget = target:FindFirstAncestorOfClass("Frame")
			if flashTarget then
				local s = stroke(flashTarget, Theme.Grabber, 2)
				task.delay(0.8, function() if s then s:Destroy() end end)
			end
		end

		local function refresh(query)
			for _, c in ipairs(ResultsFrame:GetChildren()) do
				if c:IsA("TextButton") then c:Destroy() end
			end
			if query == "" then return end

			local results = collectSearchIndex()
			local shown = 0
			for _, r in ipairs(results) do
				if r.Text:lower():find(query:lower(), 1, true) then
					shown = shown + 1
					if shown > 40 then break end

					local Btn = Instance.new("TextButton")
					Btn.Size = UDim2.new(1, 0, 0, 20)
					Btn.BackgroundColor3 = Theme.Element
					Btn.BorderSizePixel = 0
					Btn.Text = r.Text
					Btn.Font = Theme.Font
					Btn.TextSize = 11
					Btn.TextColor3 = Theme.Text
					Btn.TextXAlignment = Enum.TextXAlignment.Left
					Btn.ZIndex = 20003
					Btn.Parent = ResultsFrame

					local IPad = Instance.new("UIPadding")
					IPad.PaddingLeft = UDim.new(0, 6)
					IPad.Parent = Btn

					Btn.MouseEnter:Connect(function() Btn.BackgroundColor3 = Theme.Accent end)
					Btn.MouseLeave:Connect(function() Btn.BackgroundColor3 = Theme.Element end)
					Btn.MouseButton1Click:Connect(function() jumpTo(r) end)
				end
			end
		end

		SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
			refresh(SearchBox.Text)
		end)

		SearchBox:CaptureFocus()
	end

	Window.SearchConnection = track(UIS.InputBegan:Connect(function(input, gpe)
		if gpe or not Main.Visible then return end
		if input.KeyCode == Enum.KeyCode.F and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
			openCommandPalette()
		end
	end))

	function Window:Destroy()
		closeActivePopup()
		if Window.SearchConnection then Window.SearchConnection:Disconnect() end
		if Library.ToolWindows.Config == Window then Library.ToolWindows.Config = nil end
		if Library.ToolWindows.Style == Window then Library.ToolWindows.Style = nil end
		if Library.ToolWindows.Keybinds == Window then Library.ToolWindows.Keybinds = nil end
		Main:Destroy()
		for i, w in ipairs(Library.Windows) do
			if w == Window then table.remove(Library.Windows, i) break end
		end
	end

	function Window:SetVisible(visible)
		Main.Visible = visible
	end

	table.insert(Library.Windows, Window)
	return Window
end

-- ============================================================
-- Tools Pencereleri
-- ============================================================

local function populateConfigManager(scope)
	scope:AddLabel("Konfigürasyon Yönetimi")
	local nameBox = scope:AddTextbox("Config Adı", "", "Dosya adı gir...")

	local function getConfigList()
		local list = Library:ListConfigs()
		return #list > 0 and list or {"None"}
	end

	local configDropdown = scope:AddDropdown("Kayıtlı Configler", getConfigList(), nil, nil, nil)

	local autoLoadFile = Library.ConfigFolder .. "/autoload.txt"
	local function getAutoLoadName()
		if hasFileApi() and isfile(autoLoadFile) then
			local content = readfile(autoLoadFile)
			if content and #content > 0 then return content end
		end
		return "None"
	end

	local autoLoadLabel = scope:AddLabel("Auto Load: " .. getAutoLoadName())

	scope:AddButton("Save Config", function()
		local name = nameBox.Get()
		if name == "" then return end
		Library:SaveConfig(name)
		configDropdown.Refresh(getConfigList())
	end)

	scope:AddButton("Load Config", function()
		local name = configDropdown.Get()
		if name == "None" then return end
		Library:LoadConfig(name)
	end)

	scope:AddButton("Delete Config", function()
		local name = configDropdown.Get()
		if name == "None" or not hasFileApi() then return end
		Library:ConfirmModal("Config Silme Onayı", "'" .. name .. "' isimli konfigürasyon silinecek. Emin misin?", function()
			local path = Library.ConfigFolder .. "/" .. name .. ".json"
			if isfile(path) then
				delfile(path)
				if getAutoLoadName() == name then
					delfile(autoLoadFile)
					autoLoadLabel.Text = "Auto Load: None"
				end
				configDropdown.Refresh(getConfigList())
				Library:Notify("Config Silindi", name .. " başarıyla silindi.", 3, "warning")
			end
		end)
	end)

	scope:AddButton("Set Auto Load Config", function()
		local name = configDropdown.Get()
		if name == "None" or not hasFileApi() then return end
		ensureFolder()
		writefile(autoLoadFile, name)
		autoLoadLabel.Text = "Auto Load: " .. name
		Library:Notify("AutoLoad Ayarlandı", name .. " varsayılan olarak ayarlandı.", 3, "info")
	end)

	scope:AddButton("Clear Auto Load Config", function()
		if hasFileApi() and isfile(autoLoadFile) then
			delfile(autoLoadFile)
		end
		autoLoadLabel.Text = "Auto Load: None"
		Library:Notify("AutoLoad Temizlendi", "Otomatik yükleme kaldırıldı.", 3, "info")
	end)

	scope:AddCheckbox("Auto Save Enabled", Library.AutoSaveEnabled, function(v)
		local name = configDropdown.Get()
		Library:SetAutoSave(v, name ~= "None" and name or nil)
	end)

	if hasFileApi() and isfile(autoLoadFile) then
		local autoName = readfile(autoLoadFile)
		if autoName and autoName ~= "" and isfile(Library.ConfigFolder .. "/" .. autoName .. ".json") then
			Library:LoadConfig(autoName)
		end
	end
end

function Library:CreateConfigWindow()
	local ConfigWin = Library:CreateWindow("Config Manager", UDim2.new(0, 150, 0, 150), UDim2.new(0, 300, 0, 340))
	local MainTab = ConfigWin:AddCategory("Configs")
	populateConfigManager(MainTab)
	return ConfigWin
end

function Library:CreateStyleEditorWindow()
	local StyleWin = Library:CreateWindow("Style Editor", UDim2.new(0, 200, 0, 150), UDim2.new(0, 320, 0, 420))

	local ColorsTab = StyleWin:AddCategory("Colors")
	ColorsTab:AddLabel("ImGUI Canlı Renk Düzenleyici")

	ColorsTab:AddColorpicker("Header Color", Theme.Header, function(color)
		Theme.Header = color
		for _, win in ipairs(Library.Windows) do
			local titleBar = win.Main and win.Main:FindFirstChild("TitleBar")
			if titleBar then titleBar.BackgroundColor3 = color end
		end
	end)

	ColorsTab:AddColorpicker("Background Color", Theme.Background, function(color) Theme.Background = color end)
	ColorsTab:AddColorpicker("Accent Color", Theme.Accent, function(color) Theme.Accent = color end)
	ColorsTab:AddColorpicker("Element Color", Theme.Element, function(color) Theme.Element = color end)
	ColorsTab:AddColorpicker("Grabber Knob Color", Theme.Grabber, function(color) Theme.Grabber = color end)
	ColorsTab:AddColorpicker("Text Color", Theme.Text, function(color) Theme.Text = color end)

	local SizesTab = StyleWin:AddCategory("Style")
	SizesTab:AddLabel("Boyut ve Yazı Tipi Düzenleyici")

	SizesTab:AddDropdown("Font Type", {"RobotoMono", "Code", "SourceSans", "Gotham", "Ubuntu"}, "RobotoMono", function(fontName)
		if Enum.Font[fontName] then
			Theme.Font = Enum.Font[fontName]
		end
	end)

	SizesTab:AddSlider("Font Size", 10, 18, Theme.TextSize or 12, function(v)
		Theme.TextSize = v
	end)

	SizesTab:AddSlider("Item Spacing", 0, 12, Theme.ItemSpacing or 4, function(v)
		Theme.ItemSpacing = v
	end)

	SizesTab:AddSlider("Indent Spacing", 4, 24, Theme.IndentSpacing or 12, function(v)
		Theme.IndentSpacing = v
	end)

	SizesTab:AddSlider("Slider Grab Min Size", 4, 20, Theme.GrabberWidth or 10, function(v)
		Theme.GrabberWidth = v
	end)

	return StyleWin
end

-- Keybind List Tool Window
function Library:CreateKeybindListWindow()
	local KeybindWin = Library:CreateWindow("Keybind List", UDim2.new(0, 250, 0, 150), UDim2.new(0, 280, 0, 300))
	local MainTab = KeybindWin:AddCategory("Keybinds")

	local function refresh()
		MainTab:Clear()
		MainTab:AddLabel("Kayıtlı Tuş Atamaları")
		if #Library.RegisteredKeybinds == 0 then
			MainTab:AddLabel("Henüz atama yapılmadı.")
			return
		end

		for _, kb in ipairs(Library.RegisteredKeybinds) do
			local currentKey = kb.GetKey()
			local row = MainTab:AddRow(22, 6)
			row:AddText(kb.Name, 0.5)
			row:AddButton(currentKey and currentKey.Name or "None", function()
				Library:Notify("Keybind", "Yeni tuşa basın...", 3, "info")
				local conn
				conn = UIS.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.Keyboard then
						kb.SetKey(input.KeyCode)
						Library:Notify("Keybind", "Tuş atandı: " .. input.KeyCode.Name, 2, "success")
						conn:Disconnect()
						refresh()
					elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
						conn:Disconnect()
						refresh()
					end
				end)
			end, 0.5)
		end
	end

	refresh()
	return KeybindWin
end

-- ============================================================
-- Library:Unload()
-- ============================================================
function Library:Unload()
	for _, conn in ipairs(Library.Connections) do
		pcall(function() conn:Disconnect() end)
	end
	Library.Connections = {}

	for i = #Library.Windows, 1, -1 do
		local win = Library.Windows[i]
		if win.Destroy then
			pcall(function() win:Destroy() end)
		end
	end
	Library.Windows = {}
	Library.ToolWindows = {}
	Library.Flags = {}
	Library.RegisteredKeybinds = {}

	closeActivePopup()

	local parent = getParentGui()
	local gui = parent:FindFirstChild("ImGuiLibrary")
	if gui then gui:Destroy() end
end

return Library
