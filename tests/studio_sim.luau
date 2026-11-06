-- Headless Studio simulation. Loads the BUILT plugin .rbxm, runs its scripts with
-- Roblox-style instance requires (script.Parent.X), mocks the plugin API, and clicks
-- the real buttons. Run: lune run tests/studio_sim.luau <build dir>
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")
local process = require("@lune/process")

local BUILD = process.args[1] or "build"
local passed, failed = 0, 0
local log = {}
local function check(name: string, cond: any, info: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if info then "\n     " .. tostring(info) else ""))
	end
end

-- Fake signals for events that Lune does not implement
local function newSignal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function()
			table.remove(s.handlers, table.find(s.handlers, fn) or 0)
		end }
	end
	function s:Fire(...)
		for _, fn in table.clone(self.handlers) do
			fn(...)
		end
	end
	return s
end
local signals = {}
local function signalFor(inst, name)
	signals[inst] = signals[inst] or {}
	signals[inst][name] = signals[inst][name] or newSignal()
	return signals[inst][name]
end
roblox.implementProperty("TextButton", "Activated", function(inst)
	return signalFor(inst, "Activated")
end)
roblox.implementProperty("Workspace", "ChildAdded", function(inst)
	return signalFor(inst, "ChildAdded")
end)
roblox.implementProperty("DataModel", "PlaceId", function()
	return 0 -- unpublished place
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(inst, prop)
	return signalFor(inst, "Changed:" .. prop)
end)

-- Studio services that Lune does not implement. Registered once, state swapped per run.
local state = { selection = {}, recordings = {}, isEdit = true }
roblox.implementMethod("Selection", "Get", function()
	return table.clone(state.selection)
end)
roblox.implementMethod("Selection", "Set", function(_, list)
	state.selection = list
end)
roblox.implementMethod("ChangeHistoryService", "TryBeginRecording", function(_, name)
	table.insert(state.recordings, { name = name })
	return #state.recordings
end)
roblox.implementMethod("ChangeHistoryService", "FinishRecording", function(_, id, op)
	state.recordings[id].op = tostring(op)
end)
roblox.implementMethod("ChangeHistoryService", "SetWaypoint", function() end)
roblox.implementMethod("RunService", "IsEdit", function()
	return state.isEdit
end)

local function loadModel(path)
	return roblox.deserializeModel(fs.readFile(path))[1]
end

local function runPlugin(rbxm: string)
	local root = loadModel(rbxm)
	local game = roblox.Instance.new("DataModel")
	game.PlaceId = 0 -- unpublished place; Lune has no default for it
	local workspace = game:GetService("Workspace")
	local ServerScriptService = game:GetService("ServerScriptService")
	game:GetService("ServerStorage")
	state.selection = {}
	state.recordings = {}
	local recordings = state.recordings

	local settingsStore, opened = {}, {}
	local dock
	local plugin = {
		Unloading = newSignal(),
		CreateToolbar = function(_, name)
			return { CreateButton = function(_, text, tip, icon)
				local b = { Click = newSignal(), ClickableWhenViewportHidden = false, active = false, text = text, icon = icon }
				function b:SetActive(v)
					b.active = v
				end
				return b
			end }
		end,
		CreateDockWidgetPluginGui = function(_, id, info)
			dock = roblox.Instance.new("DockWidgetPluginGui")
			dock.Enabled = false
			return dock
		end,
		GetSetting = function(_, k)
			return settingsStore[k]
		end,
		SetSetting = function(_, k, v)
			settingsStore[k] = v
		end,
		OpenScript = function(_, s, line)
			table.insert(opened, { s, line })
		end,
	}

	local env
	local cache = {}
	local function envFor(scriptInst)
		local e = table.clone(env)
		e.script = scriptInst
		return e
	end
	local function requireInstance(m)
		if cache[m] then
			return cache[m]
		end
		assert(m.ClassName == "ModuleScript", "require of non-module " .. m:GetFullName())
		local fn = luau.load(m.Source, { debugName = m:GetFullName(), environment = envFor(m) })
		cache[m] = fn()
		return cache[m]
	end
	env = {
		game = game, workspace = workspace, plugin = plugin, task = task,
		Instance = roblox.Instance, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
		Color3 = roblox.Color3, require = requireInstance,
		DockWidgetPluginGuiInfo = { new = function(...) return { ... } end },
		settings = function() error("no Studio settings in Lune") end,
	}
	local main = luau.load(root.Source, { debugName = root:GetFullName(), environment = envFor(root) })
	main()
	return {
		root = root, game = game, workspace = workspace, sss = ServerScriptService, dock = dock,
		select = function(list) state.selection = list end,
		recordings = recordings, opened = opened, settings = settingsStore,
	}
