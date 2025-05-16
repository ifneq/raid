-- Written by F9MX 10/30/24

--[[
    Raid System Documentation

    This system defines a class that handles raids in the game. It supports features such as:
    - Multiple phases (e.g., Terminal, Payload, Bomb)
    - Customizable teams (Friendlies, Enemies)
    - Dynamic time management and freezing mechanics
    - Player respawn management
    - Raid status replication and network communication with clients

    Key Methods:
    - Raid.new(Properties): Initializes a new raid with given properties.
    - Raid:Modify(Properties): Updates the raid with new properties.
    - Raid:Start(): Starts the raid, initializing phases and timers.
    - Raid:End(Winner): Ends the raid and declares the winner.
    - Raid:AddPhase(Class, Properties, ...): Adds a new phase to the raid.
    - Raid:Update(Delta): Periodically updates the raid, handling phase logic and time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared

local Network = require(Shared.Network)
local Utility = require(Shared.Utility)
local Crypto = require(Shared.Crypto)

local PhaseTypes = {
	Terminal = require(script.Terminal),
	Payload = require(script.Payload),
	Target = require(script.Target),
	Bomb = require(script.Bomb),
}


local Raid = {}
Raid.__index = Raid

function Raid.new(Properties)
	Properties = Properties or {}
	assert(Properties.Friendlies, "The Friendly team must be set!")
	assert(Properties.Enemies, "The Enemies team must be set!")
	
	local self = setmetatable({}, Raid)

	self.Friendlies = Properties.Friendlies -- Required
	self.Enemies = Properties.Enemies
	
	self.SetSpawn = Properties.SetSpawn or false -- Optional
	self.Spawn = Properties.Respawn or false
	self.Time = Properties.Time or (60 * 30)
	self.DT = Properties.DT or game.PrivateServerOwnerId ~= 0 and true
	self.Phases = Properties.Phases or {}
	self.WinMessage = Properties.WinMessage or "The %s Forces have successfully taken over the fort." -- %s being the Team Name
	self.Kick = Properties.Kick or false
	self.KickAfter = Properties.KickAfter or 0
	
	self.MaxTime = self.Time
	self.Phase = 1 -- State Properties
	self.Timestamp = nil
	self.Running = false
	self.Code = nil
	self.Official = false
	self.Frozen = false
	self.Modified = false
	self.Heartbeat = nil
	
	self.NetworkReplicator = Network:CreateFunction("GetRaidState", function(...)
		local Data = {
			RaidTime = self.Time,
			Friendlies = self.Friendlies,
			Enemies = self.Enemies,
		}

		Data = self.Phases[self.Phase]:Pack(Data)

		return Data
	end)
	
	-- For Setting Spawns, you must have the First "Phase"'s Spawns Active
	-- Create a Folder in workspace called "Spawns", and another called "Phase1", "Phase2", etc
	
	return self
end

function Raid:Modify(Properties)
	Properties = Properties or {}
	
	Properties.Spawn = Properties.Respawn
	
	for Index, Value in next, Properties do
		self[Index] = Value
	end
	
	return self
end

function Raid:ToggleFrozen()
	self.Frozen = not self.Frozen

	return self
end

function Raid:Freeze()
	self.Frozen = true
	
	return self
end

function Raid:Unfreeze()
	self.Frozen = false

	return self
end

function Raid:RespawnAll()
	for _, plr in pairs(Players:GetPlayers()) do
		plr:LoadCharacter()
	end

	return self
end

function Raid:ToggleRespawn()
	self.Spawn = not self.Spawn

	return self
end

function Raid:Respawn()
	self.Spawn = true

	return self
end

function Raid:NoRespawn()
	self.Spawn = false

	return self
end

function Raid:AddPhase(Class, Properties, ...)
	self.Phases[#self.Phases + 1] = PhaseTypes[Class].new(self, Properties, ...)

	return self
end

function Raid:GetPhase(Index) -- Oh No! No more method chaining
	return self.Phases[Index] -- But the :Modify() function returns the raid
end -- Back to Method Chaining!

function Raid:SetPhase(Phase)
	if self.SetSpawn then
		for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
			SpawnPoint.Enabled = false
		end
	end
	
	if Phase <= #self.Phases and Phase > 0 then
		self.Phase = Phase
	end
	
	if self.SetSpawn then
		for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
			SpawnPoint.Enabled = true
		end
	end

	if self.Respawn then
		self:RespawnAll()
	end
	
	Network:FireAllClients("PhaseChanged", self.Phase)
	
	return self
end

function Raid:SkipPhase()
	if self.Phase < #self.Phases then
		self.Modified = true
		self.Official = false
		
		if self.SetSpawn then
			for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
				SpawnPoint.Enabled = false
			end
		end
		
		self.Phase += 1
		
		if self.SetSpawn then
			for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
				SpawnPoint.Enabled = true
			end
		end
		
		Network:FireAllClients("PhaseChanged", self.Phase)
		
		if self.Respawn then
			self:RespawnAll()
		end
	end
	
	return self
end

function Raid:RemovePhase(Index)
	table.remove(self.Phases, Index)
	
	return self
end

function Raid:NextPhase()
	if self.Phase == #self.Phases then
		self:End(false) -- Raider Win!
		return self
	end
	
	if self.SetSpawn then
		for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
			SpawnPoint.Enabled = false
		end
	end
	
	self.Phase += 1
	
	if self.SetSpawn then
		for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
			SpawnPoint.Enabled = true
		end
	end
	Network:FireAllClients("PhaseChanged", self.Phase)
	
	if self.Spawn then
		self:RespawnAll()
	end
	
	return self
end

function Raid:SetPhaseCallback(Index, Callback)
	self.Phases[Index].Callback = Callback
	
	return self
end

function Raid:AdjustTime(Delta)
	self.Time = math.max(self.Time + Delta, 0)
	
	return self
end

function Raid:PackUI(Player)
	
end


function Raid:Start()
	assert(#self.Phases > 0, "Raids must have at least one phase!")
	
	if self.Running then
		return self
	end
	
	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	self.Time = self.MaxTime
	
	for Index, Phase in next, self.Phases do
		Phase:Reset()
		print(Index, Phase.Mode)
	end
	
	if self.SetSpawn then
		for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
			SpawnPoint.Enabled = false
		end
	end
	
	self.Phase = 1
	
	if self.SetSpawn then
		for _, SpawnPoint in next, workspace.Spawns["Phase"..self.Phase]:GetChildren() do
			SpawnPoint.Enabled = true
		end
	end
	
	self.Running = true
	self.Official = true
	self.Modified = false
	self.Timestamp = os.clock()
	self.RaidCode = Crypto.Random.Alphanumeric(8)
	
	Network:FireAllClients("RaidStart")
	
	self.Heartbeat = RunService.Heartbeat:Connect(function(Delta)
		self:Update(Delta)
	end)
	
	if self.Spawn then
		self:RespawnAll()
	end
	
	print("Raid Started!")
	
	return self
end

function Raid:Replicate()
	local Data = {
		RaidTime = self.Time,
		Friendlies = self.Friendlies,
		Enemies = self.Enemies,
	}

	Data = self.Phases[self.Phase]:Pack(Data) -- Finally a use case for Pass By Reference (Tables in Lua are Pass by Reference, so you can modify them with functions)

	Network:UnreliableFireAllClients("RaidUpdate", Data)

	return self
end

function Raid:Update(Delta)
	self:AdjustTime(-Delta)

	if self.Time <= 0 then -- Winning + Overtime
		local CurrentPhase = self.Phases[self.Phase]
		
		local Winner = CurrentPhase:Poll(CurrentPhase)
		
		if Winner then
			self:End(true) -- Defenders won!
			return self
		else
			if not self.Frozen then -- Overtime!!!
				local CurrentPhase = self.Phases[self.Phase]
				CurrentPhase:Update(Delta)
			end
			
			self:Replicate()
			
			return self
		end
	end
	
	if not self.Frozen then
		local CurrentPhase = self.Phases[self.Phase]
		CurrentPhase:Update(Delta)
	end
	
	self:Replicate()
	
	return self
end

function Raid:End(Winner) -- True = Friendlies, False = Enemies
	self.Running = false  -- Now you can retart it using :Start()
	
	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end
	
	self:Replicate()
	
	local Team = Winner and self.Friendlies or self.Enemies 
	
	Network:FireAllClients("RaidEnd", {
		Winner = Team,
		Message = string.format(self.WinMessage, Team.Name) .. "\nRaid Code: " .. self.RaidCode,
		Elapsed = os.clock() - self.Timestamp,
		Date = Utility.DateAndTime(),
		Official = self.Official,
		Modified = self.Modified,
		DT = self.DT,
	})
	
	if self.Spawn then
		self:RespawnAll()
	end
	
	if self.Kick then
		task.wait(self.KickAfter)
		
		for _, Player in next, Players:GetPlayers() do
			Player:Kick(string.format(self.WinMessage, Team.Name) .. "\nRaid Code: " .. self.RaidCode)
		end
	end
	
	print("Raid Completed!")
	
	return self
end

return Raid
