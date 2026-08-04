local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Theme = {
	Background = Color3.fromRGB(30, 30, 34),
	Header = Color3.fromRGB(45, 82, 168),
	HeaderDark = Color3.fromRGB(35, 65, 135),
	Section = Color3.fromRGB(40, 40, 46),
	Element = Color3.fromRGB(52, 52, 58),
	ElementHover = Color3.fromRGB(64, 64, 72),
	Accent = Color3.fromRGB(66, 135, 245),
	Text = Color3.fromRGB(230, 230, 230),
	SubText = Color3.fromRGB(160, 160, 165),
	Border = Color3.fromRGB(20, 20, 24),
	SeparatorLine = Color3.fromRGB(65, 65, 72),
}

local Library = {}
Library.__index = Library
Library.Windows = {}
Library.Flags = {}
Library.ConfigFolder = "ImGuiConfigs"
Library.AutoSaveEnabled = false
Library.CurrentConfig = nil

-- ============================================================
-- Low level helpers
-- ============================================================

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 4)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.Border
	s.Thickness = thickness or 1
	s.Parent = inst
	return s
end

-- Fades a holder's background in on hover instead of keeping it permanently
-- filled. This replaces the old "every row has its own solid background"
-- look: rows are transparent at rest, and only tint slightly on hover so
-- the user still gets a clear affordance that the row is clickable.
local function hoverTint(inst, color)
	inst.BackgroundColor3 = color or Theme.Element
	inst.BackgroundTransparency = 1
	inst.MouseEnter:Connect(function()
		TS:Create(inst, TweenInfo.new(0.15), {BackgroundTransparency = 0.85}):Play()
	end)
	inst.MouseLeave:Connect(function()
		TS:Create(inst, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
	end)
end

-- Marks an instance to either take a fixed proportional width (widthScale)
-- or to flex-fill whatever space is left over in its parent's horizontal
-- UIListLayout. This is what lets you put e.g. a slider + plain text, or
-- N checkboxes, into a single row and have them share the width sanely.
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

function Library:AutoLoad(name)
	local success = Library:LoadConfig(name)
	Library.CurrentConfig = name
	return success
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
-- Widget builders. Every builder takes `container` as its first
-- argument instead of assuming a fixed `Page` — that's what lets the
-- exact same widget code be used at the top level of a tab, inside a
-- Section, or (for the compact ones) inside a Row.
-- No builder gives its own row/holder a solid background anymore.
-- Only the actual interactive control (track, box, chip, preview
-- swatch, popup panel) keeps a background; everything else is flat,
-- with a soft hover tint on rows that are clickable as a whole.
-- ============================================================

local function buildLabel(container, text)
	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, 20)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.SubText
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = container
	return Label
end

local function buildSeparator(container, text)
	local Row = Instance.new("Frame")
	Row.Size = UDim2.new(1, 0, 0, text and 20 or 12)
	Row.BackgroundTransparency = 1
	Row.Parent = container

	local Layout = Instance.new("UIListLayout")
	Layout.FillDirection = Enum.FillDirection.Horizontal
	Layout.VerticalAlignment = Enum.VerticalAlignment.Center
	Layout.Padding = UDim.new(0, 8)
	Layout.Parent = Row

	if text then
		local Label = Instance.new("TextLabel")
		Label.AutomaticSize = Enum.AutomaticSize.X
		Label.Size = UDim2.new(0, 0, 1, 0)
		Label.BackgroundTransparency = 1
		Label.Font = Enum.Font.GothamBold
		Label.TextSize = 12
		Label.TextColor3 = Theme.SubText
		Label.Text = text
		Label.Parent = Row
	end

	local Line = Instance.new("Frame")
	Line.Size = UDim2.new(0, 0, 0, 1)
	Line.BackgroundColor3 = Theme.SeparatorLine
	Line.BorderSizePixel = 0
	Line.Parent = Row
	flexify(Line)

	return Row
end

local function buildButton(container, text, callback)
	local Btn = Instance.new("TextButton")
	Btn.Size = UDim2.new(1, 0, 0, 30)
	Btn.BackgroundColor3 = Theme.Element
	Btn.Text = text
	Btn.Font = Enum.Font.Gotham
	Btn.TextSize = 13
	Btn.TextColor3 = Theme.Text
	Btn.Parent = container
	corner(Btn, 4)

	Btn.MouseEnter:Connect(function()
		TS:Create(Btn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.ElementHover}):Play()
	end)
	Btn.MouseLeave:Connect(function()
		TS:Create(Btn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.Element}):Play()
	end)
	Btn.MouseButton1Click:Connect(function()
		if callback then callback() end
	end)
	return Btn
end

