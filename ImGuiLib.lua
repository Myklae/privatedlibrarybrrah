local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Theme = {
	Background = Color3.fromRGB(15, 15, 15),
	Header = Color3.fromRGB(41, 74, 122),
	HeaderDark = Color3.fromRGB(28, 50, 84),
	Section = Color3.fromRGB(29, 47, 73),
	Element = Color3.fromRGB(36, 69, 109),
	ElementHover = Color3.fromRGB(66, 150, 250),
	Accent = Color3.fromRGB(66, 150, 250),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(140, 140, 140),
	Border = Color3.fromRGB(65, 65, 72),
}

local Library = {}
Library.__index = Library
Library.Windows = {}
Library.Flags = {}
Library.ConfigFolder = "ImGuiConfigs"
Library.AutoSaveEnabled = false
Library.CurrentConfig = nil

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 2)
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
	corner(Main, 3)
	stroke(Main, Theme.Border, 1)

	local TitleBar = Instance.new("Frame")
	TitleBar.Name = "TitleBar"
	TitleBar.Size = UDim2.new(1, 0, 0, 26)
	TitleBar.BackgroundColor3 = Theme.Header
	TitleBar.BorderSizePixel = 0
	TitleBar.Parent = Main
	corner(TitleBar, 3)

	local TitleFix = Instance.new("Frame")
	TitleFix.Size = UDim2.new(1, 0, 0, 10)
	TitleFix.Position = UDim2.new(0, 0, 1, -10)
	TitleFix.BackgroundColor3 = Theme.Header
	TitleFix.BorderSizePixel = 0
	TitleFix.Parent = TitleBar

	local TitleBottomLine = Instance.new("Frame")
	TitleBottomLine.Size = UDim2.new(1, 0, 0, 1)
	TitleBottomLine.Position = UDim2.new(0, 0, 1, 0)
	TitleBottomLine.BackgroundColor3 = Theme.Border
	TitleBottomLine.BorderSizePixel = 0
	TitleBottomLine.Parent = TitleBar

	local TitleLabel = Instance.new("TextLabel")
	TitleLabel.BackgroundTransparency = 1
	TitleLabel.Size = UDim2.new(1, -40, 1, 0)
	TitleLabel.Position = UDim2.new(0, 8, 0, 0)
	TitleLabel.Font = Enum.Font.Code
	TitleLabel.TextSize = 14
	TitleLabel.TextColor3 = Theme.Text
	TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	TitleLabel.Text = title
	TitleLabel.Parent = TitleBar

	local CollapseBtn = Instance.new("TextButton")
	CollapseBtn.Size = UDim2.new(0, 20, 0, 20)
	CollapseBtn.Position = UDim2.new(1, -24, 0, 3)
	CollapseBtn.BackgroundColor3 = Theme.HeaderDark
	CollapseBtn.Text = "-"
	CollapseBtn.Font = Enum.Font.Code
	CollapseBtn.TextSize = 16
	CollapseBtn.TextColor3 = Theme.Text
	CollapseBtn.Parent = TitleBar
	corner(CollapseBtn, 2)
	stroke(CollapseBtn, Theme.Border, 1)

	local Body = Instance.new("Frame")
	Body.Name = "Body"
	Body.Size = UDim2.new(1, 0, 1, -26)
	Body.Position = UDim2.new(0, 0, 0, 26)
	Body.BackgroundTransparency = 1
	Body.ClipsDescendants = true
	Body.Parent = Main

	local Tabs = Instance.new("Frame")
	Tabs.Name = "Tabs"
	Tabs.Size = UDim2.new(1, -10, 0, 24)
	Tabs.Position = UDim2.new(0, 5, 0, 5)
	Tabs.BackgroundTransparency = 1
	Tabs.Parent = Body

	local TabsLayout = Instance.new("UIListLayout")
	TabsLayout.FillDirection = Enum.FillDirection.Horizontal
	TabsLayout.Padding = UDim.new(0, 2)
	TabsLayout.Parent = Tabs

	local Pages = Instance.new("Frame")
	Pages.Name = "Pages"
	Pages.Size = UDim2.new(1, -10, 1, -36)
	Pages.Position = UDim2.new(0, 5, 0, 34)
	Pages.BackgroundTransparency = 1
	Pages.Parent = Body

	local fullSize = Main.Size
    CollapseBtn.MouseButton1Click:Connect(function()
        Window.Collapsed = not Window.Collapsed
        if Window.Collapsed then
            CollapseBtn.Text = "+"
            TS:Create(Main, TweenInfo.new(0.2), {Size = UDim2.new(fullSize.X.Scale, fullSize.X.Offset, 0, 26)}):Play()
        else
            CollapseBtn.Text = "-"
            TS:Create(Main, TweenInfo.new(0.2), {Size = fullSize}):Play()
        end
    end)

    makeDraggable(TitleBar, Main)

    -- ==== RESIZE HANDLE ====
    local ResizeHandle = Instance.new("Frame")
    ResizeHandle.Size = UDim2.new(0, 14, 0, 14)
    ResizeHandle.Position = UDim2.new(1, -14, 1, -14)
    ResizeHandle.BackgroundTransparency = 1
    ResizeHandle.Parent = Main
    ResizeHandle.ZIndex = 10

    local ResizeIcon = Instance.new("Frame")
    ResizeIcon.Size = UDim2.new(0, 8, 0, 8)
    ResizeIcon.Position = UDim2.new(1, -10, 1, -10)
    ResizeIcon.BackgroundTransparency = 1
    ResizeIcon.Parent = ResizeHandle
    do
        for i = 1, 3 do
            local line = Instance.new("Frame")
            line.Size = UDim2.new(0, i * 3, 0, 1)
            line.Position = UDim2.new(1, -i * 3, 1, -1)
            line.BackgroundColor3 = Theme.SubText
            line.BorderSizePixel = 0
            line.Parent = ResizeIcon
        end
    end

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
        local Category = {}

        local TabBtn = Instance.new("TextButton")
        TabBtn.Size = UDim2.new(0, 84, 1, 0)
        TabBtn.BackgroundColor3 = Theme.HeaderDark
        TabBtn.Text = name
        TabBtn.Font = Enum.Font.Code
        TabBtn.TextSize = 13
        TabBtn.TextColor3 = Theme.SubText
        TabBtn.Parent = Tabs
        corner(TabBtn, 2)

        local TabUnderline = Instance.new("Frame")
        TabUnderline.Name = "TabUnderline"
        TabUnderline.Size = UDim2.new(1, 0, 0, 2)
        TabUnderline.Position = UDim2.new(0, 0, 1, -2)
        TabUnderline.BackgroundColor3 = Theme.Accent
        TabUnderline.BorderSizePixel = 0
        TabUnderline.Visible = false
        TabUnderline.Parent = TabBtn

        local Page = Instance.new("ScrollingFrame")
        Page.Size = UDim2.new(1, 0, 1, 0)
        Page.BackgroundTransparency = 1
        Page.BorderSizePixel = 0
        Page.ScrollBarThickness = 3
        Page.ScrollBarImageColor3 = Theme.Element
        Page.CanvasSize = UDim2.new(0, 0, 0, 0)
        Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        Page.Visible = false
        Page.Parent = Pages

        local Layout = Instance.new("UIListLayout")
        Layout.Padding = UDim.new(0, 4)
        Layout.Parent = Page

        local function select()
            for _, c in ipairs(Window.Categories) do
                c.Page.Visible = false
                c.TabBtn.BackgroundColor3 = Theme.HeaderDark
                c.TabBtn.TextColor3 = Theme.SubText
                c.TabBtn.TabUnderline.Visible = false
            end
            Page.Visible = true
            TabBtn.BackgroundColor3 = Theme.Section
            TabBtn.TextColor3 = Theme.Text
            TabUnderline.Visible = true
        end

        TabBtn.MouseButton1Click:Connect(select)

        Category.Page = Page
        Category.TabBtn = TabBtn
        table.insert(Window.Categories, Category)

        if #Window.Categories == 1 then
            select()
        end

        function Category:AddLabel(text)
            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.new(1, 0, 0, 18)
            Label.BackgroundTransparency = 1
            Label.Text = text
            Label.Font = Enum.Font.Code
            Label.TextSize = 13
            Label.TextColor3 = Theme.SubText
            Label.TextXAlignment = Enum.TextXAlignment.Left
            Label.Parent = Page
            return Label
        end

        function Category:AddButton(text, callback)
            local Btn = Instance.new("TextButton")
            Btn.Size = UDim2.new(1, 0, 0, 26)
            Btn.BackgroundColor3 = Theme.Element
            Btn.Text = text
            Btn.Font = Enum.Font.Code
            Btn.TextSize = 13
            Btn.TextColor3 = Theme.Text
            Btn.Parent = Page
            corner(Btn, 2)
            stroke(Btn, Theme.Border, 1)

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

				-- ==== TEXTBOX ====
		function Category:AddTextbox(text, default, placeholder, callback, flag)
			local value = default or ""
			local Holder = Instance.new("Frame")
			Holder.Size = UDim2.new(1, 0, 0, 26)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)
			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(0.45, 0, 1, 0)
			Label.Position = UDim2.new(0, 8, 0, 0)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 13
			Label.TextColor3 = Theme.Text
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder
			local Box = Instance.new("TextBox")
			Box.Size = UDim2.new(0.5, -8, 0, 20)
			Box.Position = UDim2.new(0.5, 0, 0.5, -10)
			Box.BackgroundColor3 = Theme.Section
			Box.Text = value
			Box.PlaceholderText = placeholder or ""
			Box.ClearTextOnFocus = false
			Box.Font = Enum.Font.Code
			Box.TextSize = 12
			Box.TextColor3 = Theme.Text
			Box.PlaceholderColor3 = Theme.SubText
			Box.Parent = Holder
			corner(Box, 2)
			stroke(Box, Theme.Border, 1)
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

		-- ==== KEYBIND ====
		function Category:AddKeybind(text, default, callback, flag)
			local key = default
			local listening = false
			local Holder = Instance.new("TextButton")
			Holder.Size = UDim2.new(1, 0, 0, 26)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Text = ""
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)
			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(1, -90, 1, 0)
			Label.Position = UDim2.new(0, 8, 0, 0)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 13
			Label.TextColor3 = Theme.Text
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder
			local KeyLabel = Instance.new("TextLabel")
			KeyLabel.Size = UDim2.new(0, 80, 0, 20)
			KeyLabel.Position = UDim2.new(1, -86, 0.5, -10)
			KeyLabel.BackgroundColor3 = Theme.Section
			KeyLabel.Text = key and key.Name or "None"
			KeyLabel.Font = Enum.Font.Code
			KeyLabel.TextSize = 12
			KeyLabel.TextColor3 = Theme.Accent
			KeyLabel.Parent = Holder
			corner(KeyLabel, 2)
			stroke(KeyLabel, Theme.Border, 1)
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

		-- ==== PROGRESS BAR ====
		function Category:AddProgressBar(text, min, max, default, format)
			min, max = min or 0, max or 100
			local value = default or min
			local Holder = Instance.new("Frame")
			Holder.Size = UDim2.new(1, 0, 0, 32)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)
			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(1, -16, 0, 15)
			Label.Position = UDim2.new(0, 8, 0, 2)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 12
			Label.TextColor3 = Theme.SubText
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder
			local Track = Instance.new("Frame")
			Track.Size = UDim2.new(1, -16, 0, 8)
			Track.Position = UDim2.new(0, 8, 0, 19)
			Track.BackgroundColor3 = Theme.Section
			Track.Parent = Holder
			corner(Track, 2)
			stroke(Track, Theme.Border, 1)
			local Fill = Instance.new("Frame")
			Fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
			Fill.BackgroundColor3 = Theme.Accent
			Fill.Parent = Track
			corner(Fill, 2)
			-- Not: tween kullanılmıyor (sürekli update'lerde performans için anlık set)
			return {Set = function(v)
				value = math.clamp(v, min, max)
				Fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
			end}
		end

				-- ==== COLORPICKER ====
		function Category:AddColorpicker(text, default, callback, flag)
			local color = default or Color3.fromRGB(255, 255, 255)
			local open = false
			local Holder = Instance.new("TextButton")
			Holder.Size = UDim2.new(1, 0, 0, 26)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Text = ""
			Holder.ZIndex = 2
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)
			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(1, -50, 1, 0)
			Label.Position = UDim2.new(0, 8, 0, 0)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 13
			Label.TextColor3 = Theme.Text
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder
			local Preview = Instance.new("Frame")
			Preview.Size = UDim2.new(0, 32, 0, 16)
			Preview.Position = UDim2.new(1, -40, 0.5, -8)
			Preview.BackgroundColor3 = color
			Preview.Parent = Holder
			corner(Preview, 2)
			stroke(Preview, Theme.Border, 1)

			local Panel = Instance.new("Frame")
			Panel.Size = UDim2.new(1, 0, 0, 104)
			Panel.Position = UDim2.new(0, 0, 1, 2)
			Panel.BackgroundColor3 = Theme.Section
			Panel.Visible = false
			Panel.ZIndex = 5
			Panel.Parent = Holder
			corner(Panel, 2)
			stroke(Panel, Theme.Border, 1)

			local function makeSlider(labelText, yPos, initial)
				local L = Instance.new("TextLabel")
				L.Size = UDim2.new(0, 16, 0, 16)
				L.Position = UDim2.new(0, 8, 0, yPos)
				L.BackgroundTransparency = 1
				L.Text = labelText
				L.Font = Enum.Font.Code
				L.TextSize = 12
				L.TextColor3 = Theme.SubText
				L.ZIndex = 6
				L.Parent = Panel
				local Track = Instance.new("Frame")
				Track.Size = UDim2.new(1, -34, 0, 6)
				Track.Position = UDim2.new(0, 26, 0, yPos + 5)
				Track.BackgroundColor3 = Theme.Background
				Track.ZIndex = 6
				Track.Parent = Panel
				corner(Track, 2)
				stroke(Track, Theme.Border, 1)
				local Fill = Instance.new("Frame")
				Fill.Size = UDim2.new(initial / 255, 0, 1, 0)
				Fill.BackgroundColor3 = Theme.Accent
				Fill.ZIndex = 6
				Fill.Parent = Track
				corner(Fill, 2)
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

			-- tek global ActiveSlider mekanizmasını yeniden kullanıyoruz
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

		-- ==== MULTI-SELECT DROPDOWN ====
		function Category:AddMultiDropdown(text, options, defaults, callback, flag)
			local selected = {}
			for _, v in ipairs(defaults or {}) do selected[v] = true end
			local open = false
			local currentOptions = options

			local Holder = Instance.new("TextButton")
			Holder.Size = UDim2.new(1, 0, 0, 26)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Text = ""
			Holder.ZIndex = 2
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)
			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(0.5, 0, 1, 0)
			Label.Position = UDim2.new(0, 8, 0, 0)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 13
			Label.TextColor3 = Theme.Text
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder
			local SelectedLabel = Instance.new("TextLabel")
			SelectedLabel.Size = UDim2.new(0.4, -10, 1, 0)
			SelectedLabel.Position = UDim2.new(0.6, 0, 0, 0)
			SelectedLabel.BackgroundTransparency = 1
			SelectedLabel.Font = Enum.Font.Code
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
			corner(ListHolder, 2)
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
				ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 24)
				for _, opt in ipairs(currentOptions) do
					local OptBtn = Instance.new("TextButton")
					OptBtn.Size = UDim2.new(1, 0, 0, 24)
					OptBtn.BackgroundColor3 = selected[opt] and Theme.Accent or Theme.Section
					OptBtn.Text = tostring(opt)
					OptBtn.Font = Enum.Font.Code
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

		function Category:AddToggle(text, default, callback, flag)
			local state = default or false

			local Holder = Instance.new("TextButton")
			Holder.Size = UDim2.new(1, 0, 0, 26)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Text = ""
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)

			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(1, -50, 1, 0)
			Label.Position = UDim2.new(0, 8, 0, 0)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 13
			Label.TextColor3 = Theme.Text
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder

			-- ImGui-style checkbox: square box with a checkmark, not a switch
			local Box = Instance.new("Frame")
			Box.Size = UDim2.new(0, 18, 0, 18)
			Box.Position = UDim2.new(1, -28, 0.5, -9)
			Box.BackgroundColor3 = Theme.Section
			Box.Parent = Holder
			corner(Box, 2)
			stroke(Box, Theme.Border, 1)

			local Check = Instance.new("Frame")
			Check.Size = UDim2.new(0, 12, 0, 12)
			Check.Position = UDim2.new(0.5, -6, 0.5, -6)
			Check.BackgroundColor3 = Theme.Accent
			Check.BorderSizePixel = 0
			Check.Visible = state
			Check.Parent = Box
			corner(Check, 1)

			local function visual()
				Check.Visible = state
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
			return {Set = function(v) setState(v, false) end}
		end

		function Category:AddSlider(text, min, max, default, callback, flag)
			min = min or 0
			max = max or 100
			local value = default or min

			local Holder = Instance.new("Frame")
			Holder.Size = UDim2.new(1, 0, 0, 40)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)

			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(1, -16, 0, 16)
			Label.Position = UDim2.new(0, 8, 0, 2)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 13
			Label.TextColor3 = Theme.Text
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder

			local ValueLabel = Instance.new("TextLabel")
			ValueLabel.Size = UDim2.new(0, 50, 0, 16)
			ValueLabel.Position = UDim2.new(1, -58, 0, 2)
			ValueLabel.BackgroundTransparency = 1
			ValueLabel.Text = tostring(value)
			ValueLabel.Font = Enum.Font.Code
			ValueLabel.TextSize = 13
			ValueLabel.TextColor3 = Theme.SubText
			ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
			ValueLabel.Parent = Holder

			local Track = Instance.new("Frame")
			Track.Size = UDim2.new(1, -16, 0, 16)
			Track.Position = UDim2.new(0, 8, 0, 22)
			Track.BackgroundColor3 = Theme.Section
			Track.Parent = Holder
			corner(Track, 2)
			stroke(Track, Theme.Border, 1)

			-- ImGui sliders fill from the left as a solid grab bar, not a thin line
			local Fill = Instance.new("Frame")
			Fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
			Fill.BackgroundColor3 = Theme.Header
			Fill.BorderSizePixel = 0
			Fill.Parent = Track
			corner(Fill, 2)

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
			return {Set = function(v) apply(v) end}
		end

		function Category:AddDropdown(text, options, default, callback, flag)
			local selected = default or options[1]
			local open = false
			local currentOptions = options

			local Holder = Instance.new("TextButton")
			Holder.Size = UDim2.new(1, 0, 0, 26)
			Holder.BackgroundColor3 = Theme.Element
			Holder.Text = ""
			Holder.ClipsDescendants = false
			Holder.ZIndex = 2
			Holder.Parent = Page
			corner(Holder, 2)
			stroke(Holder, Theme.Border, 1)

			local Label = Instance.new("TextLabel")
			Label.Size = UDim2.new(0.5, 0, 1, 0)
			Label.Position = UDim2.new(0, 8, 0, 0)
			Label.BackgroundTransparency = 1
			Label.Text = text
			Label.Font = Enum.Font.Code
			Label.TextSize = 13
			Label.TextColor3 = Theme.Text
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.Parent = Holder

			local SelectedLabel = Instance.new("TextLabel")
			SelectedLabel.Size = UDim2.new(0.4, -10, 1, 0)
			SelectedLabel.Position = UDim2.new(0.6, 0, 0, 0)
			SelectedLabel.BackgroundTransparency = 1
			SelectedLabel.Text = tostring(selected)
			SelectedLabel.Font = Enum.Font.Code
			SelectedLabel.TextSize = 13
			SelectedLabel.TextColor3 = Theme.Accent
			SelectedLabel.TextXAlignment = Enum.TextXAlignment.Right
			SelectedLabel.Parent = Holder

			local ListHolder = Instance.new("Frame")
			ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 24)
			ListHolder.Position = UDim2.new(0, 0, 1, 2)
			ListHolder.BackgroundColor3 = Theme.Section
			ListHolder.Visible = false
			ListHolder.ZIndex = 5
			ListHolder.Parent = Holder
			corner(ListHolder, 2)
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
				ListHolder.Size = UDim2.new(1, 0, 0, #currentOptions * 24)
				for _, opt in ipairs(currentOptions) do
					local OptBtn = Instance.new("TextButton")
					OptBtn.Size = UDim2.new(1, 0, 0, 24)
					OptBtn.BackgroundColor3 = Theme.Section
					OptBtn.Text = tostring(opt)
					OptBtn.Font = Enum.Font.Code
					OptBtn.TextSize = 12
					OptBtn.TextColor3 = Theme.Text
					OptBtn.ZIndex = 6
					OptBtn.Parent = ListHolder

					OptBtn.MouseEnter:Connect(function()
						OptBtn.BackgroundColor3 = Theme.Header
					end)
					OptBtn.MouseLeave:Connect(function()
						OptBtn.BackgroundColor3 = Theme.Section
					end)

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
				Get = function() return selected end,   -- BUNU EKLE
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
