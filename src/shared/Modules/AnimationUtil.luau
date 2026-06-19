local AnimationUtil = {}

local function isValidAnimId(id)
	if not id or id == "" then return false end
	if id:find("YOUR_ID") then return false end
	return id:match("^rbxassetid://%d+$") ~= nil
end

-- Loads and returns an animation track on a humanoid.
-- Returns nil if the ID is invalid or loading fails.
function AnimationUtil.loadTrack(humanoid, animId, priority, looped)
	if not isValidAnimId(animId) then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return humanoid.Animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = priority or Enum.AnimationPriority.Action
		track.Looped   = looped or false
		return track
	end
	return nil
end

AnimationUtil.isValidAnimId = isValidAnimId

return AnimationUtil