--[[
	I Need Good Script - "+1 Muscle to Break Walls"
	Orion-style UI, written from scratch. Fully readable, loads no code from the internet.

	Run: loadstring(readfile("INeedGoodScript.lua"))()

	Keybinds:
	  RightShift = show / hide menu
	  M = Auto Click,  N = Auto Rebirth
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
local genv = (typeof(getgenv) == "function" and getgenv()) or _G
local robloxSettings = settings -- Roblox's settings() function; the config table below shadows the name

for _, name in ipairs({ "AutoRebirthCleanup", "MuscleHelperCleanup", "INGSCleanup" }) do
	if type(genv[name]) == "function" then
		pcall(genv[name])
	end
end

--------------------------------------------------------------------------------
-- Game remotes
--------------------------------------------------------------------------------

local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local trainRemote = remotes and remotes:WaitForChild("Train", 10)
local rebirthRemote = remotes and remotes:WaitForChild("Rebirth", 10)
if not trainRemote or not rebirthRemote then
	warn("[I Need Good Script] Made for: +1 Muscle to Break Walls")
	return
end
local teleportRemote = remotes:FindFirstChild("Teleport")
local eventRemotes = remotes:FindFirstChild("Event")
local pumpkinRemote = eventRemotes and eventRemotes:FindFirstChild("CollectPumpkinOrb")
local questRemote = eventRemotes and eventRemotes:FindFirstChild("ClaimEventQuest")

--------------------------------------------------------------------------------
-- Settings (saved to file)
--------------------------------------------------------------------------------

local CONFIG_FILE = "INeedGoodScript.json"
local REBIRTH_MODES = { "100", "10", "1", "Best" }

-- Discord gate (değiştir): davet linkini ve sunucu adını kendininkiyle değiştir
local DISCORD_INVITE = "https://discord.gg/wgMmdpnYnt"
local DISCORD_NAME = "I Need Good Script"
local GATE_FILE = "INeedGoodScript_joined.txt" -- "Devam" dedikten sonra bir daha sorMAZ

local settings = {
	AutoClick = false,
	ClickPerSecond = 10,
	AutoRebirth = false,
	RebirthMode = "100",
	AutoPumpkin = false,
	AutoQuest = false,
	WalkSpeedOn = false,
	WalkSpeed = 60,
	JumpPowerOn = false,
	JumpPower = 80,
	InfiniteJump = false,
	AntiAfk = true,
	LowGraphics = false,
}

pcall(function()
	local saved = HttpService:JSONDecode(readfile(CONFIG_FILE))
	for key, value in pairs(saved) do
		if settings[key] ~= nil and type(settings[key]) == type(value) then
			settings[key] = value
		end
	end
end)
if not table.find(REBIRTH_MODES, settings.RebirthMode) then
	settings.RebirthMode = "Best"
end

local saveQueued = false
local function saveSettings()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(1, function()
		saveQueued = false
		pcall(writefile, CONFIG_FILE, HttpService:JSONEncode(settings))
	end)
end

local alive = true
local connections = {}
local function track(connection)
	table.insert(connections, connection)
	return connection
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function stat(name)
	local leaderstats = localPlayer:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(name)
	return value and tonumber(value.Value) or 0
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td" }
local function short(n)
	n = tonumber(n) or 0
	local negative = n < 0
	n = math.abs(n)
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	local text = index == 1 and tostring(math.floor(n)) or string.format("%.2f", n)
	return (negative and "-" or "") .. text .. SUFFIXES[index]
end

local function getHumanoid()
	local character = localPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function rebirthFrame()
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local frames = playerGui and playerGui:FindFirstChild("Frames")
	return frames and frames:FindFirstChild("Rebirth")
end

local function reachedMaxRebirth()
	local frame = rebirthFrame()
	local max = frame and frame:FindFirstChild("Max")
	return max ~= nil and max:IsA("GuiObject") and max.Visible
end

-- The game pops its Rebirth / Event panels on the right during automation.
-- These helpers keep them closed so nothing flashes open while farming.
local function hideFrame(name)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local frames = playerGui and playerGui:FindFirstChild("Frames")
	local frame = frames and frames:FindFirstChild(name)
	if frame and frame:IsA("GuiObject") and frame.Visible then
		frame.Visible = false
	end
end

-- After our own rebirth/quest request the game may pop its panel for ~0.5s.
-- Close it only during that short window, so the player can still open these
-- menus by hand whenever automation isn't mid-action.
local function suppressFrameBriefly(name, seconds)
	task.spawn(function()
		local deadline = os.clock() + (seconds or 0.8)
		while os.clock() < deadline and alive do
			hideFrame(name)
			task.wait(0.1)
		end
	end)
end

--------------------------------------------------------------------------------
-- UI library (Orion-style)
--------------------------------------------------------------------------------

local THEME = {
	Main = Color3.fromRGB(25, 25, 28),
	Second = Color3.fromRGB(32, 32, 37),
	Element = Color3.fromRGB(38, 38, 44),
	Hover = Color3.fromRGB(46, 46, 54),
	Stroke = Color3.fromRGB(60, 60, 68),
	Divider = Color3.fromRGB(55, 55, 62),
	Text = Color3.fromRGB(240, 240, 245),
	TextDark = Color3.fromRGB(150, 150, 162),
	Accent = Color3.fromRGB(255, 170, 50),
	AccentDark = Color3.fromRGB(200, 120, 30),
	Off = Color3.fromRGB(70, 70, 80),
	Success = Color3.fromRGB(80, 210, 120),
}

local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function create(className, props, children)
	local instance = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for key, value in pairs(props) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function stroke(color, thickness, transparency)
	return create("UIStroke", { Color = color or THEME.Stroke, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function padding(top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

local function tween(instance, props, info)
	TweenService:Create(instance, info or FAST, props):Play()
end

local function hoverEffect(button, normal, hover)
	button.MouseEnter:Connect(function()
		tween(button, { BackgroundColor3 = hover })
	end)
	button.MouseLeave:Connect(function()
		tween(button, { BackgroundColor3 = normal })
	end)
end

local guiParent = CoreGui
if typeof(gethui) == "function" then
	local ok, result = pcall(gethui)
	if ok and typeof(result) == "Instance" then
		guiParent = result
	end
end

local screenGui = create("ScreenGui", {
	Name = "INeedGoodScript",
	ResetOnSpawn = false,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
})

-- Notifications (bottom right)
local notificationHolder = create("Frame", {
	Parent = screenGui,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.new(0, 300, 1, -40),
	BackgroundTransparency = 1,
}, {
	create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}),
})

local notificationOrder = 0
-- On-screen notifications are disabled (the menu already shows state).
-- Kept as a no-op so existing calls still work; prints to the F9 console only.
local function notify(title, text)
	print(string.format("[I Need Good Script] %s: %s", tostring(title), tostring(text)))
end

local function notifyDisabled(title, text, duration)
	notificationOrder += 1
	local card = create("Frame", {
		Parent = notificationHolder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Second,
		BackgroundTransparency = 1,
		LayoutOrder = notificationOrder,
	}, {
		corner(8),
		stroke(THEME.Stroke, 1, 1),
		padding(12),
		create("Frame", { Size = UDim2.new(0, 3, 1, 0), Position = UDim2.fromOffset(-12, 0), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0 }),
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			TextSize = 14,
			TextColor3 = THEME.Text,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = title,
			LayoutOrder = 1,
		}),
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 13,
			TextColor3 = THEME.TextDark,
			TextTransparency = 1,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = text,
			LayoutOrder = 2,
		}),
	})

	local function fade(visible)
		local alpha = visible and 0 or 1
		tween(card, { BackgroundTransparency = visible and 0.05 or 1 })
		for _, descendant in ipairs(card:GetDescendants()) do
			if descendant:IsA("TextLabel") then
				tween(descendant, { TextTransparency = alpha })
			elseif descendant:IsA("UIStroke") then
				tween(descendant, { Transparency = alpha })
			elseif descendant:IsA("Frame") then
				tween(descendant, { BackgroundTransparency = alpha })
			end
		end
	end

	fade(true)
	task.delay(duration or 3.5, function()
		fade(false)
		task.wait(0.3)
		card:Destroy()
	end)
