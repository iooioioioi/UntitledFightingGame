-- StarterPlayerScripts/CombatClient (LocalScript)
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local Config   = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))

local AnimationUtil   = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationUtil"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationConfig"))

local M1Hit        = Remotes:WaitForChild("M1Hit")
local M1Animation  = Remotes:WaitForChild("M1Animation")
local RagdollEvent = Remotes:WaitForChild("RagdollEvent")
local BlockState   = Remotes:WaitForChild("BlockState")
local PlaySound    = Remotes:WaitForChild("PlaySound")
local BlockBroken  = Remotes:WaitForChild("BlockBroken")
local ComboReset   = Remotes:WaitForChild("ComboReset")

local FinisherLaunch = Remotes:WaitForChild("FinisherLaunch")

local ANIM_IDS      = AnimationConfig.M1
local BLOCK_ANIM_ID = AnimationConfig.BLOCK

-- ──────────────────────────────────────────────
-- STATE
-- ──────────────────────────────────────────────
local loadedTracks  = {}
local blockTrack    = nil
local canM1         = true
local isBlocking    = false
local comboCooldown = false  -- post-M4 lockout

-- ──────────────────────────────────────────────
-- ANIMATION HELPERS
-- ──────────────────────────────────────────────
local function getTrack(human, index)
	local id = ANIM_IDS[index]
	if not AnimationUtil.isValidAnimId(id) then return nil end
	if loadedTracks[index] then return loadedTracks[index] end
	local track = AnimationUtil.loadTrack(human, id)
	if track then loadedTracks[index] = track end
	return track
end

local function getBlockTrack()
	local char  = player.Character
	if not char then
		if Config.DEBUG then print("[BLOCK DEBUG] No character found") end
		return nil
	end
	local human = char:FindFirstChildOfClass("Humanoid")
	if not human then
		if Config.DEBUG then print("[BLOCK DEBUG] No humanoid found") end
		return nil
	end

	if not AnimationUtil.isValidAnimId(BLOCK_ANIM_ID) then
		if Config.DEBUG then print("[BLOCK DEBUG] Block anim ID is invalid:", BLOCK_ANIM_ID) end
		return nil
	end

	if blockTrack then
		local ok = pcall(function() return blockTrack.Length end)
		if ok then
			return blockTrack
		else
			if Config.DEBUG then print("[BLOCK DEBUG] Old track invalid, reloading") end
			blockTrack = nil
		end
	end

	if Config.DEBUG then print("[BLOCK DEBUG] Loading block animation:", BLOCK_ANIM_ID) end
	local track = AnimationUtil.loadTrack(human, BLOCK_ANIM_ID, Enum.AnimationPriority.Action, true)
	if track then
		if Config.DEBUG then print("[BLOCK DEBUG] Block animation loaded successfully") end
		blockTrack = track
		return track
	else
		if Config.DEBUG then print("[BLOCK DEBUG] Failed to load block animation") end
		return nil
	end
end

-- ──────────────────────────────────────────────
-- SOUND
-- ──────────────────────────────────────────────
local function playSound(position, key)
	local id = Config.SOUNDS and Config.SOUNDS[key]
	if not id or id == "" then return end

	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.CastShadow   = false
	part.Transparency = 1
	part.Size         = Vector3.new(1, 1, 1)
	part.Position     = position
	part.Parent       = workspace

	local sound = Instance.new("Sound")
	sound.SoundId            = id
	sound.RollOffMaxDistance = 60
	sound.Parent             = part
	sound:Play()

	game:GetService("Debris"):AddItem(part, 3)
end

PlaySound.OnClientEvent:Connect(function(position, key)
	playSound(position, key)
end)

-- ──────────────────────────────────────────────
-- BLOCK
-- ──────────────────────────────────────────────
local function startBlock()
	if player:GetAttribute("IsDashing") then return end
	if comboCooldown then return end
	isBlocking = true
	player:SetAttribute("IsBlocking", true)
	BlockState:FireServer(true)
	local track = getBlockTrack()
	if track then track:Play() end
