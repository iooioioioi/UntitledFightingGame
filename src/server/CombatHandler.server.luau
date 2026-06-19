local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))
local AntiCheat = require(game:GetService("ServerScriptService"):WaitForChild("AntiCheat"))

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local M1Hit           = Remotes:WaitForChild("M1Hit")
local M1Animation     = Remotes:WaitForChild("M1Animation")
local RagdollEvent    = Remotes:WaitForChild("RagdollEvent")
local HitboxViz       = Remotes:WaitForChild("HitboxViz")
local BlockState      = Remotes:WaitForChild("BlockState")
local PlaySound       = Remotes:WaitForChild("PlaySound")
local FinisherLaunch  = Remotes:WaitForChild("FinisherLaunch")
local BlockBroken     = Remotes:WaitForChild("BlockBroken")
local ComboReset      = Remotes:WaitForChild("ComboReset")

local DashHit = Remotes:WaitForChild("DashHit")
local DashCancelled = Remotes:WaitForChild("DashCancelled")
local DashState = Remotes:WaitForChild("DashState")

local playerData = {}

local function getData(player)
	if not playerData[player] then
		playerData[player] = {
			combo            = 0,
			stunned          = false,
			ragdolled        = false,
			blocking         = false,
			protected        = false,
			finisherState    = false,
			comboCooldown    = false,
			damageImmune     = false,
			stunImmune       = false,
			dashState        = nil,   -- "front", "side", "back", or nil
			lastDashHit      = 0,
			lastM1           = 0,
			resetThread      = nil,
		}
	end
	return playerData[player]
end

-- ──────────────────────────────────────────────
-- RAGDOLL
-- ──────────────────────────────────────────────
local function enableRagdoll(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)

	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") then
			local socket = Instance.new("BallSocketConstraint")
			local a0     = Instance.new("Attachment")
			local a1     = Instance.new("Attachment")
			a0.Parent    = motor.Part0
			a1.Parent    = motor.Part1
			a0.CFrame    = motor.C0
			a1.CFrame    = motor.C1
			socket.Attachment0        = a0
			socket.Attachment1        = a1
			socket.LimitsEnabled      = true
			socket.TwistLimitsEnabled = true
			socket.Parent             = motor.Parent
			motor.Enabled             = false
		end
	end
	RagdollEvent:FireAllClients(character, true)
end

local function disableRagdoll(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") then
			motor.Enabled = true
		end
	end
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("BallSocketConstraint") then
			obj:Destroy()
		elseif obj:IsA("Attachment") and obj.Name == "Attachment" then
			obj:Destroy()
		end
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	RagdollEvent:FireAllClients(character, false)
end


-- ──────────────────────────────────────────────
-- STUN POSITION CORRECTION
-- Polls during stun and snaps player back if they move too far
-- Exempt threshold accounts for legitimate nudge distance
-- ──────────────────────────────────────────────
local STUN_CORRECTION_THRESHOLD = 2    -- studs before correction triggers
local STUN_CORRECTION_INTERVAL  = 0.05 -- poll every 50ms during stun

local function applyStunLock(victimPlayer, victimChar, stunDuration)
	local victimHRP = victimChar:FindFirstChild("HumanoidRootPart")
	if not victimHRP then return end

	local lockedPosition = victimHRP.Position
	local elapsed        = 0
	local conn

	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		-- Stop if stun expired or character gone
		if elapsed >= stunDuration or not victimChar or not victimChar.Parent then
			conn:Disconnect()
			return
		end

		local vd = getData(victimPlayer)
		if not vd.stunned then
			conn:Disconnect()
			return
		end

		local hrp = victimChar:FindFirstChild("HumanoidRootPart")
		if not hrp then
			conn:Disconnect()
			return
		end

		local delta = (hrp.Position - lockedPosition).Magnitude
		if delta > STUN_CORRECTION_THRESHOLD then
			-- Snap back — preserve Y to avoid floor clipping
			hrp.CFrame = CFrame.new(
				lockedPosition.X,
				hrp.Position.Y,
				lockedPosition.Z
			)
			hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
		end
	end)
end


