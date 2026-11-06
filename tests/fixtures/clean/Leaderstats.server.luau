-- Normal leaderstats with DataStore save. Must stay clean.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("Coins_v1")
local Config = require(script.Parent.Config)

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	local ok, saved = pcall(function()
		return store:GetAsync(tostring(player.UserId))
	end)
	coins.Value = if ok and saved then saved else Config.StartCoins
	coins.Parent = stats
end)

Players.PlayerRemoving:Connect(function(player)
	local coins = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Coins")
	if coins then
		pcall(function()
			store:SetAsync(tostring(player.UserId), coins.Value)
		end)
	end
end)
