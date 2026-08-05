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
	Font = Enum.Font.RobotoMono,
	TextSize = 12,
	ItemSpacing = 4,
	IndentSpacing = 12,
	GrabberWidth = 10,
}

local Library = {}
Library.__index = Library
Library.Windows = {}
Library.ToolWindows = {} -- Tools menüsünden açılan pencerelerin referansı
Library.Flags = {}
Library.ConfigFolder = "ImGuiConfigs"
Library.AutoSaveEnabled = false
Library.CurrentConfig = nil

-- Helper Functions
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

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	handle.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

local function getScreenGui()
	local existing = PlayerGui:FindFirstChild("ImGuiLibrary")
	if existing then return existing end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ImGuiLibrary"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	return gui
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

UIS.InputChanged:Connect(function(input)
	if TooltipFrame.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
		TooltipFrame.Position = UDim2.new(0, input.Position.X + 12, 0, input.Position.Y + 12)
	end
end)

local function bindTooltip(inst, text)
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
		if popup.onClose then popup.onClose() end
		if popup.catcher then popup.catcher:Destroy() end
		if popup.panel then popup.panel:Destroy() end
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
	Library.Flags[flag] = getSet
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

UIS.InputChanged:Connect(function(input)
	if ActiveSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		ActiveSlider.Update(input.Position.X)
	end
end)

UIS.InputEnded:Connect(function(input)
	if ActiveSlider and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		ActiveSlider.Release()
		ActiveSlider = nil
	end
end)

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
	return Label
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

	return Row
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
		if callback then callback() end
	end)

	return Btn
end

local function buildCheckbox(container, text, default, callback, flag)
	local state = default or false

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
		if callback then callback(state) end
		if fromUser then pushAutoSave() end
	end

	Holder.MouseButton1Click:Connect(function()
		setState(not state, true)
	end)

	registerFlag(flag, {Get = function() return state end, Set = function(v) setState(v, false) end})
	if callback then callback(state) end

	return Holder, {Set = function(v) setState(v, false) end, Get = function() return state end}
end

