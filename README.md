Untitled Fighting Game

A TSB / Jujutsu Shenanigans inspired PvP fighting game built in Roblox Studio using Rojo.

The project is currently in early development and focuses on establishing a strong, scalable foundation before expanding into additional mechanics and content.

IMPORTANT

This README provides project context, design goals, and architecture guidance.

The codebase is always the source of truth.

If information in this README conflicts with the current implementation, trust the code over the documentation.

Before implementing new functionality:

Inspect existing systems first.
Reuse existing modules and patterns whenever possible.
Extend existing systems instead of creating replacements.
Avoid duplicating functionality.
PROJECT STRUCTURE MAPPING
Roblox Services
SERVER SIDED CODE GOES INTO ServerScriptService
CLIENT SIDED CODE GOES INTO StarterPlayerScripts (StarterPlayer.StarterPlayerScripts)
MODULES LOCATION CAN DEPEND ON WHETHER THEY NEED TO BE ACCESSIBLE TO THE CLIENT OR NOT. MOST SHARED MODULES SHOULD BE LOCATED IN ReplicatedStorage.Modules
Equivalent Folders Inside /src
/src/server = ServerScriptService
/src/client = StarterPlayerScripts
/src/shared/Modules = ReplicatedStorage.Modules
Rules
Server code must never run on the client.
Client code must never handle authoritative game logic.
Shared modules must be safe for both environments.
Damage, combat validation, currencies, inventories, and progression systems must remain server authoritative.
Never trust client-reported combat results, damage values, or rewards.
ARCHITECTURE PRIORITY

When making implementation decisions, use the following priority order:

Existing codebase
Project rules/instructions
README documentation
Assumptions

Never replace or restructure working systems based solely on README information.

## Repository Limitations

Some Roblox instances may exist in Studio and may not be represented in the Rojo source tree.

Examples may include:
- RemoteEvents
- RemoteFunctions
- Folders
- Testing assets
- Placeholder instances

Do not assume these objects are missing simply because they are not present in the repository.

If an object appears to be referenced but its creation cannot be found, ask whether it exists in Studio before reporting it as a bug or architectural issue.

GAME CONCEPT

Simple freeform PvP combat.

Players spawn into an arena and fight using basic movement, positioning, blocking, dashing, and melee combat.

The gameplay focuses on mechanical skill, timing, spacing, and reading opponents rather than ability spam or complex gimmicks.

Core combat loop:

Find an opponent
Land a 4-hit M1 combo
Use movement and dashes to create openings
Block incoming attacks
Finish opponents to earn rewards

Skill expression should come from decision-making and execution rather than random mechanics.

COMBAT DESIGN
M1 Combo

Players attack using a 4-hit combo chain.

Hits 1–3
Deal light damage
Slightly push the target
Continue combo progression
Hit 4 (Finisher)
Deals significantly more damage
Launches the target backwards
Applies ragdoll
Serves as the combo finisher
Kill Finisher

If any hit would kill the target:

The hit becomes a kill finisher regardless of combo count
The target is launched much further than normal
The target is ragdolled dramatically
The elimination should feel impactful and satisfying
DEFENSIVE OPTIONS
Block (F)

Holding F allows players to block incoming frontal attacks.

Blocking should:

Reduce or prevent frontal damage
Reward correct timing and positioning
Force attackers to reposition or bait reactions
Dash (Q)

Players can dash in their current movement direction.

Dashing should:

Create offensive opportunities
Allow repositioning
Enable evasive movement
Reward movement skill and timing
CONTROLS
Action	Input
Punch (M1)	Left Click
Block	Hold F
Dash	Q While Moving
PROGRESSION
Coins

Players earn Coins for eliminations.

Coins should:

Be awarded server-side
Save between sessions
Never be controlled by the client

Future systems may expand the use of Coins, but the currency should remain secure and server authoritative.

CONFIGURATION

Combat values should remain configurable through:

ReplicatedStorage/Modules/CombatConfig

Example configuration:

Config.DAMAGE        = {10, 10, 10, 30}
Config.HITBOX_SIZE   = Vector3.new(3.5, 4, 2.5)
Config.DASH_POWER    = 100
Config.DASH_COOLDOWN = 0.9
Config.RAGDOLL_TIME  = 2.5
Config.COINS_PER_KILL = 10
Config.SHOW_HITBOX   = false

Config.SOUNDS = {
    M1_1 = "",
    M1_2 = "",
    M1_3 = "",
    FINISHER = "",
    BLOCK = "",
    DASH = "",
}

All gameplay tuning should be performed through configuration values whenever practical rather than hardcoding numbers throughout the project.

DEVELOPMENT GOALS

Current focus:

Stable combat foundation
Clean client/server separation
Server-authoritative gameplay
Maintainable architecture
Scalable systems for future expansion

Priority should always be maintaining a clean and extensible codebase over implementing features quickly.