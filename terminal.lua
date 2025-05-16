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

return Terminal