end

local function find(parent, name)
	for _, d in parent:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function findAll(parent, name)
	local out = {}
	for _, d in parent:GetDescendants() do
		if d.Name == name then
			table.insert(out, d)
		end
	end
	return out
end
local function click(btn)
	assert(btn, "button not found")
	signalFor(btn, "Activated"):Fire()
end
local function status(sim)
	return find(sim.dock, "Status").Text
end
-- Text dump of the panel in layout order, used as the run log
local function dump(inst, depth, out)
	local kids = inst:GetChildren()
	table.sort(kids, function(a, b)
		local la = if a:IsA("GuiObject") then a.LayoutOrder else 0
		local lb = if b:IsA("GuiObject") then b.LayoutOrder else 0
		return la < lb
	end)
	for _, k in kids do
		if k:IsA("TextLabel") or k:IsA("TextBox") then
			table.insert(out, string.rep("  ", depth) .. k.Text)
		elseif k:IsA("TextButton") then
			table.insert(out, string.rep("  ", depth) .. "[" .. k.Text .. "]")
		end
		dump(k, if k:IsA("Frame") then depth + 1 else depth, out)
	end
	return out
end

------------------------------------------------------------------ FREE build
local sim = runPlugin(BUILD .. "/ZovoBackdoorScanner.rbxm")
check("dock created", sim.dock ~= nil)
check("panel built", find(sim.dock, "ScannerRoot") ~= nil)
check("free footer shows Pro note", find(sim.dock, "ProNote") ~= nil and find(sim.dock, "Export") == nil)

local infected = loadModel(BUILD .. "/fixtures/infected.rbxm")
infected.Parent = sim.workspace
local clean = loadModel(BUILD .. "/fixtures/clean.rbxm")
clean.Parent = sim.workspace

-- empty selection
sim.select({})
click(find(sim.dock, "ScanSelection"))
check("empty selection message", string.find(status(sim), "Nothing is selected", 1, true), status(sim))

-- clean kit
sim.select({ clean })
click(find(sim.dock, "ScanSelection"))
check("clean kit is clean", string.find(status(sim), "No risky code found. 3 scripts checked", 1, true), status(sim))
check("clean kit shows empty note", find(sim.dock, "Empty") ~= nil)

-- infected kit
sim.select({ infected })
click(find(sim.dock, "ScanSelection"))
local s = status(sim)
table.insert(log, "== Scan selection on FreeCarKit (infected fixture)")
for _, l in dump(sim.dock, 0, {}) do
	table.insert(log, l)
end
check("infected kit verdict", string.find(s, "Dangerous code found. 10 scripts checked", 1, true), s)
local entries = 0
for _, c in find(sim.dock, "Results"):GetChildren() do
	if string.match(c.Name, "^Entry") then
		entries += 1
	end
end
check("9 risky scripts listed (Settings module is clean)", entries == 9, entries)
local text = table.concat(log, "\n")
for _, want in {
	"Loads code by asset ID (require with a number)", "Code pushed off screen with spaces",
	"Script name used by known viruses", "Same script copied many times", "Script hides or renames itself",
	"Builds a dangerous name from pieces", "Sends data to a Discord webhook", "Script inside an object that does not run scripts",
	"Changes the script environment", "Prompts players to buy something", "Teleports players to a fixed place",
	"Code from a known obfuscator", "String written as escape codes", "Special handling for a fixed user ID",
} do
	check("infected report shows: " .. want, string.find(text, want, 1, true))
