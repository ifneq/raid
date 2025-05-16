local UserInputService = game:GetService("UserInputService")

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

local Network = {}
do -- Network (Server Only, It's assymetrical)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	
	local UnreliableRemoteEvent = ReplicatedStorage:WaitForChild("UnreliableRemoteEvent")
	local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
	local BindableEvent = ReplicatedStorage:WaitForChild("Event")
	local Public = ReplicatedStorage:WaitForChild("Public")
	local Local = ReplicatedStorage:WaitForChild("Local")

	-- Self Communication
	function Network:Fire(Channel, ...)
		BindableEvent:Fire(Channel, ...)
	end

	function Network.Event(Channel, Callback)
		return BindableEvent.Event:Connect(function(RecievedChannel, ...)
			if RecievedChannel == Channel then
				Callback(...)
			end
		end)
	end

	function Network:CreateLocalFunction(Channel, Callback)
		local BindableFuncation = Utility.Create("BindableFunction", {
			Name = Channel,
			Parent = Local,
		})

		return BindableFuncation
	end

	function Network:DestroyLocalFunction(Channel)
		Local:FindFirstChild(Channel):Destroy()
	end

	function Network:InvokeLocalFunction(Channel, ...)
		local BindableFunction = Local:WaitForChild(Channel)
		BindableFunction:Invoke(...)
	end

	function Network:ListenForLocalFunction(Channel, Callback)
		local BindableFunction = Local:WaitForChild(Channel)
		BindableFunction.OnInvoke = Callback
	end
	
	-- Client to Server Communcation
	function Network:ListenForFunction(Channel, Callback)
		local RemoteFunction = Public:WaitForChild(Channel)
		RemoteFunction.OnClientInvoke = Callback
	end
	
	function Network:InvokeServer(Channel, ...)
		local RemoteFunction = Public:FindFirstChild(Channel)

		if RemoteFunction then
			return RemoteFunction:InvokeServer(...)
		end
	end
	
	function Network:UnreliableFireServer(Channel, ...)
		UnreliableRemoteEvent:FireServer(Channel, ...)
	end

	function Network:FireServer(Channel, ...) 
		RemoteEvent:FireServer(Channel, ...)
	end
	
	function Network.OnUnreliableClientEvent(Channel, Callback)
		return UnreliableRemoteEvent.OnClientEvent:Connect(function(RecievedChannel, ...)
			if RecievedChannel == Channel then
				Callback(...)
			end
		end)
	end
	function Network.OnClientEvent(Channel, Callback) -- Could this optimized? Probably.
		return RemoteEvent.OnClientEvent:Connect(function(RecievedChannel, ...)
			if RecievedChannel == Channel then
				Callback(...)
			end
		end)
	end
end

local Main = script.Parent
local Checkpoints = Main.Checkpoints
local Capture = Main.Capture
local Progress = Main.Progress
local Percent = Main.Percent
local RaidTime = Main.RaidTime
local TimeLeft = Main.TimeLeft
local Location = Main.Location
local Win = Main.Parent.Win

local function SecondsToMinuteString(s)
	local Minutes = math.floor(s / 60)
	local Seconds = math.floor(s % 60)

	return string.format("%02d:%02d", Minutes, Seconds)
end

local function Update(Data)
	if Data.RaidTime then
		RaidTime.Text = SecondsToMinuteString(Data.RaidTime)
	end

	if Data.Percent then
		Percent.Text = math.floor(math.abs(Data.Percent) * 100) .. "%"
		Progress.Size = UDim2.new(math.abs(Data.Percent), 0, 0, 2)
	end

	if Data.Progress then
		Capture.Size = UDim2.new(math.abs(Data.Progress)/100, 0, 0, 2)
		if Data.Progress < 0 then
			Capture.BackgroundColor3 = Data.Friendlies.TeamColor.Color
		else
			Capture.BackgroundColor3 = Data.Enemies.TeamColor.Color
		end
	end

	if Data.TimeLeft then
		TimeLeft.Text = SecondsToMinuteString(Data.TimeLeft)
		
		if Data.Bombs then
			TimeLeft.Text ..= "\nBombs Left: ".. Data.Bombs
		end
	end
	
	if Data.Name then
		Location.Visible = Data.Name ~= nil
		Location.Text = Data.Name
	end
	
	if Data.Capture ~= nil then
		Capture.Visible = Data.Capture
		TimeLeft.Visible = Data.Capture
	end
	
	for _, Child in next, Main.Checkpoints:GetChildren() do -- Is this performant? No!
		Child:Destroy() -- But it allows for dynamic behavior, and you can recompute on server
	end
	
	if Data.Checkpoints then
		for NodeIndex, Percent in pairs(Data.Checkpoints) do
			Utility.Clone(script.Checkpoint, {
				Name = NodeIndex,
				Position = UDim2.fromScale(Percent, 0.5),
				Parent = Main.Checkpoints
			})
		end
	end
end


Network.OnClientEvent("RaidStart", function()
	Win.Visible = false
end)

local Data = Network:InvokeServer("GetRaidState")

Update(Data)

Network.OnUnreliableClientEvent("RaidUpdate", Update)

Network.OnClientEvent("RaidEnd", function(Data)
	Win.Container.Title.Text = string.upper(Data.Winner.Name) .. " VICTORY" 
	Win.Container.Title.TextColor3 = Data.Winner.TeamColor.Color
	Win.Container.Content.Text = Data.Message
	Win.Container.Date.Text = Data.Date
	Win.Visible = true
end)

UserInputService.InputBegan:Connect(function(Input, Processed)
	if Processed then
		return
	end
	
	if Input.KeyCode == Enum.KeyCode.E then
		Network:InvokeServer("DamageTarget", 10)
	end
end)
