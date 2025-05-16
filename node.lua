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

return Node
