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

local Utility = {}
do -- Utility
	local TweenService = game:GetService("TweenService")

	function Utility.Create(Class, Properties)
		local Object = Instance.new(Class)

		for Property, Value in next, Properties do
			Object[Property] = Value
		end

		return Object	
	end

	function Utility.Clone(Object, Properties)
		local Clone = Object:Clone()

		for Property, Value in next, Properties do
			Clone[Property] = Value
		end

		return Clone
	end

	function Utility.Tween(Object, Properties, ...)
		local Tween = TweenService:Create(Object, TweenInfo.new(...), Properties)

		Tween:Play()

		return Tween
	end

	function Utility.DateAndTime()
		local Months = {'January','February','March','April','May','June','July','August','September','October','November','December'}
		local Seconds = os.time()
		local Data = os.date('!*t',Seconds)
		local Day = tostring(Data.Day)
		local Suffix = ((Day:sub(#Day)=='1' and Day~='11') and 'st' or (Day:sub(#Day)=='2' and Day~='12') and 'nd' or (Day:sub(#Day)=='3' and Day~='13') and 'rd' or 'th')
		Day = Day..Suffix
		return ((Day).." "..Months[Data.month]..', '..Data.year)..'; '..(((Data.hour>=13 and Data.hour-12 or Data.hour))..':'..(tonumber(Data.min)<10 and '0'..Data.min or Data.min)..' '..(Data.hour>=13 and 'PM' or 'AM')..' GMT')
	end

	function Utility.LoadAnimation(Animator, AnimationId)
		local Animation = Instance.new("Animation")

		Animation.AnimationId = "rbxassetid://"..tostring(AnimationId)

		return Animator:LoadAnimation(Animation)
	end

	function Utility.CreateConnection(Signal, Callback)
		return Signal:Connect(Callback)
	end

	function Utility.RandomAlphanumericString(Length)
		Length = Length or 1

		local Output = {}
		local Alphabet = {}

		for i = 48, 57 do
			table.insert(Alphabet, i)
		end

		for i = 65, 90 do
			table.insert(Alphabet, i)
		end

		for i = 97, 122 do
			table.insert(Alphabet, i)
		end

		math.random(os.clock())

		for i = 1, Length do
			Output[i] = Alphabet[math.random(1, #Alphabet)]
		end

		return table.concat(Output)
	end
end

local PhaseTypes = {}
do -- PhaseTypes
	do -- Terminal
		local Players = game:GetService("Players")

		-- Terminal Module
		local Terminal = {}
		Terminal.__index = Terminal

		function Terminal.new(Parent, Properties)
			Properties = Properties or {}

			assert(Properties.Region, "Terminal must have a region!")

			local self = setmetatable({}, Terminal)

			self.Parent = Parent -- Ancestry
			self.Name = Properties.Name or "Terminal"
			self.Mode = "Terminal" -- Identity (For Clients)

			self.Region = Properties.Region -- Terminal Properties
			self.MaxPlayers = Properties.MaxPlayers or 4

			self.MaxTime = Properties.Time or 60 * 1 -- Time Properties
			self.CapSpeed = Properties.CapSpeed or 10
			self.Rollback = Properties.Rollback or 2
			self.BonusTime = Properties.BonusTime or 60 * 5

			self.CapTime = 0  -- State Properties
			self.CapProgress = 0
			self.Callback = Properties.Callback or function()
				print("Terminal Completed")
			end

			return self
		end

		function Terminal:IsOwnedByFriendlies()
			return self.CapProgress == 0
		end

		function Terminal:IsOwnedByEnemies()
			return self.CapProgress == 100
		end

		function Terminal:Reset()
			self.CapTime = 0
			self.CapProgress = 0
		end

		function Terminal:Poll()
			if self:IsOwnedByFriendlies() then
				return self.Parent.Friendlies
			end
		end

		function Terminal:Pack(Data)

			Data.Name = self.Name
			Data.Mode = self.Mode
			Data.Capture = true
			Data.Progress = self.CapProgress
			Data.MaxTime = self.MaxTime
			Data.TimeLeft = self.MaxTime - self.CapTime
			Data.Percent = self.CapTime/self.MaxTime

			return Data
		end

		function Terminal:OnComplete()
			self.Parent:AdjustTime(self.BonusTime)
			self.Callback(self.Parent)
			self.Parent:NextPhase()
		end

		function Terminal:GetWeight()
			local Direction = 0 

			for _, Part in next, workspace:GetPartsInPart(self.Region) do
				if Part:IsA("BasePart") and Part.Parent:FindFirstChild("HumanoidRootPart")  then
					local Character = Part.Parent
					local Player = Players:GetPlayerFromCharacter(Character)

					if not Player then
						continue
					end

					local Humanoid = Character:FindFirstChild("Humanoid")

					if not Humanoid or Humanoid.Health <= 0 then
						continue
					end

					if Player.Team == self.Parent.Friendlies then
						Direction -= 1
					elseif Player.Team == self.Parent.Enemies then
						Direction += 1
					end
				end
			end

			return self.CapSpeed * math.clamp(Direction, -self.MaxPlayers, self.MaxPlayers)
		end

		function Terminal:Update(Delta)	
			local Weight = self:GetWeight()

			self.CapProgress = math.clamp(self.CapProgress + (Weight * Delta), 0, 100)

			if self:IsOwnedByEnemies() then -- Enemies
				self.CapTime = math.min(self.CapTime + Delta, self.MaxTime)

				if self.CapTime == self.MaxTime then
					self:OnComplete()
				end
			elseif self:IsOwnedByFriendlies() then -- Friendlies
				self.CapTime = math.max(self.CapTime - Delta * self.Rollback, 0)
			end
		end

		PhaseTypes.Terminal = Terminal
	end
	
	do -- Payload Module
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Players = game:GetService("Players")

		local Shared = ReplicatedStorage.Shared

		local Network = require(Shared.Network)

		local Payload = {}
		Payload.__index = Payload

		function Payload.new(Parent, Properties)
			Properties = Properties or {}

			assert(Properties.Model, "Payload must have a model")
			assert(#Properties.Nodes > 1, "Payload cannot have less than 2 nodes")

			local self = setmetatable({}, Payload)

			self.Parent = Parent -- Ancestry
			self.Name = Properties.Name or "Payload"
			self.Mode = "Payload" -- Identity (For Clients, in the future we can change the UI per Phase)

			self.Region = Properties.Region or nil -- Payload Properties
			self.Model = Properties.Model or nil
			self.Speed = Properties.Speed or 8
			self.MaxPlayers = Properties.MaxPlayers or 4

			self.Nodes = Properties.Nodes -- Nodes (Required)
			self.TotalDistance = 0
			self.Checkpoints = {}

			self.Position = 1 -- State Properties
			self.NodeProgress = 0
			self.Distance = 0
			self.Callback = Properties.Callback or function() 
				print("Payload Completed")
			end

			self:CalculateTotalDistance()

			-- Point the Cart at Node2
			self.Model:PivotTo(CFrame.new(self.Nodes[1].CFrame.Position, self.Nodes[2].CFrame.Position))

			return self
		end

		function Payload:CalculateTotalDistance()
			self.TotalDistance = 0

			-- Calculate Distances
			for i = 1, #self.Nodes do
				local CurrentNode = self.Nodes[i]
				if CurrentNode.Checkpoint then
					self.Checkpoints[i] = self.TotalDistance
				end

				if i < #self.Nodes then
					local NextNode = self.Nodes[i+1]
					self.TotalDistance += (CurrentNode.CFrame.Position - NextNode.CFrame.Position).Magnitude
				end
			end

			for i, Distance in pairs(self.Checkpoints) do
				self.Checkpoints[i] = Distance/self.TotalDistance
			end
		end

		function Payload:CalculatePosition(Origin, Target, Percent)
			return Origin:Lerp(Target, math.clamp(Percent, 0, 1))
		end

		function Payload:GetPercentSpeed()
			return self.Speed / (self.Nodes[self.Position].CFrame.Position - self.Nodes[self.Position + 1].CFrame.Position).Magnitude
		end

		function Payload:AdjustCurrentPosPercent(Delta)
			self.NodeProgress = math.clamp(self.NodeProgress + Delta, 0, 1)
		end

		function Payload:SetSpeed(Speed)
			self.Speed = Speed
		end

		function Payload:Modify(Properties)
			Properties = Properties or {}

			for Index, Value in next, Properties do
				self[Index] = Value
			end

			return self.Parent
		end

		function Payload:AddNode(Node)
			self.Nodes[#self.Nodes + 1] = Node

			self:CalculateTotalDistance() -- Recalculate Distance

			return self.Parent
		end

		function Payload:Reset()
			self.Position = 1
			self.NodeProgress = 0
			self.Distance = 0

			-- Calculate Distances
			self:CalculateTotalDistance()

			for NodeIndex, Distance in next, self.Checkpoints do
				self.Nodes[NodeIndex].CapProgress = 0
				self.Nodes[NodeIndex].CapTime = 0
			end

			-- Point the Cart at Node2
			self.Model:PivotTo(CFrame.new(self.Nodes[1].CFrame.Position, self.Nodes[2].CFrame.Position))
		end

		function Payload:Poll()
			local CurrentNode = self.Nodes[self.Position]
			local Direction = self:GetWeight()

			if CurrentNode:CanCap() then -- If we can Cap during overtime
				if CurrentNode:IsOwnedByFriendlies() then -- Wait for defenders to fully cap
					return self.Parent.Friendlies
				end
			elseif Direction <= 0 then -- If we can't Cap, but the Payload is moving
				return self.Parent.Friendlies -- Wait for it to stop then declare a win
			end
		end

		function Payload:Pack(Data)
			local CurrentNode = self.Nodes[self.Position]

			Data.Name = self.Name
			Data.Mode = self.Mode
			Data.Percent = self.Distance/self.TotalDistance;
			Data.Checkpoints = self.Checkpoints

			if CurrentNode:CanCap() then
				Data.Capture = true
				Data.TimeLeft = CurrentNode.MaxTime - CurrentNode.CapTime
				Data.Progress = CurrentNode.CapProgress

				if CurrentNode:IsOwnedByEnemies() then
					if CurrentNode.CapTime == CurrentNode.MaxTime then
						Data.Capture = false
						Data.Percent = self.Distance/self.TotalDistance
					end
				end
			else
				Data.Capture = false
				Data.Percent = self.Distance/self.TotalDistance
			end

			return Data
		end

		function Payload:OnComplete()
			self.Parent:AdjustTime(self.BonusTime)
			self.Callback(self.Parent)
			self.Parent:NextPhase()
		end

		function Payload:GetWeight()
			local Direction = 0

			for _, Part in next, workspace:GetPartsInPart(self.Region) do
				if Part:IsA("BasePart") and Part.Parent:FindFirstChild("HumanoidRootPart")  then
					local Character = Part.Parent
					local Player = Players:GetPlayerFromCharacter(Character)

					if not Player then
						continue
					end

					local Humanoid = Character:FindFirstChild("Humanoid")

					if not Humanoid or Humanoid.Health <= 0 then
						continue
					end

					if Player.Team == self.Parent.Friendlies then
						Direction -= 1
					elseif Player.Team == self.Parent.Enemies then
						Direction += 1
					end
				end
			end

			return math.clamp(Direction, -self.MaxPlayers, self.MaxPlayers)
		end

		function Payload:Update(Delta)
			local Direction = self:GetWeight()
			local CurrentNode = self.Nodes[self.Position]

			if CurrentNode:CanCap() then -- Cart reached a checkpoint
				CurrentNode:AdjustCaptureProgress(CurrentNode.CapSpeed * Direction * Delta)

				if CurrentNode:IsOwnedByFriendlies() then
					CurrentNode:AdjustTime(-Delta * CurrentNode.Rollback)
					if CurrentNode.CapTime == 0 and self.Position > 1 then
						self.Position -= 1
						self.NodeProgress = 0.999
					end
				elseif CurrentNode:IsOwnedByEnemies() then
					CurrentNode:AdjustTime(Delta)
					if CurrentNode.CapTime == CurrentNode.MaxTime then
						self.Parent:AdjustTime(CurrentNode.BonusTime)
						CurrentNode.Callback()
					end
				end
			elseif self.Position == #self.Nodes then
				self.NodeProgress = 1 -- So it doesn't get stuck at 99%
				self.Distance = self.TotalDistance
				self.Parent:NextPhase()
			elseif Direction ~= 0 then
				local Speed = self:GetPercentSpeed()

				if Direction > 0 then
					self:AdjustCurrentPosPercent(Speed * Delta) -- Forwards
					if self.NodeProgress == 1 then
						if self.Position < #self.Nodes then
							self.Position += 1
							self.NodeProgress = 0
						end
					end
				elseif Direction < 0 then -- Backwards
					self:AdjustCurrentPosPercent(-Speed * Delta)
					if self.NodeProgress == 0 then 
						if self.Position > 1 and not CurrentNode.Checkpoint then -- Can't go behind a checkpoint
							self.Position -= 1
							self.NodeProgress = 1
						end
					end
				end

				if self.Position < #self.Nodes then
					local CurrentNodePosition = self.Nodes[self.Position].CFrame.Position
					local NextNodePosition = self.Nodes[self.Position + 1].CFrame.Position
					local OldPosition = self.Model:GetPivot().Position
					local NewPosition = self:CalculatePosition(CurrentNodePosition, NextNodePosition, self.NodeProgress)
					local Magnitude = (NewPosition - OldPosition).Magnitude * (Direction < 0 and 1 or -1)
					self.Distance += Magnitude

					local NewCFrame

					if self.NodeProgress > 0.8 and self.Position + 2 <= #self.Nodes then
						NewCFrame = CFrame.new(NewPosition, NextNodePosition:Lerp(self.Nodes[self.Position + 2].CFrame.Position, (self.NodeProgress - 0.8)/0.2))
					elseif self.NodeProgress == 1 then
						NewCFrame = NextNodePosition
					else
						NewCFrame = CFrame.new(NewPosition, NextNodePosition)
					end

					self.Model:PivotTo(NewCFrame)
				end
			end
		end

		PhaseTypes.Payload = Payload
	end
	
	do -- Target
		-- Welcome to the EASIEST code of my life
		local ReplicatedStorage = game:GetService("ReplicatedStorage")

		local Shared = ReplicatedStorage.Shared

		local Network = require(Shared.Network)

		local Target = {}
		Target.__index = Target

		function Target.new(Parent, Properties)
			Properties = Properties or {}

			assert(Properties.Hitbox, "Target must have a hitbox!")

			local self = setmetatable({}, Target)

			self.Parent = Parent -- Ancestry
			self.Name = Properties.Name or "Target"
			self.Mode = "Target" -- Identity (For Clients)

			self.Hitbox = Properties.Hitbox -- Target Properties
			self.MaxHealth = Properties.MaxHealth or 100
			self.Invulnerable = Properties.Invulnerable or false
			self.Regen = Properties.Regen or 5
			self.BonusTime = Properties.BonusTime or 60 * 5

			self.WasInvulnerable = self.Invulnerable -- Saved Properties

			self.Health = self.MaxHealth -- State Properties
			self.Callback = Properties.Callback or function()
				print("Target Completed")
			end

			self.Connection = nil

			return self
		end

		function Target:OnComplete()	
			self.Parent:AdjustTime(self.BonusTime)
			self.Callback(self.Parent)
			self.Parent:NextPhase()
		end


		function Target:Reset() -- Default Settings
			self.Health = self.MaxHealth
			self.Invulnerable = self.WasInvulnerable

			if self.Connection then
				Network:DestroyFunction("DamageTarget")
				self.Connection = nil
			end

			return self.Parent
		end

		function Target:Pack(Data)

			Data.Name = self.Name
			Data.Mode = self.Mode
			Data.Capture = false
			Data.Percent = self.Health/self.MaxHealth
			Data.Invulnerable = self.Invulnerable

			return Data
		end

		function Target:Poll()
			if self.Health == self.MaxHealth then -- Overtime
				return self.Parent.Defenders
			end
		end

		function Target:Update(Delta)
			if not self.Connection then -- INSECURE CODE
				self.Connection = Network:CreateFunction("DamageTarget", function(Client, Damage)
					Damage = Damage or 0 -- So it doesn't error		
					if not self.Invulnerable then
						self.Health = math.clamp(self.Health - Damage, 0, self.MaxHealth)
					end
				end)
			end

			if self.Health <= 0 then
				Network:DestroyFunction("DamageTarget")
				self.Connection = nil
				self:OnComplete()
			end

			self.Health = math.clamp(self.Health + self.Regen * Delta, 0, self.MaxHealth)

			-- Completely optional only for demo purposes
			self.Hitbox.Color = Color3.fromRGB(75, 151, 75):Lerp(Color3.fromRGB(196, 40, 28), 1 - self.Health/self.MaxHealth)
		end

		PhaseTypes.Target = Target
	end
	
	do
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Players = game:GetService("Players")

		local Shared = ReplicatedStorage.Shared

		local Bomb = {}
		Bomb.__index = Bomb

		function Bomb.new(Parent, Properties)
			Properties = Properties or {}

			assert(Properties.Region, "Bomb must have a region!")
			assert(Properties.Pickup, "Bomb must have a pickup!")
			assert(Properties.BombModel, "Bomb must have a model!")

			local self = setmetatable({}, Bomb)

			self.Parent = Parent -- Ancestry
			self.Name = Properties.Name or "Bomb"
			self.Mode = "Bomb" -- Identity (For Clients)

			self.Region = Properties.Region -- Bomb Properties
			self.Pickup = Properties.Pickup
			self.BombModel = Properties.BombModel
			self.MaxBombs = Properties.MaxBombs or 0

			self.MaxTime = Properties.Time or 60 * 1 -- Time Properties
			self.CapSpeed = Properties.CapSpeed or 10
			self.Rollback = Properties.Rollback or 2
			self.BonusTime = Properties.BonusTime or 60 * 5

			self.CapTime = 0 -- State Properties
			self.CapProgress = 0
			self.Bombs = self.MaxBombs
			self.Bomber = nil
			self.Attached = false
			self.ActiveBomb = nil
			self.Planted = false
			self.Callback = Properties.Callback or function()
				print("Bomb Completed")
			end

			return self
		end

		function Bomb:IsOwnedByFriendlies()
			return self.CapProgress == 0
		end

		function Bomb:IsOwnedByEnemies()
			return self.CapProgress == 100
		end

		function Bomb:Modify(Properties)
			Properties = Properties or {}

			for Index, Value in next, Properties do
				self[Index] = Value
			end

			return self.Parent
		end

		function Bomb:AddBomb(Bombs)
			self.Bombs += Bombs

			return self.Parent
		end

		function Bomb:Reset()
			self.CapTime = 0
			self.CapProgress = 0
			self.Bombs = self.MaxBombs
			if self.ActiveBomb then
				self.ActiveBomb:Destroy()
			end
			self.ActiveBomb = nil
			self.Attached = false
			self.Bomber = nil
			self.Planted = false
		end

		function Bomb:Poll()
			if self:IsOwnedByEnemies() then
				return self.Parent.Friendlies
			end
		end

		function Bomb:Pack(Data)

			Data.Name = self.Name
			Data.Mode = self.Mode
			Data.Capture = true
			Data.Progress = self.CapProgress
			Data.MaxTime = self.MaxTime
			Data.TimeLeft = self.MaxTime - self.CapTime
			Data.Percent = self.CapTime/self.MaxTime
			Data.Bombs = self.MaxBombs > 0 and self.Bombs

			return Data
		end

		function Bomb:OnComplete()
			self.Parent:AdjustTime(self.BonusTime)
			self.Callback(self.Parent)
			self.Parent:NextPhase()
		end

		function Bomb:AttachToCharacter(Character)
			local Humanoid = Character:FindFirstChild("Humanoid")

			if not self.ActiveBomb then
				self.ActiveBomb = Utility.Clone(self.BombModel, {
					Name = "Bomb",
					CFrame = Character:FindFirstChild("Torso").CFrame - Character:FindFirstChild("Torso").CFrame.LookVector,
					Parent = Character
				})
			end

			self.ActiveBomb:SetNetworkOwner(nil) -- So players cannot teleport it, increases server usage

			local Weld = Utility.Create("Weld", {
				Part0 = self.ActiveBomb,
				Part1 = Character:FindFirstChild("Torso"),
				C0 = CFrame.new(0, 1, 0) * CFrame.fromEulerAnglesXYZ(math.pi/2, 0, 0),
				Parent = self.ActiveBomb,
			})

			local Connection; Connection = Humanoid.Died:Connect(function()
				Weld:Destroy()
				self.ActiveBomb.Parent = workspace.Raid
				self.Attached = false
				self.Bomber = nil
				Connection:Disconnect() -- Cleans itself up
				Connection = nil
			end)

			self.Attached = true
		end

		function Bomb:GetBomber()
			if self.Planted then
				return
			end

			for _, Part in next, workspace:GetPartsInPart(self.Pickup) do
				if Part:IsA("BasePart") and Part.Parent:FindFirstChild("HumanoidRootPart") then

					local Character = Part.Parent
					local Player = Players:GetPlayerFromCharacter(Character)

					if not Player then
						continue
					end

					local Humanoid = Character:FindFirstChild("Humanoid")

					if not Humanoid or Humanoid.Health <= 0 then
						continue
					end

					if Player.Team == self.Parent.Enemies then
						self.Bomber = Player
						self:AttachToCharacter(Character)
					end
				end
			end
		end

		function Bomb:FindPlayer()
			if not self.ActiveBomb then
				return
			end

			for _, Part in next, workspace:GetPartBoundsInBox(self.ActiveBomb.CFrame, self.ActiveBomb.Size * 2) do
				if Part:IsA("BasePart") and Part.Parent and Part.Parent:FindFirstChild("HumanoidRootPart") then
					local Character = Part.Parent
					local Player = Players:GetPlayerFromCharacter(Character)

					if not Player then
						continue
					end

					local Humanoid = Character:FindFirstChild("Humanoid")

					if not Humanoid or Humanoid.Health <= 0 then
						continue
					end

					if Player.Team == self.Parent.Enemies then
						self.Bomber = Player
						self:AttachToCharacter(Character)
					elseif Player.Team == self.Parent.Friendlies then
						if self.ActiveBomb then -- Recheck cause its super fast
							self.ActiveBomb:Destroy()
							self.ActiveBomb = nil
							self.Attached = false
							self.Bomber = nil
							self.Bombs = math.max(self.Bombs - 1, 0)
							if self.Bombs == 0 and self.MaxBombs > 0 then
								self.Parent:End(true)
							end
						end
					end
				end
			end
		end

		function Bomb:GetWeight()
			local Direction = 0 

			for _, Part in next, workspace:GetPartsInPart(self.Region) do
				if Part:IsA("BasePart") and Part.Parent:FindFirstChild("HumanoidRootPart")  then
					local Character = Part.Parent
					local Player = Players:GetPlayerFromCharacter(Character)

					if not Player then
						continue
					end

					local Humanoid = Character:FindFirstChild("Humanoid")

					if not Humanoid or Humanoid.Health <= 0 then
						continue
					end

					if Player.Team == self.Parent.Friendlies and self.Planted then
						Direction -= 1
					elseif Player.Team == self.Parent.Enemies and (Player == self.Bomber or self.Planted or self.CapProgress > 0) then
						Direction += 1
					end
				end
			end

			return self.CapSpeed * math.clamp(Direction, -1, 1)
		end

		function Bomb:Update(Delta)
			if not self.Bomber and not self.Attached and not self.ActiveBomb then
				self:GetBomber()
			end

			if not self.Bomber and not self.Attached and self.ActiveBomb then -- Bomb is in Workspace
				self:FindPlayer() -- Destroy when Friendly touches, Attach when Enemy touches
			end

			local Weight = self:GetWeight()

			self.CapProgress = math.clamp(self.CapProgress + self.CapSpeed * Weight * Delta, 0, 100)	

			if self:IsOwnedByFriendlies() then
				if self.Planted then
					self.Planted = false
					self.Bombs = math.max(self.Bombs - 1, 0)
				end

				if self.Bombs == 0 and self.MaxBombs > 0 then
					self.Parent:End(true)
				end
			end

			if self:IsOwnedByEnemies() then -- Enemies
				if self.ActiveBomb then
					self.ActiveBomb:Destroy()
					self.ActiveBomb = nil
					self.Attached = false
					self.Bomber = nil
					self.Bombs = math.max(self.Bombs - 1, 0)
				end

				self.Planted = true
				self.CapTime = math.min(self.CapTime + Delta, self.MaxTime)
				self.Region.BrickColor = BrickColor.new("Really red")

				if self.CapTime == self.MaxTime then
					self:OnComplete()
				end
			elseif self:IsOwnedByFriendlies() then -- Friendlies
				self.CapTime = math.max(self.CapTime - Delta * self.Rollback, 0)
				self.Region.BrickColor = BrickColor.new("Really blue")
			end
		end

		PhaseTypes.Bomb = Bomb
	end
end

local Raid = {}
Raid.__index = Raid

function Raid.new(Properties)
	Properties = Properties or {}
	assert(Properties.Friendlies, "The Friendly team must be set!")
	assert(Properties.Enemies, "The Enemies team must be set!")
	assert(Properties.SetSpawn and workspace:FindFirstChild("Spawns"), 
		"If SetSpawn is true, make a folder named \"Spawns\" and a folder(s) under it, named \"PhaseN\" where the number corresponding to the phase.")
	
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

do -- Node for Payload
	local Node = {}
	Node.__index = Node

	function Node.new(Position, Properties)
		Properties = Properties or {}

		local self = setmetatable({}, Node)

		self.Name = "Node" -- Identity

		self.CFrame = Position -- Node Properties

		self.MaxTime = Properties.Time -- Time Properties
		self.CapTime = 0
		self.CapProgress = 0
		self.CapSpeed = Properties.CapSpeed or 10
		self.Rollback = Properties.Rollback or 2
		self.BonusTime = Properties.BonusTime or 60 * 5

		self.Checkpoint = Properties.Time ~= nil -- State Properties
		self.Callback = Properties.Callback or function() 
			print("Checkpoint Completed!")
		end

		return self
	end

	function Node:CanCap()
		return self.Checkpoint and self.CapTime < self.MaxTime
	end

	function Node:IsOwnedByFriendlies()
		return self.CapProgress == 0
	end

	function Node:IsOwnedByEnemies()
		return self.CapProgress == 100
	end

	function Node:AdjustCaptureProgress(Delta)
		self.CapProgress =  math.clamp(self.CapProgress + Delta, 0, 100)
	end

	function Node:AdjustTime(Delta)
		self.CapTime = math.clamp(self.CapTime + Delta, 0, self.MaxTime)
	end

	function Node:IsCaptured()
		return self.CapTime == self.MaxTime
	end

	function Node:OnComplete() -- Nodes technically have no parent
		self.Callback()
	end
	
	Raid.CreateNode = Node.new
end

return Raid
