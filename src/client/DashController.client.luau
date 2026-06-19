-- StarterPlayerScripts/DashController (LocalScript)
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))
local AnimationUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationUtil"))

local DASH_ANIM_ID = "rbxassetid://" -- TODO: fill in dash animation ID

local dashTrack  = nil
local canDash    = true
local isDashing  = false

-- Share dash state with CombatClient via a module or just a bindable
-- We use a shared table in ReplicatedStorage so CombatClient can read it
local sharedState = {
	isDashing  = false,
	isBlocking = false,
}
-- Store on player so other local scripts can access it
player:SetAttribute("IsDashing",  false)
player:SetAttribute("IsBlocking", false)

local function getDashTrack()
	local char  = player.Character
	if not char then return nil end
	local human = char:FindFirstChildOfClass("Humanoid")
	if not human then return nil end
	if dashTrack then return dashTrack end
	local track = AnimationUtil.loadTrack(human, DASH_ANIM_ID)
	if track then dashTrack = track end
	return track
end

local function playDashSound()
	local id = Config.SOUNDS and Config.SOUNDS.DASH
	if not id or id == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume  = 1
	sound.Parent  = workspace
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 3)
end

local function getInputDirection()
	local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local d = UserInputService:IsKeyDown(Enum.KeyCode.D)

	local inputX = (d and 1 or 0) - (a and 1 or 0)
	local inputZ = (s and 1 or 0) - (w and 1 or 0)

	if inputX == 0 and inputZ == 0 then return nil end
	return inputX, inputZ
end

-- Gets world direction from current camera + current input
local function getWorldDirection()
	local inputX, inputZ = getInputDirection()
	if not inputX then return nil end

	local camCF   = camera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local right   = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)

	if forward.Magnitude < 0.01 then return nil end
	forward = forward.Unit
	right   = right.Unit

	local worldDir = forward * -inputZ + right * inputX
	if worldDir.Magnitude == 0 then return nil end
	return worldDir.Unit
end

local function doDash()
	if not canDash then return end
	if player:GetAttribute("IsBlocking") then return end  -- no dash while blocking

	local char  = player.Character
	if not char then return end
	local hrp   = char:FindFirstChild("HumanoidRootPart")
	local human = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not human or human.Health <= 0 then return end

	if not getInputDirection() then return end  -- standing still

	canDash   = false
	isDashing = true
	player:SetAttribute("IsDashing", true)

	local track = getDashTrack()
	if track then track:Play() end
	playDashSound()

	local elapsed = 0

	-- Easing function: smooth ramp up, hold, smooth ramp down
	-- Input: progress 0-1, Output: speed multiplier 0-1
	local function easedSpeed(progress)
		if progress < 0.2 then
			-- Ramp up over first 20%
			return progress / 0.2
		elseif progress < 0.65 then
			-- Hold at peak for middle 45%
			return 1
		else
			-- Smooth ramp down over last 35% using sine ease
			local t = (progress - 0.65) / 0.35
			return 1 - math.sin(t * math.pi * 0.5)
		end
	end

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		if not hrp or not hrp.Parent then
			conn:Disconnect()
			isDashing = false
			player:SetAttribute("IsDashing", false)
			return
		end

		if elapsed >= Config.DASH_DURATION then
			conn:Disconnect()
			isDashing = false
			player:SetAttribute("IsDashing", false)

			-- Bleed off remaining horizontal velocity smoothly
			local vel = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(
				vel.X * 0.3,
				vel.Y,
				vel.Z * 0.3
			)
			return
		end

		local progress = elapsed / Config.DASH_DURATION
		local speed    = easedSpeed(progress) * Config.DASH_POWER

		-- Re-evaluate direction every frame from current camera
		-- This is what lets you steer mid-dash in shiftlock
		local dir = getWorldDirection()
		if dir then
			hrp.AssemblyLinearVelocity = Vector3.new(
				dir.X * speed,
				hrp.AssemblyLinearVelocity.Y,
				dir.Z * speed
			)
		else
			-- Player let go of keys mid-dash — bleed out
			local vel = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(
				vel.X * 0.85,
				vel.Y,
				vel.Z * 0.85
			)
		end
	end)

	task.delay(Config.DASH_COOLDOWN, function()
		canDash = true
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		doDash()
	end
end)

player.CharacterAdded:Connect(function()
	dashTrack = nil
	canDash   = true
	isDashing = false
	player:SetAttribute("IsDashing", false)
end)