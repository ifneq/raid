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

return Payload
