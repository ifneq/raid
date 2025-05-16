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

return Target
