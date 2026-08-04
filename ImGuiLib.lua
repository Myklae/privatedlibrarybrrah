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
	Text = Color3.fromRGB(240, 240, 240),
	SubText = Color3.fromRGB(160, 160, 165),
	Border = Color3.fromRGB(50, 50, 60),
	SeparatorLine = Color3.fromRGB(50, 50, 60),
	Font = Enum.Font.RobotoMono,
}

local Library = {}
Library.__index = Library
Library.Windows = {}
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
TooltipFrame.ZIndex = 999
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
	Label.TextSize = 12
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

	if text then
		local Label = Instance.new("TextLabel")
		Label.LayoutOrder = 1
		Label.AutomaticSize = Enum.AutomaticSize.X
		Label.Size = UDim2.new(0, 0, 1, 0)
		Label.BackgroundTransparency = 1
		Label.Font = Theme.Font
		Label.TextSize = 12
		Label.TextColor3 = Theme.SubText
		Label.TextXAlignment = Enum.TextXAlignment.Left
		Label.Text = text
		Label.Parent = Row
	end

	local Line = Instance.new("Frame")
	Line.LayoutOrder = 2
	Line.Size = UDim2.new(0, 0, 0, 1)
	Line.BackgroundColor3 = Theme.SeparatorLine
	Line.BorderSizePixel = 0
	Line.Parent = Row
	flexify(Line)

	return Row
end