-- ──────────────────────────────────────────────
-- ANGLE CHECKS
-- ──────────────────────────────────────────────
local function isHittingFront(attackerHRP, victimHRP)
	local toAttacker = (attackerHRP.Position - victimHRP.Position).Unit
	local victimLook = victimHRP.CFrame.LookVector
	local dot        = toAttacker:Dot(victimLook)
	local angle      = math.deg(math.acos(math.clamp(dot, -1, 1)))
	return angle < Config.BLOCK_ANGLE
end

local function isHittingBack(attackerHRP, victimHRP)
	local toAttacker = (attackerHRP.Position - victimHRP.Position).Unit
	local victimLook = victimHRP.CFrame.LookVector
	local dot        = toAttacker:Dot(victimLook)
	local angle      = math.deg(math.acos(math.clamp(dot, -1, 1)))
	return angle > Config.BLOCK_BREAK_ANGLE
end

-- ──────────────────────────────────────────────
-- HITBOX
-- ──────────────────────────────────────────────
local function getHitbox(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return {} end

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = {character}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hitboxCFrame = hrp.CFrame * Config.HITBOX_OFFSET
	local hitboxSize   = Config.HITBOX_SIZE

	if Config.SHOW_HITBOX then
		HitboxViz:FireAllClients(hitboxCFrame, hitboxSize)
	end

	local parts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, params)
	local hits  = {}
	local seen  = {}

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				seen[model] = true
				local victimPlayer = Players:GetPlayerFromCharacter(model)
				table.insert(hits, {
					player    = victimPlayer,
					character = model,
					humanoid  = humanoid,
					isNPC     = victimPlayer == nil,
				})
			end
		end
	end
	return hits
end

-- ──────────────────────────────────────────────
-- NPC STATE
-- ──────────────────────────────────────────────
local npcData = {}

local function getNPCData(model)
	if not npcData[model] then
		npcData[model] = { stunned = false, ragdolled = false }

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				npcData[model] = nil
			end)
		end

		model.AncestryChanged:Connect(function()
			if not model.Parent then
				npcData[model] = nil
			end
		end)
	end
	return npcData[model]
end

-- ──────────────────────────────────────────────
-- FINISHER LAUNCH
-- ──────────────────────────────────────────────
local CINEMATIC_DURATION    = 0.4   -- seconds both players are locked
local ATTACKER_RELEASE_DELAY = 0.1  -- seconds after victim launch before attacker freed

