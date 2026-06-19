local Config = {}

-- Combo
Config.MAX_COMBO        = 4
Config.COMBO_WINDOW     = 1.4    -- seconds before combo resets if no hit lands
Config.M4_COOLDOWN      = 1.7    -- attacker cannot M1 after completing full combo
Config.DAMAGE           = {8, 8, 8, 20}

-- Hitbox
Config.HITBOX_SIZE      = Vector3.new(3.5, 4, 2.5)
Config.HITBOX_OFFSET    = CFrame.new(0, 0, -2.8)

-- Knockback
Config.KNOCKBACK_FORCE  = 0.2    -- studs nudge on regular M1s
Config.M4_KNOCKBACK     = 2      -- studs nudge on M4 before ragdoll

-- Block
Config.BLOCK_ANGLE          = 60     -- degrees: front block cone
Config.BLOCK_BREAK_ANGLE    = 150    -- degrees: must be genuinely behind victim
Config.BLOCK_HIT_DAMAGE     = 2      -- damage when hitting a blocking player from front
Config.BLOCK_BREAK_MULTIPLIER = 1.2  -- damage + stun multiplier on block break

-- Stun
Config.STUN_TIME            = 0.2    -- base stun duration
Config.POST_RAGDOLL_DAMAGE_IMMUNITY = 0.04   -- damage immunity after unragdoll
Config.POST_RAGDOLL_STUN_IMMUNITY   = 0.12   -- stun immunity after unragdoll

-- Ragdoll
Config.RAGDOLL_TIME         = 1.3    -- M4 ground ragdoll duration

-- M1 cooldown
Config.M1_COOLDOWN          = 0.35

-- Finisher (kill hit)
Config.FINISHER_FORCE_NORMAL   = 120   -- launch force for M1-3 finisher
Config.FINISHER_LIFT_NORMAL    = 55    -- upward component for M1-3 finisher
Config.FINISHER_FORCE_M4       = 280   -- launch force for M4 finisher
Config.FINISHER_LIFT_M4        = 35    -- lower angle = less lift, more horizontal
Config.FINISHER_COLLISION_THRESHOLD = 8  -- velocity magnitude to confirm collision
Config.FINISHER_STICK_TIME     = 0.2   -- seconds body sticks to wall before falling
Config.FINISHER_RESPAWN_DELAY  = 0.8   -- seconds after collision before respawn
Config.FINISHER_BODY_LINGER    = 1.5   -- seconds cosmetic body stays after respawn
Config.FINISHER_CINEMATIC_DURATION = 0.4  -- seconds both players locked during finisher
Config.RESPAWN_DELAY_NORMAL = 3  -- seconds before respawn on normal death

-- Dash
-- Dash
Config.DASH_POWER_FORWARD      = 150
Config.DASH_POWER_SIDE         = 100
Config.DASH_POWER_BACKWARD     = 140

Config.DASH_DURATION_FORWARD   = 0.55
Config.DASH_DURATION_SIDE      = 0.2
Config.DASH_DURATION_BACKWARD  = 0.35

Config.DASH_COOLDOWN_FORWARD   = 7
Config.DASH_COOLDOWN_SIDE      = 4
Config.DASH_COOLDOWN_BACKWARD  = 4

-- Front dash hitbox + end-lag
Config.DASH_HIT_DAMAGE         = 5
Config.DASH_HIT_STUN           = 0.3
Config.DASH_HIT_BLOCK_DAMAGE   = 0.0001
Config.DASH_HITBOX_START       = 0.08   -- progress % before hitbox activates
Config.DASH_END_LAG            = 0.18   -- seconds of end-lag on missed front dash
Config.DASH_HIT_MAX_DISTANCE   = 8      -- studs max for dash hit validation

Config.MAX_HIT_DISTANCE        = 15

-- Spawn protection
Config.SPAWN_PROTECTION        = 0.3
Config.SPAWN_FREEZE_DURATION   = 0.1

-- Currency
Config.COINS_PER_KILL_NORMAL      = 10
Config.COINS_PER_KILL_M4_FINISHER = 15   -- 1.5x

-- Debug
Config.SHOW_HITBOX = false
Config.DEBUG       = false

-- Sound IDs
Config.SOUNDS = {
	M1_1        = "",
	M1_2        = "",
	M1_3        = "",
	M1_4        = "",
	FINISHER    = "",
	FINISHER_M4 = "",
	BLOCK       = "",
	BLOCK_BREAK = "",
	DASH        = "",
}

return Config