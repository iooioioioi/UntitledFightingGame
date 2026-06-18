local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local store             = DataStoreService:GetDataStore("CombatGameV1")

-- Only ever called once per player on join
local function loadData(player)
	local key = "player_" .. player.UserId
	local ok, data = pcall(store.GetAsync, store, key)

	local kills  = 0
	local deaths = 0
	local coins  = 0

	if ok and type(data) == "table" then
		kills  = data.kills  or 0
		deaths = data.deaths or 0
		coins  = data.coins  or 0
	end

	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then return end

	leaderstats:WaitForChild("Kills").Value  = kills
	leaderstats:WaitForChild("Deaths").Value = deaths
	leaderstats:WaitForChild("Coins").Value  = coins
end

-- Only ever called once per player on leave
local function saveData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local key  = "player_" .. player.UserId
	local data = {
		kills  = leaderstats.Kills.Value,
		deaths = leaderstats.Deaths.Value,
		coins  = leaderstats.Coins.Value,
	}

	local ok, err = pcall(store.SetAsync, store, key, data)
	if not ok then
		warn("Save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

Players.PlayerAdded:Connect(loadData)
Players.PlayerRemoving:Connect(saveData)

game:BindToClose(function()
	-- Studio: this runs immediately so we save inline
	-- Live server: players are already gone via PlayerRemoving by this point
	if game:GetService("RunService"):IsStudio() then
		for _, player in ipairs(Players:GetPlayers()) do
			saveData(player)
		end
	end
end)