local function handleFinisherLaunch(attacker, victimPlayer, victimChar, victimHuman, isM4Finisher)
	local victimHRP    = victimChar:FindFirstChild("HumanoidRootPart")
	local attackerChar = attacker.Character
	local attackerHRP  = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
	if not victimHRP or not attackerHRP then return end

	local attackerHuman = attackerChar:FindFirstChildOfClass("Humanoid")
	local victimHumanoid = victimChar:FindFirstChildOfClass("Humanoid")
	if not attackerHuman or not victimHumanoid then return end

	-- Lock kill credit immediately
	local tag = Instance.new("ObjectValue")
	tag.Name   = "creator"
	tag.Value  = attacker
	tag.Parent = victimHuman
	Debris:AddItem(tag, 10)

	if isM4Finisher then
		local m4Tag = Instance.new("BoolValue")
		m4Tag.Name   = "isM4"
		m4Tag.Value  = true
		m4Tag.Parent = tag
	end

	-- Set victim to 1 HP and mark states
	victimHuman.Health = 1
	local vd = getData(victimPlayer)
	local ad = getData(attacker)
	vd.finisherState = true
	vd.ragdolled     = true
	vd.protected     = true
	ad.protected     = true  -- attacker invincible during cinematic

	-- ── CINEMATIC LOCK-IN ──
	-- Disable movement on both
	attackerHuman.WalkSpeed   = 0
	attackerHuman.JumpPower   = 0
	attackerHuman.AutoRotate  = false
	victimHumanoid.WalkSpeed  = 0
	victimHumanoid.JumpPower  = 0
	victimHumanoid.AutoRotate = false

	-- Anchor both HRPs
	attackerHRP.Anchored = true
	victimHRP.Anchored   = true

	-- Snap victim to face attacker
	local flatDir = (victimHRP.Position - attackerHRP.Position)
	flatDir = Vector3.new(flatDir.X, 0, flatDir.Z).Unit

	victimHRP.CFrame = CFrame.new(victimHRP.Position, victimHRP.Position + flatDir)
		* CFrame.Angles(0, math.pi, 0)

	-- Fire clients for cinematic visuals
	FinisherLaunch:FireAllClients(victimChar, flatDir, isM4Finisher, true) -- true = cinematic phase

	-- ── IMPACT MOMENT after cinematic delay ──
	task.delay(CINEMATIC_DURATION, function()
		if not victimChar or not victimChar.Parent then
			-- Victim gone — clean up attacker
			attackerHRP.Anchored      = false
			attackerHuman.WalkSpeed   = 16
			attackerHuman.JumpPower   = 50
			attackerHuman.AutoRotate  = true
			ad.protected              = false
			return
		end

		-- Unanchor victim and enable ragdoll
		victimHRP.Anchored = false
		enableRagdoll(victimChar)

		-- Calculate and apply launch force
		local force, lift
		if isM4Finisher then
			force = Config.FINISHER_FORCE_M4
			lift  = Config.FINISHER_LIFT_M4
		else
			force = Config.FINISHER_FORCE_NORMAL
			lift  = Config.FINISHER_LIFT_NORMAL
		end

		victimHRP.AssemblyLinearVelocity = flatDir * force + Vector3.new(0, lift, 0)

		-- Fire clients for launch visuals
		FinisherLaunch:FireAllClients(victimChar, flatDir, isM4Finisher, false) -- false = launch phase

		-- Release attacker slightly after victim launches
		task.delay(ATTACKER_RELEASE_DELAY, function()
			if attackerHRP and attackerHRP.Parent then
				attackerHRP.Anchored      = false
			end
			if attackerHuman and attackerHuman.Parent then
				attackerHuman.WalkSpeed   = 16
				attackerHuman.JumpPower   = 50
				attackerHuman.AutoRotate  = true
			end
			ad.protected = false
		end)

		-- Poll for collision
		local pollConn
		local stuckHandled = false
		pollConn = RunService.Heartbeat:Connect(function()
			if not victimChar or not victimChar.Parent
				or not victimHRP or not victimHRP.Parent then
				pollConn:Disconnect()
				return
			end

			local speed = victimHRP.AssemblyLinearVelocity.Magnitude

			if speed < Config.FINISHER_COLLISION_THRESHOLD and not stuckHandled then
				stuckHandled = true
				pollConn:Disconnect()

				-- Stick briefly then fall
				victimHRP.Anchored = true
				task.delay(Config.FINISHER_STICK_TIME, function()
					if victimHRP and victimHRP.Parent then
						victimHRP.Anchored = false
					end
					task.delay(0.1, function()
						if victimHuman and victimChar and victimChar.Parent then
							victimHuman:TakeDamage(1)
						end
					end)
				end)
			end
		end)

		-- Safety fallback: force kill after 10s if no collision detected
		task.delay(10, function()
			if vd.finisherState and victimHuman and victimChar and victimChar.Parent then
				pollConn:Disconnect()
				victimHuman:TakeDamage(1)
			end
		end)
	end)
end

