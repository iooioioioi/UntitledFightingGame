-- StarterPlayerScripts/DashController (LocalScript)
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Config        = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))
local AnimationUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationUtil"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationConfig"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local DashHit        = Remotes:WaitForChild("DashHit")
local DashCancelled  = Remotes:WaitForChild("DashCancelled")
local DashState = Remotes:WaitForChild("DashState")

local DASH_ANIM_ID = AnimationConfig.DASH

-- ──────────────────────────────────────────────
-- STATE
-- ──────────────────────────────────────────────
local dashTrack       = nil
local canDashForward  = true
local canDashSide     = true
local canDashBackward = true
local isDashing       = false      -- local loop control only
local currentDashConn = nil        -- active Heartbeat connection
local dashCancelled   = false      -- set true when server cancels dash

-- Player attributes for cross-script communication (UI/CombatClient)
player:SetAttribute("IsDashing",  false)
player:SetAttribute("IsBlocking", false)

-- ──────────────────────────────────────────────
-- ANIMATION
-- ──────────────────────────────────────────────
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

-- ──────────────────────────────────────────────
-- SOUND
-- ──────────────────────────────────────────────
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

-- ──────────────────────────────────────────────
-- DIRECTION HELPERS
-- ──────────────────────────────────────────────
local function getCameraRelativeDirection()
	local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local d = UserInputService:IsKeyDown(Enum.KeyCode.D)

	if not (w or s or a or d) then return nil, nil end

	local camCF   = camera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local right   = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)

	if forward.Magnitude < 0.01 then return nil, nil end
	forward = forward.Unit
	right   = right.Unit

	local inputX = (d and 1 or 0) - (a and 1 or 0)
	local inputZ = (s and 1 or 0) - (w and 1 or 0)

	local worldDir = forward * -inputZ + right * inputX
	if worldDir.Magnitude == 0 then return nil, nil end

	-- Determine dash type from input
	local dashType
	if w and not s then
		dashType = "front"
	elseif s and not w then
		dashType = "back"
	else
		dashType = "side"
	end

	return worldDir.Unit, dashType
end

-- ──────────────────────────────────────────────
-- END-LAG (front dash miss penalty)
-- ──────────────────────────────────────────────
local function applyEndLag(char, hrp)
	local human = char:FindFirstChildOfClass("Humanoid")
	if not human then return end

	human.WalkSpeed  = 0
	human.JumpPower  = 0
	hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)

	-- Position lock during end-lag (same as stun correction)
	local lockedPos = hrp.Position
	local elapsed   = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= Config.DASH_END_LAG or not hrp.Parent then
			conn:Disconnect()
			return
		end
		local delta = (hrp.Position - lockedPos).Magnitude
		if delta > 1 then
			hrp.CFrame = CFrame.new(lockedPos.X, hrp.Position.Y, lockedPos.Z)
			hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
		end
	end)

	task.delay(Config.DASH_END_LAG, function()
		if human and human.Parent then
			human.WalkSpeed = 16
			human.JumpPower = 50
		end
	end)
end

-- ──────────────────────────────────────────────
-- MAIN DASH
-- ──────────────────────────────────────────────
local function doDash()
	if player:GetAttribute("IsBlocking") then return end
	if isDashing then return end

	local char  = player.Character
	if not char then return end
	local hrp   = char:FindFirstChild("HumanoidRootPart")
	local human = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not human or human.Health <= 0 then return end

	-- Get locked direction and type at moment of activation
	local lockedDir, dashType = getCameraRelativeDirection()
	if not lockedDir or not dashType then return end

	-- Check cooldowns
	if dashType == "front"  and not canDashForward  then return end
	if dashType == "back"   and not canDashBackward then return end
	if dashType == "side"   and not canDashSide     then return end

	-- Pick values
	local dashPower, dashDuration, dashCooldown
	if dashType == "front" then
		dashPower    = Config.DASH_POWER_FORWARD
		dashDuration = Config.DASH_DURATION_FORWARD
		dashCooldown = Config.DASH_COOLDOWN_FORWARD
	elseif dashType == "back" then
		dashPower    = Config.DASH_POWER_BACKWARD
		dashDuration = Config.DASH_DURATION_BACKWARD
		dashCooldown = Config.DASH_COOLDOWN_BACKWARD
	else
		dashPower    = Config.DASH_POWER_SIDE
		dashDuration = Config.DASH_DURATION_SIDE
		dashCooldown = Config.DASH_COOLDOWN_SIDE
	end

	-- Lock cooldown
	if dashType == "front" then
		canDashForward = false
	elseif dashType == "back" then
		canDashBackward = false
	else
		canDashSide = false
	end

	isDashing     = true
	dashCancelled = false
	player:SetAttribute("IsDashing", true)

	-- Disable AutoRotate during dash
	human.AutoRotate = false

	local track = getDashTrack()
	if track then track:Play() end
	playDashSound()

	local elapsed      = 0
	local hitboxActive = false
	local lastDashFireTime = -1  -- last elapsed time DashHit was fired

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

	local function endDash(hitSomething)
		if currentDashConn then
			currentDashConn:Disconnect()
			currentDashConn = nil
		end
		isDashing = false
		DashState:FireServer(nil)
		player:SetAttribute("IsDashing", false)
		human.AutoRotate = true

		-- Bleed velocity
		local vel = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(
			vel.X * 0.3,
			vel.Y,
			vel.Z * 0.3
		)

		-- Front dash miss end-lag
		if dashType == "front" and not hitSomething and not dashCancelled then
			applyEndLag(char, hrp)
		end
	end

	currentDashConn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		-- Server cancelled this dash (hit registered or blocked)
		if dashCancelled then
			endDash(true)  -- treat as hit so no end-lag on server cancel
			return
		end

		if not hrp or not hrp.Parent then
			endDash(false)
			return
		end

		if elapsed >= dashDuration then
			endDash(false)
			return
		end

		local progress = elapsed / dashDuration
		local speed    = easedSpeed(progress) * dashPower

		-- Always use locked direction — no momentum bleed
		hrp.AssemblyLinearVelocity = Vector3.new(
			lockedDir.X * speed,
			hrp.AssemblyLinearVelocity.Y,
			lockedDir.Z * speed
		)

		-- Front dash hitbox: poll server every 0.05s after threshold
		if dashType == "front" then
			if progress >= Config.DASH_HITBOX_START then
				hitboxActive = true
			end
			if hitboxActive and (elapsed - lastDashFireTime) >= 0.05 then
				lastDashFireTime = elapsed
				DashHit:FireServer()
			end
		end
	end)

	-- Cooldown timer
	task.delay(dashCooldown, function()
		if dashType == "front" then
			canDashForward = true
		elseif dashType == "back" then
			canDashBackward = true
		else
			canDashSide = true
		end
	end)
end

-- ──────────────────────────────────────────────
-- SERVER CANCEL LISTENER
-- ──────────────────────────────────────────────
DashCancelled.OnClientEvent:Connect(function()
	dashCancelled = true
end)

-- ──────────────────────────────────────────────
-- INPUT
-- ──────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		doDash()
	end
end)

-- ──────────────────────────────────────────────
-- RESPAWN CLEANUP
-- ──────────────────────────────────────────────
player.CharacterAdded:Connect(function()
	if currentDashConn then
		currentDashConn:Disconnect()
		currentDashConn = nil
	end
	dashTrack       = nil
	canDashForward  = true
	canDashSide     = true
	canDashBackward = true
	isDashing       = false
	dashCancelled   = false
	player:SetAttribute("IsDashing", false)
end)