local function buildTextbox(container, text, default, placeholder, callback, flag)
	local value = default or ""
	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 30)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.45, 0, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local Box = Instance.new("TextBox")
	Box.Size = UDim2.new(0.55, -6, 0, 24)
	Box.Position = UDim2.new(0.45, 6, 0.5, -12)
	Box.BackgroundColor3 = Theme.Section
	Box.Text = value
	Box.PlaceholderText = placeholder or ""
	Box.ClearTextOnFocus = false
	Box.Font = Enum.Font.Gotham
	Box.TextSize = 12
	Box.TextColor3 = Theme.Text
	Box.PlaceholderColor3 = Theme.SubText
	Box.Parent = Holder
	corner(Box, 4)

	Box.FocusLost:Connect(function(enterPressed)
		value = Box.Text
		if callback then callback(value, enterPressed) end
		pushAutoSave()
	end)
	registerFlag(flag, {Get = function() return value end, Set = function(v)
		value = v
		Box.Text = v
	end})
	return {
		Set = function(v) value = v; Box.Text = v end,
		Get = function() return value end,
	}
end

local function buildKeybind(container, text, default, callback, flag)
	local key = default
	local listening = false
	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 30)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.Parent = container
	hoverTint(Holder)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -90, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local KeyLabel = Instance.new("TextLabel")
	KeyLabel.Size = UDim2.new(0, 80, 0, 22)
	KeyLabel.AnchorPoint = Vector2.new(1, 0.5)
	KeyLabel.Position = UDim2.new(1, 0, 0.5, 0)
	KeyLabel.BackgroundColor3 = Theme.Section
	KeyLabel.Text = key and key.Name or "None"
	KeyLabel.Font = Enum.Font.Gotham
	KeyLabel.TextSize = 12
	KeyLabel.TextColor3 = Theme.Accent
	KeyLabel.Parent = Holder
	corner(KeyLabel, 4)

	Holder.MouseButton1Click:Connect(function()
		listening = true
		KeyLabel.Text = "..."
	end)
	local conn
	conn = UIS.InputBegan:Connect(function(input, gpe)
		if listening and input.UserInputType == Enum.UserInputType.Keyboard then
			key = input.KeyCode
			KeyLabel.Text = key.Name
			listening = false
			if callback then callback(key, true) end
			pushAutoSave()
		elseif not listening and not gpe and key and input.KeyCode == key then
			if callback then callback(key, false) end
		end
	end)
	Holder.Destroying:Connect(function() conn:Disconnect() end)
	registerFlag(flag, {Get = function() return key and key.Name or "None" end, Set = function(v)
		key = Enum.KeyCode[v]
		KeyLabel.Text = key and key.Name or "None"
	end})
	return {Set = function(v)
		key = Enum.KeyCode[v]
		KeyLabel.Text = key and key.Name or "None"
	end}
end

local function buildProgressBar(container, text, min, max, default, format)
	min, max = min or 0, max or 100
	local value = default or min

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 34)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -70, 0, 16)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 12
	Label.TextColor3 = Theme.SubText
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	-- current value, top-right of the bar
	local ValueLabel = Instance.new("TextLabel")
	ValueLabel.Size = UDim2.new(0, 64, 0, 16)
	ValueLabel.AnchorPoint = Vector2.new(1, 0)
	ValueLabel.Position = UDim2.new(1, 0, 0, 0)
	ValueLabel.BackgroundTransparency = 1
	ValueLabel.Text = formatValue(format, value)
	ValueLabel.Font = Enum.Font.Gotham
	ValueLabel.TextSize = 12
	ValueLabel.TextColor3 = Theme.Accent
	ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
	ValueLabel.Parent = Holder

	local Track = Instance.new("Frame")
	Track.Size = UDim2.new(1, 0, 0, 8)
	Track.Position = UDim2.new(0, 0, 0, 20)
	Track.BackgroundColor3 = Theme.Section
	Track.Parent = Holder
	corner(Track, 4)

	local Fill = Instance.new("Frame")
	Fill.Size = UDim2.new((value - min) / math.max(1e-9, max - min), 0, 1, 0)
	Fill.BackgroundColor3 = Theme.Accent
	Fill.Parent = Track
	corner(Fill, 4)

	return {
		Set = function(v)
			value = math.clamp(v, min, max)
			Fill.Size = UDim2.new((value - min) / math.max(1e-9, max - min), 0, 1, 0)
			ValueLabel.Text = formatValue(format, value)
		end,
		Get = function() return value end,
	}
end

