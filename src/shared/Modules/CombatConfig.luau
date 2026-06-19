local Config = {}

-- Combo
Config.MAX_COMBO     = 4
Config.COMBO_WINDOW  = 0.85
Config.DAMAGE        = {10, 10, 10, 30}

-- Hitbox
Config.HITBOX_SIZE   = Vector3.new(3.5, 4, 2.5)
Config.HITBOX_OFFSET = CFrame.new(0, 0, -2.8)

-- Knockback
Config.KNOCKBACK_FORCE  = 0.2
Config.FINISH_KNOCKBACK = 180   -- big launch on kill finisher
Config.FINISH_LIFT      = 60    -- lots of upward pop

-- Ragdoll
Config.RAGDOLL_TIME  = 2.5

-- Stun
Config.STUN_TIME     = 0.3

-- M1 cooldown
Config.M1_COOLDOWN   = 0.38

-- Block
Config.BLOCK_DAMAGE_REDUCTION = 0.0   -- 100% blocked from front
Config.BLOCK_ANGLE   = 60             -- degrees either side of facing = blocked

-- Dash
Config.DASH_POWER_FORWARD  = 160  -- slightly faster than current 140
Config.DASH_POWER_SIDE     = 120  -- shorter pop
Config.DASH_POWER_BACKWARD = 130  -- between side and forward

Config.DASH_DURATION_FORWARD  = 0.5
Config.DASH_DURATION_SIDE     = 0.25
Config.DASH_DURATION_BACKWARD = 0.35

Config.DASH_COOLDOWN_FORWARD  = 7
Config.DASH_COOLDOWN_SIDE     = 4
Config.DASH_COOLDOWN_BACKWARD = 4

Config.MAX_HIT_DISTANCE = 15  -- studs; accounts for latency + hitbox reach

-- Spawn protection
Config.SPAWN_PROTECTION = 2

-- Currency
Config.COINS_PER_KILL = 10

-- Debug
Config.SHOW_HITBOX = false
Config.DEBUG       = false

-- Sound IDs — leave blank to skip, fill in when you have them
Config.SOUNDS = {
	M1_1     = "",   -- regular hit 1
	M1_2     = "",   -- regular hit 2
	M1_3     = "",   -- regular hit 3
	FINISHER = "",   -- finisher hit
	BLOCK    = "",   -- blocked hit
	DASH     = "",   -- dash sound
}

return Config