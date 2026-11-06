-- dictation.lua · read-aloud for any Roblox UI
--
-- Point at a label for three seconds and it is read out. A bar grows from the
-- middle of the text toward both of its edges while the wait runs, so the wait
-- is visible rather than mysterious.
--
-- Nothing here depends on a framework: mount() builds its own ScreenGui and
-- returns a handle. Speaking goes through opts.speak when one is given; the
-- built-in voice is a quiet tone per word, because a client script has no
-- speech synthesiser (see the README for what that means in practice).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local SoundService = game:GetService("SoundService")

local LP = Players.LocalPlayer

local Dictation = {}

local DEFAULTS = {
	hold = 3,                              -- seconds of hover before it speaks
	thickness = 1.5,                       -- underline height
	scan = 0.08,                           -- pointer re-test interval
	name = "Dictation",
	topLayer = true,                       -- parent to CoreGui when allowed
	promptOnFirstRun = true,
	accent = Color3.fromHex("0A84FF"),
	text = Color3.fromHex("FFFFFF"),
	muted = Color3.fromHex("98989D"),
	panel = Color3.fromHex("242426"),
	raised = Color3.fromHex("2C2C2E"),
	stroke = Color3.fromHex("38383A"),
	bg = Color3.fromHex("1C1C1E"),
	font = Enum.Font.Gotham,
	speak = nil,                           -- function(text) - nil uses the built-in voice
	state = nil,                           -- { get = fn(key), set = fn(key, value) }
}

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