-- ──────────────────────────────────────────────
-- APPLY HIT
-- ──────────────────────────────────────────────
local function applyHit(attacker, attackerChar, hit, comboIndex)
	local victimChar   = hit.character
	local victimHuman  = hit.humanoid
	local victimPlayer = hit.player
	local isNPC        = hit.isNPC

	-- State checks
	local stunned, ragdolled, blocking, protected, finisherState, damageImmune, stunImmune
	if isNPC then
		local nd    = getNPCData(victimChar)
		stunned     = nd.stunned
		ragdolled   = nd.ragdolled
		blocking    = false
		protected   = false
		finisherState = false
		damageImmune  = false
		stunImmune    = false
	else
		local vd    = getData(victimPlayer)
		stunned     = vd.stunned
		ragdolled   = vd.ragdolled
		blocking    = vd.blocking
		protected   = vd.protected
		finisherState = vd.finisherState
		damageImmune  = vd.damageImmune
		stunImmune    = vd.stunImmune
	end

	-- Never hit ragdolled, finisher, or protected targets
	if ragdolled or finisherState or protected then return end
	if victimHuman.Health <= 0 then return end

	-- Stunned players can still take damage but not be re-stunned
	-- (handled below per hit type)

	local myHRP     = attackerChar:FindFirstChild("HumanoidRootPart")
	local victimHRP = victimChar:FindFirstChild("HumanoidRootPart")
	if not myHRP or not victimHRP then return end

	-- Distance sanity check
	local hitboxCenter = (myHRP.CFrame * Config.HITBOX_OFFSET).Position
	if (victimHRP.Position - hitboxCenter).Magnitude > Config.MAX_HIT_DISTANCE then return end

	local isM4 = (comboIndex == Config.MAX_COMBO)

	-- ── BLOCK HANDLING ──
	if blocking and not isNPC then
		if isHittingBack(myHRP, victimHRP) then
			-- Block break: hit from behind
			local baseDamage = Config.DAMAGE[comboIndex] or 8
			local damage     = math.floor(baseDamage * Config.BLOCK_BREAK_MULTIPLIER)
			local stunTime   = Config.STUN_TIME * Config.BLOCK_BREAK_MULTIPLIER

			local willKill = (victimHuman.Health - damage) <= 0
			if willKill then
				handleFinisherLaunch(attacker, victimPlayer, victimChar, victimHuman, isM4)
				return
			end

			-- Tag and damage
			local tag = Instance.new("ObjectValue")
			tag.Name   = "creator"
			tag.Value  = attacker
			tag.Parent = victimHuman
			Debris:AddItem(tag, 2)

			victimHuman:TakeDamage(damage)

			-- Force stop block on victim client
			BlockBroken:FireClient(victimPlayer)

			-- Apply stun to victim
			local vd.blocking = false
			if not stunImmune then
				vd.stunned = true
				applyStunLock(victimPlayer, victimChar, stunTime)
				task.delay(stunTime, function() vd.stunned = false end)
			end

			-- Small knockback
			local dir = (victimHRP.Position - myHRP.Position).Unit
			victimHRP.CFrame = victimHRP.CFrame + dir * Config.KNOCKBACK_FORCE

			PlaySound:FireAllClients(victimHRP.Position, "BLOCK_BREAK")
			return

		elseif isHittingFront(myHRP, victimHRP) then
			-- Front block: reduced damage, no stun
			if not damageImmune then
				victimHuman:TakeDamage(Config.BLOCK_HIT_DAMAGE)
			end
			PlaySound:FireAllClients(victimHRP.Position, "BLOCK")
			return
		end
	end

	-- ── NORMAL HIT ──
	local damage = Config.DAMAGE[comboIndex] or 8
	local willKill = (victimHuman.Health - damage) <= 0

	-- Finisher check
	if willKill and not isNPC then
		handleFinisherLaunch(attacker, victimPlayer, victimChar, victimHuman, isM4)
		return
	end

	-- Kill credit tag
	if not isNPC then
		local tag = Instance.new("ObjectValue")
		tag.Name   = "creator"
		tag.Value  = attacker
		tag.Parent = victimHuman
		Debris:AddItem(tag, 2)
	end

	if not damageImmune then
		victimHuman:TakeDamage(damage)
	end

	-- Sound
	local soundKey = "M1_" .. comboIndex
	PlaySound:FireAllClients(victimHRP.Position, soundKey)

	-- M4: ragdoll onto ground
	if isM4 then
		local dir = myHRP.CFrame.LookVector
		dir = Vector3.new(dir.X, 0, dir.Z).Unit

		-- Face victim toward attacker then randomize rotation slightly
		local faceDir = (myHRP.Position - victimHRP.Position)
		faceDir = Vector3.new(faceDir.X, 0, faceDir.Z).Unit

		local randomRoll = math.random() < 0.8
			and 0
			or math.rad(math.random(-30, 30))

		victimHRP.CFrame = CFrame.new(victimHRP.Position, victimHRP.Position + faceDir)
			* CFrame.Angles(0, math.pi, randomRoll)

		if isNPC then
			local nd = getNPCData(victimChar)
			nd.ragdolled = true
			enableRagdoll(victimChar)
			victimHRP.AssemblyLinearVelocity = dir * Config.M4_KNOCKBACK + Vector3.new(0, 5, 0)
			task.delay(Config.RAGDOLL_TIME, function()
				if victimChar and victimChar.Parent then
					disableRagdoll(victimChar)
				end
				nd.ragdolled = false
			end)
		else
			local vd = getData(victimPlayer)
			vd.ragdolled = true
			enableRagdoll(victimChar)
			victimHRP.AssemblyLinearVelocity = dir * Config.M4_KNOCKBACK + Vector3.new(0, 5, 0)
			task.delay(Config.RAGDOLL_TIME, function()
				if victimChar and victimChar.Parent then
					disableRagdoll(victimChar)
				end
				vd.ragdolled = false

				-- Post-ragdoll immunity windows
				vd.damageImmune = true
				task.delay(Config.POST_RAGDOLL_DAMAGE_IMMUNITY, function()
					vd.damageImmune = false
				end)
				vd.stunImmune = true
				task.delay(Config.POST_RAGDOLL_STUN_IMMUNITY, function()
					vd.stunImmune = false
				end)
			end)
		end

	else
		-- Regular M1: nudge + stun
		local dir = (victimHRP.Position - myHRP.Position).Unit
		victimHRP.CFrame = victimHRP.CFrame + dir * Config.KNOCKBACK_FORCE

        if isNPC then
			local nd = getNPCData(victimChar)
			nd.stunned = true
			task.delay(Config.STUN_TIME, function() nd.stunned = false end)
		else
			local vd = getData(victimPlayer)
			if not stunImmune then
				vd.stunned = true
				applyStunLock(victimPlayer, victimChar, Config.STUN_TIME)
				task.delay(Config.STUN_TIME, function() vd.stunned = false end)
			end
		end
	end