local function buildSlider(container, text, min, max, default, callback, flag)
	min = min or 0
	max = max or 100
	local value = default or min

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
	ValueLabel.Text = text .. ": " .. tostring(value)
	ValueLabel.Font = Theme.Font
	ValueLabel.TextSize = Theme.TextSize
	ValueLabel.TextColor3 = Theme.Text
	ValueLabel.TextXAlignment = Enum.TextXAlignment.Left
	ValueLabel.ZIndex = 4
	ValueLabel.Parent = Track

	local function apply(v)
		value = math.clamp(v, min, max)
		grabWidth = Theme.GrabberWidth or 10
		local r = (value - min) / math.max(1e-9, max - min)
		Fill.Size = UDim2.new(r, 0, 1, 0)
		Grabber.Size = UDim2.new(0, grabWidth, 1, 0)
		Grabber.Position = UDim2.new(r, -r * grabWidth, 0, 0)
		ValueLabel.Text = text .. ": " .. tostring(value)
		if callback then callback(value) end
	end

	local function setFromX(x)
		local r = math.clamp((x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
		apply(math.floor(min + (max - min) * r))
	end

	Track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
			ActiveSlider = { Update = setFromX, Release = pushAutoSave }
		end
	end)

	registerFlag(flag, {Get = function() return value end, Set = function(v) apply(v) end})
	if callback then callback(value) end
	return {Set = function(v) apply(v) end, Get = function() return value end}
end

local function buildRangeSlider(container, text, min, max, defaultLow, defaultHigh, callback, flag)
	min, max = min or 0, max or 100
	local valLow = defaultLow or min
	local valHigh = defaultHigh or max

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
		if callback then callback(valLow, valHigh) end
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

	registerFlag(flag, {
		Get = function() return {low = valLow, high = valHigh} end,
		Set = function(v)
			valLow, valHigh = v.low or min, v.high or max
			apply()
		end
	})
	if callback then callback(valLow, valHigh) end
	return {
		Set = function(l, h) valLow, valHigh = l, h; apply() end,
		Get = function() return valLow, valHigh end
	}
end

-- altschuler/imgui-knobs "STEPPED" Variantında Döner Kadran (Boyut Ayarlanabilir)
local function buildKnob(container, text, values, defaultIndex, callback, flag, size)
	values = values or {"1", "2", "3"}
	size = size or 32
	local index = math.clamp(defaultIndex or 1, 1, #values)

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

	-- Stepped Variant için dış dairesel adım çentikleri (Ticks)
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

		if callback then callback(currentVal, index) end
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

	registerFlag(flag, {
		Get = function() return {index = index, value = values[index]} end,
		Set = function(v)
			if type(v) == "table" then index = v.index or 1 else index = tonumber(v) or 1 end
			apply()
		end
	})

	apply()
	return {
		Set = function(i) index = i; apply() end,
		Get = function() return values[index], index end
	}
end

local function buildTextbox(container, text, default, placeholder, callback, flag)
	local value = default or ""
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
		if callback then callback(value, enterPressed) end
		pushAutoSave()
	end)

	registerFlag(flag, {Get = function() return value end, Set = function(v) value = v; Box.Text = v end})
	return {Set = function(v) value = v; Box.Text = v end, Get = function() return value end}
end

local function buildKeybind(container, text, default, callback, flag)
	local key = default
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

	local KeyBtn = Instance.new("TextButton")
	KeyBtn.Size = UDim2.new(0, 64, 1, 0)
	KeyBtn.Position = UDim2.new(1, -64, 0, 0)
	KeyBtn.BackgroundColor3 = Theme.Element
	KeyBtn.BorderSizePixel = 0
	KeyBtn.Text = key and key.Name or "None"
	KeyBtn.Font = Theme.Font
	KeyBtn.TextSize = 11
	KeyBtn.TextColor3 = Theme.Accent
	KeyBtn.Parent = Holder
	stroke(KeyBtn, Theme.Border)

	KeyBtn.MouseButton1Click:Connect(function()
		listening = true
		KeyBtn.Text = "..."
	end)

	local conn
	conn = UIS.InputBegan:Connect(function(input, gpe)
		if listening and input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				listening = false
				KeyBtn.Text = key and key.Name or "None"
				return
			end
			key = input.KeyCode
			KeyBtn.Text = key.Name
			listening = false
			if callback then callback(key, true) end
			pushAutoSave()
		elseif not listening and not gpe and key and input.KeyCode == key then
			if callback then callback(key, false) end
		end
	end)
	Holder.Destroying:Connect(function() conn:Disconnect() end)

	registerFlag(flag, {
		Get = function() return key and key.Name or "None" end,
		Set = function(v)
			key = Enum.KeyCode[v]
			KeyBtn.Text = key and key.Name or "None"
		end
	})

	return {
		Set = function(v)
			key = Enum.KeyCode[v]
			KeyBtn.Text = key and key.Name or "None"
		end,
		Get = function() return key and key.Name or "None" end,
	}
end

local function buildProgressBar(container, text, min, max, default, format)
	min, max = min or 0, max or 100
	local value = default or min

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Track = Instance.new("Frame")
	Track.Size = UDim2.new(1, 0, 1, 0)
	Track.BackgroundColor3 = Theme.Element
	Track.BorderSizePixel = 0
	Track.Parent = Holder
	stroke(Track, Theme.Border)

	local Fill = Instance.new("Frame")
	Fill.Size = UDim2.new((value - min) / math.max(1e-9, max - min), 0, 1, 0)
	Fill.BackgroundColor3 = Theme.Accent
	Fill.BorderSizePixel = 0
	Fill.Parent = Track

	local ValueLabel = Instance.new("TextLabel")
	ValueLabel.Size = UDim2.new(1, -8, 1, 0)
	ValueLabel.Position = UDim2.new(0, 4, 0, 0)
	ValueLabel.BackgroundTransparency = 1
	ValueLabel.Text = (text and (text .. ": ") or "") .. formatValue(format, value)
	ValueLabel.Font = Theme.Font
	ValueLabel.TextSize = Theme.TextSize
	ValueLabel.TextColor3 = Theme.Text
	ValueLabel.TextXAlignment = Enum.TextXAlignment.Left
	ValueLabel.ZIndex = 2
	ValueLabel.Parent = Track

	return {
		Set = function(v)
			value = math.clamp(v, min, max)
			Fill.Size = UDim2.new((value - min) / math.max(1e-9, max - min), 0, 1, 0)
			ValueLabel.Text = (text and (text .. ": ") or "") .. formatValue(format, value)
		end,
		Get = function() return value end,
	}
end

-- Colorpicker With Direct RGB Numeric Input Textboxes
local function buildColorpicker(container, text, default, callback, flag)
	local color = default or Color3.fromRGB(255, 255, 255)
	local isOpen = false

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.ZIndex = 1
	Holder.Parent = container

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -34, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = Theme.TextSize
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local PreviewBtn = Instance.new("TextButton")
	PreviewBtn.Size = UDim2.new(0, 28, 0, 16)
	PreviewBtn.Position = UDim2.new(1, -28, 0.5, -8)
	PreviewBtn.BackgroundColor3 = color
	PreviewBtn.BorderSizePixel = 0
	PreviewBtn.Text = ""
	PreviewBtn.Parent = Holder
	stroke(PreviewBtn, Theme.Border)

	local r, g, b = color.R * 255, color.G * 255, color.B * 255
	local rFill, gFill, bFill
	local rBox, gBox, bBox

	local function applyColor(fromUser)
		r = math.clamp(r, 0, 255)
		g = math.clamp(g, 0, 255)
		b = math.clamp(b, 0, 255)

		color = Color3.fromRGB(math.floor(r), math.floor(g), math.floor(b))
		PreviewBtn.BackgroundColor3 = color

		if rFill then rFill.Size = UDim2.new(r / 255, 0, 1, 0) end
		if gFill then gFill.Size = UDim2.new(g / 255, 0, 1, 0) end
		if bFill then bFill.Size = UDim2.new(b / 255, 0, 1, 0) end

		if rBox then rBox.Text = tostring(math.floor(r)) end
		if gBox then gBox.Text = tostring(math.floor(g)) end
		if bBox then bBox.Text = tostring(math.floor(b)) end

		if callback then callback(color) end
		if fromUser then pushAutoSave() end
	end

	local function makeChannelRow(panel, labelText, yPos, initial, setter)
		local L = Instance.new("TextLabel")
		L.Size = UDim2.new(0, 14, 0, 16)
		L.Position = UDim2.new(0, 6, 0, yPos)
		L.BackgroundTransparency = 1
		L.Text = labelText
		L.Font = Theme.Font
		L.TextSize = 11
		L.TextColor3 = Theme.SubText
		L.Parent = panel

		local Track = Instance.new("Frame")
		Track.Size = UDim2.new(1, -70, 0, 12)
		Track.Position = UDim2.new(0, 22, 0, yPos + 2)
		Track.BackgroundColor3 = Theme.Element
		Track.BorderSizePixel = 0
		Track.Active = true
		Track.Parent = panel
		stroke(Track, Theme.Border)

		local Fill = Instance.new("Frame")
		Fill.Size = UDim2.new(initial / 255, 0, 1, 0)
		Fill.BackgroundColor3 = Theme.Accent
		Fill.BorderSizePixel = 0
		Fill.Parent = Track

		local ValBox = Instance.new("TextBox")
		ValBox.Size = UDim2.new(0, 38, 0, 16)
		ValBox.Position = UDim2.new(1, -42, 0, yPos)
		ValBox.BackgroundColor3 = Theme.Element
		ValBox.BorderSizePixel = 0
		ValBox.Text = tostring(math.floor(initial))
		ValBox.Font = Theme.Font
		ValBox.TextSize = 11
		ValBox.TextColor3 = Theme.Text
		ValBox.ClearTextOnFocus = false
		ValBox.Parent = panel
		stroke(ValBox, Theme.Border)

		Track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local function setFromX(x)
					local rel = math.clamp((x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
					setter(rel * 255)
					applyColor(false)
				end
				setFromX(input.Position.X)
				ActiveSlider = { Update = setFromX, Release = function() applyColor(true) end }
			end
		end)

		ValBox.FocusLost:Connect(function()
			local num = tonumber(ValBox.Text)
			if num then
				setter(num)
				applyColor(true)
			else
				ValBox.Text = tostring(math.floor(initial))
			end
		end)

		return Fill, ValBox
	end

	local function closePanel()
		isOpen = false
		rFill, gFill, bFill = nil, nil, nil
		rBox, gBox, bBox = nil, nil, nil
	end

	local function openPanel()
		isOpen = true
		openOverlayPanel(Holder, 86, function(panel)
			rFill, rBox = makeChannelRow(panel, "R", 6, r, function(v) r = v end)
			gFill, gBox = makeChannelRow(panel, "G", 30, g, function(v) g = v end)
			bFill, bBox = makeChannelRow(panel, "B", 54, b, function(v) b = v end)
		end, closePanel)
	end

	PreviewBtn.MouseButton1Click:Connect(function()
		if isOpen then
			closeActivePopup()
		else
			openPanel()
		end
	end)

	registerFlag(flag, {
		Get = function() return {r = color.R, g = color.G, b = color.B} end,
		Set = function(v)
			r, g, b = v.r * 255, v.g * 255, v.b * 255
			applyColor(false)
		end
	})
	if callback then callback(color) end

	return {Set = function(c)
		r, g, b = c.R * 255, c.G * 255, c.B * 255
		applyColor(false)
	end}
end

local function buildMultiDropdown(container, text, options, defaults, callback, flag)
	local selected = {}
	for _, v in ipairs(defaults or {}) do selected[v] = true end
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
		openOverlayPanel(Btn, #currentOptions * 20, function(panel)
			local ListLayout = Instance.new("UIListLayout")
			ListLayout.Parent = panel
			for _, opt in ipairs(currentOptions) do
				local OptBtn = Instance.new("TextButton")
				OptBtn.Size = UDim2.new(1, 0, 0, 20)
				OptBtn.BackgroundColor3 = selected[opt] and Theme.Accent or Theme.Element
				OptBtn.BorderSizePixel = 0
				OptBtn.Text = tostring(opt)
				OptBtn.Font = Theme.Font
				OptBtn.TextSize = Theme.TextSize
				OptBtn.TextColor3 = Theme.Text
				OptBtn.TextXAlignment = Enum.TextXAlignment.Left
				OptBtn.Parent = panel

				local OPad = Instance.new("UIPadding")
				OPad.PaddingLeft = UDim.new(0, 6)
				OPad.Parent = OptBtn

				OptBtn.MouseButton1Click:Connect(function()
					selected[opt] = not selected[opt] or nil
					OptBtn.BackgroundColor3 = selected[opt] and Theme.Accent or Theme.Element
					refreshLabel()
					if callback then callback(selected) end
					pushAutoSave()
				end)
			end
		end, closePanel)
	end

	Btn.MouseButton1Click:Connect(function()
		if isOpen then
			closeActivePopup()
		else
			openPanel()
		end
	end)

	registerFlag(flag, {
		Get = function() return selected end,
		Set = function(v)
			selected = v
			refreshLabel()
		end
	})
	if callback then callback(selected) end

	return {
		Set = function(v) selected = v; refreshLabel() end,
		Refresh = function(newOptions)
			currentOptions = newOptions
			refreshLabel()
		end,
	}
end

local function buildDropdown(container, text, options, default, callback, flag)
	local selected = default or options[1]
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
		if callback then callback(opt) end
		if fromUser then pushAutoSave() end
	end

	local function closePanel()
		isOpen = false
	end

	local function openPanel()
		isOpen = true
		openOverlayPanel(Btn, #currentOptions * 20, function(panel)
			local ListLayout = Instance.new("UIListLayout")
			ListLayout.Parent = panel
			for _, opt in ipairs(currentOptions) do
				local OptBtn = Instance.new("TextButton")
				OptBtn.Size = UDim2.new(1, 0, 0, 20)
				OptBtn.BackgroundColor3 = Theme.Element
				OptBtn.BorderSizePixel = 0
				OptBtn.Text = tostring(opt)
				OptBtn.Font = Theme.Font
				OptBtn.TextSize = Theme.TextSize
				OptBtn.TextColor3 = Theme.Text
				OptBtn.TextXAlignment = Enum.TextXAlignment.Left
				OptBtn.Parent = panel

				local OPad = Instance.new("UIPadding")
				OPad.PaddingLeft = UDim.new(0, 6)
				OPad.Parent = OptBtn

				OptBtn.MouseEnter:Connect(function() OptBtn.BackgroundColor3 = Theme.Accent end)
				OptBtn.MouseLeave:Connect(function() OptBtn.BackgroundColor3 = Theme.Element end)

				OptBtn.MouseButton1Click:Connect(function()
					selectOption(opt, true)
					closeActivePopup()
				end)
			end
		end, closePanel)
	end

	Btn.MouseButton1Click:Connect(function()
		if isOpen then
			closeActivePopup()
		else
			openPanel()
		end
	end)

	registerFlag(flag, {Get = function() return selected end, Set = function(v) selectOption(v, false) end})
	if callback then callback(selected) end

	return {
		Set = function(v) selectOption(v, false) end,
		Get = function() return selected end,
		Refresh = function(newOptions)
			currentOptions = newOptions
			selectOption(newOptions[1], false)
		end
	}
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
		if callback then callback(state) end
	end)

	return {
		Set = function(v)
			state = v
			Btn.BackgroundColor3 = state and Theme.Accent or Theme.Element
		end,
		Get = function() return state end
	}
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
		if callback then callback(state) end
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

	return api
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
		local Label = buildLabel(RowFrame, text)
		flexify(Label, widthScale)
		return Label
	end

	function Row:AddCheckbox(text, default, callback, flag, widthScale)
		local Holder, api = buildCheckbox(RowFrame, text, default, callback, flag)
		flexify(Holder, widthScale)
		return api
	end

	function Row:AddButton(text, callback, widthScale)
		local Btn = buildButton(RowFrame, text, callback)
		flexify(Btn, widthScale)
		return Btn
	end

	function Row:AddSlider(text, min, max, default, callback, flag, widthScale)
		local api = buildSlider(RowFrame, text, min, max, default, callback, flag)
		flexify(RowFrame:GetChildren()[#RowFrame:GetChildren()], widthScale)
		return api
	end

	return Row
end

-- Scope Construction
local function buildScope(container)
	local Scope = {}

	function Scope:AddLabel(text) return buildLabel(container, text) end
	function Scope:AddSeparator(text) return buildSeparator(container, text) end
	function Scope:AddButton(text, callback) return buildButton(container, text, callback) end
	function Scope:AddCheckbox(text, default, callback, flag)
		local _, api = buildCheckbox(container, text, default, callback, flag)
		return api
	end
	function Scope:AddToggle(text, default, callback, flag)
		local _, api = buildCheckbox(container, text, default, callback, flag)
		return api
	end
	function Scope:AddSlider(text, min, max, default, callback, flag)
		return buildSlider(container, text, min, max, default, callback, flag)
	end
	function Scope:AddRangeSlider(text, min, max, defaultLow, defaultHigh, callback, flag)
		return buildRangeSlider(container, text, min, max, defaultLow, defaultHigh, callback, flag)
	end
	function Scope:AddKnob(text, values, defaultIndex, callback, flag, size)
		return buildKnob(container, text, values, defaultIndex, callback, flag, size)
	end
	function Scope:AddTextbox(text, default, placeholder, callback, flag)
		return buildTextbox(container, text, default, placeholder, callback, flag)
	end
	function Scope:AddKeybind(text, default, callback, flag)
		return buildKeybind(container, text, default, callback, flag)
	end
	function Scope:AddProgressBar(text, min, max, default, format)
		return buildProgressBar(container, text, min, max, default, format)
	end
	function Scope:AddColorpicker(text, default, callback, flag)
		return buildColorpicker(container, text, default, callback, flag)
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
	Main.Parent = screenGui
	stroke(Main, Theme.Border)
	Window.Main = Main

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

	-- Orijinal ImGUI Top MenuBar Yapısı
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

	TitleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			closeActivePopup()
		end
	end)
	makeDraggable(TitleBar, Main)

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
			if callback then callback(MenuBtn) end
		end)
		return MenuBtn
	end

	addMenuItem("Menu", function() end)
	addMenuItem("Examples", function() end)

	-- Tools Menüsü (Toggle Pencere Açma/Kapatma Mantığı)
	addMenuItem("Tools", function(anchorBtn)
		openOverlayPanel(anchorBtn, 42, function(panel)
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

			-- Toggle Mantığı: Açıksa kapat, kapalıysa aç
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

	function Window:Destroy()
		closeActivePopup()
		if Library.ToolWindows.Config == Window then Library.ToolWindows.Config = nil end
		if Library.ToolWindows.Style == Window then Library.ToolWindows.Style = nil end
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

function Library:CreateConfigWindow()
	local ConfigWin = Library:CreateWindow("Config Manager", UDim2.new(0, 150, 0, 150), UDim2.new(0, 300, 0, 320))
	local MainTab = ConfigWin:AddCategory("Configs")

	MainTab:AddLabel("Konfigürasyon Yönetimi")
	local nameBox = MainTab:AddTextbox("Config Adı", "", "Dosya adı gir...")

	local function getConfigList()
		local list = Library:ListConfigs()
		return #list > 0 and list or {"None"}
	end

	local configDropdown = MainTab:AddDropdown("Kayıtlı Configler", getConfigList(), nil, nil, nil)

	local autoLoadFile = Library.ConfigFolder .. "/autoload.txt"
	local function getAutoLoadName()
		if hasFileApi() and isfile(autoLoadFile) then
			local content = readfile(autoLoadFile)
			if content and #content > 0 then return content end
		end
		return "None"
	end

	local autoLoadLabel = MainTab:AddLabel("Auto Load: " .. getAutoLoadName())

	MainTab:AddButton("Save Config", function()
		local name = nameBox.Get()
		if name == "" then return end
		Library:SaveConfig(name)
		configDropdown.Refresh(getConfigList())
	end)

	MainTab:AddButton("Load Config", function()
		local name = configDropdown.Get()
		if name == "None" then return end
		Library:LoadConfig(name)
	end)

	MainTab:AddButton("Delete Config", function()
		local name = configDropdown.Get()
		if name == "None" or not hasFileApi() then return end
		local path = Library.ConfigFolder .. "/" .. name .. ".json"
		if isfile(path) then
			delfile(path)
			if getAutoLoadName() == name then
				delfile(autoLoadFile)
				autoLoadLabel.Text = "Auto Load: None"
			end
			configDropdown.Refresh(getConfigList())
		end
	end)

	MainTab:AddButton("Set Auto Load Config", function()
		local name = configDropdown.Get()
		if name == "None" or not hasFileApi() then return end
		ensureFolder()
		writefile(autoLoadFile, name)
		autoLoadLabel.Text = "Auto Load: " .. name
	end)

	MainTab:AddButton("Clear Auto Load Config", function()
		if hasFileApi() and isfile(autoLoadFile) then
			delfile(autoLoadFile)
		end
		autoLoadLabel.Text = "Auto Load: None"
	end)

	MainTab:AddCheckbox("Auto Save Enabled", Library.AutoSaveEnabled, function(v)
		local name = configDropdown.Get()
		Library:SetAutoSave(v, name ~= "None" and name or nil)
	end)

	return ConfigWin
end

-- Gelişmiş ImGUI Style Editor (Font, Font Size, Spacing, Color)
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

function Library:CreateConfigTab(Window, categoryName)
	local Category = Window:AddCategory(categoryName or "Settings")
	Category:AddLabel("Config Manager")

	local nameBox = Category:AddTextbox("Config Adı", "", "Config ismi...")

	local function getConfigList()
		local list = Library:ListConfigs()
		return #list > 0 and list or {"None"}
	end

	local configDropdown = Category:AddDropdown("Saved Configs", getConfigList(), nil, nil, nil)

	local autoLoadFile = Library.ConfigFolder .. "/autoload.txt"
	local function getAutoLoadName()
		if hasFileApi() and isfile(autoLoadFile) then
			local content = readfile(autoLoadFile)
			if content and #content > 0 then return content end
		end
		return "None"
	end

	local autoLoadLabel = Category:AddLabel("Auto Load Config: " .. getAutoLoadName())

	Category:AddButton("Save Config", function()
		local name = nameBox.Get()
		if name == "" then return end
		Library:SaveConfig(name)
		configDropdown.Refresh(getConfigList())
	end)

	Category:AddButton("Load Config", function()
		local name = configDropdown.Get()
		if name == "None" then return end
		Library:LoadConfig(name)
	end)

	Category:AddButton("Delete Config", function()
		local name = configDropdown.Get()
		if name == "None" or not hasFileApi() then return end
		local path = Library.ConfigFolder .. "/" .. name .. ".json"
		if isfile(path) then
			delfile(path)
			if getAutoLoadName() == name then
				delfile(autoLoadFile)
				autoLoadLabel.Text = "Auto Load Config: None"
			end
			configDropdown.Refresh(getConfigList())
		end
	end)

	Category:AddButton("Set Auto Load Config", function()
		local name = configDropdown.Get()
		if name == "None" or not hasFileApi() then return end
		ensureFolder()
		writefile(autoLoadFile, name)
		autoLoadLabel.Text = "Auto Load Config: " .. name
	end)

	Category:AddButton("Clear Auto Load Config", function()
		if hasFileApi() and isfile(autoLoadFile) then
			delfile(autoLoadFile)
		end
		autoLoadLabel.Text = "Auto Load Config: None"
	end)

	Category:AddCheckbox("Auto Save", Library.AutoSaveEnabled, function(v)
		local name = configDropdown.Get()
		Library:SetAutoSave(v, name ~= "None" and name or nil)
	end)

	if hasFileApi() and isfile(autoLoadFile) then
		local autoName = readfile(autoLoadFile)
		if autoName and autoName ~= "" and isfile(Library.ConfigFolder .. "/" .. autoName .. ".json") then
			Library:LoadConfig(autoName)
		end
	end

	return Category
end

return Library