end

local function stopBlock()
	isBlocking = false
	player:SetAttribute("IsBlocking", false)
	BlockState:FireServer(false)
	if blockTrack and blockTrack.IsPlaying then
		blockTrack:Stop()
	end
end

-- Server tells us our block was broken from behind
BlockBroken.OnClientEvent:Connect(function()
	stopBlock()
	if Config.DEBUG then print("[BLOCK DEBUG] Block broken by back hit") end
end)

-- ──────────────────────────────────────────────
-- M1 INPUT
-- ──────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not canM1 or isBlocking or comboCooldown then return end
		local char = player.Character
		if not char then return end
		local human = char:FindFirstChildOfClass("Humanoid")
		if not human or human.Health <= 0 then return end
		canM1 = false
		M1Hit:FireServer()
		task.wait(Config.M1_COOLDOWN)
		canM1 = true
	end
end)

-- ──────────────────────────────────────────────
-- BLOCK INPUT
-- ──────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if Config.DEBUG then print("[INPUT DEBUG] Key pressed:", input.KeyCode, "| Processed:", processed) end
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then
		if Config.DEBUG then print("[BLOCK DEBUG] F key detected in InputBegan") end
		startBlock()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F then
		if Config.DEBUG then print("[BLOCK DEBUG] F key released") end
		stopBlock()
	end
end)

-- ──────────────────────────────────────────────
-- COMBO RESET (post-M4 cooldown)
-- ──────────────────────────────────────────────
ComboReset.OnClientEvent:Connect(function()
	comboCooldown = true
	if Config.DEBUG then print("[COMBO DEBUG] Post-M4 cooldown started") end
	task.delay(Config.M4_COOLDOWN, function()
		comboCooldown = false
		if Config.DEBUG then print("[COMBO DEBUG] Post-M4 cooldown ended") end
	end)
end)

-- ──────────────────────────────────────────────
-- FINISHER LAUNCH (client visual handler)
-- ──────────────────────────────────────────────
FinisherLaunch.OnClientEvent:Connect(function(victimChar, launchDir, force, isM4)
	if not victimChar then return end

	-- Keep a reference to the cosmetic body parts
	-- The actual character will respawn but we want the old body to linger
	local humanoid = victimChar:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Wait for death then linger the body
	humanoid.Died:Connect(function()
		-- Disable humanoid so body stays frozen cosmetically
		task.delay(0.1, function()
			if not victimChar or not victimChar.Parent then return end

			-- Make all parts non-collidable so it doesnt interfere
			for _, part in ipairs(victimChar:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
					part.CanQuery   = false
					part.CanTouch   = false
				end
			end

			-- Linger for configured duration then clean up
			task.delay(Config.FINISHER_BODY_LINGER, function()
				if victimChar and victimChar.Parent then
					victimChar:Destroy()
				end
			end)
		end)
	end)
end)

-- ──────────────────────────────────────────────
-- ANIMATION EVENTS
-- ──────────────────────────────────────────────
M1Animation.OnClientEvent:Connect(function(attacker, comboIndex, isM4)
	local char = attacker.Character
	if not char then return end
	local human = char:FindFirstChildOfClass("Humanoid")
	if not human then return end
	local track = getTrack(human, comboIndex)
	if track then track:Play() end
end)

RagdollEvent.OnClientEvent:Connect(function(ragChar, isRagdolled)
	-- visual/camera effects to be added later
end)

-- ──────────────────────────────────────────────
-- RESPAWN CLEANUP
-- ──────────────────────────────────────────────
player.CharacterAdded:Connect(function()
	if Config.DEBUG then print("[DEBUG] Character added, resetting combat state") end
	canM1         = false
	isBlocking    = false
	comboCooldown = false
	loadedTracks  = {}
	blockTrack    = nil
	task.wait(0.1)
	canM1 = true
end)