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

local playerData = {}

local function getData(player)
	if not playerData[player] then
		playerData[player] = {
			combo            = 0,
			stunned          = false,
			ragdolled        = false,
			blocking         = false,
			protected        = false,
			finisherState    = false, -- true = launched, untouchable
			comboCooldown    = false, -- true = post-M4 lockout
			damageImmune     = false, -- post-ragdoll damage immunity
			stunImmune       = false, -- post-ragdoll stun immunity
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
local function handleFinisherLaunch(attacker, victimPlayer, victimChar, victimHuman, isM4Finisher)
	local victimHRP = victimChar:FindFirstChild("HumanoidRootPart")
	local attackerChar = attacker.Character
	local attackerHRP  = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
	if not victimHRP or not attackerHRP then return end

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

	-- Set victim to 1 HP and mark as finisher state
	victimHuman.Health = 1
	local vd = getData(victimPlayer)
	vd.finisherState = true
	vd.ragdolled     = true

	-- Enable ragdoll
	enableRagdoll(victimChar)

	-- Calculate launch direction with upward angle
	local flatDir = (victimHRP.Position - attackerHRP.Position)
	flatDir = Vector3.new(flatDir.X, 0, flatDir.Z).Unit

	local force, lift
	if isM4Finisher then
		force = Config.FINISHER_FORCE_M4
		lift  = Config.FINISHER_LIFT_M4
	else
		force = Config.FINISHER_FORCE_NORMAL
		lift  = Config.FINISHER_LIFT_NORMAL
	end

	-- Rotate victim to face away from attacker (back faces travel direction)
	victimHRP.CFrame = CFrame.new(victimHRP.Position, victimHRP.Position + flatDir)
		* CFrame.Angles(0, math.pi, 0)

	-- Apply launch velocity server side
	victimHRP.AssemblyLinearVelocity = flatDir * force + Vector3.new(0, lift, 0)

	-- Fire clients for visual effects
	FinisherLaunch:FireAllClients(victimChar, flatDir, force, isM4Finisher)

	-- Server polls for collision
	local pollConn
	local stuckHandled = false
	pollConn = RunService.Heartbeat:Connect(function()
		if not victimChar or not victimChar.Parent or not victimHRP or not victimHRP.Parent then
			pollConn:Disconnect()
			return
		end

		local velocity = victimHRP.AssemblyLinearVelocity
		local speed    = velocity.Magnitude

		if speed < Config.FINISHER_COLLISION_THRESHOLD and not stuckHandled then
			stuckHandled = true
			pollConn:Disconnect()

			-- Stick briefly then fall
			victimHRP.Anchored = true
			task.delay(Config.FINISHER_STICK_TIME, function()
				if victimHRP and victimHRP.Parent then
					victimHRP.Anchored = false
				end

				-- Deal final kill blow
				task.delay(0.1, function()
					if victimHuman and victimChar and victimChar.Parent then
						victimHuman:TakeDamage(1)
					end
				end)
			end)
		end
	end)

	-- Safety fallback: if collision never detected after 10s force kill
	task.delay(10, function()
		if vd.finisherState and victimHuman and victimChar and victimChar.Parent then
			pollConn:Disconnect()
			victimHuman:TakeDamage(1)
		end
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
			local vd = getData(victimPlayer)
			vd.blocking = false
			if not stunImmune then
				vd.stunned = true
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
		data.ragdolled     = false
		data.stunned       = false
		data.blocking      = false
		data.combo         = 0
		data.comboCooldown = false
		data.finisherState = false
		data.damageImmune  = false
		data.stunImmune    = false

		if data.resetThread then
			task.cancel(data.resetThread)
			data.resetThread = nil
		end

		-- Respawn delay — finisher deaths are handled by handleFinisherLaunch
		-- This covers normal deaths only
		local vd = getData(player)
		local delay = vd.finisherState
			and Config.FINISHER_RESPAWN_DELAY
			or  Config.RESPAWN_DELAY_NORMAL

		task.delay(delay, function()
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
	local data = getData(player)
	if data.ragdolled or data.finisherState then return end

	-- Validate with anticheat before accepting
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