local function buildColorpicker(container, text, default, callback, flag)
	local color = default or Color3.fromRGB(255, 255, 255)
	local open = false
	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 30)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.ZIndex = 2
	Holder.Parent = container
	hoverTint(Holder)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -50, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local Preview = Instance.new("Frame")
	Preview.Size = UDim2.new(0, 34, 0, 18)
	Preview.AnchorPoint = Vector2.new(1, 0.5)
	Preview.Position = UDim2.new(1, 0, 0.5, 0)
	Preview.BackgroundColor3 = color
	Preview.Parent = Holder
	corner(Preview, 4)
	stroke(Preview, Theme.Border, 1)

	local Panel = Instance.new("Frame")
	Panel.Size = UDim2.new(1, 0, 0, 110)
	Panel.Position = UDim2.new(0, 0, 1, 2)
	Panel.BackgroundColor3 = Theme.Section
	Panel.Visible = false
	Panel.ZIndex = 5
	Panel.Parent = Holder
	corner(Panel, 4)
	stroke(Panel, Theme.Border, 1)

	local function makeSlider(labelText, yPos, initial)
		local L = Instance.new("TextLabel")
		L.Size = UDim2.new(0, 16, 0, 16)
		L.Position = UDim2.new(0, 8, 0, yPos)
		L.BackgroundTransparency = 1
		L.Text = labelText
		L.Font = Enum.Font.Gotham
		L.TextSize = 12
		L.TextColor3 = Theme.SubText
		L.ZIndex = 6
		L.Parent = Panel
		local Track = Instance.new("Frame")
		Track.Size = UDim2.new(1, -34, 0, 6)
		Track.Position = UDim2.new(0, 26, 0, yPos + 5)
		Track.BackgroundColor3 = Theme.Element
		Track.ZIndex = 6
		Track.Parent = Panel
		corner(Track, 3)
		local Fill = Instance.new("Frame")
		Fill.Size = UDim2.new(initial / 255, 0, 1, 0)
		Fill.BackgroundColor3 = Theme.Accent
		Fill.ZIndex = 6
		Fill.Parent = Track
		corner(Fill, 3)
		return Track, Fill
	end

	local rTrack, rFill = makeSlider("R", 6, color.R * 255)
	local gTrack, gFill = makeSlider("G", 30, color.G * 255)
	local bTrack, bFill = makeSlider("B", 54, color.B * 255)

	local r, g, b = color.R * 255, color.G * 255, color.B * 255
	local function update(fromUser)
		color = Color3.fromRGB(math.floor(r), math.floor(g), math.floor(b))
		Preview.BackgroundColor3 = color
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

	Holder.MouseButton1Click:Connect(function()
		open = not open
		Panel.Visible = open
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

	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 30)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.ZIndex = 2
	Holder.Parent = container
	hoverTint(Holder)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.5, 0, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local SelectedLabel = Instance.new("TextLabel")
	SelectedLabel.Size = UDim2.new(0.5, 0, 1, 0)
	SelectedLabel.Position = UDim2.new(0.5, 0, 0, 0)
	SelectedLabel.BackgroundTransparency = 1
	SelectedLabel.Font = Enum.Font.Gotham
	SelectedLabel.TextSize = 12
	SelectedLabel.TextColor3 = Theme.Accent
	SelectedLabel.TextXAlignment = Enum.TextXAlignment.Right
	SelectedLabel.TextTruncate = Enum.TextTruncate.AtEnd
	SelectedLabel.Parent = Holder

	local ListHolder = Instance.new("Frame")
	ListHolder.Position = UDim2.new(0, 0, 1, 2)
	ListHolder.BackgroundColor3 = Theme.Section
	ListHolder.Visible = false
	ListHolder.ZIndex = 5
	ListHolder.Parent = Holder
	corner(ListHolder, 4)
	stroke(ListHolder, Theme.Border, 1)
	local ListLayout = Instance.new("UIListLayout")
	ListLayout.Parent = ListHolder

	local function refreshLabel()
		local names = {}
		for _, opt in ipairs(currentOptions) do
			if selected[opt] then table.insert(names, tostring(opt)) end
		end
		SelectedLabel.Text = #names > 0 and table.concat(names, ", ") or "None"
	end

	local function build()
		for _, c in ipairs(ListHolder:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 26)
		for _, opt in ipairs(currentOptions) do
			local OptBtn = Instance.new("TextButton")
			OptBtn.Size = UDim2.new(1, 0, 0, 26)
			OptBtn.BackgroundColor3 = selected[opt] and Theme.Accent or Theme.Section
			OptBtn.Text = tostring(opt)
			OptBtn.Font = Enum.Font.Gotham
			OptBtn.TextSize = 12
			OptBtn.TextColor3 = Theme.Text
			OptBtn.ZIndex = 6
			OptBtn.Parent = ListHolder
			OptBtn.MouseButton1Click:Connect(function()
				selected[opt] = not selected[opt] or nil
				OptBtn.BackgroundColor3 = selected[opt] and Theme.Accent or Theme.Section
				refreshLabel()
				if callback then callback(selected) end
				pushAutoSave()
			end)
		end
	end
	build()
	refreshLabel()

	Holder.MouseButton1Click:Connect(function()
		open = not open
		ListHolder.Visible = open
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

local function buildToggle(container, text, default, callback, flag)
	local state = default or false

	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 30)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.Parent = container
	hoverTint(Holder)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -50, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local Box = Instance.new("Frame")
	Box.Size = UDim2.new(0, 34, 0, 18)
	Box.AnchorPoint = Vector2.new(1, 0.5)
	Box.Position = UDim2.new(1, 0, 0.5, 0)
	Box.BackgroundColor3 = state and Theme.Accent or Theme.Section
	Box.Parent = Holder
	corner(Box, 9)

	local Dot = Instance.new("Frame")
	Dot.Size = UDim2.new(0, 14, 0, 14)
	Dot.Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
	Dot.BackgroundColor3 = Theme.Text
	Dot.Parent = Box
	corner(Dot, 7)

	local function visual()
		TS:Create(Box, TweenInfo.new(0.15), {BackgroundColor3 = state and Theme.Accent or Theme.Section}):Play()
		TS:Create(Dot, TweenInfo.new(0.15), {Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}):Play()
	end

	local function setState(v, fromUser)
		state = v
		visual()
		if callback then callback(state) end
		if fromUser then pushAutoSave() end
	end

	Holder.MouseButton1Click:Connect(function()
		setState(not state, true)
	end)

	registerFlag(flag, {Get = function() return state end, Set = function(v) setState(v, false) end})

	if callback then callback(state) end
	return {Set = function(v) setState(v, false) end, Get = function() return state end}