local function tweenTo(obj, dur, props, style)
	local t = TweenService:Create(obj, TweenInfo.new(dur, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- the bar has to finish exactly when the hold does, so it ignores any easing
local function linear(obj, dur, props)
	local t = TweenService:Create(obj, TweenInfo.new(dur, Enum.EasingStyle.Linear), props)
	t:Play()
	return t
end

local function plain(text)
	return (tostring(text or ""):gsub("<[^>]->", ""):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1"))
end

function Dictation.mount(opts)
	local o = copy(DEFAULTS)
	for k, v in pairs(opts or {}) do o[k] = v end

	local gui
	pcall(function()
		gui = (o.topLayer and type(gethui) == "function") and gethui() or game:GetService("CoreGui")
	end)
	if not gui then gui = LP:WaitForChild("PlayerGui") end

	local screen = Instance.new("ScreenGui")
	screen.Name = o.name
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = gui

	local api = { enabled = false, screen = screen }

	-- persistence: optional, supplied by the caller as opts.state
	local function readState(key, default)
		if o.state and type(o.state.get) == "function" then
			local ok, v = pcall(o.state.get, key)
			if ok and v ~= nil then return v end
		end
		return default
	end

	local function writeState(key, value)
		if o.state and type(o.state.set) == "function" then
			pcall(o.state.set, key, value)
		end
	end

	-- speaking --------------------------------------------------
	local function blip()
		local s = Instance.new("Sound")
		s.Name = "dictationVoice"
		s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		s.Volume = 0.12
		s.PlaybackSpeed = 1.18
		s.Parent = SoundService
		pcall(function() s:Play() end)
		task.delay(1, function() if s.Parent then s:Destroy() end end)
	end

	function api.speak(text)
		text = plain(text)
		if text == "" then return end
		if o.speak then
			local ok, err = pcall(o.speak, text)
			if not ok then warn("[dictation] speak: " .. tostring(err)) end
			return
		end
		local n = 0
		for _ in text:gmatch("%S+") do n += 1 end
		for i = 1, math.min(n, 8) do
			task.delay((i - 1) * 0.11, function()
				if api.enabled then blip() end
			end)
		end
	end

	-- underline -------------------------------------------------
	local bar = Instance.new("Frame")
	bar.Name = "dictationUnderline"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Size = UDim2.fromOffset(0, o.thickness)
	bar.BackgroundColor3 = o.accent
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.ZIndex = 300
	bar.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bar

	local barTween, barToken = nil, 0

	local function hideBar()
		barToken += 1
		local id = barToken
		if barTween then barTween:Cancel(); barTween = nil end
		tweenTo(bar, 0.12, { Size = UDim2.fromOffset(0, o.thickness) })
		task.delay(0.2, function()
			if barToken == id and bar.Parent then bar.Visible = false end
		end)
	end

	local function textWidth(lbl)
		if lbl.TextScaled then return lbl.AbsoluteSize.X end
		local ok, size = pcall(function()
			return TextService:GetTextSize(lbl.Text, lbl.TextSize, lbl.Font, Vector2.new(10000, lbl.TextSize * 3))
		end)
		if ok and typeof(size) == "Vector2" then return math.min(size.X, lbl.AbsoluteSize.X) end
		return lbl.AbsoluteSize.X
	end

	local function showBar(lbl)
		barToken += 1
		if barTween then barTween:Cancel(); barTween = nil end

		local ap, as = lbl.AbsolutePosition, lbl.AbsoluteSize
		local w = textWidth(lbl)
		local x
		if lbl.TextXAlignment == Enum.TextXAlignment.Center then
			x = ap.X + (as.X - w) / 2
		elseif lbl.TextXAlignment == Enum.TextXAlignment.Right then
			x = ap.X + as.X - w
		else
			x = ap.X
		end

		local textTop
		if lbl.TextYAlignment == Enum.TextYAlignment.Top then
			textTop = ap.Y
		elseif lbl.TextYAlignment == Enum.TextYAlignment.Bottom then
			textTop = ap.Y + as.Y - lbl.TextSize
		else
			textTop = ap.Y + (as.Y - lbl.TextSize) / 2
		end

		bar.Visible = true
		bar.Position = UDim2.fromOffset(x + w / 2, textTop + lbl.TextSize * 1.02)
		-- offsets, not scale: UDim2.new(w, 0, ...) would read w as a fraction of
		-- the screen and draw a full-width line
		bar.Size = UDim2.fromOffset(0, o.thickness)
		barTween = linear(bar, o.hold, { Size = UDim2.fromOffset(w, o.thickness) })
	end

	-- hit testing -----------------------------------------------
	local cache, cacheAt = {}, 0

	local function reachable(d)
		local p = d.Parent
		while p and p ~= screen do
			if not p.Visible then return false end
			p = p.Parent
		end
		return p == screen
	end

	local function refresh()
		cacheAt = os.clock()
		cache = {}
		for _, d in ipairs(screen:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible and d.TextTransparency < 0.98 then
				local t = d.Text
				if type(t) == "string" and t ~= "" and reachable(d) then
					cache[#cache + 1] = d
				end
			end
		end
	end

	local function under(m)
		for i = #cache, 1, -1 do
			local d = cache[i]
			if d.Parent then
				local p, s = d.AbsolutePosition, d.AbsoluteSize
				if m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y then
					return d
				end
			end
		end
		return nil
	end

	local current, startedAt, spoken, acc = nil, 0, false, 0
	local blocked = false -- true while the first-run card is up

	local function clear()
		current, startedAt, spoken = nil, 0, false
		hideBar()
	end

	local conn = RunService.Heartbeat:Connect(function(dt)
		if not api.enabled or blocked then
			if current then clear() end
			return
		end
		acc += math.min(dt, 1 / 20)
		if acc < o.scan then return end
		acc = 0

		if os.clock() - cacheAt > 1 then refresh() end

		local hit = under(UserInputService:GetMouseLocation())
		if hit ~= current then
			current, spoken, startedAt = hit, false, os.clock()
			if hit then showBar(hit) else hideBar() end
		end
		if not current then return end

		if not spoken and os.clock() - startedAt >= o.hold then
			spoken = true
			api.speak(current.Text)
			barToken += 1
			local id = barToken
			task.delay(0.4, function() if barToken == id then hideBar() end end)
		end
	end)

	function api.setEnabled(on)
		api.enabled = on and true or false
		if not api.enabled then clear() end
		writeState("enabled", api.enabled)
	end

	function api.toggle()
		api.setEnabled(not api.enabled)
	end

	-- first-run card --------------------------------------------
	-- A yes is remembered whether or not the checkbox is ticked: choosing to have
	-- it read to you is the answer. A no only sticks when it is ticked.
	local function drawTick(parent)
		for i = 1, 2 do
			local arm = Instance.new("Frame")
			arm.Name = "tick"
			arm.AnchorPoint = Vector2.new(0.5, 0.5)
			arm.Position = UDim2.fromScale(i == 1 and 0.36 or 0.62, i == 1 and 0.60 or 0.42)
			arm.Size = UDim2.fromOffset(i == 1 and 5 or 9, 1.6)
			arm.Rotation = i == 1 and 45 or -45
			arm.BackgroundColor3 = o.bg
			arm.BorderSizePixel = 0
			arm.Parent = parent
		end
	end

	function api.prompt()
		if api.enabled or blocked or readState("promptDone", false) then return end
		blocked = true

		local backdrop = Instance.new("TextButton")
		backdrop.Text = ""
		backdrop.AutoButtonColor = false
		backdrop.BorderSizePixel = 0
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
		backdrop.BackgroundTransparency = 1
		backdrop.ZIndex = 500
		backdrop.Parent = screen

		-- CanvasGroup so the whole card fades as one; a plain Frame would drop its
		-- background and leave the text hanging for a frame
		local card = Instance.new("CanvasGroup")
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromOffset(360, 206)
		card.BackgroundColor3 = o.panel
		card.BackgroundTransparency = 0.02
		card.GroupTransparency = 0
		card.BorderSizePixel = 0
		card.ZIndex = 501
		card.Parent = screen
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 12)
		cc.Parent = card

		local function text(str, size, colour, y, h, wrapped, bold)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Font = bold and (o.fontBold or o.font) or o.font
			l.Text = str
			l.TextSize = size
			l.TextColor3 = colour
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.TextWrapped = wrapped or false
			l.Position = UDim2.fromOffset(22, y)
			l.Size = UDim2.new(1, -44, 0, h)
			l.ZIndex = 502
			l.Parent = card
			return l
		end

		text("Read text aloud?", 15, o.text, 20, 18, false, true)
		text("Point at a label and hold for three seconds and it will be read out. It stays off until you turn it on.", 11, o.muted, 46, 40, true)

		local function button(x, w, label, accent, onClick)
			local b = Instance.new("TextButton")
			b.Text = label
			b.Font = o.font
			b.TextSize = 12
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.Position = UDim2.fromOffset(x, 102)
			b.Size = UDim2.fromOffset(w, 34)
			b.TextColor3 = accent and o.bg or o.text
			b.BackgroundColor3 = accent and o.accent or o.stroke
			b.ZIndex = 502
			b.Parent = card
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = b
			b.MouseButton1Click:Connect(onClick)
			return b
		end

		local checked = false
		local box = Instance.new("Frame")
		box.Position = UDim2.fromOffset(22, 158)
		box.Size = UDim2.fromOffset(14, 14)
		box.BackgroundColor3 = o.raised
		box.BorderSizePixel = 0
		box.ZIndex = 502
		box.Parent = card
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 4)
		bc.Parent = box
		local bs = Instance.new("UIStroke")
		bs.Color = o.stroke
		bs.Thickness = 1
		bs.Parent = box

		local mark = Instance.new("Frame")
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundTransparency = 1
		mark.Visible = false
		mark.ZIndex = 503
		mark.Parent = box
		drawTick(mark)

		local row = Instance.new("TextButton")
		row.Text = ""
		row.AutoButtonColor = false
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Position = UDim2.fromOffset(18, 150)
		row.Size = UDim2.new(1, -36, 0, 30)
		row.ZIndex = 502
		row.Parent = card
		text("Don't show this again", 11, o.muted, 150, 30)

		row.MouseButton1Click:Connect(function()
			checked = not checked
			mark.Visible = checked
			box.BackgroundColor3 = checked and o.accent or o.raised
			bs.Color = checked and o.accent or o.stroke
		end)

		local function close()
			blocked = false
			tweenTo(card, 0.25, { GroupTransparency = 1 })
			tweenTo(backdrop, 0.25, { BackgroundTransparency = 1 })
			task.delay(0.26, function()
				card:Destroy()
				backdrop:Destroy()
			end)
		end

		button(22, 155, "Enable", true, function()
			api.setEnabled(true)
			writeState("promptDone", true)
			close()
		end)
		button(185, 153, "Not now", false, function()
			api.setEnabled(false)
			if checked then writeState("promptDone", true) end
			close()
		end)

		tweenTo(backdrop, 0.3, { BackgroundTransparency = 0.45 })
	end

	function api.destroy()
		conn:Disconnect()
		if bar.Parent then bar:Destroy() end
		if screen.Parent then screen:Destroy() end
	end

	local saved = readState("enabled", nil)
	if saved ~= nil then api.setEnabled(saved) end
	if o.promptOnFirstRun then task.delay(0.2, api.prompt) end

	return api
end

return Dictation
