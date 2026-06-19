-- ServerScriptService/AntiCheat
-- Fully server-side. Never exposes data to clients.
-- CombatHandler calls AntiCheat.flag() and AntiCheat.validateBlock() externally.

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")

local ACConfig = require(game:GetService("ServerScriptService"):WaitForChild("AntiCheatConfig"))local ACConfig = require(game:GetService("ServerScriptService"):WaitForChild("AntiCheatConfig"))

local store = DataStoreService:GetDataStore(ACConfig.DATASTORE_NAME)

local AntiCheat = {}

-- ──────────────────────────────────────────────
-- INTERNAL STATE
-- ──────────────────────────────────────────────
local playerACData   = {}  -- runtime data per player
local webhookCache   = {}  -- dedup cache: "userId_reason" = last post timestamp

local function getACData(player)
	if not playerACData[player] then
		playerACData[player] = {
			warnings         = 0,
			banned           = false,
			banReason        = "",
			log              = {},

			-- Runtime detection state
			minorFlags       = {},   -- { timestamp } list
			lastBlockToggle  = 0,
			rapidToggleList  = {},   -- { timestamp } list
			blockToggleTimes = {},   -- for variance detection
			m1TimingList     = {},   -- for auto-clicker detection
			m1FireList       = {},   -- for remote spam detection
			blockFireList    = {},   -- for remote spam detection
			blockHeldSince   = nil,  -- timestamp block started
			speedOverTime    = 0,    -- seconds sustained over max speed
			lastPosition     = nil,  -- last recorded HRP position
		}
	end
	return playerACData[player]
end

-- ──────────────────────────────────────────────
-- DATASTORE
-- ──────────────────────────────────────────────
local function loadACData(player)
	local key = "ac_player_" .. player.UserId
	local ok, data = pcall(store.GetAsync, store, key)
	if ok and type(data) == "table" then
		local acd = getACData(player)
		acd.warnings  = data.warnings  or 0
		acd.banned    = data.banned    or false
		acd.banReason = data.banReason or ""
		acd.log       = data.log       or {}
	end
end

local function saveACData(player)
	local acd = getACData(player)
	if not acd then return end
	local key  = "ac_player_" .. player.UserId
	local data = {
		warnings  = acd.warnings,
		banned    = acd.banned,
		banReason = acd.banReason,
		log       = acd.log,
	}
	pcall(store.SetAsync, store, key, data)
end

-- ──────────────────────────────────────────────
-- WEBHOOK
-- ──────────────────────────────────────────────
local function postWebhook(player, reason, severity)
	if not ACConfig.WEBHOOK_ENABLED or ACConfig.WEBHOOK_URL == "" then return end

	local dedupKey = tostring(player.UserId) .. "_" .. reason
	local now      = tick()

	if webhookCache[dedupKey] and (now - webhookCache[dedupKey]) < ACConfig.WEBHOOK_DEDUP_WINDOW then
		return  -- same message posted too recently
	end
	webhookCache[dedupKey] = now

	local acd     = getACData(player)
	local color   = severity == "blatant" and 16711680  -- red
		or severity == "major"   and 16744272  -- orange
		or                           16776960  -- yellow

	local payload = HttpService:JSONEncode({
		embeds = {{
			title       = "⚠️ AntiCheat Flag — " .. severity:upper(),
			color       = color,
			description = "**Player:** " .. player.Name
				.. " (" .. player.UserId .. ")\n"
				.. "**Reason:** " .. reason .. "\n"
				.. "**Warnings:** " .. acd.warnings .. "/" .. ACConfig.WARNINGS_BEFORE_BAN .. "\n"
				.. "**Banned:** " .. tostring(acd.banned),
			footer = { text = "UntitledFightingGame Anticheat • " .. os.date("%Y-%m-%d %H:%M:%S") },
		}}
	})

	pcall(function()
		HttpService:PostAsync(ACConfig.WEBHOOK_URL, payload, Enum.HttpContentType.ApplicationJson)
	end)
end

-- ──────────────────────────────────────────────
-- BAN / KICK
-- ──────────────────────────────────────────────
local function banPlayer(player, reason)
	local acd     = getACData(player)
	acd.banned    = true
	acd.banReason = reason

	-- Add to log
	table.insert(acd.log, {
		reason    = reason,
		timestamp = os.time(),
	})
	-- Keep log at max 20 entries
	while #acd.log > 20 do
		table.remove(acd.log, 1)
	end

	saveACData(player)
	postWebhook(player, "BANNED: " .. reason, "blatant")

	player:Kick("You have been banned.\nReason: " .. reason
		.. "\nIf you believe this is a mistake, contact support.")
