local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared

local Utility = require(Shared.Utility)

local BombModel = script.Model

local Bomb = {}
Bomb.__index = Bomb

function Bomb.new(Parent, Properties)
	Properties = Properties or {}
	
	assert(Properties.Region, "Bomb must have a region!")
	assert(Properties.Pickup, "Bomb must have a pickup!")
	
	local self = setmetatable({}, Bomb)
	
	self.Parent = Parent -- Ancestry
	self.Name = Properties.Name or "Bomb"
	self.Mode = "Bomb" -- Identity (For Clients)
	
	self.Region = Properties.Region -- Bomb Properties
	self.Pickup = Properties.Pickup
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
		self.ActiveBomb = Utility.Clone(BombModel, {
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

return Bomb