end

-- Compact classic checkbox (square + check), meant to be cheap to place
-- several of in a row, unlike the big pill Toggle above.
local function buildCheckbox(container, text, default, callback, flag)
	local state = default or false

	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 22)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.Parent = container

	local Box = Instance.new("Frame")
	Box.Size = UDim2.new(0, 16, 0, 16)
	Box.AnchorPoint = Vector2.new(0, 0.5)
	Box.Position = UDim2.new(0, 0, 0.5, 0)
	Box.BackgroundColor3 = Theme.Section
	Box.Parent = Holder
	corner(Box, 4)
	stroke(Box, Theme.Border, 1)

	local Check = Instance.new("Frame")
	Check.Size = UDim2.new(0, 10, 0, 10)
	Check.Position = UDim2.new(0.5, -5, 0.5, -5)
	Check.BackgroundColor3 = Theme.Accent
	Check.Visible = state
	Check.Parent = Box
	corner(Check, 2)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -22, 1, 0)
	Label.Position = UDim2.new(0, 22, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextTruncate = Enum.TextTruncate.AtEnd
	Label.Parent = Holder

	local function setState(v, fromUser)
		state = v
		Check.Visible = state
		if callback then callback(state) end
		if fromUser then pushAutoSave() end
	end

	Holder.MouseButton1Click:Connect(function() setState(not state, true) end)
	registerFlag(flag, {Get = function() return state end, Set = function(v) setState(v, false) end})
	if callback then callback(state) end

	return Holder, {Set = function(v) setState(v, false) end, Get = function() return state end}
end

local function buildSlider(container, text, min, max, default, callback, flag)
	min = min or 0
	max = max or 100
	local value = default or min

	local Holder = Instance.new("Frame")
	Holder.Size = UDim2.new(1, 0, 0, 44)
	Holder.BackgroundTransparency = 1
	Holder.Parent = container

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -60, 0, 18)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local ValueLabel = Instance.new("TextLabel")
	ValueLabel.Size = UDim2.new(0, 50, 0, 18)
	ValueLabel.AnchorPoint = Vector2.new(1, 0)
	ValueLabel.Position = UDim2.new(1, 0, 0, 0)
	ValueLabel.BackgroundTransparency = 1
	ValueLabel.Text = tostring(value)
	ValueLabel.Font = Enum.Font.Gotham
	ValueLabel.TextSize = 13
	ValueLabel.TextColor3 = Theme.SubText
	ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
	ValueLabel.Parent = Holder

	local Track = Instance.new("Frame")
	Track.Size = UDim2.new(1, 0, 0, 6)
	Track.Position = UDim2.new(0, 0, 0, 28)
	Track.BackgroundColor3 = Theme.Section
	Track.Parent = Holder
	corner(Track, 3)

	local Fill = Instance.new("Frame")
	Fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
	Fill.BackgroundColor3 = Theme.Accent
	Fill.Parent = Track
	corner(Fill, 3)

	local function apply(v)
		value = math.clamp(v, min, max)
		local rel = (value - min) / (max - min)
		Fill.Size = UDim2.new(rel, 0, 1, 0)
		ValueLabel.Text = tostring(value)
		if callback then callback(value) end
	end

	local function setFromX(x)
		local rel = math.clamp((x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
		apply(math.floor(min + (max - min) * rel))
	end

	Track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
			ActiveSlider = {
				Update = setFromX,
				Release = pushAutoSave,
			}
		end
	end)

	registerFlag(flag, {Get = function() return value end, Set = function(v) apply(v) end})

	if callback then callback(value) end
	return {Set = function(v) apply(v) end, Get = function() return value end}
end

local function buildDropdown(container, text, options, default, callback, flag)
	local selected = default or options[1]
	local open = false
	local currentOptions = options

	local Holder = Instance.new("TextButton")
	Holder.Size = UDim2.new(1, 0, 0, 30)
	Holder.BackgroundTransparency = 1
	Holder.Text = ""
	Holder.AutoButtonColor = false
	Holder.ClipsDescendants = false
	Holder.ZIndex = 2
	Holder.Parent = container
	hoverTint(Holder)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.5, 0, 1, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.Font = Enum.Font.Gotham
	Label.TextSize = 13
	Label.TextColor3 = Theme.Text
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Holder

	local SelectedLabel = Instance.new("TextLabel")
	SelectedLabel.Size = UDim2.new(0.5, 0, 1, 0)
	SelectedLabel.Position = UDim2.new(0.5, 0, 0, 0)
	SelectedLabel.BackgroundTransparency = 1
	SelectedLabel.Text = tostring(selected)
	SelectedLabel.Font = Enum.Font.Gotham
	SelectedLabel.TextSize = 13
	SelectedLabel.TextColor3 = Theme.Accent
	SelectedLabel.TextXAlignment = Enum.TextXAlignment.Right
	SelectedLabel.Parent = Holder

	local ListHolder = Instance.new("Frame")
	ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 26)
	ListHolder.Position = UDim2.new(0, 0, 1, 2)
	ListHolder.BackgroundColor3 = Theme.Section
	ListHolder.Visible = false
	ListHolder.ZIndex = 5
	ListHolder.Parent = Holder
	corner(ListHolder, 4)
	stroke(ListHolder, Theme.Border, 1)

	local ListLayout = Instance.new("UIListLayout")
	ListLayout.Parent = ListHolder

	local function selectOption(opt, fromUser)
		selected = opt
		SelectedLabel.Text = tostring(opt)
		ListHolder.Visible = false
		open = false
		if callback then callback(opt) end
		if fromUser then pushAutoSave() end
	end

	local function build()
		for _, child in ipairs(ListHolder:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 26)
		for _, opt in ipairs(currentOptions) do
			local OptBtn = Instance.new("TextButton")
			OptBtn.Size = UDim2.new(1, 0, 0, 26)
			OptBtn.BackgroundColor3 = Theme.Section
			OptBtn.Text = tostring(opt)
			OptBtn.Font = Enum.Font.Gotham
			OptBtn.TextSize = 12
			OptBtn.TextColor3 = Theme.Text
			OptBtn.ZIndex = 6
			OptBtn.Parent = ListHolder

			OptBtn.MouseButton1Click:Connect(function()
				selectOption(opt, true)
			end)
		end
	end

	build()

	Holder.MouseButton1Click:Connect(function()
		open = not open
		ListHolder.Visible = open
	end)

	registerFlag(flag, {Get = function() return selected end, Set = function(v) selectOption(v, false) end})

	if callback then callback(selected) end

	return {
		Set = function(v) selectOption(v, false) end,
		Get = function() return selected end,
		Refresh = function(newOptions, keepSelection)
			currentOptions = newOptions
			build()
			if not keepSelection or not table.find(newOptions, selected) then
				selected = newOptions[1]
				SelectedLabel.Text = tostring(selected)
			end
		end,
		GetOptions = function() return currentOptions end,
	}
