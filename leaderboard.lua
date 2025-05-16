-- Written by @ifeq on 5/15/25

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared

local Utility;
do -- Utility Module
	Utility = {}
	
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
end

local Cache = {}
local Leaderboard = {}

function Leaderboard:AddPlayer(Player)
	local LeaderStats = Utility.Create("Folder", {
		Name = "leaderstats"
	})

	Utility.Create("IntValue", {
		Name = "Kills",
		Value = 0,
		Parent = LeaderStats
	})

	Utility.Create("IntValue", {
		Name = "Assists",
		Value = 0,
		Parent = LeaderStats
	})

	Utility.Create("IntValue", {
		Name = "Damage",
		Value = 0,
		Parent = LeaderStats
	})

	Utility.Create("IntValue", {
		Name = "Heals",
		Value = 0,
		Parent = LeaderStats
	})

	LeaderStats.Parent = Player

	if Cache[Player.UserId] then
		for Index, Value in next, Cache do
			LeaderStats[Index].Value = Value
		end
	else
		Cache[Player.UserId] = {}

		for _, Value in next, LeaderStats:GetChildren() do
			Cache[Value.Name] = Value.Value
		end
	end
end

function Leaderboard:GetStat(Player, Stat)
	return Cache[Player.UserId][Stat]
end

function Leaderboard:GetMVP(Stat) -- When you calculate the MVP at the end
	local MVP, Highest = nil, 0 -- You don't have to be in the server anymore
	
	for PlayerId, _ in next, Cache do
		local PlayerStat = Cache[PlayerId][Stat]
		if PlayerStat > Highest then
			Highest = PlayerStat
			MVP = PlayerId
		end
	end
	
	return MVP, Highest
end

function Leaderboard:SetStat(Player, Stat, Value)
	Cache[Player.UserId][Stat] = Value

	Player.leaderstats:FindFirstChild(Stat).Value = Cache[Player.UserId][Stat]
end

function Leaderboard:IncrementStat(Player, Stat, Amount)
	Cache[Player.UserId][Stat] += Amount

	Player.leaderstats:FindFirstChild(Stat).Value = Cache[Player.UserId][Stat]
end

function Leaderboard:ResetStats(Player)
	for Stat, Value in next, Cache[Player.UserId] do
		Cache[Player.UserId][Stat] = 0
		Player.leaderstats:FindFirstChild(Stat).Value = Cache[Player.UserId][Stat]
	end
end

function Leaderboard:ResetAllStats()
	for _, Player in next, Players:GetPlayers() do
		local PlayerStats = Cache[Player.UserId]
		if PlayerStats then
			for Stat, Value in next, PlayerStats do
				PlayerStats[Stat] = 0
				Player.leaderstats:FindFirstChild(Stat).Value = PlayerStats[Stat]
			end
		end
	end
end

return Leaderboard
