-- StarterPlayerScripts/HitboxVisualizer (LocalScript)
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HitboxViz = Remotes:WaitForChild("HitboxViz")
local player  = Players.LocalPlayer

local boxes = {}

local function makeBox(size)
	local box = Instance.new("Part")
	box.Name          = "HitboxViz"
	box.Size          = size
	box.Anchored      = true
	box.CanCollide    = false
	box.CanQuery      = false
	box.CanTouch      = false
	box.CastShadow    = false
	box.BrickColor    = BrickColor.new("Bright red")
	box.Material      = Enum.Material.SmoothPlastic
	box.Transparency  = 0.6
	box.Parent        = workspace
	return box
end

local function trackCharacter(character)
	-- Wait for root
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	local box = makeBox(Config.HITBOX_SIZE)
	boxes[character] = box

	character.AncestryChanged:Connect(function()
		if not character.Parent then
			if box and box.Parent then box:Destroy() end
			boxes[character] = nil
		end
	end)
end

local function onPlayerAdded(p)
	if p.Character then trackCharacter(p.Character) end
	p.CharacterAdded:Connect(trackCharacter)
end

for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Move boxes every frame
RunService.RenderStepped:Connect(function()
	for character, box in pairs(boxes) do
		if not character.Parent then
			if box and box.Parent then box:Destroy() end
			boxes[character] = nil
		else
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				box.CFrame = hrp.CFrame * Config.HITBOX_OFFSET
			end
		end
	end
end)

-- Flash on actual hit (server tells us)
if Config.SHOW_HITBOX then
	HitboxViz.OnClientEvent:Connect(function(cf, size)
		local flash = Instance.new("Part")
		flash.Size          = size
		flash.CFrame        = cf
		flash.Anchored      = true
		flash.CanCollide    = false
		flash.CanQuery      = false
		flash.BrickColor    = BrickColor.new("Bright orange")
		flash.Material      = Enum.Material.Neon
		flash.Transparency  = 0.3
		flash.CastShadow    = false
		flash.Parent        = workspace
		game:GetService("Debris"):AddItem(flash, 0.12)
	end)
end