-- Normal door script. Must stay clean.
local TweenService = game:GetService("TweenService")
local door = script.Parent
local open = false
local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad)
door.ClickDetector.MouseClick:Connect(function(player)
	open = not open
	local goal = { CFrame = door.CFrame * CFrame.Angles(0, if open then math.rad(90) else 0, 0) }
	TweenService:Create(door, info, goal):Play()
	print(player.Name .. " used the door")
end)