end

-- ============================================================
-- Row ("SameLine"): a single item-frame that can hold several
-- compact widgets side by side, e.g. a slider on the left + a plain
-- text label on the right, or N checkboxes sharing the row equally.
-- Pass widthScale (0..1) to any Row:Add* call to give it a fixed
-- share of the row; leave it out to flex-fill the remaining space.
-- ============================================================

local function buildRow(container, height, gap)
	local RowFrame = Instance.new("Frame")
	RowFrame.Size = UDim2.new(1, 0, 0, height or 24)
	RowFrame.BackgroundTransparency = 1
	RowFrame.Parent = container

	local RowLayout = Instance.new("UIListLayout")
	RowLayout.FillDirection = Enum.FillDirection.Horizontal
	RowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	RowLayout.Padding = UDim.new(0, gap or 10)
	RowLayout.Parent = RowFrame

	local Row = {}

	function Row:AddText(text, widthScale)
		local Label = Instance.new("TextLabel")
		Label.BackgroundTransparency = 1
		Label.Text = text
		Label.Font = Enum.Font.Gotham
		Label.TextSize = 13
		Label.TextColor3 = Theme.SubText
		Label.TextXAlignment = Enum.TextXAlignment.Left
		Label.TextTruncate = Enum.TextTruncate.AtEnd
		Label.Parent = RowFrame
		flexify(Label, widthScale)
		return Label
	end

	function Row:AddCheckbox(text, default, callback, flag, widthScale)
		local Holder, api = buildCheckbox(RowFrame, text, default, callback, flag)
		flexify(Holder, widthScale)
		return api
	end

	-- Compact inline slider: value is shown centered on the bar itself
	-- (like the reference "drag int/float" widgets) instead of above it,
	-- so it stays cheap on vertical space when paired with Row:AddText.
	function Row:AddSlider(text, min, max, default, callback, flag, widthScale)
		min, max = min or 0, max or 100
		local value = default or min

		local Holder = Instance.new("Frame")
		Holder.Size = UDim2.new(0, 0, 1, 0)
		Holder.BackgroundTransparency = 1
		Holder.Parent = RowFrame

		local Track = Instance.new("Frame")
		Track.Size = UDim2.new(1, 0, 0, 18)
		Track.AnchorPoint = Vector2.new(0, 0.5)
		Track.Position = UDim2.new(0, 0, 0.5, 0)
		Track.BackgroundColor3 = Theme.Section
		Track.Parent = Holder
		corner(Track, 4)

		local Fill = Instance.new("Frame")
		Fill.Size = UDim2.new((value - min) / math.max(1e-9, max - min), 0, 1, 0)
		Fill.BackgroundColor3 = Theme.Accent
		Fill.BackgroundTransparency = 0.3
		Fill.Parent = Track
		corner(Fill, 4)

		local ValueLabel = Instance.new("TextLabel")
		ValueLabel.Size = UDim2.new(1, 0, 1, 0)
		ValueLabel.BackgroundTransparency = 1
		ValueLabel.Text = (text and (text .. ": ") or "") .. tostring(value)
		ValueLabel.Font = Enum.Font.Gotham
		ValueLabel.TextSize = 12
		ValueLabel.TextColor3 = Theme.Text
		ValueLabel.ZIndex = 2
		ValueLabel.Parent = Track

		local function apply(v)
			value = math.clamp(v, min, max)
			Fill.Size = UDim2.new((value - min) / math.max(1e-9, max - min), 0, 1, 0)
			ValueLabel.Text = (text and (text .. ": ") or "") .. tostring(value)
			if callback then callback(value) end
		end

		local function setFromX(x)
			local rel = math.clamp((x - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
			apply(math.floor(min + (max - min) * rel))
		end

		Track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				setFromX(input.Position.X)
				ActiveSlider = {Update = setFromX, Release = pushAutoSave}
			end
		end)

		flexify(Holder, widthScale or 0.5)
		registerFlag(flag, {Get = function() return value end, Set = function(v) apply(v) end})
		if callback then callback(value) end
		return {Set = function(v) apply(v) end, Get = function() return value end}
	end

	return Row
end

-- ============================================================
-- Section (collapsible group box). Its content is indented from the
-- left so nesting is readable, and its right edge lines up with the
-- rest of the tab instead of leaving a dead gap — that's the bug the
-- old fixed-offset math used to cause (indent applied to position but
-- not width, so rows looked flush-left with empty space on the right).
-- Using UIPadding on the content frame sidesteps that class of bug.
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
	SectionLayout.Padding = UDim.new(0, 6)
	SectionLayout.Parent = SectionFrame

	local Header = Instance.new("TextButton")
	Header.Size = UDim2.new(1, 0, 0, 20)
	Header.BackgroundTransparency = 1
	Header.Text = ""
	Header.AutoButtonColor = false
	Header.Parent = SectionFrame

	local HeaderLayout = Instance.new("UIListLayout")
	HeaderLayout.FillDirection = Enum.FillDirection.Horizontal
	HeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	HeaderLayout.Padding = UDim.new(0, 6)
	HeaderLayout.Parent = Header

	local Arrow = Instance.new("TextLabel")
	Arrow.Size = UDim2.new(0, 12, 1, 0)
	Arrow.BackgroundTransparency = 1
	Arrow.Font = Enum.Font.GothamBold
	Arrow.TextSize = 11
	Arrow.TextColor3 = Theme.SubText
	Arrow.Text = collapsed and "▸" or "▾"
	Arrow.Parent = Header

	local TitleLbl = Instance.new("TextLabel")
	TitleLbl.AutomaticSize = Enum.AutomaticSize.X
	TitleLbl.Size = UDim2.new(0, 0, 1, 0)
	TitleLbl.BackgroundTransparency = 1
	TitleLbl.Font = Enum.Font.GothamBold
	TitleLbl.TextSize = 12
	TitleLbl.TextColor3 = Theme.SubText
	TitleLbl.Text = title
	TitleLbl.Parent = Header

	local HLine = Instance.new("Frame")
	HLine.Size = UDim2.new(0, 0, 0, 1)
	HLine.BackgroundColor3 = Theme.SeparatorLine
	HLine.BorderSizePixel = 0
	HLine.Parent = Header
	flexify(HLine)

	local Content = Instance.new("Frame")
	Content.Size = UDim2.new(1, 0, 0, 0)
	Content.AutomaticSize = Enum.AutomaticSize.Y
	Content.BackgroundTransparency = 1
	Content.Visible = not collapsed
	Content.Parent = SectionFrame

	-- The fix: indent via UIPadding (both sides), not manual offsets.
	-- Left padding creates the "this is nested" cue; right padding is 0
	-- so content still reaches the same right edge as everything else.
	local ContentPad = Instance.new("UIPadding")
	ContentPad.PaddingLeft = UDim.new(0, 14)
	ContentPad.PaddingRight = UDim.new(0, 0)
	ContentPad.Parent = Content

	local ContentLayout = Instance.new("UIListLayout")
	ContentLayout.Padding = UDim.new(0, 6)
	ContentLayout.Parent = Content

	Header.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		Content.Visible = not collapsed
		Arrow.Text = collapsed and "▸" or "▾"
	end)

	return Content
