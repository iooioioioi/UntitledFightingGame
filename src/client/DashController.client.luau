-- StarterPlayerScripts/DashController (LocalScript)
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))
local AnimationUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationUtil"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationConfig"))

local DASH_ANIM_ID = AnimationConfig.DASH

local dashTrack       = nil
local canDashForward  = true
local canDashSide     = true
local canDashBackward = true
local isDashing       = false

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

-- Returns "forward", "backward", "side", or nil if standing still
local function getDashDirection()
	local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local d = UserInputService:IsKeyDown(Enum.KeyCode.D)

	if not (w or s or a or d) then return nil end

	if w and not s then return "forward" end
	if s and not w then return "backward" end
	return "side"
end


local function playDashSound()
	local id = Config.SOUNDS and Config.SOUNDS.DASH
	if not id or id == "" then return end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local pos  = hrp and hrp.Position or Vector3.new(0, 0, 0)

	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.CastShadow   = false
	part.Transparency = 1
	part.Size         = Vector3.new(1, 1, 1)
	part.Position     = pos
	part.Parent       = workspace

	local sound = Instance.new("Sound")
	sound.SoundId            = id
	sound.RollOffMaxDistance = 60
	sound.Volume             = 1
	sound.Parent             = part
	sound:Play()

	game:GetService("Debris"):AddItem(part, 3)
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
	if player:GetAttribute("IsBlocking") then return end
	if isDashing then return end

	local char  = player.Character
	if not char then return end
	local hrp   = char:FindFirstChild("HumanoidRootPart")
	local human = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not human or human.Health <= 0 then return end

	local direction = getDashDirection()
	if not direction then return end

	-- Check correct cooldown
	if direction == "forward"  and not canDashForward  then return end
	if direction == "backward" and not canDashBackward then return end
	if direction == "side"     and not canDashSide     then return end

	-- Pick values based on direction
	local dashPower, dashDuration, dashCooldown
	if direction == "forward" then
		dashPower    = Config.DASH_POWER_FORWARD
		dashDuration = Config.DASH_DURATION_FORWARD
		dashCooldown = Config.DASH_COOLDOWN_FORWARD
	elseif direction == "backward" then
		dashPower    = Config.DASH_POWER_BACKWARD
		dashDuration = Config.DASH_DURATION_BACKWARD
		dashCooldown = Config.DASH_COOLDOWN_BACKWARD
	else
		dashPower    = Config.DASH_POWER_SIDE
		dashDuration = Config.DASH_DURATION_SIDE
		dashCooldown = Config.DASH_COOLDOWN_SIDE
	end

	-- Lock the correct cooldown
	if direction == "forward" then
		canDashForward = false
	elseif direction == "backward" then
		canDashBackward = false
	else
		canDashSide = false
	end

	isDashing = true
	player:SetAttribute("IsDashing", true)

	local track = getDashTrack()
	if track then track:Play() end
	playDashSound()

	local elapsed = 0

	local function easedSpeed(progress)
		if progress < 0.2 then
			return progress / 0.2
		elseif progress < 0.65 then
			return 1
		else
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

		if elapsed >= dashDuration then
			conn:Disconnect()
			isDashing = false
			player:SetAttribute("IsDashing", false)

			local vel = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(
				vel.X * 0.3,
				vel.Y,
				vel.Z * 0.3
			)
			return
		end

		local progress = elapsed / dashDuration
		local speed    = easedSpeed(progress) * dashPower

		local dir = getWorldDirection()
		if dir then
			hrp.AssemblyLinearVelocity = Vector3.new(
				dir.X * speed,
				hrp.AssemblyLinearVelocity.Y,
				dir.Z * speed
			)
		else
			local vel = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(
				vel.X * 0.85,
				vel.Y,
				vel.Z * 0.85
			)
		end
	end)

	task.delay(dashCooldown, function()
		if direction == "forward" then
			canDashForward = true
		elseif direction == "backward" then
			canDashBackward = true
		else
			canDashSide = true
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		doDash()
	end
end)

player.CharacterAdded:Connect(function()
	dashTrack       = nil
	canDashForward  = true
	canDashSide     = true
	canDashBackward = true
	isDashing       = false
	player:SetAttribute("IsDashing", false)
end)