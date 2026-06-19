-- ServerScriptService/RemoteSetup
-- Creates all RemoteEvents in ReplicatedStorage.Remotes if they don't already exist.
-- This ensures the project is fully reproducible from source without manual Studio setup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local Remotes = getOrCreate(ReplicatedStorage, "Folder", "Remotes")

local remoteNames = {
	"M1Hit",
	"M1Animation",
	"RagdollEvent",
	"HitboxViz",
	"BlockState",
	"PlaySound",
	"ShowCombo",
	"ShowDamage",
	"FinisherLaunch",
	"BlockBroken",
	"ComboReset",
	"DashHit",
    "DashCancelled",
    "DashState",
}

for _, name in ipairs(remoteNames) do
	getOrCreate(Remotes, "RemoteEvent", name)
end