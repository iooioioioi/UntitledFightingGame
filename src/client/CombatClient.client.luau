-- StarterPlayerScripts/CombatClient (LocalScript)
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local Config   = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))

local AnimationUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationUtil"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimationConfig"))

local M1Hit        = Remotes:WaitForChild("M1Hit")
local M1Animation  = Remotes:WaitForChild("M1Animation")
local RagdollEvent = Remotes:WaitForChild("RagdollEvent")
local BlockState   = Remotes:WaitForChild("BlockState")
local PlaySound    = Remotes:WaitForChild("PlaySound")

local ANIM_IDS      = AnimationConfig.M1
local BLOCK_ANIM_ID = AnimationConfig.BLOCK

-- ──────────────────────────────────────────────
-- HELPERS
-- ──────────────────────────────────────────────

local loadedTracks = {}
local blockTrack   = nil
local canM1        = true
local isBlocking   = false

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
-- SOUND — reads from CombatConfig centrally
-- ──────────────────────────────────────────────
local function playSound(position, key)
	local id = Config.SOUNDS and Config.SOUNDS[key]
	if not id or id == "" then return end

	local part = Instance.new("Part")
	part.Anchored    = true
	part.CanCollide  = false
	part.CastShadow  = false
	part.Transparency = 1
	part.Size        = Vector3.new(1, 1, 1)
	part.Position    = position
	part.Parent      = workspace

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
-- M1 INPUT
-- ──────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Can M1 during a dash (as requested), but not while blocking
		if not canM1 or isBlocking then return end
		local char = player.Character
		if not char then return end
		local human = char:FindFirstChildOfClass("Humanoid")
		if not human or human.Health <= 0 then return end
		canM1 = false
		M1Hit:FireServer()
		task.wait(0.38)
		canM1 = true
	end
end)

-- Replace startBlock() with this to prevent blocking while dashing:
local function startBlock()
	if player:GetAttribute("IsDashing") then return end  -- no block while dashing
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
-- ANIMATION EVENTS
-- ──────────────────────────────────────────────
M1Animation.OnClientEvent:Connect(function(attacker, comboIndex, isFinisher)
	local char = attacker.Character
	if not char then return end
	local human = char:FindFirstChildOfClass("Humanoid")
	if not human then return end
	local track = getTrack(human, comboIndex)
	if track then track:Play() end
end)

RagdollEvent.OnClientEvent:Connect(function(ragChar, isRagdolled)
	-- camera effects later
end)

-- ──────────────────────────────────────────────
-- RESPAWN CLEANUP
-- ──────────────────────────────────────────────
player.CharacterAdded:Connect(function()
	if Config.DEBUG then print("[DEBUG] Character added, resetting combat state") end
	canM1        = false
	isBlocking   = false
	loadedTracks = {}
	blockTrack   = nil
	task.wait(0.1)
	canM1 = true
end)