end

local function warnPlayer(player, reason)
	local acd = getACData(player)
	acd.warnings += 1

	table.insert(acd.log, {
		reason    = "WARNING " .. acd.warnings .. ": " .. reason,
		timestamp = os.time(),
	})
	while #acd.log > 20 do
		table.remove(acd.log, 1)
	end

	postWebhook(player, reason, acd.warnings >= ACConfig.WARNINGS_BEFORE_BAN and "blatant" or "major")

	if acd.warnings >= ACConfig.WARNINGS_BEFORE_BAN then
		banPlayer(player, reason)
	else
		saveACData(player)
		-- Notify player silently via kick message preview — just save, no kick yet
		-- Optionally you could notify in-game here in future
	end
end

-- ──────────────────────────────────────────────
-- PUBLIC FLAG FUNCTION
-- Called by CombatHandler for combat-related flags
-- ──────────────────────────────────────────────
function AntiCheat.flag(player, severity, reason)
	if not player or not player.Parent then return end
	local acd = getACData(player)
	if acd.banned then return end

	if severity == "blatant" then
		warnPlayer(player, reason)

	elseif severity == "major" then
		warnPlayer(player, reason)

	elseif severity == "minor" then
		local now = tick()
		table.insert(acd.minorFlags, now)

		-- Clean flags outside window
		local cutoff = now - ACConfig.MINOR_FLAG_WINDOW
		local fresh  = {}
		for _, t in ipairs(acd.minorFlags) do
			if t > cutoff then
				table.insert(fresh, t)
			end
		end
		acd.minorFlags = fresh

		postWebhook(player, reason, "minor")

		if #acd.minorFlags >= ACConfig.MINOR_FLAGS_PER_WARNING then
			acd.minorFlags = {}
			warnPlayer(player, "Accumulated suspicious behavior: " .. reason)
		end
	end
end

-- ──────────────────────────────────────────────
-- BLOCK VALIDATION
-- Called by CombatHandler on every BlockState event
-- Returns true if block toggle is legitimate
-- ──────────────────────────────────────────────
function AntiCheat.validateBlock(player, isBlocking)
	if not player or not player.Parent then return true end
	local acd = getACData(player)
	local now = tick()

	-- Rate limit: minimum interval between toggles
	if (now - acd.lastBlockToggle) < ACConfig.MIN_BLOCK_TOGGLE_INTERVAL then
		-- Rapid toggle detected
		table.insert(acd.rapidToggleList, now)

		-- Clean outside window
		local cutoff = now - ACConfig.RAPID_TOGGLE_WINDOW
		local fresh  = {}
		for _, t in ipairs(acd.rapidToggleList) do
			if t > cutoff then table.insert(fresh, t) end
		end
		acd.rapidToggleList = fresh

		if #acd.rapidToggleList >= ACConfig.RAPID_TOGGLE_COUNT then
			acd.rapidToggleList = {}
			AntiCheat.flag(player, "minor", "Rapid block toggle spam")
		end

		return false  -- reject this toggle
	end

	-- Auto-block variance detection
	table.insert(acd.blockToggleTimes, now)
	if #acd.blockToggleTimes > ACConfig.AUTO_BLOCK_SAMPLE then
		table.remove(acd.blockToggleTimes, 1)
	end

	if #acd.blockToggleTimes >= ACConfig.AUTO_BLOCK_SAMPLE then
		local intervals = {}
		for i = 2, #acd.blockToggleTimes do
			table.insert(intervals, acd.blockToggleTimes[i] - acd.blockToggleTimes[i-1])
		end
		local avg = 0
		for _, v in ipairs(intervals) do avg += v end
		avg /= #intervals

		local variance = 0
		for _, v in ipairs(intervals) do
			variance += math.abs(v - avg)
		end
		variance /= #intervals

		if variance < ACConfig.AUTO_BLOCK_VARIANCE then
			AntiCheat.flag(player, "major", "Auto-block detected (inhuman toggle variance)")
			acd.blockToggleTimes = {}
		end
	end

	-- Infinite block detection
	if isBlocking then
		acd.blockHeldSince = now
	else
		acd.blockHeldSince = nil
	end

	acd.lastBlockToggle = now
	return true  -- legitimate toggle