end

-- ============================================================
-- Scope: the shared API surface for both a tab's Page and any
-- Section's Content frame, so AddSection can nest freely and every
-- widget type is available at every nesting level.
-- ============================================================

local function buildScope(container)
	local Scope = {}

	function Scope:AddLabel(text) return buildLabel(container, text) end
	function Scope:AddSeparator(text) return buildSeparator(container, text) end
	function Scope:AddButton(text, callback) return buildButton(container, text, callback) end
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
	function Scope:AddToggle(text, default, callback, flag)
		return buildToggle(container, text, default, callback, flag)
	end
	function Scope:AddCheckbox(text, default, callback, flag)
		local _, api = buildCheckbox(container, text, default, callback, flag)
		return api
	end
	function Scope:AddSlider(text, min, max, default, callback, flag)
		return buildSlider(container, text, min, max, default, callback, flag)
	end
	function Scope:AddDropdown(text, options, default, callback, flag)
		return buildDropdown(container, text, options, default, callback, flag)
	end
	function Scope:AddRow(height, gap)
		return buildRow(container, height, gap)
	end
	function Scope:AddSection(title, opts)
		local Content = buildSectionHeader(container, title, opts)
		return buildScope(Content)
	end

	return Scope
end

function Library:CreateWindow(title, pos, size)
	local screenGui = getScreenGui()
	local offset = #Library.Windows * 30

	local Window = {}
	Window.Categories = {}
	Window.Collapsed = false

	local Main = Instance.new("Frame")
	Main.Name = title
	Main.Size = size or UDim2.new(0, 320, 0, 400)
	Main.Position = pos or UDim2.new(0, 100 + offset, 0, 100 + offset)
	Main.BackgroundColor3 = Theme.Background
	Main.BorderSizePixel = 0
	Main.Parent = screenGui
	corner(Main, 6)
	stroke(Main, Theme.Border, 1)

	local TitleBar = Instance.new("Frame")
	TitleBar.Name = "TitleBar"
	TitleBar.Size = UDim2.new(1, 0, 0, 32)
	TitleBar.BackgroundColor3 = Theme.Header
	TitleBar.BorderSizePixel = 0
	TitleBar.Parent = Main
	corner(TitleBar, 6)

	local TitleFix = Instance.new("Frame")
	TitleFix.Size = UDim2.new(1, 0, 0, 10)
	TitleFix.Position = UDim2.new(0, 0, 1, -10)
	TitleFix.BackgroundColor3 = Theme.Header
	TitleFix.BorderSizePixel = 0
	TitleFix.Parent = TitleBar

	local TitleLabel = Instance.new("TextLabel")
	TitleLabel.BackgroundTransparency = 1
	TitleLabel.Size = UDim2.new(1, -40, 1, 0)
	TitleLabel.Position = UDim2.new(0, 10, 0, 0)
	TitleLabel.Font = Enum.Font.GothamBold
	TitleLabel.TextSize = 14
	TitleLabel.TextColor3 = Theme.Text
	TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	TitleLabel.Text = title
	TitleLabel.Parent = TitleBar

	local CollapseBtn = Instance.new("TextButton")
	CollapseBtn.Size = UDim2.new(0, 26, 0, 26)
	CollapseBtn.Position = UDim2.new(1, -30, 0, 3)
	CollapseBtn.BackgroundColor3 = Theme.HeaderDark
	CollapseBtn.Text = "▾"
	CollapseBtn.Font = Enum.Font.GothamBold
	CollapseBtn.TextSize = 16
	CollapseBtn.TextColor3 = Theme.Text
	CollapseBtn.Parent = TitleBar
	corner(CollapseBtn, 4)

	local Body = Instance.new("Frame")
	Body.Name = "Body"
	Body.Size = UDim2.new(1, 0, 1, -32)
	Body.Position = UDim2.new(0, 0, 0, 32)
	Body.BackgroundTransparency = 1
	Body.ClipsDescendants = true
	Body.Parent = Main

	local Tabs = Instance.new("Frame")
	Tabs.Name = "Tabs"
	Tabs.Size = UDim2.new(1, -10, 0, 28)
	Tabs.Position = UDim2.new(0, 5, 0, 5)
	Tabs.BackgroundTransparency = 1
	Tabs.Parent = Body

	local TabsLayout = Instance.new("UIListLayout")
	TabsLayout.FillDirection = Enum.FillDirection.Horizontal
	TabsLayout.Padding = UDim.new(0, 4)
	TabsLayout.Parent = Tabs

	local Pages = Instance.new("Frame")
	Pages.Name = "Pages"
	Pages.Size = UDim2.new(1, -10, 1, -40)
	Pages.Position = UDim2.new(0, 5, 0, 38)
	Pages.BackgroundTransparency = 1
	Pages.Parent = Body

	local fullSize = Main.Size
    CollapseBtn.MouseButton1Click:Connect(function()
        Window.Collapsed = not Window.Collapsed
        if Window.Collapsed then
            CollapseBtn.Text = "▸"
            TS:Create(Main, TweenInfo.new(0.2), {Size = UDim2.new(fullSize.X.Scale, fullSize.X.Offset, 0, 32)}):Play()
        else
            CollapseBtn.Text = "▾"
            TS:Create(Main, TweenInfo.new(0.2), {Size = fullSize}):Play()
        end
    end)

    makeDraggable(TitleBar, Main)

    -- ==== RESIZE HANDLE ====
    local ResizeHandle = Instance.new("Frame")
    ResizeHandle.Size = UDim2.new(0, 16, 0, 16)
    ResizeHandle.Position = UDim2.new(1, -16, 1, -16)
    ResizeHandle.BackgroundTransparency = 1
    ResizeHandle.Parent = Main
    ResizeHandle.ZIndex = 10

    local ResizeIcon = Instance.new("TextLabel")
    ResizeIcon.Size = UDim2.new(1, 0, 1, 0)
    ResizeIcon.BackgroundTransparency = 1
    ResizeIcon.Text = "◢"
    ResizeIcon.Font = Enum.Font.GothamBold
    ResizeIcon.TextSize = 14
    ResizeIcon.TextColor3 = Theme.SubText
    ResizeIcon.Parent = ResizeHandle

    local resizing = false
    local resizeStart, startSize
    local MIN_SIZE = Vector2.new(240, 150)

    ResizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if Window.Collapsed then return end
            resizing = true
            resizeStart = input.Position
            startSize = Main.Size
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    resizing = false
                end
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
        TabBtn.Size = UDim2.new(0, 90, 1, 0)
        TabBtn.BackgroundColor3 = Theme.Element
        TabBtn.Text = name
        TabBtn.Font = Enum.Font.Gotham
        TabBtn.TextSize = 13
        TabBtn.TextColor3 = Theme.SubText
        TabBtn.Parent = Tabs
        corner(TabBtn, 4)

        local Page = Instance.new("ScrollingFrame")
        Page.Size = UDim2.new(1, 0, 1, 0)
        Page.BackgroundTransparency = 1
        Page.BorderSizePixel = 0
        Page.ScrollBarThickness = 4
        Page.ScrollBarImageColor3 = Theme.Accent
        Page.CanvasSize = UDim2.new(0, 0, 0, 0)
        Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        Page.Visible = false
        Page.Parent = Pages

        -- small left inset + a bit more on the right so content clears
        -- the scrollbar instead of being flush underneath it
        local PagePad = Instance.new("UIPadding")
        PagePad.PaddingLeft = UDim.new(0, 2)
        PagePad.PaddingRight = UDim.new(0, 8)
        PagePad.Parent = Page

        local Layout = Instance.new("UIListLayout")
        Layout.Padding = UDim.new(0, 6)
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

        if #Window.Categories == 1 then
            select()
        end

        return Category
    end

	function Window:Destroy()
		Main:Destroy()
		for i, w in ipairs(Library.Windows) do
			if w == Window then
				table.remove(Library.Windows, i)
				break
			end
		end
	end

	function Window:SetVisible(visible)
		Main.Visible = visible
	end

	table.insert(Library.Windows, Window)
	return Window
end

function Library:CreateConfigTab(Window, categoryName)
	local Category = Window:AddCategory(categoryName or "Settings")

	Category:AddLabel("Config Manager")

	local nameBox = Category:AddTextbox("Config Name", "", "config adı yaz...")

	local function getConfigList()
		local list = Library:ListConfigs()
		return #list > 0 and list or {"None"}
	end

	local configDropdown = Category:AddDropdown("Saved Configs", getConfigList(), nil, nil, nil)

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
			configDropdown.Refresh(getConfigList())
		end
	end)

	Category:AddToggle("Auto Save", Library.AutoSaveEnabled, function(v)
		local name = configDropdown.Get()
		Library:SetAutoSave(v, name ~= "None" and name or nil)
	end)

	return Category
end

return Library
