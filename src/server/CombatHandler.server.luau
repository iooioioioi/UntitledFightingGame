local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))

local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local M1Hit        = Remotes:WaitForChild("M1Hit")
local M1Animation  = Remotes:WaitForChild("M1Animation")
local RagdollEvent = Remotes:WaitForChild("RagdollEvent")
local HitboxViz    = Remotes:WaitForChild("HitboxViz")
local BlockState   = Remotes:WaitForChild("BlockState")
local PlaySound    = Remotes:WaitForChild("PlaySound")

local playerData = {}

local function getData(player)
	if not playerData[player] then
		playerData[player] = {
			combo       = 0,
			stunned     = false,
			ragdolled   = false,
			blocking    = false,
			protected   = false,
			lastM1      = 0,
			resetThread = nil,
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
			local a0 = Instance.new("Attachment")
			local a1 = Instance.new("Attachment")
			a0.Parent = motor.Part0
			a1.Parent = motor.Part1
			a0.CFrame = motor.C0
			a1.CFrame = motor.C1
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
-- BLOCK ANGLE CHECK
-- ──────────────────────────────────────────────
local function isHittingFront(attackerHRP, victimHRP)
	local toAttacker = (attackerHRP.Position - victimHRP.Position).Unit
	local victimLook = victimHRP.CFrame.LookVector
	local dot        = toAttacker:Dot(victimLook)
	local angle      = math.deg(math.acos(math.clamp(dot, -1, 1)))
	return angle < Config.BLOCK_ANGLE
end

-- ──────────────────────────────────────────────
-- HITBOX — hits both players AND NPCs
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
				-- victimPlayer is nil for NPCs, that's fine
				table.insert(hits, {
					player    = victimPlayer,  -- nil if NPC
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
-- NPC state table (since they have no playerData)
-- ──────────────────────────────────────────────
local npcData = {}  -- [model] = { stunned, ragdolled }

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
-- APPLY HIT — works for both players and NPCs
-- ──────────────────────────────────────────────
local function applyHit(attacker, attackerChar, hit, isFinisher, comboIndex)
	local victimChar   = hit.character
	local victimHuman  = hit.humanoid
	local victimPlayer = hit.player
	local isNPC        = hit.isNPC

	-- Get state depending on type
	local stunned, ragdolled, blocking, protected
	if isNPC then
		local nd   = getNPCData(victimChar)
		stunned    = nd.stunned
		ragdolled  = nd.ragdolled
		blocking   = false
		protected  = false
	else
		local vd   = getData(victimPlayer)
		stunned    = vd.stunned
		ragdolled  = vd.ragdolled
		blocking   = vd.blocking
		protected  = vd.protected
	end

	if stunned or ragdolled or protected then return end
	if victimHuman.Health <= 0 then return end

	local myHRP     = attackerChar:FindFirstChild("HumanoidRootPart")
	local victimHRP = victimChar:FindFirstChild("HumanoidRootPart")
	if not myHRP or not victimHRP then return end
    -- Distance sanity check
	local hitboxCenter = (myHRP.CFrame * Config.HITBOX_OFFSET).Position
	if (victimHRP.Position - hitboxCenter).Magnitude > Config.MAX_HIT_DISTANCE then return end

	-- Block check (players only)
	if blocking and isHittingFront(myHRP, victimHRP) then
		PlaySound:FireAllClients(victimHRP.Position, "BLOCK")
		return
	end

	local damage  = Config.DAMAGE[comboIndex] or 10
	local willKill = (victimHuman.Health - damage) <= 0

	-- Kill credit tag (players only, for leaderboard)
	if not isNPC then
		local tag = Instance.new("ObjectValue")
		tag.Name   = "creator"
		tag.Value  = attacker
		tag.Parent = victimHuman
		Debris:AddItem(tag, 2)
	end

	victimHuman:TakeDamage(damage)

	-- Sound + UI feedback
	local soundKey = isFinisher and "FINISHER" or ("M1_" .. comboIndex)
	PlaySound:FireAllClients(victimHRP.Position, soundKey)
	-- ShowCombo:FireAllClients(victimHRP.Position, comboIndex, isFinisher)
	-- ShowDamage:FireAllClients(victimHRP.Position, damage)

	-- Apply physics effects
	if isFinisher then
		local knockback = willKill and Config.FINISH_KNOCKBACK * 2 or Config.FINISH_KNOCKBACK
		local lift      = willKill and Config.FINISH_LIFT * 1.5    or Config.FINISH_LIFT
		local dir       = (victimHRP.Position - myHRP.Position).Unit

		if isNPC then
			local nd = getNPCData(victimChar)
			nd.ragdolled = true
			enableRagdoll(victimChar)
			victimHRP.AssemblyLinearVelocity = dir * knockback + Vector3.new(0, lift, 0)
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
			victimHRP.AssemblyLinearVelocity = dir * knockback + Vector3.new(0, lift, 0)
			task.delay(Config.RAGDOLL_TIME, function()
				if victimChar and victimChar.Parent then
					disableRagdoll(victimChar)
				end
				vd.ragdolled = false
			end)
		end

	else
		-- Regular M1: small nudge + stun
		local dir = (victimHRP.Position - myHRP.Position).Unit
		victimHRP.CFrame = victimHRP.CFrame + dir * Config.KNOCKBACK_FORCE

		if isNPC then
			local nd = getNPCData(victimChar)
			nd.stunned = true
			task.delay(Config.STUN_TIME, function() nd.stunned = false end)
		else
			local vd = getData(victimPlayer)
			vd.stunned = true
			task.delay(Config.STUN_TIME, function() vd.stunned = false end)
		end
	end
end

-- ──────────────────────────────────────────────
-- DEATH TRACKING (players only)
-- ──────────────────────────────────────────────
local function onCharacterDied(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.Died:Connect(function()
		local tag = humanoid:FindFirstChild("creator")
		if tag and tag.Value and tag.Value ~= player then
			local killer = tag.Value
			local kStats = killer:FindFirstChild("leaderstats")
			if kStats then
				kStats.Kills.Value += 1
				kStats.Coins.Value += Config.COINS_PER_KILL
			end
		end

		local dStats = player:FindFirstChild("leaderstats")
		if dStats then dStats.Deaths.Value += 1 end

		local data = getData(player)
		data.ragdolled  = false
		data.stunned    = false
		data.blocking   = false
		data.combo      = 0
		if data.resetThread then
			task.cancel(data.resetThread)
			data.resetThread = nil
		end

		task.delay(1, function()
			if player and player.Parent then
				player:LoadCharacter()
			end
		end)
	end)
end

-- ──────────────────────────────────────────────
-- BLOCK STATE
-- ──────────────────────────────────────────────
BlockState.OnServerEvent:Connect(function(player, isBlocking)
	getData(player).blocking = isBlocking
end)

-- ──────────────────────────────────────────────
-- M1 HIT
-- ──────────────────────────────────────────────
M1Hit.OnServerEvent:Connect(function(attacker)
	local character = attacker.Character
	if not character then return end

	local human = character:FindFirstChildOfClass("Humanoid")
	if not human or human.Health <= 0 then return end

	local data = getData(attacker)
	if data.stunned or data.ragdolled or data.blocking then return end

	local now = tick()
	if (now - data.lastM1) < (Config.M1_COOLDOWN * 0.9) then return end
	data.lastM1 = now

	data.combo   = (data.combo % Config.MAX_COMBO) + 1
	local comboIndex = data.combo
	local isFinisher = (comboIndex == Config.MAX_COMBO)

	if data.resetThread then
		task.cancel(data.resetThread)
		data.resetThread = nil
	end

	if isFinisher then
		data.combo = 0
	else
		data.resetThread = task.delay(Config.COMBO_WINDOW, function()
			data.combo = 0
			data.resetThread = nil
		end)
	end

    M1Animation:FireAllClients(attacker, comboIndex, isFinisher)

	local function tryHitbox()
		local hits = getHitbox(character)
		if #hits > 0 then
			for _, hit in ipairs(hits) do
				applyHit(attacker, character, hit, isFinisher, comboIndex)
			end
			return true
		end
		return false
	end

	if not tryHitbox() then
		task.delay(0.1, function()
			if character and character.Parent then
				tryHitbox()
			end
		end)
	end
end)

-- ──────────────────────────────────────────────
-- PLAYER ADDED / REMOVED
-- ──────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	playerData[player] = {
		combo       = 0,
		stunned     = false,
		ragdolled   = false,
		blocking    = false,
		protected   = false,
		lastM1      = 0,
		resetThread = nil,
	}

	player.CharacterAdded:Connect(function(character)
		onCharacterDied(player, character)

		local pdata = getData(player)
		pdata.protected = true
		task.delay(Config.SPAWN_PROTECTION, function()
			pdata.protected = false
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerData[player] = nil
end)