end

-- ──────────────────────────────────────────────
-- M1 TIMING VALIDATION
-- Called by CombatHandler on every M1Hit event
-- Returns true if timing is legitimate
-- ──────────────────────────────────────────────
function AntiCheat.validateM1(player)
	if not player or not player.Parent then return true end
	local acd = getACData(player)
	local now = tick()

	-- Remote spam check
	table.insert(acd.m1FireList, now)
	local cutoff = now - ACConfig.REMOTE_SPAM_WINDOW
	local fresh  = {}
	for _, t in ipairs(acd.m1FireList) do
		if t > cutoff then table.insert(fresh, t) end
	end
	acd.m1FireList = fresh

	if #acd.m1FireList > ACConfig.M1_MAX_RATE then
		acd.m1FireList = {}
		AntiCheat.flag(player, "minor", "M1 remote spam")
		return false
	end

	-- Auto-clicker variance check
	table.insert(acd.m1TimingList, now)
	if #acd.m1TimingList > ACConfig.AUTO_CLICKER_SAMPLE then
		table.remove(acd.m1TimingList, 1)
	end

	if #acd.m1TimingList >= ACConfig.AUTO_CLICKER_SAMPLE then
		local intervals = {}
		for i = 2, #acd.m1TimingList do
			table.insert(intervals, acd.m1TimingList[i] - acd.m1TimingList[i-1])
		end
		local avg = 0
		for _, v in ipairs(intervals) do avg += v end
		avg /= #intervals

		local variance = 0
		for _, v in ipairs(intervals) do
			variance += math.abs(v - avg)
		end
		variance /= #intervals

		if variance < ACConfig.AUTO_CLICKER_VARIANCE then
			AntiCheat.flag(player, "major", "Auto-clicker detected (inhuman M1 timing)")
			acd.m1TimingList = {}
			return false
		end
	end

	return true
end

-- ──────────────────────────────────────────────
-- SPEED + POSITION MONITOR
-- Runs on server heartbeat per player
-- ──────────────────────────────────────────────
local lastPollTime = {}

RunService.Heartbeat:Connect(function()
	local now = tick()
	for _, player in ipairs(Players:GetPlayers()) do
		local last = lastPollTime[player] or 0
		if (now - last) < ACConfig.SPEED_POLL_INTERVAL then continue end
		lastPollTime[player] = now

		local acd = getACData(player)
		if acd.banned then continue end

		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			acd.lastPosition = nil
			acd.speedOverTime = 0
			continue
		end

		local pos   = hrp.Position
		local speed = hrp.AssemblyLinearVelocity.Magnitude

		-- Position delta check
		if acd.lastPosition then
			local delta = (pos - acd.lastPosition).Magnitude
			if delta > ACConfig.MAX_POSITION_DELTA then
				AntiCheat.flag(player, "blatant",
					"Teleport detected (delta: " .. math.floor(delta) .. " studs)")
			end
		end
		acd.lastPosition = pos

		-- Speed sustain check
		if speed > ACConfig.MAX_LEGITIMATE_SPEED then
			acd.speedOverTime += ACConfig.SPEED_POLL_INTERVAL
			if acd.speedOverTime >= ACConfig.SPEED_SUSTAINED_TIME then
				acd.speedOverTime = 0
				AntiCheat.flag(player, "major",
					"Speed hack detected (" .. math.floor(speed) .. " studs/s)")
			end
		else
			acd.speedOverTime = 0
		end

		-- Infinite block check
		if acd.blockHeldSince and (now - acd.blockHeldSince) > ACConfig.MAX_BLOCK_HOLD_TIME then
			acd.blockHeldSince = nil
			-- Force release server side via CombatHandler data
			-- AntiCheat doesn't directly access playerData so we flag only
			AntiCheat.flag(player, "minor", "Block held for abnormal duration")
		end
	end
end)

-- ──────────────────────────────────────────────
-- PLAYER ADDED / REMOVED
-- ──────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	loadACData(player)

	-- Check ban on join before character loads
	local acd = getACData(player)
	if acd.banned then
		player:Kick("You are banned from this game.\nReason: " .. acd.banReason
			.. "\nIf you believe this is a mistake, contact support.")
		return
	end
end)

Players.PlayerRemoving:Connect(function(player)
	saveACData(player)
	playerACData[player]  = nil
	lastPollTime[player]  = nil
end)

return AntiCheat