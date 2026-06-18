# 🥊 Untitled Fighting Game
> A TSB / Jujutsu Shenanigans inspired PvP fighting game built in Roblox Studio using Rojo. Early in development — this is the base foundation.

> KEEP IN MIND THIS INFORMATION MIGHT BE INNACURATE IN THE FUTURE AFTER UPDATES | TAKE THIS INFORMATION WITH A GRAIN OF SALT AND USE WHATEVER U NEED OF IT.
---

## 📖 Concept

Simple freeform PvP. Find a player, land a **4-hit M1 combo** on them. No abilities, no gimmicks — just movement and combat reads.

- Hits **1–3** deal light damage and nudge the opponent
- Hit **4** is the **finisher** — big damage, ragdolls and launches them
- **Block** (F) to tank frontal hits, forcing opponents to reposition
- **Dash** (Q) in your movement direction to dodge or close distance
- Kills earn **Coins** that save to your account

Skill comes from reading your opponent — when to dash in, when to block, when to go for the finisher.

---

## 🗂️ Script Overview

### ServerScriptService
| Script | What it does |
|---|---|
| `CombatHandler` | Server-side brain. Hit detection, damage, ragdoll, kill/death tracking, coins, spawn protection. Server-authoritative so it can't be exploited |
| `DataManager` | Saves and loads each player's Kills, Deaths and Coins via DataStore |

### ReplicatedStorage/Modules
| Script | What it does |
|---|---|
| `CombatConfig` | Single config file for every tunable value — damage, hitbox size, dash speed, animation IDs, sound IDs. Change numbers here, not in the scripts |

### StarterPlayerScripts
| Script | What it does |
|---|---|
| `CombatClient` | Mouse click to punch, block input, M1 animations and sound playback |
| `DashController` | Q to dash in your movement direction, steers with your camera, smooth eased speed curve |
| `CameraShake` | Screen shake on hits, stronger shake on finisher |
| `HitboxVisualizer` | Debug only — shows the punch hitbox as a red box in front of every player |
| `CombatUI` | Floating combo counter (2x, 3x, FINISH!) and damage numbers above hit targets |

### StarterGui
| Script | What it does |
|---|---|
| `CombatHUD` | Personal health bar and spawn shield indicator |

---

## ⚙️ Controls

| Action | Input |
|---|---|
| Punch (M1) | Left click |
| Block | Hold `F` |
| Dash | `Q` while moving |

---

## 🔧 Configuration

Everything tuneable lives in `ReplicatedStorage/Modules/CombatConfig`:

```lua
Config.DAMAGE        = {10, 10, 10, 30}  -- damage per hit, index 4 = finisher
Config.HITBOX_SIZE   = Vector3.new(3.5, 4, 2.5)
Config.DASH_POWER    = 100
Config.DASH_COOLDOWN = 0.9
Config.RAGDOLL_TIME  = 2.5
Config.COINS_PER_KILL = 10
Config.SHOW_HITBOX   = false  -- toggle hitbox debug visualizer

Config.SOUNDS = {
    M1_1 = "", M1_2 = "", M1_3 = "",
    FINISHER = "", BLOCK = "", DASH = "",
}
```

Animation IDs are set in `CombatClient` (`ANIM_IDS` table) and `DashController` (`Config.DASH_ANIM_ID`).

---

## 📦 Project Setup

Built with **Rojo** and **VS Code**. All source files live inside `src/`.

```
src/
├── ServerScriptService/
│   ├── CombatHandler
│   └── DataManager
├── ReplicatedStorage/
│   ├── Modules/
│   │   └── CombatConfig
│   └── Remotes/
│       └── (RemoteEvents — see below)
└── StarterPlayerScripts/
    ├── CombatClient
    ├── DashController
    ├── CameraShake
    ├── HitboxVisualizer
    └── CombatUI
```

## 🚧 Status

This is an early base — the combat loop is functional but the game is not finished. Planned additions include VFX, more polish, a round system and additional mechanics built on top of the M1 foundation.