end

-- ──────────────────────────────────────────────
-- DEATH TRACKING
-- ──────────────────────────────────────────────
local function onCharacterDied(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.Died:Connect(function()
		local tag    = humanoid:FindFirstChild("creator")
		local killer = tag and tag.Value

		if killer and killer ~= player and killer.Parent then
			local kStats = killer:FindFirstChild("leaderstats")
			if kStats then
				kStats.Kills.Value += 1

				-- Check if this was an M4 finisher by tag
				local isM4Kill = tag:FindFirstChild("isM4") ~= nil
				local baseCoins = isM4Kill
					and Config.COINS_PER_KILL_M4_FINISHER
					or  Config.COINS_PER_KILL_NORMAL

				-- Stackable multiplier hook (future gamepasses add to this)
				local multiplier = 1
				kStats.Coins.Value += math.floor(baseCoins * multiplier)
			end
		end

		local dStats = player:FindFirstChild("leaderstats")
		if dStats then dStats.Deaths.Value += 1 end

        local data = getData(player)

		-- Capture finisher state BEFORE clearing so respawn delay is correct
		local wasFinisher = data.finisherState

		data.ragdolled     = false
		data.stunned       = false
		data.blocking      = false
		data.combo         = 0
		data.comboCooldown = false
		data.finisherState = false
		data.damageImmune  = false
		data.stunImmune    = false
		data.dashState = nil
        DashCancelled:FireClient(attacker)

		if data.resetThread then
			task.cancel(data.resetThread)
			data.resetThread = nil
		end

		local respawnDelay = wasFinisher
			and Config.FINISHER_RESPAWN_DELAY
			or  Config.RESPAWN_DELAY_NORMAL

		task.delay(respawnDelay, function()
			if not player or not player.Parent then return end
			player:LoadCharacter()
		end)    
	end)
end

-- ──────────────────────────────────────────────
-- RESPAWN FREEZE + PROTECTION
-- ──────────────────────────────────────────────
local function onCharacterAdded(player, character)
	onCharacterDied(player, character)

	local humanoid = character:WaitForChild("Humanoid")

	-- Brief movement freeze
	humanoid.WalkSpeed  = 0
	humanoid.JumpPower  = 0
	task.delay(Config.SPAWN_FREEZE_DURATION, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = 16
			humanoid.JumpPower = 50
		end
	end)

	-- Spawn protection
	local pdata = getData(player)
	pdata.protected = true
	task.delay(Config.SPAWN_PROTECTION, function()
		pdata.protected = false
	end)
end

-- ──────────────────────────────────────────────
-- BLOCK STATE
-- ──────────────────────────────────────────────
BlockState.OnServerEvent:Connect(function(player, isBlocking)
	-- Validate arg type
	if type(isBlocking) ~= "boolean" then return end

	local data = getData(attacker)
	if data.stunned or data.ragdolled or data.blocking or data.comboCooldown then return end
	if data.dashState == "front" then return end

	local legitimate = AntiCheat.validateBlock(player, isBlocking)
	if not legitimate then return end

	data.blocking = isBlocking
end)

-- ──────────────────────────────────────────────
-- M1 HIT
-- ──────────────────────────────────────────────
M1Hit.OnServerEvent:Connect(function(attacker)
	-- Anticheat M1 validation
	if not AntiCheat.validateM1(attacker) then return end

	local character = attacker.Character
	if not character then return end

	local human = character:FindFirstChildOfClass("Humanoid")
	if not human or human.Health <= 0 then return end

	local data = getData(attacker)
	if data.stunned or data.ragdolled or data.blocking or data.comboCooldown then return end

	local now = tick()
	if (now - data.lastM1) < (Config.M1_COOLDOWN * 0.9) then return end
	data.lastM1 = now

	data.combo   = (data.combo % Config.MAX_COMBO) + 1
	local comboIndex = data.combo
	local isM4       = (comboIndex == Config.MAX_COMBO)

	if data.resetThread then
		task.cancel(data.resetThread)
		data.resetThread = nil
	end

	if isM4 then
		data.combo = 0
		-- Post-M4 cooldown: lock M1s, fire client to reset UI
		data.comboCooldown = true
		ComboReset:FireClient(attacker)
		task.delay(Config.M4_COOLDOWN, function()
			data.comboCooldown = false
		end)
	else
		data.resetThread = task.delay(Config.COMBO_WINDOW, function()
			data.combo       = 0
			data.resetThread = nil
		end)
	end

	M1Animation:FireAllClients(attacker, comboIndex, isM4)

	local function tryHitbox()
		local hits = getHitbox(character)
		if #hits > 0 then
			for _, hit in ipairs(hits) do
				applyHit(attacker, character, hit, comboIndex)
			end
			return true
		end
		return false
	end

	if not tryHitbox() then
		task.delay(0.1, function()
			if character and character.Parent then
				local retryHuman = character:FindFirstChildOfClass("Humanoid")
				if retryHuman and retryHuman.Health > 0 then
					tryHitbox()
				end
			end
		end)
	end
end)

-- ──────────────────────────────────────────────
-- DASH HIT (front dash offensive hitbox)
-- ──────────────────────────────────────────────
DashHit.OnServerEvent:Connect(function(attacker)
	local character = attacker.Character
	if not character then return end

	local human = character:FindFirstChildOfClass("Humanoid")
	if not human or human.Health <= 0 then return end

	local data = getData(attacker)

	-- Must be in a front dash
	if data.dashState ~= "front" then return end

	-- Rate limit: can't fire faster than dash cooldown allows
	local now = tick()
	if (now - data.lastDashHit) < (Config.DASH_COOLDOWN_FORWARD * 0.9) then return end
	data.lastDashHit = now

	local hits = getHitbox(character)
	if #hits == 0 then return end

	for _, hit in ipairs(hits) do
		local victimChar   = hit.character
		local victimHuman  = hit.humanoid
		local victimPlayer = hit.player
		local isNPC        = hit.isNPC

		if isNPC then continue end -- dash hit only affects players for now

		local vd = getData(victimPlayer)
		if vd.ragdolled or vd.finisherState or vd.protected then continue end
		if victimHuman.Health <= 0 then continue end

		local myHRP     = character:FindFirstChild("HumanoidRootPart")
		local victimHRP = victimChar:FindFirstChild("HumanoidRootPart")
		if not myHRP or not victimHRP then continue end

		-- Distance check
		local hitboxCenter = (myHRP.CFrame * Config.HITBOX_OFFSET).Position
		if (victimHRP.Position - hitboxCenter).Magnitude > Config.DASH_HIT_MAX_DISTANCE then continue end

		-- Check if victim is blocking
		if vd.blocking then
			if isHittingFront(myHRP, victimHRP) then
				-- Blocked: near-zero damage, cancel dash, attacker gets end-lag
				victimHuman:TakeDamage(Config.DASH_HIT_BLOCK_DAMAGE)
				PlaySound:FireAllClients(victimHRP.Position, "BLOCK")
				-- Signal client to cancel dash with end-lag
				data.dashState = nil
				DashCancelled:FireClient(attacker)
				return
			elseif isHittingBack(myHRP, victimHRP) then
				-- Block break from dash
				local damage = math.floor(Config.DASH_HIT_DAMAGE * Config.BLOCK_BREAK_MULTIPLIER)
				local willKill = (victimHuman.Health - damage) <= 0
				if willKill then
					handleFinisherLaunch(attacker, victimPlayer, victimChar, victimHuman, false)
					data.dashState = nil    
                    DashCancelled:FireClient(attacker)
					return
				end
				victimHuman:TakeDamage(damage)
				BlockBroken:FireClient(victimPlayer)
				vd.blocking = false
				if not vd.stunImmune then
					vd.stunned = true
					applyStunLock(victimPlayer, victimChar,
						Config.DASH_HIT_STUN * Config.BLOCK_BREAK_MULTIPLIER)
					task.delay(Config.DASH_HIT_STUN * Config.BLOCK_BREAK_MULTIPLIER,
						function() vd.stunned = false end)
				end
				PlaySound:FireAllClients(victimHRP.Position, "BLOCK_BREAK")
				data.dashState = nil
				DashCancelled:FireClient(attacker)
				return
			end
		end

		-- Normal dash hit
		local willKill = (victimHuman.Health - Config.DASH_HIT_DAMAGE) <= 0
		if willKill then
			handleFinisherLaunch(attacker, victimPlayer, victimChar, victimHuman, false)
			data.dashState = nil
            DashCancelled:FireClient(attacker)
			return
		end

		local tag = Instance.new("ObjectValue")
		tag.Name   = "creator"
		tag.Value  = attacker
		tag.Parent = victimHuman
		Debris:AddItem(tag, 2)

		victimHuman:TakeDamage(Config.DASH_HIT_DAMAGE)
		PlaySound:FireAllClients(victimHRP.Position, "M1_1")

		if not vd.stunImmune then
			vd.stunned = true
			applyStunLock(victimPlayer, victimChar, Config.DASH_HIT_STUN)
			task.delay(Config.DASH_HIT_STUN, function() vd.stunned = false end)
		end

		-- Cancel dash on hit
		data.dashState = nil
		return
	end
end)


-- ──────────────────────────────────────────────
-- DASH STATE
-- ──────────────────────────────────────────────
DashState.OnServerEvent:Connect(function(player, state)
	if type(state) ~= "string" and state ~= nil then return end
	local validStates = { front = true, side = true, back = true }
	if state ~= nil and not validStates[state] then return end
	local data = getData(player)
	data.dashState = state
end)

-- ──────────────────────────────────────────────
-- PLAYER ADDED / REMOVED
-- ──────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	playerData[player] = {
		combo            = 0,
		stunned          = false,
		ragdolled        = false,
		blocking         = false,
		protected        = false,
		finisherState    = false,
		comboCooldown    = false,
		damageImmune     = false,
		stunImmune       = false,
		dashState        = nil,
		lastDashHit      = 0,
		lastM1           = 0,
		resetThread      = nil,
	}

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerData[player] = nil
end)