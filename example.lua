-- example.lua · the smallest useful mount
-- Paste this into an executor with dictation.lua somewhere it can reach.

local Dictation = loadstring(game:HttpGet("https://raw.githubusercontent.com/0craxy0/Aether-Dictation/main/dictation.lua"))()

-- a tiny UI to read from: three labels, nothing else
local gui = Instance.new("ScreenGui")
gui.IgnoreGuiInset = true
gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(320, 150)
panel.Position = UDim2.new(0.5, -160, 0.5, -75)
panel.BackgroundColor3 = Color3.fromHex("242426")
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

for i, text in ipairs({ "Hover me for three seconds", "And this one too", "The bar grows from the middle" }) do
	local label = Instance.new("TextLabel")
	label.Text = text
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(20, 16 + (i - 1) * 40)
	label.Size = UDim2.new(1, -40, 0, 24)
	label.Parent = panel
end

local d = Dictation.mount()

-- turn it on without waiting for the card
d.setEnabled(true)

print("[example] hover any label above for three seconds")