end
check("Settings module not listed", not string.find(text, "FreeCarKit.Settings", 1, true))

-- Open at line: first entry is the critical Loader script? find Open button of Loader
local firstEntry = find(sim.dock, "Entry1")
local firstPath = find(firstEntry, "Path").Text
click(find(firstEntry, "Open"))
check("Open calls plugin:OpenScript with a line", #sim.opened == 1 and sim.opened[1][2] >= 1, firstPath)

-- Delete the loader through the UI and check undo recording + rescan
local loader = infected.Body.Loader
local loaderEntry
for _, e in findAll(sim.dock, "Path") do
	if string.find(e.Text, "FreeCarKit.Body.Loader", 1, true) then
		loaderEntry = e.Parent
	end
end
click(find(loaderEntry, "Delete"))
check("Delete removed the script", loader.Parent == nil)
check("Delete was recorded for undo", #sim.recordings == 1 and string.find(sim.recordings[1].op or "", "Commit", 1, true), sim.recordings[1] and sim.recordings[1].op)
check("rescan after delete", string.find(status(sim), "Deleted FreeCarKit.Body.Loader", 1, true) and string.find(status(sim), "9 scripts checked", 1, true), status(sim))

-- Disable a Vaccine copy
local vacEntry
for _, e in findAll(sim.dock, "Path") do
	if string.find(e.Text, "FreeCarKit.Wheel1.Vaccine", 1, true) then
		vacEntry = e.Parent
	end
end
click(find(vacEntry, "Disable"))
check("Disable sets Enabled false", infected.Wheel1.Vaccine.Enabled == false)

-- Ignore one finding (session only in free)
local before = #findAll(sim.dock, "Title")
click(find(find(sim.dock, "Entry1"), "Ignore"))
local after = #findAll(sim.dock, "Title")
check("Ignore hides one finding", after == before - 1, before .. " -> " .. after)
check("free build does not save ignore list", next(sim.settings) == nil)

-- Creator Store check on the plugin itself (dogfood) and on the infected kit
local selfCopy = loadModel(BUILD .. "/ZovoBackdoorScanner.rbxm")
selfCopy.Parent = sim.sss
sim.select({ selfCopy })
click(find(sim.dock, "Preflight"))
check("the plugin passes its own Creator Store check", string.find(status(sim), "Ready for the Creator Store", 1, true), status(sim))
click(find(sim.dock, "ScanSelection"))
check("the plugin has no findings at all", string.find(status(sim), "No risky code found. 8 scripts checked", 1, true), status(sim))
sim.select({ infected })
click(find(sim.dock, "Preflight"))
check("infected kit is blocked for the store", string.find(status(sim), "Not ready for the Creator Store", 1, true), status(sim))
local storeText = table.concat(dump(sim.dock, 0, {}), "\n")
check("store mode hides non-store rules", not string.find(storeText, "Prompts players to buy", 1, true) and string.find(storeText, "(Creator Store rule)", 1, true))
table.insert(log, "\n== Creator Store check on FreeCarKit after delete, disable and ignore")
table.insert(log, status(sim))

-- Delete a script that is itself the scanned selection: the list must refresh
local lone = loadModel(BUILD .. "/fixtures/infected.rbxm").Packed
lone.Parent = sim.workspace
sim.select({ lone })
click(find(sim.dock, "ScanSelection"))
check("lone script scanned", string.find(status(sim), "1 scripts checked", 1, true), status(sim))
click(find(find(sim.dock, "Entry1"), "Delete"))
check("list refreshes after deleting the scanned root", find(sim.dock, "Entry1") == nil and find(sim.dock, "Empty") ~= nil)

-- Whole place
click(find(sim.dock, "ScanPlace"))
check("whole place scan", string.find(status(sim), "scripts checked", 1, true) and string.find(status(sim), "Dangerous code found", 1, true), status(sim))
table.insert(log, "\n== Scan whole place")
table.insert(log, status(sim))

------------------------------------------------------------------ PRO build
local pro = runPlugin(BUILD .. "/ZovoBackdoorScannerPro.rbxm")
check("pro footer has tools", find(pro.dock, "Export") ~= nil and find(pro.dock, "ProNote") == nil)
click(find(pro.dock, "Export"))
check("export needs a scan first", string.find(status(pro), "Run a scan first", 1, true))
click(find(pro.dock, "AutoScan"))
check("auto-scan setting saved", pro.settings.autoScan == true)
check("auto-scan label on", string.find(find(pro.dock, "AutoScan").Text, "is on", 1, true))
local inserted = loadModel(BUILD .. "/fixtures/infected.rbxm")
inserted.Parent = pro.workspace
signalFor(pro.workspace, "ChildAdded"):Fire(inserted)
check("auto-scan opens the panel on a risky insert", pro.dock.Enabled == true)
check("auto-scan names the inserted model", string.find(status(pro), "You just inserted FreeCarKit", 1, true), status(pro))
table.insert(log, "\n== Pro auto-scan on insert")
table.insert(log, status(pro))
-- playtest: no auto-scan outside Edit mode
state.isEdit = false
pro.dock.Enabled = false
local playIns = loadModel(BUILD .. "/fixtures/infected.rbxm")
playIns.Parent = pro.workspace
signalFor(pro.workspace, "ChildAdded"):Fire(playIns)
check("auto-scan is off during playtests", pro.dock.Enabled == false)
playIns.Parent = nil
state.isEdit = true
local cleanIns = loadModel(BUILD .. "/fixtures/clean.rbxm")
pro.dock.Enabled = false
cleanIns.Parent = pro.workspace
signalFor(pro.workspace, "ChildAdded"):Fire(cleanIns)
check("auto-scan stays quiet on a clean insert", pro.dock.Enabled == false)
click(find(find(pro.dock, "Entry1"), "Ignore"))
local key = next(pro.settings, nil)
local savedIgnore = false
for k, v in pro.settings do
	if string.sub(k, 1, 7) == "ignore:" and next(v) then
		savedIgnore = true
	end
end
check("pro saves ignore list per place", savedIgnore, key)
click(find(pro.dock, "Export"))
local reports = pro.game:GetService("ServerStorage"):FindFirstChild("ZovoScanReports")
check("export wrote two report modules", reports and #reports:GetChildren() == 2)
if reports then
	local csv
	for _, m in reports:GetChildren() do
		if string.find(m.Name, "Csv", 1, true) then
			csv = m.Source
		end
	end
	check("csv report has header and rows", csv and string.find(csv, "path,class,severity,rule,store_rule,line,detail", 1, true)
		and string.find(csv, "FreeCarKit.Body.Loader,Script,high,hidden-code,yes,4", 1, true), csv)
	check("csv report leaves out the ignored finding", not string.find(csv, "FreeCarKit.Body.Loader,Script,critical,remote-require", 1, true))
	check("csv report has the obfuscator finding", string.find(csv, "FreeCarKit.Packed,Script,critical,obfuscator-signature,yes,1", 1, true))
	local fnc = luau.load(csv)
	check("exported module is valid Luau", fnc() == nil)
end

-- exported reports are left out of later scans
for _, c in pro.workspace:GetChildren() do
	if c.Name == "FreeCarKit" or c.Name == "DoorKit" then
		c.Parent = nil
	end
end
click(find(pro.dock, "ScanPlace"))
check("whole place scan skips exported reports", string.find(status(pro), "No risky code found. 0 scripts checked", 1, true), status(pro))

fs.writeFile(BUILD .. "/studio_sim_log.txt", table.concat(log, "\n") .. "\n")
print(string.format("studio_sim: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