end

-- Main window
local WINDOW_SIZE = UDim2.fromOffset(680, 460)

local window = create("Frame", {
	Parent = screenGui,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = WINDOW_SIZE,
	BackgroundColor3 = THEME.Main,
	ClipsDescendants = true,
}, { corner(10), stroke(THEME.Stroke, 1) })

-- Top bar
local topBar = create("Frame", {
	Parent = window,
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundTransparency = 1,
	Active = true,
})

create("TextLabel", {
	Parent = topBar,
	Position = UDim2.fromOffset(20, 8),
	Size = UDim2.new(1, -140, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 18,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "I Need Good Script",
}, {
	create("UIGradient", { Color = ColorSequence.new(THEME.Text, THEME.Accent) }),
})

create("TextLabel", {
	Parent = topBar,
	Position = UDim2.fromOffset(20, 28),
	Size = UDim2.new(1, -140, 0, 14),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 12,
	TextColor3 = THEME.TextDark,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "+1 Muscle to Break Walls",
})

create("Frame", { Parent = window, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.Divider, BorderSizePixel = 0 })

-- Minimize / close pill
local controlPill = create("Frame", {
	Parent = topBar,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(70, 30),
	BackgroundColor3 = THEME.Second,
}, { corner(7), stroke(THEME.Stroke, 1) })

create("Frame", { Parent = controlPill, Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.new(0, 1, 1, -12), BackgroundColor3 = THEME.Stroke, BorderSizePixel = 0 })

local function pillButton(text, x)
	return create("TextButton", {
		Parent = controlPill,
		Position = UDim2.new(x, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 16,
		TextColor3 = THEME.Text,
		Text = text,
	})
end

local minimizeButton = pillButton("-", 0)
local closeButton = pillButton("X", 0.5)
closeButton.TextSize = 14

-- Sidebar
local sidebar = create("Frame", {
	Parent = window,
	Position = UDim2.fromOffset(0, 51),
	Size = UDim2.new(0, 170, 1, -51),
	BackgroundColor3 = THEME.Second,
	BorderSizePixel = 0,
})
create("Frame", { Parent = sidebar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = THEME.Divider, BorderSizePixel = 0 })

local tabList = create("ScrollingFrame", {
	Parent = sidebar,
	Size = UDim2.new(1, -1, 1, -64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, {
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	padding(8, 8, 8, 8),
})

-- Profile card (bottom left)
local profile = create("Frame", {
	Parent = sidebar,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, -1, 0, 64),
	BackgroundTransparency = 1,
})
create("Frame", { Parent = profile, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.Divider, BorderSizePixel = 0 })

local avatar = create("ImageLabel", {
	Parent = profile,
	Position = UDim2.fromOffset(12, 14),
	Size = UDim2.fromOffset(36, 36),
	BackgroundColor3 = THEME.Element,
	Image = "",
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

task.spawn(function()
	local ok, image = pcall(Players.GetUserThumbnailAsync, Players, localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	if ok then
		avatar.Image = image
	end
end)

create("TextLabel", {
	Parent = profile,
	Position = UDim2.fromOffset(56, 15),
	Size = UDim2.new(1, -64, 0, 16),
	BackgroundTransparency = 1,
	Font = FONT_BOLD,
	TextSize = 13,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = localPlayer.DisplayName,
})

create("TextLabel", {
	Parent = profile,
	Position = UDim2.fromOffset(56, 32),
	Size = UDim2.new(1, -64, 0, 14),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 12,
	TextColor3 = THEME.TextDark,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "@" .. localPlayer.Name,
})

-- Content area
local content = create("Frame", {
	Parent = window,
	Position = UDim2.fromOffset(171, 51),
	Size = UDim2.new(1, -171, 1, -51),
	BackgroundTransparency = 1,
})

local tabs = {}
local tabOrder = 0

local function selectTab(target)
	for _, tab in ipairs(tabs) do
		local active = tab == target
		tab.Page.Visible = active
		tween(tab.Button, { BackgroundTransparency = active and 0 or 1 })
		tween(tab.Title, { TextColor3 = active and THEME.Text or THEME.TextDark })
		tween(tab.Icon, { TextColor3 = active and THEME.Accent or THEME.TextDark })
	end
end

local Library = {}

function Library.Tab(name, icon)
	tabOrder += 1
	local button = create("TextButton", {
		Parent = tabList,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.Element,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = tabOrder,
	}, { corner(6) })

	local iconLabel = create("TextLabel", {
		Parent = button,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(0, 20, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 15,
		TextColor3 = THEME.TextDark,
		Text = icon,
	})

	local titleLabel = create("TextLabel", {
		Parent = button,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -44, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = THEME.TextDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
	})

	local page = create("ScrollingFrame", {
		Parent = content,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		padding(12, 14, 12, 12),
	})

	local tab = { Button = button, Page = page, Title = titleLabel, Icon = iconLabel, Order = 0 }
	table.insert(tabs, tab)
	button.Activated:Connect(function()
		selectTab(tab)
	end)
	if #tabs == 1 then
		selectTab(tab)
	end

	local function nextOrder()
		tab.Order += 1
		return tab.Order
	end

	local function element(height)
		return create("Frame", {
			Parent = page,
			Size = UDim2.new(1, 0, 0, height or 38),
			BackgroundColor3 = THEME.Element,
			LayoutOrder = nextOrder(),
		}, { corner(6), stroke(THEME.Stroke, 1) })
	end

	local function elementTitle(parent, text, rightSpace)
		return create("TextLabel", {
			Parent = parent,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -(12 + (rightSpace or 0)), 0, 38),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			TextSize = 14,
			TextColor3 = THEME.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
		})
	end

	local api = {}

	function api.Section(text)
		create("TextLabel", {
			Parent = page,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			TextSize = 13,
			TextColor3 = THEME.TextDark,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Text = text,
			LayoutOrder = nextOrder(),
		})
	end

	function api.Toggle(text, key, onChange)
		local frame = element()
		elementTitle(frame, text, 60)
		local box = create("Frame", {
			Parent = frame,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(40, 22),
			BackgroundColor3 = THEME.Off,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local knob = create("Frame", {
			Parent = box,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = THEME.Text,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local click = create("TextButton", { Parent = frame, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" })

		local function render()
			local on = settings[key]
			tween(box, { BackgroundColor3 = on and THEME.Accent or THEME.Off })
			tween(knob, { Position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
		end

		local function set(value)
			settings[key] = value
			render()
			saveSettings()
			if onChange then
				onChange(value)
			end
		end

		click.Activated:Connect(function()
			set(not settings[key])
		end)
		hoverEffect(frame, THEME.Element, THEME.Hover)
		render()
		return set
	end

	function api.Slider(text, key, minimum, maximum, step, suffix, onChange)
		local frame = element(58)
		elementTitle(frame, text, 90).Size = UDim2.new(1, -102, 0, 32)
		local valueBox = create("TextLabel", {
			Parent = frame,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 7),
			Size = UDim2.fromOffset(80, 20),
			BackgroundColor3 = THEME.Second,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = THEME.Text,
		}, { corner(4), stroke(THEME.Stroke, 1) })
		local bar = create("Frame", {
			Parent = frame,
			Position = UDim2.new(0, 12, 0, 38),
			Size = UDim2.new(1, -24, 0, 8),
			BackgroundColor3 = THEME.Second,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(THEME.Stroke, 1) })
		local fill = create("Frame", {
			Parent = bar,
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = THEME.Accent,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

		local function render()
			local value = settings[key]
			tween(fill, { Size = UDim2.fromScale((value - minimum) / (maximum - minimum), 1) }, TweenInfo.new(0.08))
			valueBox.Text = tostring(value) .. (suffix and (" " .. suffix) or "")
		end

		local dragging = false
		local function update(x)
			local ratio = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			local value = minimum + (maximum - minimum) * ratio
			value = math.clamp(math.floor(value / step + 0.5) * step, minimum, maximum)
			if value ~= settings[key] then
				settings[key] = value
				render()
				saveSettings()
				if onChange then
					onChange(value)
				end
			end
		end

		bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				update(input.Position.X)
			end
		end)
		track(UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				update(input.Position.X)
			end
		end))
		track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end))
		render()
	end

	function api.Dropdown(text, key, options, onChange)
		local frame = element()
		frame.ClipsDescendants = true
		elementTitle(frame, text, 130)
		local selected = create("TextLabel", {
			Parent = frame,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -34, 0, 0),
			Size = UDim2.fromOffset(100, 38),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 13,
			TextColor3 = THEME.TextDark,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local arrow = create("TextLabel", {
			Parent = frame,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.fromOffset(16, 38),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			TextSize = 14,
			TextColor3 = THEME.TextDark,
			Text = "▾",
		})
		local header = create("TextButton", { Parent = frame, Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Text = "" })
		local list = create("Frame", {
			Parent = frame,
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, #options * 30),
			BackgroundTransparency = 1,
		}, {
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			create("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.Divider, BorderSizePixel = 0, LayoutOrder = 0 }),
		})

		local open = false
		local optionButtons = {}

		local function render()
			selected.Text = tostring(settings[key])
			for option, optionButton in pairs(optionButtons) do
				optionButton.TextColor3 = option == settings[key] and THEME.Accent or THEME.Text
			end
		end

		for index, option in ipairs(options) do
			local optionButton = create("TextButton", {
				Parent = list,
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = THEME.Element,
				AutoButtonColor = false,
				Font = FONT,
				TextSize = 13,
				TextColor3 = THEME.Text,
				Text = option,
				LayoutOrder = index,
			})
			hoverEffect(optionButton, THEME.Element, THEME.Hover)
			optionButton.Activated:Connect(function()
				settings[key] = option
				saveSettings()
				render()
				open = false
				tween(frame, { Size = UDim2.new(1, 0, 0, 38) })
				tween(arrow, { Rotation = 0 })
				if onChange then
					onChange(option)
				end
			end)
			optionButtons[option] = optionButton
		end

		header.Activated:Connect(function()
			open = not open
			tween(frame, { Size = UDim2.new(1, 0, 0, open and (38 + #options * 30 + 1) or 38) })
			tween(arrow, { Rotation = open and 180 or 0 })
		end)
		render()
	end

	function api.Button(text, callback)
		local frame = element()
		elementTitle(frame, text, 40)
		create("TextLabel", {
			Parent = frame,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.fromOffset(20, 38),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			TextSize = 16,
			TextColor3 = THEME.Accent,
			Text = "›",
		})
		local click = create("TextButton", { Parent = frame, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" })
		hoverEffect(frame, THEME.Element, THEME.Hover)
		click.Activated:Connect(function()
			tween(frame, { BackgroundColor3 = THEME.Stroke }, TweenInfo.new(0.05))
			task.delay(0.1, function()
				tween(frame, { BackgroundColor3 = THEME.Element })
			end)
			task.spawn(callback)
		end)
	end

	-- Key / value row; returns the value label
	function api.Info(text)
		local frame = element(34)
		elementTitle(frame, text, 160).Size = UDim2.new(0.5, -12, 1, 0)
		local value = create("TextLabel", {
			Parent = frame,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			TextSize = 13,
			TextColor3 = THEME.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "-",
		})
		frame:FindFirstChildOfClass("TextLabel").TextColor3 = THEME.TextDark
		return value
	end

	function api.Paragraph(text)
		local frame = create("Frame", {
			Parent = page,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = THEME.Element,
			LayoutOrder = nextOrder(),
		}, { corner(6), stroke(THEME.Stroke, 1), padding(10, 12) })
		create("TextLabel", {
			Parent = frame,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 13,
			TextColor3 = THEME.TextDark,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = text,
		})
	end

	return api
end

-- Window position: top-left in pixels, always kept fully on screen
local minimized = false
local MINIMIZED_HEIGHT = 50

local function windowHeight()
	return minimized and MINIMIZED_HEIGHT or WINDOW_SIZE.Y.Offset
end

local function placeWindow(x, y)
	local viewport = screenGui.AbsoluteSize
	local width = WINDOW_SIZE.X.Offset
	x = math.clamp(x, 0, math.max(0, viewport.X - width))
	y = math.clamp(y, 0, math.max(0, viewport.Y - windowHeight()))
	window.Position = UDim2.fromOffset(x, y)
end

window.AnchorPoint = Vector2.new(0, 0)

local function centerWindow()
	local viewport = screenGui.AbsoluteSize
	placeWindow((viewport.X - WINDOW_SIZE.X.Offset) / 2, (viewport.Y - WINDOW_SIZE.Y.Offset) / 2)
end

track(screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	placeWindow(window.Position.X.Offset, window.Position.Y.Offset)
end))

do
	local dragging, dragStart, startPosition = false, nil, nil
	topBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPosition = true, input.Position, Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			placeWindow(startPosition.X + delta.X, startPosition.Y + delta.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

-- Minimize: hide everything below the top bar so nothing overlaps the title
minimizeButton.Activated:Connect(function()
	minimized = not minimized
	minimizeButton.Text = minimized and "+" or "-"
	if minimized then
		sidebar.Visible = false
		content.Visible = false
	end
	local animation = TweenService:Create(window, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
		Size = UDim2.fromOffset(WINDOW_SIZE.X.Offset, windowHeight()),
	})
	animation.Completed:Connect(function()
		if not minimized then
			sidebar.Visible = true
			content.Visible = true
		end
	end)
	animation:Play()
	placeWindow(window.Position.X.Offset, window.Position.Y.Offset)
end)

closeButton.Activated:Connect(function()
	window.Visible = false
	notify("Menu hidden", "Press RightShift to open it again.")
end)

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

local Farm = Library.Tab("Farm", "⚡")
local Event = Library.Tab("Event", "🎃")
local PlayerTab = Library.Tab("Player", "🏃")
local Stats = Library.Tab("Stats", "📊")
local Settings = Library.Tab("Settings", "⚙")

-- Farm
Farm.Section("Strength")
local setAutoClick = Farm.Toggle("Auto Click   [M]", "AutoClick")
Farm.Slider("Clicks per second", "ClickPerSecond", 2, 30, 1, "CPS")

Farm.Section("Rebirth")
local setAutoRebirth = Farm.Toggle("Auto Rebirth   [N]", "AutoRebirth")
Farm.Dropdown("Rebirth amount", "RebirthMode", REBIRTH_MODES)
local farmStatus = Farm.Info("Status")
Farm.Button("Rebirth x100 now", function()
	local before = stat("Rebirth")
	pcall(rebirthRemote.InvokeServer, rebirthRemote, 100)
	suppressFrameBriefly("Rebirth", 0.8)
	task.wait(0.3)
	local gained = stat("Rebirth") - before
	notify("Rebirth", gained > 0 and ("+" .. gained .. " rebirths") or "Not enough strength for x100 yet.")
end)

-- Event
Event.Section("Pumpkins")
Event.Toggle("Auto Collect Pumpkins (current world)", "AutoPumpkin")
local pumpkinStatus = Event.Info("Status")
local pumpkinCount = Event.Info("Pumpkins")

Event.Section("Quests")
Event.Toggle("Auto Claim Event Quests", "AutoQuest")
local questStatus = Event.Info("Last claimed")

Event.Section("Teleport")
do
	local worlds = {}
	for _, child in ipairs(workspace:GetChildren()) do
		local number = tonumber(string.match(child.Name, "^World(%d+)$"))
		if number then
			table.insert(worlds, number)
		end
	end
	table.sort(worlds)
	if #worlds == 0 then
		worlds = { 1, 2, 3, 4 }
	end
	for _, number in ipairs(worlds) do
		Event.Button("Teleport to World " .. number, function()
			if teleportRemote then
				pcall(teleportRemote.FireServer, teleportRemote, number)
			end
		end)
	end
end

-- Player
PlayerTab.Section("Movement")
PlayerTab.Toggle("Custom WalkSpeed", "WalkSpeedOn", function(on)
	if not on then
		local humanoid = getHumanoid()
		if humanoid then
			humanoid.WalkSpeed = tonumber(localPlayer:GetAttribute("CustomSpeed")) or 16
		end
	end
end)
PlayerTab.Slider("WalkSpeed", "WalkSpeed", 16, 250, 1)
PlayerTab.Toggle("Custom JumpPower", "JumpPowerOn", function(on)
	local humanoid = getHumanoid()
	if humanoid and not on then
		humanoid.JumpPower = 50
	end
end)
PlayerTab.Slider("JumpPower", "JumpPower", 50, 300, 5)
PlayerTab.Toggle("Infinite Jump", "InfiniteJump")

PlayerTab.Section("Misc")
PlayerTab.Toggle("Anti-AFK", "AntiAfk")
PlayerTab.Button("Reset Character", function()
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.Health = 0
	end
end)

-- Stats
Stats.Section("Player")
local worldInfo = Stats.Info("World / Stage")
Stats.Section("Statistics")
local strengthInfo = Stats.Info("Strength")
local winsInfo = Stats.Info("Wins")
local rebirthInfo = Stats.Info("Rebirths")
local pumpkinInfo = Stats.Info("Pumpkins")
Stats.Section("Rates")
local strengthRateInfo = Stats.Info("Strength / sec")
local rebirthRateInfo = Stats.Info("Rebirths / hour")
local sessionInfo = Stats.Info("This session")
Stats.Section("Multipliers")
local strengthTierInfo = Stats.Info("Strength Tier")
local winsTierInfo = Stats.Info("Wins Tier")
local treadmillInfo = Stats.Info("Treadmill multiplier")
local relicInfo = Stats.Info("Relic multiplier")
local potionInfo = Stats.Info("x2 Strength potion")

-- Settings
local originalShadows = Lighting.GlobalShadows
local function applyLowGraphics(on)
	Lighting.GlobalShadows = not on and originalShadows or false
	pcall(function()
		robloxSettings().Rendering.QualityLevel = on and Enum.QualityLevel.Level01 or Enum.QualityLevel.Automatic
	end)
end

Settings.Section("Performance")
Settings.Toggle("Low Graphics (more FPS)", "LowGraphics", applyLowGraphics)
Settings.Section("Keybinds")
Settings.Info("Show / hide menu").Text = "RightShift"
Settings.Info("Auto Click").Text = "M"
Settings.Info("Auto Rebirth").Text = "N"
Settings.Section("Community")
local function copyInvite()
	local clip = setclipboard or toclipboard or (syn and syn.setclipboard)
	if type(clip) == "function" and pcall(clip, DISCORD_INVITE) then
		notify("Discord", "Invite copied to clipboard!", 3)
	else
		notify("Discord", DISCORD_INVITE, 6)
	end
end
Settings.Button("Copy Discord Invite", copyInvite)

Settings.Section("Script")
Settings.Paragraph("Your settings are saved automatically to " .. CONFIG_FILE .. " and restored next time you run the script.")
Settings.Button("Destroy UI", function()
	genv.INGSCleanup()
end)

track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightShift then
		window.Visible = not window.Visible
	elseif input.KeyCode == Enum.KeyCode.M then
		setAutoClick(not settings.AutoClick)
		notify("Auto Click", settings.AutoClick and "Enabled" or "Disabled", 2)
	elseif input.KeyCode == Enum.KeyCode.N then
		setAutoRebirth(not settings.AutoRebirth)
		notify("Auto Rebirth", settings.AutoRebirth and "Enabled" or "Disabled", 2)
	end
end))

--------------------------------------------------------------------------------
-- Features
--------------------------------------------------------------------------------

-- Auto Click
task.spawn(function()
	while alive do
		if settings.AutoClick then
			pcall(trainRemote.FireServer, trainRemote)
			task.wait(1 / math.max(settings.ClickPerSecond, 1))
		else
			task.wait(0.2)
		end
	end
end)

-- Auto Rebirth
local function tryRebirth(amount)
	local before = stat("Rebirth")
	pcall(rebirthRemote.InvokeServer, rebirthRemote, amount)
	suppressFrameBriefly("Rebirth", 0.8)
	task.wait(0.25)
	return stat("Rebirth") - before
end

task.spawn(function()
	local backoff = 1
	while alive do
		if settings.AutoRebirth then
			if reachedMaxRebirth() then
				farmStatus.Text = "Max rebirths reached"
				task.wait(3)
			else
				local amounts = settings.RebirthMode == "Best" and { 100, 10, 1 } or { tonumber(settings.RebirthMode) }
				local gained = 0
				for _, amount in ipairs(amounts) do
					gained = tryRebirth(amount)
					if gained > 0 or not settings.AutoRebirth then
						break
					end
				end
				if gained > 0 then
					backoff = 1 -- basardik, hizli devam et
					farmStatus.Text = "+" .. gained .. " rebirths"
					task.wait(0.5)
				else
					-- guc yetmedi: tekrar denemeyi gittikce gecikir (panel surekli acilmasin)
					backoff = math.min(backoff * 2, 15)
					farmStatus.Text = string.format("Waiting for strength (%ds)", backoff)
					local waited = 0
					while waited < backoff and alive and settings.AutoRebirth do
						waited += task.wait(0.5)
					end
				end
			end
		else
			farmStatus.Text = settings.AutoClick and "Training" or "Idle"
			backoff = 1
			task.wait(1)
		end
	end
end)

-- Auto Pumpkin: go to each pumpkin in the current world, let the game's touch handler
-- collect it; if it is still there, send the game's own collect request. Then go back.
local function currentWorldOrbs()
	local folder = workspace:FindFirstChild("LocalPumpkinOrbs")
	local world = tonumber(localPlayer:GetAttribute("CurrentWorldNumber"))
	local orbs = {}
	if folder then
		for _, orb in ipairs(folder:GetChildren()) do
			if orb:IsA("BasePart") and tonumber(orb:GetAttribute("World")) == world and orb:GetAttribute("OrbId") then
				table.insert(orbs, orb)
			end
		end
	end
	return orbs
end

task.spawn(function()
	while alive do
		if settings.AutoPumpkin and pumpkinRemote then
			local orbs = currentWorldOrbs()
			local character = localPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if #orbs > 0 and root then
				local home = root.CFrame
				local collected = 0
				for _, orb in ipairs(orbs) do
					if not settings.AutoPumpkin or not alive then
						break
					end
					if orb.Parent then
						pumpkinStatus.Text = string.format("Collecting %d/%d", collected + 1, #orbs)
						root.CFrame = CFrame.new(orb.Position + Vector3.new(0, 2, 0))
						root.AssemblyLinearVelocity = Vector3.zero
						task.wait(0.35)
						if orb.Parent then
							pcall(pumpkinRemote.FireServer, pumpkinRemote, orb:GetAttribute("OrbId"))
							task.wait(0.2)
						end
						collected += 1
					end
				end
				if root.Parent then
					root.CFrame = home
					root.AssemblyLinearVelocity = Vector3.zero
				end
				pumpkinStatus.Text = "Collected " .. collected
			else
				pumpkinStatus.Text = "No pumpkins here, waiting"
			end
			task.wait(3)
		else
			pumpkinStatus.Text = pumpkinRemote and "Idle" or "No event in this game"
			task.wait(1)
		end
		pumpkinCount.Text = tostring(localPlayer:GetAttribute("Pumpkins") or "-")
	end
end)

-- Auto Event Quest: claim each quest once when progress reaches its goal
local claimedQuests = {}
task.spawn(function()
	while alive do
		if settings.AutoQuest and questRemote then
			local ok, quests = pcall(function()
				return HttpService:JSONDecode(localPlayer:GetAttribute("EventQuests"))
			end)
			if ok and type(quests) == "table" then
				for index, quest in ipairs(quests) do
					local progress, goal = tonumber(quest.Progress), tonumber(quest.Goal)
					local key = tostring(quest.Text) .. "|" .. tostring(goal)
					if progress and goal and progress >= goal and claimedQuests[index] ~= key and quest.Claimed ~= true then
						claimedQuests[index] = key
						pcall(questRemote.FireServer, questRemote, index)
						suppressFrameBriefly("EventFrame", 0.8)
						task.wait(0.2)
						questStatus.Text = tostring(quest.Text)
						notify("Quest claimed", tostring(quest.Text), 3)
						task.wait(1)
					end
				end
			end
		end
		task.wait(5)
	end
end)

-- Let the player open the game's Rebirth panel by hand: when they click the
-- in-game sidebar Rebirth button we leave the panel alone for a few seconds.
-- Otherwise, while Auto Rebirth runs, we keep the panel the game auto-opens closed.
local allowRebirthPanelUntil = 0
task.spawn(function()
	local rebirthButton
	for _ = 1, 40 do
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
		local hud = playerGui and playerGui:FindFirstChild("HUD")
		local bar = hud and hud:FindFirstChild("SidebarLeft")
		local buttons = bar and bar:FindFirstChild("LeftButtons")
		rebirthButton = buttons and buttons:FindFirstChild("Rebirth")
		if rebirthButton then
			break
		end
		task.wait(0.5)
	end
	if rebirthButton and rebirthButton:IsA("GuiButton") then
		local function allow()
			allowRebirthPanelUntil = os.clock() + 6
		end
		track(rebirthButton.Activated:Connect(allow))
		track(rebirthButton.MouseButton1Click:Connect(allow))
	end
end)

task.spawn(function()
	while alive do
		if settings.AutoRebirth and os.clock() > allowRebirthPanelUntil then
			hideFrame("Rebirth")
		end
		task.wait(0.15)
	end
end)

-- Movement
track(RunService.Heartbeat:Connect(function()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	if settings.WalkSpeedOn then
		humanoid.WalkSpeed = settings.WalkSpeed
	end
	if settings.JumpPowerOn then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = settings.JumpPower
	end
end))

track(UserInputService.JumpRequest:Connect(function()
	if settings.InfiniteJump then
		local humanoid = getHumanoid()
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end))

-- Anti-AFK
track(localPlayer.Idled:Connect(function()
	if settings.AntiAfk then
		pcall(function()
			local virtualUser = game:GetService("VirtualUser")
			virtualUser:CaptureController()
			virtualUser:ClickButton2(Vector2.new())
		end)
	end
end))

if settings.LowGraphics then
	applyLowGraphics(true)
end

-- Stats refresh
task.spawn(function()
	local startRebirth = stat("Rebirth")
	local startTime = os.clock()
	local lastStrength = stat("Strength")
	local strengthRate = 0

	while alive do
		task.wait(1)
		local strength = stat("Strength")
		local delta = strength - lastStrength
		lastStrength = strength
		-- A rebirth can reset strength; ignore negative jumps
		if delta >= 0 then
			strengthRate = strengthRate == 0 and delta or strengthRate * 0.8 + delta * 0.2
		end

		local elapsedHours = math.max((os.clock() - startTime) / 3600, 1 / 3600)
		local rebirthNow = stat("Rebirth")

		worldInfo.Text = string.format("%s / %s", tostring(localPlayer:GetAttribute("CurrentWorldNumber") or "-"), tostring(localPlayer:GetAttribute("CompletedStage") or "-"))
		strengthInfo.Text = short(strength)
		winsInfo.Text = short(stat("Wins"))
		rebirthInfo.Text = short(rebirthNow)
		pumpkinInfo.Text = tostring(localPlayer:GetAttribute("Pumpkins") or "-")
		strengthRateInfo.Text = short(strengthRate)
		rebirthRateInfo.Text = short((rebirthNow - startRebirth) / elapsedHours)
		sessionInfo.Text = string.format("+%s  ·  %d min", short(rebirthNow - startRebirth), math.floor((os.clock() - startTime) / 60))
		strengthTierInfo.Text = tostring(localPlayer:GetAttribute("StrengthMultiplierTier") or "-")
		winsTierInfo.Text = tostring(localPlayer:GetAttribute("WinsMultiplierTier") or "-")
		treadmillInfo.Text = "x" .. tostring(localPlayer:GetAttribute("TreadmillMultiplier") or "-")
		relicInfo.Text = "x" .. tostring(localPlayer:GetAttribute("RelicMultiplier") or "-")
		potionInfo.Text = tostring(localPlayer:GetAttribute("x2StrengthPotion") or 0) .. "s"
	end
end)

--------------------------------------------------------------------------------
-- Cleanup / start
--------------------------------------------------------------------------------

genv.INGSCleanup = function()
	alive = false
	for _, connection in ipairs(connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	pcall(function()
		screenGui:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Discord gate (first launch)
--------------------------------------------------------------------------------

local function openWindow()
	-- Wait until the viewport size is actually known, otherwise centering
	-- can place the window off the left edge.
	local tries = 0
	while screenGui.AbsoluteSize.X < WINDOW_SIZE.X.Offset and tries < 120 do
		task.wait()
		tries += 1
	end
	centerWindow()
	window.Visible = true
	window.Size = UDim2.fromOffset(WINDOW_SIZE.X.Offset, 0)
	tween(window, { Size = WINDOW_SIZE }, TweenInfo.new(0.35, Enum.EasingStyle.Quint))
	notify("I Need Good Script", "Loaded! Press RightShift to show / hide the menu.", 4)
end

local function alreadyJoined()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then
		return false
	end
	local ok, exists = pcall(isfile, GATE_FILE)
	return ok and exists == true
end

local function markJoined()
	pcall(function()
		if type(writefile) == "function" then
			writefile(GATE_FILE, DISCORD_INVITE)
		end
	end)
end

local function showGate()
	local overlay = create("Frame", {
		Parent = screenGui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
	})
	tween(overlay, { BackgroundTransparency = 0.45 })

	local card = create("Frame", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 250),
		BackgroundColor3 = THEME.Main,
		ZIndex = 51,
	}, { corner(12), stroke(THEME.Accent, 1) })

	create("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 40,
		Text = "🎮",
		ZIndex = 52,
	})
	create("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(20, 78),
		Size = UDim2.new(1, -40, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = THEME.Text,
		Text = "Join " .. DISCORD_NAME,
		ZIndex = 52,
	})
	create("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(20, 104),
		Size = UDim2.new(1, -40, 0, 36),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 13,
		TextColor3 = THEME.TextDark,
		TextWrapped = true,
		Text = "Join our Discord to use the script and get updates & support.",
		ZIndex = 52,
	})
	create("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(20, 142),
		Size = UDim2.new(1, -40, 0, 24),
		BackgroundColor3 = THEME.Second,
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = THEME.Accent,
		Text = DISCORD_INVITE,
		ZIndex = 52,
	}, { corner(6) })

	local function gateButton(text, x, width, color, textColor)
		local button = create("TextButton", {
			Parent = card,
			Position = UDim2.fromOffset(x, 182),
			Size = UDim2.fromOffset(width, 40),
			BackgroundColor3 = color,
			Font = FONT_BOLD,
			TextSize = 14,
			TextColor3 = textColor,
			Text = text,
			AutoButtonColor = false,
			ZIndex = 52,
		}, { corner(8) })
		hoverEffect(button, color, color:Lerp(Color3.new(1, 1, 1), 0.12))
		return button
	end

	local copyButton = gateButton("Copy Invite", 20, 176, Color3.fromRGB(88, 101, 242), Color3.new(1, 1, 1))
	local continueButton = gateButton("I Joined - Continue", 204, 176, THEME.Accent, Color3.fromRGB(20, 20, 20))

	copyButton.Activated:Connect(copyInvite)
	continueButton.Activated:Connect(function()
		markJoined()
		tween(overlay, { BackgroundTransparency = 1 })
		task.delay(0.2, function()
			overlay:Destroy()
		end)
		openWindow()
	end)
end

screenGui.Parent = guiParent
window.Visible = false

if alreadyJoined() then
	openWindow()
else
	showGate()
end
