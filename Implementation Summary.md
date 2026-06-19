Project Context
Roblox Luau fighting game using Rojo + VS Code. TSB/JJS inspired PvP melee combat. Server authoritative. All files in /src. Shared modules in src/shared/Modules. Server in src/server. Client in src/client.

What We Are Implementing
1. Damage & Balance Rebalance
All values centralized in CombatConfig.luau:

Regular M1 hits 1-3: 8 damage
M4 hit: 20 damage
Blocked hit (front block, no break): 2 damage, no stun to victim
Block break hit (back hit on blocking player): 1.2x damage multiplier on whatever M1 it was, 1.2x stun duration
STUN_TIME: 0.2s base
M1_COOLDOWN: 0.35s
COMBO_WINDOW (reset timer if player stops hitting): 1.4s
Post-M4 combo cooldown (attacker cant M1 after full combo): 1.7s
Post-ragdoll damage immunity window: 0.04s
Post-ragdoll stun immunity window: 0.12s
Spawn protection after finisher respawn: 0.3s
Movement freeze on respawn: 0.1s (set WalkSpeed/JumpPower to 0 then restore)

2. Block System Rework

Hitting a blocking player from the front: deals 2 damage, no stun, play block sound
Hitting a blocking player from the back: breaks their block, deals 1.2x damage, 1.2x stun, fires BlockBroken remote to client, brief stun so attacker can continue combo
Back angle check: victim must be facing away from attacker, angle threshold ~150 degrees (tight, must genuinely be behind them)
While blocked/blocking: player cannot M1 or dash
While dashing: player cannot block

3. M1 Combo System Rework

4 hit combo chain
Hits 1-3: 8 damage, small backward nudge (~0.2 studs), 0.2s stun
Hit 4: 20 damage, victim ragdolled on ground, nudged ~2 studs in direction attacker is looking, victim faces attacker on impact (rotated to face attacker then falls on back), 80% chance lands on back 20% random rotation
M4 ragdoll duration: 1.3s then victim stands up normally
After M4 completes: attacker enters 1.7s combo cooldown — can dash and block freely but cannot M1. ComboReset remote fires to client to handle UI/feedback. If player clicks M1 during this window nothing happens
Combo window: if attacker does not land another hit within 1.4s of last hit, combo resets to M1
Ragdolled players: cannot take damage or stun from any player while ragdolled
Post-ragdoll: 0.04s damage immunity then 0.12s stun immunity after getting up

4. Finisher System (Kill Hit)
Triggered when any M1 hit would reduce victim health to 0 or below:

Victim health is set to 1 HP instead of dying immediately
Victim enters finisher ragdoll state — untouchable, no hitbox, purely cosmetic after launch. Any player hitting the launched body gets zero rewards and deals zero damage
Kill credit is locked to the attacker the moment finisher is triggered — cannot be stolen
Victim is launched in punch direction
M1-3 finisher trajectory: moderate upward angle (~25 degrees), moderate force
M4 finisher trajectory: lower angle (~15 degrees), massively increased force, travels much further
Trajectory applied server side for authority, visual effects handled client side via FinisherLaunch remote
Victim body rotates mid-air so their back faces the direction of travel (they hit walls/ground back-first or torso-first)
If victim hits a wall/object high up: body sticks for 0.2s then falls and ragdolls down to ground
Collision detection: server polls victim HRP velocity — when velocity drops significantly, collision is confirmed
On collision: server deals final 1 damage to kill victim, death is processed
0.8s after collision → victim respawns
Victim cosmetic body stays visible for 1.5s after respawn then disappears
On respawn: WalkSpeed and JumpPower set to 0 for 0.1s, then 0.3s spawn protection
Kill reward: attacker gets coins. M4 finisher = 1.5x coins vs M1-3 finisher. Coin multipliers stack with future gamepass bonuses

5. Coin System Update

CombatConfig gets COINS_PER_KILL_NORMAL and COINS_PER_KILL_M4_FINISHER
Coin calculation done server side only
Built to support future multiplier stacking (VIP gamepass, Roblox Premium bonus etc.)

6. New RemoteEvents (already added to RemoteSetup)

FinisherLaunch — fires to all clients with victim character, launch direction, force, and finisher type (normal/M4). Client handles visual trajectory smoothing and effects
BlockBroken — fires to victim client when their block is broken so client can stop block animation and play break feedback
ComboReset — fires to attacker client after M4 cooldown starts so client can handle UI

7. Files Changing

src/shared/Modules/CombatConfig.luau — all new config values
src/server/CombatHandler.server.luau — all server logic changes
src/client/CombatClient.client.luau — M1 lockout during post-M4 cooldown, block broken handling
src/shared/Modules/AnimationConfig.luau — placeholder slots for new animations

8. Files NOT Changing

DataManager, RemoteSetup, DashController, CameraShake, AnimationUtil, HitboxVisualizer