local function buildButton(container, text, callback)
	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 0, 22)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text
	Btn.Font = Theme.Font
	Btn.TextSize = 12
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
	Box.Parent = Holder
	stroke(Box, Theme.Border)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -20, 1, 0)
	Label.Position = UDim2.new(0, 20, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = 12
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
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
	Track.Parent = Holder
	stroke(Track, Theme.Border)

	local Fill = Instance.new("Frame")
	Fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
	Fill.BackgroundColor3 = Theme.Accent
	Fill.BorderSizePixel = 0
	Fill.Parent = Track

	local ValueLabel = Instance.new("TextLabel")
	ValueLabel.Size = UDim2.new(1, -8, 1, 0)
	ValueLabel.Position = UDim2.new(0, 4, 0, 0)
	ValueLabel.BackgroundTransparency = 1
	ValueLabel.Text = text .. ": " .. tostring(value)
	ValueLabel.Font = Theme.Font
	ValueLabel.TextSize = 12
	ValueLabel.TextColor3 = Theme.Text
	ValueLabel.TextXAlignment = Enum.TextXAlignment.Left
	ValueLabel.ZIndex = 2
	ValueLabel.Parent = Track

	local function apply(v)
		value = math.clamp(v, min, max)
		local rel = (value - min) / (max - min)
		Fill.Size = UDim2.new(rel, 0, 1, 0)
		ValueLabel.Text = text .. ": " .. tostring(value)
		if callback then callback(value) end
	end

	local function setFromX(x)
		local rel = math.clamp((x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
		apply(math.floor(min + (max - min) * rel))
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
	Box.TextSize = 12
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
	Label.TextSize = 12
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
		end
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
	ValueLabel.TextSize = 12
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

local function buildColorpicker(container, text, default, callback, flag)
	local color = default or Color3.fromRGB(255, 255, 255)
	local open = false

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
	Label.TextSize = 12
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

	local Panel = Instance.new("Frame")
	Panel.Size = UDim2.new(1, 0, 0, 80)
	Panel.Position = UDim2.new(0, 0, 1, 2)
	Panel.BackgroundColor3 = Theme.Background
	Panel.BorderSizePixel = 0
	Panel.Visible = false
	Panel.ZIndex = 100
	Panel.Parent = Holder
	stroke(Panel, Theme.Border)

	local function makeSlider(labelText, yPos, initial)
		local L = Instance.new("TextLabel")
		L.Size = UDim2.new(0, 16, 0, 16)
		L.Position = UDim2.new(0, 6, 0, yPos)
		L.BackgroundTransparency = 1
		L.Text = labelText
		L.Font = Theme.Font
		L.TextSize = 11
		L.TextColor3 = Theme.SubText
		L.ZIndex = 101
		L.Parent = Panel

		local Track = Instance.new("Frame")
		Track.Size = UDim2.new(1, -30, 0, 12)
		Track.Position = UDim2.new(0, 24, 0, yPos + 2)
		Track.BackgroundColor3 = Theme.Element
		Track.BorderSizePixel = 0
		Track.ZIndex = 101
		Track.Parent = Panel
		stroke(Track, Theme.Border)

		local Fill = Instance.new("Frame")
		Fill.Size = UDim2.new(initial / 255, 0, 1, 0)
		Fill.BackgroundColor3 = Theme.Accent
		Fill.BorderSizePixel = 0
		Fill.ZIndex = 101
		Fill.Parent = Track

		return Track, Fill
	end

	local rTrack, rFill = makeSlider("R", 6, color.R * 255)
	local gTrack, gFill = makeSlider("G", 28, color.G * 255)
	local bTrack, bFill = makeSlider("B", 50, color.B * 255)

	local r, g, b = color.R * 255, color.G * 255, color.B * 255
	local function update(fromUser)
		color = Color3.fromRGB(math.floor(r), math.floor(g), math.floor(b))
		PreviewBtn.BackgroundColor3 = color
		rFill.Size = UDim2.new(r / 255, 0, 1, 0)
		gFill.Size = UDim2.new(g / 255, 0, 1, 0)
		bFill.Size = UDim2.new(b / 255, 0, 1, 0)
		if callback then callback(color) end
		if fromUser then pushAutoSave() end
	end

	local function bind(track, setter)
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local function setFromX(x)
					local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
					setter(rel * 255)
					update(false)
				end
				setFromX(input.Position.X)
				ActiveSlider = {Update = setFromX, Release = function() update(true) end}
			end
		end)
	end
	bind(rTrack, function(v) r = v end)
	bind(gTrack, function(v) g = v end)
	bind(bTrack, function(v) b = v end)

	PreviewBtn.MouseButton1Click:Connect(function()
		open = not open
		Panel.Visible = open
		Holder.ZIndex = open and 100 or 1
	end)

	registerFlag(flag, {
		Get = function() return {r = color.R, g = color.G, b = color.B} end,
		Set = function(v)
			r, g, b = v.r * 255, v.g * 255, v.b * 255
			update(false)
		end
	})
	if callback then callback(color) end

	return {Set = function(c)
		r, g, b = c.R * 255, c.G * 255, c.B * 255
		update(false)
	end}
end

local function buildMultiDropdown(container, text, options, defaults, callback, flag)
	local selected = {}
	for _, v in ipairs(defaults or {}) do selected[v] = true end
	local open = false
	local currentOptions = options

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.ZIndex = 1
	Holder.Parent = container

	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 1, 0)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text .. ": ..."
	Btn.Font = Theme.Font
	Btn.TextSize = 12
	Btn.TextColor3 = Theme.Text
	Btn.TextXAlignment = Enum.TextXAlignment.Left
	Btn.Parent = Holder
	stroke(Btn, Theme.Border)

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 6)
	Pad.Parent = Btn

	local ListHolder = Instance.new("Frame")
	ListHolder.Position = UDim2.new(0, 0, 1, 2)
	ListHolder.BackgroundColor3 = Theme.Background
	ListHolder.BorderSizePixel = 0
	ListHolder.Visible = false
	ListHolder.ZIndex = 100
	ListHolder.Parent = Holder
	stroke(ListHolder, Theme.Border)

	local ListLayout = Instance.new("UIListLayout")
	ListLayout.Parent = ListHolder

	local function refreshLabel()
		local names = {}
		for _, opt in ipairs(currentOptions) do
			if selected[opt] then table.insert(names, tostring(opt)) end
		end
		Btn.Text = text .. ": " .. (#names > 0 and table.concat(names, ", ") or "None")
	end

	local function build()
		for _, c in ipairs(ListHolder:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 20)
		for _, opt in ipairs(currentOptions) do
			local OptBtn = Instance.new("TextButton")
			OptBtn.Size = UDim2.new(1, 0, 0, 20)
			OptBtn.BackgroundColor3 = selected[opt] and Theme.Accent or Theme.Element
			OptBtn.BorderSizePixel = 0
			OptBtn.Text = tostring(opt)
			OptBtn.Font = Theme.Font
			OptBtn.TextSize = 12
			OptBtn.TextColor3 = Theme.Text
			OptBtn.TextXAlignment = Enum.TextXAlignment.Left
			OptBtn.ZIndex = 101
			OptBtn.Parent = ListHolder

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
	end

	build()
	refreshLabel()

	Btn.MouseButton1Click:Connect(function()
		open = not open
		ListHolder.Visible = open
		Holder.ZIndex = open and 100 or 1
	end)

	registerFlag(flag, {
		Get = function() return selected end,
		Set = function(v)
			selected = v
			build()
			refreshLabel()
		end
	})
	if callback then callback(selected) end

	return {
		Set = function(v) selected = v; build(); refreshLabel() end,
		Refresh = function(newOptions)
			currentOptions = newOptions
			build()
			refreshLabel()
		end,
	}
end

local function buildDropdown(container, text, options, default, callback, flag)
	local selected = default or options[1]
	local open = false
	local currentOptions = options

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.ZIndex = 1
	Holder.Parent = container

	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 1, 0)
	Btn.BackgroundColor3 = Theme.Element
	Btn.BorderSizePixel = 0
	Btn.Text = text .. ": " .. tostring(selected)
	Btn.Font = Theme.Font
	Btn.TextSize = 12
	Btn.TextColor3 = Theme.Text
	Btn.TextXAlignment = Enum.TextXAlignment.Left
	Btn.Parent = Holder
	stroke(Btn, Theme.Border)

	local Pad = Instance.new("UIPadding")
	Pad.PaddingLeft = UDim.new(0, 6)
	Pad.Parent = Btn

	local ListHolder = Instance.new("Frame")
	ListHolder.Position = UDim2.new(0, 0, 1, 2)
	ListHolder.BackgroundColor3 = Theme.Background
	ListHolder.BorderSizePixel = 0
	ListHolder.Visible = false
	ListHolder.ZIndex = 100
	ListHolder.Parent = Holder
	stroke(ListHolder, Theme.Border)

	local ListLayout = Instance.new("UIListLayout")
	ListLayout.Parent = ListHolder

	local function selectOption(opt, fromUser)
		selected = opt
		Btn.Text = text .. ": " .. tostring(selected)
		ListHolder.Visible = false
		open = false
		Holder.ZIndex = 1
		if callback then callback(opt) end
		if fromUser then pushAutoSave() end
	end

	local function build()
		for _, child in ipairs(ListHolder:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 20)
		for _, opt in ipairs(currentOptions) do
			local OptBtn = Instance.new("TextButton")
			OptBtn.Size = UDim2.new(1, 0, 0, 20)
			OptBtn.BackgroundColor3 = Theme.Element
			OptBtn.BorderSizePixel = 0
			OptBtn.Text = tostring(opt)
			OptBtn.Font = Theme.Font
			OptBtn.TextSize = 12
			OptBtn.TextColor3 = Theme.Text
			OptBtn.TextXAlignment = Enum.TextXAlignment.Left
			OptBtn.ZIndex = 101
			OptBtn.Parent = ListHolder

			local OPad = Instance.new("UIPadding")
			OPad.PaddingLeft = UDim.new(0, 6)
			OPad.Parent = OptBtn

			OptBtn.MouseEnter:Connect(function() OptBtn.BackgroundColor3 = Theme.Accent end)
			OptBtn.MouseLeave:Connect(function() OptBtn.BackgroundColor3 = Theme.Element end)

			OptBtn.MouseButton1Click:Connect(function()
				selectOption(opt, true)
			end)
		end
	end

	build()

	Btn.MouseButton1Click:Connect(function()
		open = not open
		ListHolder.Visible = open
		Holder.ZIndex = open and 100 or 1
	end)

	registerFlag(flag, {Get = function() return selected end, Set = function(v) selectOption(v, false) end})
	if callback then callback(selected) end

	return {
		Set = function(v) selectOption(v, false) end,
		Get = function() return selected end,
		Refresh = function(newOptions)
			currentOptions = newOptions
			build()
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
	Btn.TextSize = 12
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

local function buildRadioButton(container, text, active, callback)
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
	Outer.Parent = Holder
	stroke(Outer, Theme.Border)

	local Dot = Instance.new("Frame")
	Dot.Size = UDim2.new(0, 6, 0, 6)
	Dot.Position = UDim2.new(0.5, -3, 0.5, -3)
	Dot.BackgroundColor3 = Theme.Accent
	Dot.BorderSizePixel = 0
	Dot.Visible = state
	Dot.Parent = Outer

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -20, 1, 0)
	Label.Position = UDim2.new(0, 20, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Theme.Font
	Label.TextSize = 12
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local function setState(v)
		state = v
		Dot.Visible = state
		if callback then callback(state) end
	end

	Holder.MouseButton1Click:Connect(function()
		if not state then
			setState(true)
		end
	end)

	return { Set = setState, Get = function() return state end }
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
	Arrow.Parent = Header

	local TitleLbl = Instance.new("TextLabel")
	TitleLbl.Size = UDim2.new(1, -20, 1, 0)
	TitleLbl.BackgroundTransparency = 1
	TitleLbl.Font = Theme.Font
	TitleLbl.TextSize = 12
	TitleLbl.TextColor3 = Theme.Text
	TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	TitleLbl.Text = title
	TitleLbl.Parent = Header

	local Content = Instance.new("Frame")
	Content.LayoutOrder = 2
	Content.Size = UDim2.new(1, 0, 0, 0)
	Content.AutomaticSize = Enum.AutomaticSize.Y
	Content.BackgroundTransparency = 1
	Content.Visible = not collapsed
	Content.Parent = SectionFrame

	local ContentPad = Instance.new("UIPadding")
	ContentPad.PaddingLeft = UDim.new(0, 12)
	ContentPad.PaddingTop = UDim.new(0, 4)
	ContentPad.PaddingBottom = UDim.new(0, 4)
	ContentPad.Parent = Content

	local ContentLayout = Instance.new("UIListLayout")
	ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ContentLayout.Padding = UDim.new(0, 4)
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
	Arrow.Parent = Header

	local TitleLbl = Instance.new("TextLabel")
	TitleLbl.Size = UDim2.new(1, -16, 1, 0)
	TitleLbl.BackgroundTransparency = 1
	TitleLbl.Font = Theme.Font
	TitleLbl.TextSize = 12
	TitleLbl.TextColor3 = Theme.Text
	TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	TitleLbl.Text = title
	TitleLbl.Parent = Header

	local Content = Instance.new("Frame")
	Content.LayoutOrder = 2
	Content.Size = UDim2.new(1, 0, 0, 0)
	Content.AutomaticSize = Enum.AutomaticSize.Y
	Content.BackgroundTransparency = 1
	Content.Visible = false
	Content.Parent = TreeFrame

	local ContentPad = Instance.new("UIPadding")
	ContentPad.PaddingLeft = UDim.new(0, 14)
	ContentPad.Parent = Content

	local ContentLayout = Instance.new("UIListLayout")
	ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ContentLayout.Padding = UDim.new(0, 4)
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
	function Scope:AddRadioButton(text, active, callback)
		return buildRadioButton(container, text, active, callback)
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
		GroupLayout.Padding = UDim.new(0, 4)
		GroupLayout.Parent = GroupFrame

		return buildScope(GroupFrame)
	end
	function Scope:AddTooltip(inst, text)
		bindTooltip(inst, text)
	end

	return Scope
end

-- ============================================================
-- Window & Config Tab API
-- ============================================================

function Library:CreateWindow(title, pos, size)
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

	local Body = Instance.new("Frame")
	Body.Name = "Body"
	Body.Size = UDim2.new(1, 0, 1, -22)
	Body.Position = UDim2.new(0, 0, 0, 22)
	Body.BackgroundTransparency = 1
	Body.ClipsDescendants = true
	Body.Parent = Main

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
		Layout.Padding = UDim.new(0, 4)
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

-- Config Tab With Auto-Load Feature Included
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

	-- Auto load file execution on startup
	if hasFileApi() and isfile(autoLoadFile) then
		local autoName = readfile(autoLoadFile)
		if autoName and autoName ~= "" and isfile(Library.ConfigFolder .. "/" .. autoName .. ".json") then
			Library:LoadConfig(autoName)
		end
	end

	return Category
end

return Library
