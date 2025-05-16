# Roblox Raid System

A comprehensive framework for creating team-based raid/mission systems in Roblox games. This system provides a flexible architecture for implementing objective-based gameplay with multiple phases and customizable mechanics.

## Features

- **Modular Phase System**: Create missions with multiple sequential objectives
- **Multiple Phase Types**:
  - **Terminal**: Capture points by team presence
  - **Payload**: Push/escort objectives through paths with checkpoints
  - **Bomb**: Plant and defuse mechanics with carrier tracking
  - **Target**: Health-based objectives with damage systems
- **Time Management**: Built-in time tracking with overtime mechanics
- **Team System**: Support for attackers vs defenders gameplay
- **Dynamic Respawn System**: Optional respawn control and spawn point management
- **Network Replication**: Client-side state updates for UI integration
- **Customizable Callbacks**: Hook into phase events for custom game logic

## Installation

1. Place the `raid.lua` file in your game's ServerStorage or ServerScriptService
2. Require the module in your server scripts:

```lua
local ServerStorage = game:GetService("ServerStorage")
local Raid = require(ServerStorage.raid)
```

## Basic Setup

```lua
local Raid = require(path.to.raid)

-- Create a new raid instance
local myRaid = Raid.new({
    Friendlies = Teams.Defender,  -- Defending team
    Enemies = Teams.Raider,       -- Attacking team
    Respawn = true,               -- Allow players to respawn
    SetSpawn = true,              -- Use phase-specific spawn points
    Time = 60 * 10,               -- Raid time in seconds (10 minutes)
})
```

## Phase Creation

### Terminal Phase

```lua
myRaid:AddPhase("Terminal", {
    Region = workspace.Raid.Terminal.Region,  -- BasePart defining the capture area
    Time = 60,                                -- Seconds to capture
    CapSpeed = 10,                            -- Capture speed multiplier
    Rollback = 2,                             -- Defenders' rollback speed
    BonusTime = 60 * 5,                       -- Time bonus when completed
})
```

### Payload Phase

```lua
myRaid:AddPhase("Payload", {
    Region = workspace.Raid.Payload.Region,   -- BasePart defining the push area
    Model = workspace.Raid.Payload,           -- Model to move
    Speed = 10,                               -- Movement speed
    Nodes = {
        -- Create path nodes (points the payload travels through)
        Raid.CreateNode(workspace.Raid.Nodes.A1.CFrame),
        Raid.CreateNode(workspace.Raid.Nodes.A2.CFrame),
        -- Checkpoint node (requires capture to proceed)
        Raid.CreateNode(workspace.Raid.Nodes.ACap.CFrame, {
            Time = 30,                        -- Time to capture
            CapSpeed = 10,                    -- Capture speed
        }),
    }
})
```

### Bomb Phase

```lua
myRaid:AddPhase("Bomb", {
    Region = workspace.Raid.Bomb.Region,      -- BasePart defining the plant area
    Pickup = workspace.Raid.Bomb.Pickup,      -- BasePart where bomb can be picked up
    Time = 45,                                -- Seconds to detonate
    MaxBombs = 2,                             -- Maximum bomb attempts
    CapSpeed = 10,                            -- Plant/defuse speed
    Rollback = 2,                             -- Defenders' rollback speed
})
```

### Target Phase

```lua
myRaid:AddPhase("Target", {
    Hitbox = workspace.Raid.Target.Hitbox,    -- BasePart to damage
    MaxHealth = 1000,                         -- Target health
    Regen = 5,                                -- Health regeneration per second
    Invulnerable = false,                     -- Whether target can be damaged
})
```

## Raid Control

```lua
-- Start the raid
myRaid:Start()

-- End the raid (true = Defenders win, false = Attackers win)
myRaid:End(true)

-- Pause/freeze raid progression
myRaid:Freeze()
myRaid:Unfreeze()

-- Skip to next phase
myRaid:NextPhase()

-- Jump to a specific phase
myRaid:SetPhase(2)

-- Add time to the raid
myRaid:AdjustTime(60)  -- Add 60 seconds

-- Toggle respawning
myRaid:ToggleRespawn()
```

## Spawn System

When using `SetSpawn = true`, create folders in your workspace with this structure:

```
workspace
└── Spawns
    ├── Phase1
    │   ├── SpawnLocation1
    │   └── SpawnLocation2
    └── Phase2
        ├── SpawnLocation1
        └── SpawnLocation2
```

The system will automatically enable/disable spawn points based on the current phase.

## Custom Callbacks

```lua
-- Add a callback to a phase
myRaid:GetPhase(1).Callback = function(raidInstance)
    print("Phase 1 completed!")
    -- Add custom logic here
end

-- Or when creating the phase
myRaid:AddPhase("Terminal", {
    Region = workspace.Raid.Terminal.Region,
    Callback = function(raidInstance)
        print("Terminal phase completed!")
    },
})
```

## Full Example

```lua
local Raid = require(path.to.raid)

local myRaid = Raid.new({
    Friendlies = Teams.Defender,
    Enemies = Teams.Raider,
    Respawn = true,
    SetSpawn = true,
    Time = 60 * 10,
    WinMessage = "The %s have completed the mission!",
})
:AddPhase("Terminal", {
    Region = workspace.Raid.Terminal.Region,
    Time = 60,
    CapSpeed = 10,
})
:AddPhase("Bomb", {
    Region = workspace.Raid.Bomb.Region,
    Pickup = workspace.Raid.Bomb.Pickup,
    Time = 45,
    MaxBombs = 2,
})
:AddPhase("Payload", {
    Region = workspace.Raid.Payload.Region,
    Model = workspace.Raid.Payload,
    Speed = 10,
    Nodes = {
        Raid.CreateNode(workspace.Raid.Nodes.A1.CFrame),
        Raid.CreateNode(workspace.Raid.Nodes.A2.CFrame),
        Raid.CreateNode(workspace.Raid.Nodes.ACap.CFrame, {
            Time = 30,
            CapSpeed = 10,
        }),
    }
})
:AddPhase("Target", {
    Hitbox = workspace.Raid.Target.Hitbox,
    MaxHealth = 1000,
    Regen = 5,
})

-- Start the raid
myRaid:Start()
```

## Advanced Usage

### Phase Modification

```lua
-- Get and modify an existing phase
myRaid:GetPhase(1):Modify({
    CapSpeed = 20,
    Rollback = 3,
})

-- Change phase callback
myRaid:SetPhaseCallback(2, function()
    print("Custom callback for phase 2")
    -- Custom logic
end)
```

### Raid Modification

```lua
-- Modify raid properties
myRaid:Modify({
    Time = 60 * 15,  -- Change to 15 minutes
    Respawn = false, -- Disable respawning
})
```

## Network Events

The raid system automatically replicates state to clients for UI integration:

- `RaidStart`: Fired when a raid begins
- `RaidEnd`: Fired when a raid ends with winner information
- `PhaseChanged`: Fired when the phase changes
- `RaidUpdate`: Continuously fired with current raid state

## License

Created by F9MX (10/30/24)
