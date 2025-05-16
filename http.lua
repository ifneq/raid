
-- Writen by @ifeq on 5/15/25
-- HttpService Wrapper with Safety
local HttpService = game:GetService("HttpService")

local MAX_RETRIES = 5;

local Http = {}

function Http:Request(URL, Method, Headers, Body)
	local Response, Success, Err;
	for _ = 1, MAX_RETRIES, 1 do
		Success, Err = pcall(function()
			Response = HttpService:RequestAsync({
				Url = URL, 
				Method = Method,
				Headers = Headers,
				Body = HttpService:JSONEncode(Body),
			})
		end)

		if Success then
			return Response
		else
			return error(Err)
		end
	end
	
	if (Err) then
		return error(Err)
	end
	
	return
end

function Http:Get(URL)
	local Data, Success, Err;
	for _ = 1, MAX_RETRIES, 1 do
		Success, Err = pcall(function()
			local GetRequest = HttpService:GetAsync(URL)
			Data = HttpService:JSONDecode(GetRequest)
		end)

		if Success then
			return Data -- JSON Data
		end
	end
	
	if Err then
		return error(Err)
	end
	
	return
end

function Http:Post(URL, Payload, ...)
	local Success, Err;
	for _ = 1, MAX_RETRIES, 1 do
		Success, Err = pcall(function(...)
			HttpService:PostAsync(URL, HttpService:JSONEncode(Payload), ...)
		end)(...)

		if Success then
			return Success
		end
	end
	
	if Err then
		return error(Err)
	end
	
	return
end

return Http
