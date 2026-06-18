-- StarterPlayerScripts/CombatClient (LocalScript)
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local Config   = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig"))

local M1Hit        = Remotes:WaitForChild("M1Hit")
local M1Animation  = Remotes:WaitForChild("M1Animation")
local RagdollEvent = Remotes:WaitForChild("RagdollEvent")
local BlockState   = Remotes:WaitForChild("BlockState")
local PlaySound    = Remotes:WaitForChild("PlaySound")

-- M1 animation IDs — fill in when ready, leave as "" to skip
local ANIM_IDS = {
	[1] = "rbxassetid://135625480489610",  -- M1 hit 1
	[2] = "",  -- M1 hit 2
	[3] = "",  -- M1 hit 3
	[4] = "",  -- M1 hit 4 / finisher
}

-- Block animation ID
local BLOCK_ANIM_ID = "rbxassetid://80663798062489"

-- ──────────────────────────────────────────────
-- HELPERS
-- ──────────────────────────────────────────────
local function isValidAnimId(id)
	if not id or id == "" then return false end
	if id:find("YOUR_ID") then return false end
	return id:match("^rbxassetid://%d+$") ~= nil
end

local loadedTracks = {}
local blockTrack   = nil
local canM1        = true
local isBlocking   = false

local function getTrack(human, index)
	local id = ANIM_IDS[index]
	if not isValidAnimId(id) then return nil end
	if loadedTracks[index] then return loadedTracks[index] end

	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return human.Animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		loadedTracks[index] = track
		return track
	end
	return nil
end

local function getBlockTrack()
	local char  = player.Character
	if not char then
		print("[BLOCK DEBUG] No character found")
		return nil
	end
	local human = char:FindFirstChildOfClass("Humanoid")
	if not human then
		print("[BLOCK DEBUG] No humanoid found")
		return nil
	end

	if not isValidAnimId(BLOCK_ANIM_ID) then
		print("[BLOCK DEBUG] Block anim ID is invalid:", BLOCK_ANIM_ID)
		return nil
	end

	-- Always reload if blockTrack belongs to old humanoid
	if blockTrack then
		local ok = pcall(function() return blockTrack.Length end)
		if ok then
			return blockTrack
		else
			print("[BLOCK DEBUG] Old track invalid, reloading")
			blockTrack = nil
		end
	end

	print("[BLOCK DEBUG] Loading block animation:", BLOCK_ANIM_ID)
	local anim = Instance.new("Animation")
	anim.AnimationId = BLOCK_ANIM_ID
	local ok, track = pcall(function()
		return human.Animator:LoadAnimation(anim)
	end)
	if ok and track then
		print("[BLOCK DEBUG] Block animation loaded successfully")
		track.Priority = Enum.AnimationPriority.Action
		track.Looped   = true
		blockTrack     = track
		return track
	else
		print("[BLOCK DEBUG] Failed to load block animation:", track)
		return nil
	end
end

-- ──────────────────────────────────────────────
-- SOUND — reads from CombatConfig centrally
-- ──────────────────────────────────────────────
local soundCache = {}

local function playSound(position, key)
	local id = Config.SOUNDS and Config.SOUNDS[key]
	if not id or id == "" then return end
	local sound = soundCache[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId            = id
		sound.RollOffMaxDistance = 60
		sound.Parent             = workspace
		soundCache[key]          = sound
	end
	sound:Play()
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
	print("[INPUT DEBUG] Key pressed:", input.KeyCode, "| Processed:", processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then
		print("[BLOCK DEBUG] F key detected in InputBegan")
		startBlock()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F then
		print("[BLOCK DEBUG] F key released")
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
	print("[DEBUG] Character added, resetting combat state")
	canM1        = false
	isBlocking   = false
	loadedTracks = {}
	blockTrack   = nil
	task.wait(0.1)
	canM1 = true
end)