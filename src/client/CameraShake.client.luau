-- CameraShake (LocalScript → StarterPlayerScripts)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local M1Animation = Remotes:WaitForChild("M1Animation")

local function shake(intensity, duration)
	local elapsed = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration then
			conn:Disconnect()
			return
		end
		local fade = 1 - (elapsed / duration)
		local rx = math.random(-100, 100) / 100 * intensity * fade
		local ry = math.random(-100, 100) / 100 * intensity * fade
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(rx), math.rad(ry), 0)
	end)
end

-- Only shake, never touch animations
M1Animation.OnClientEvent:Connect(function(attacker, comboIndex, isFinisher)
	if attacker ~= player then return end
	if isFinisher then
		shake(1.8, 0.25)
	else
		shake(0.6, 0.12)
	end
end)