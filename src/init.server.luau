--!nonstrict
-- Backdoor & Virus Scanner by Zovo. Studio plugin entry point.
-- Reads script sources in the open place, never sends anything off the machine,
-- and only changes the place when you click Disable, Delete or Export.

if not plugin then
	return
end

local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local TreeScan = require(script.Core.TreeScan)
local Report = require(script.Core.Report)
local Widget = require(script.Ui.Widget)
local Edition = require(script.Edition)

local PLACE_SERVICES = {
	"Workspace", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage",
	"StarterGui", "StarterPack", "StarterPlayer", "Lighting", "SoundService", "Teams", "TextChatService",
}

local toolbar = plugin:CreateToolbar("Zovo")
local toggle = toolbar:CreateButton("Backdoor Scanner", "Find backdoors, viruses and Creator Store rule problems", Edition.icon)
toggle.ClickableWhenViewportHidden = true

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 400, 560, 300, 300)
local dock = plugin:CreateDockWidgetPluginGui("ZovoBackdoorScanner" .. (if Edition.pro then "Pro" else ""), info)
dock.Title = Edition.name
dock.Name = "ZovoBackdoorScanner"

toggle.Click:Connect(function()
	dock.Enabled = not dock.Enabled
end)
dock:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(dock.Enabled)
end)

local function palette()
	local ok, theme = pcall(function()
		return settings().Studio.Theme
	end)
	if not ok or not theme then
		return nil
	end
	local C = Enum.StudioStyleGuideColor
	return {
		background = theme:GetColor(C.MainBackground),
		text = theme:GetColor(C.MainText),
		dimText = theme:GetColor(C.DimmedText),
		button = theme:GetColor(C.Button),
		accent = theme:GetColor(C.DialogMainButton),
	}
end

local placeKey = "ignore:" .. tostring(game.PlaceId) .. ":" .. game.Name
local ignore = {}
if Edition.pro then
	ignore = plugin:GetSetting(placeKey) or {}
end
local lastMode = "selection"
local lastRoots = {}
local lastReport = nil
local ui

local function roots(mode)
	if mode == "place" then
		local list = {}
		for _, name in PLACE_SERVICES do
			local ok, svc = pcall(game.GetService, game, name)
			if ok and svc then
				table.insert(list, svc)
			end
		end
		return list
	end
	return Selection:Get()
end

-- our own exported reports contain snippets of bad code, so scans leave them out
local function skipOwn(node)
	return node.Name == "ZovoScanReports" and node.Parent == ServerStorage
end

local function run(mode, given)
	lastMode = mode
	local list = given or roots(mode)
	lastRoots = list
	if #list == 0 then
		ui.setStatus("Nothing is selected. Select a model or folder in the Explorer, or scan the whole place.")
		return
	end
	ui.setStatus("Scanning...")
	local report = TreeScan.scan(list, TreeScan.InstanceAdapter, {
		storeOnly = mode == "preflight",
		ignore = ignore,
		skip = skipOwn,
		yield = function()
			task.wait()
		end,
	})
	lastReport = report
	ui.render(report)
	return report
end

local function rescan()
	-- keep only roots that still exist in the place
	local alive = {}
	for _, r in lastRoots do
		if r.Parent ~= nil or r == game then
			table.insert(alive, r)
		end
	end
	if lastMode == "place" then
		run("place")
	elseif #alive > 0 then
		run(lastMode, alive)
	else
		-- the scanned object itself was removed
		lastReport = TreeScan.scan({}, TreeScan.InstanceAdapter, { storeOnly = lastMode == "preflight" })
		ui.render(lastReport)
	end
end

local function record(name, fn)
	local ok, id = pcall(function()
		return ChangeHistoryService:TryBeginRecording(name)
	end)
	local okFn, err = pcall(fn)
	if ok and id then
		ChangeHistoryService:FinishRecording(id, if okFn then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	else
		ChangeHistoryService:SetWaypoint(name)
	end
	if not okFn then
		ui.setStatus("That change failed. " .. tostring(err))
	end
	return okFn
end

local autoOn = Edition.pro and plugin:GetSetting("autoScan") == true
local autoConn

local actions = {}
function actions.scanSelection()
	run("selection")
end
function actions.scanPlace()
	run("place")
end
function actions.preflight()
	run("preflight")
end
function actions.open(entry, f)
	plugin:OpenScript(entry.node, if f.line > 0 then f.line else 1)
end
function actions.select(entry)
	Selection:Set({ entry.node })
end
function actions.disable(entry)
	if record("Disable script (Zovo Scanner)", function()
		entry.node.Enabled = false
	end) then
		ui.setStatus(entry.path .. " is disabled. Press Ctrl+Z to undo.")
	end
end
function actions.delete(entry)
	if not record("Delete script (Zovo Scanner)", function()
		entry.node.Parent = nil
	end) then
		return
	end
	rescan()
	ui.setStatus("Deleted " .. entry.path .. ". Press Ctrl+Z to undo. " .. (if lastReport then Report.summary(lastReport) else ""))
end
function actions.ignore(entry, f)
	ignore[entry.path .. "|" .. f.rule] = true
	if Edition.pro then
		plugin:SetSetting(placeKey, ignore)
	end
	rescan()
end
function actions.export()
	if not Edition.pro or not lastReport then
		ui.setStatus("Run a scan first.")
		return
	end
	local ok = record("Export scan report (Zovo Scanner)", function()
		local folder = ServerStorage:FindFirstChild("ZovoScanReports") or Instance.new("Folder")
		folder.Name = "ZovoScanReports"
		folder.Parent = ServerStorage
		local stamp = os.date("!%Y-%m-%d %H%M")
		for kind, body in { Text = Report.toText(lastReport), Csv = Report.toCsv(lastReport) } do
			local m = Instance.new("ModuleScript")
			m.Name = "Report " .. stamp .. " " .. kind
			m.Source = "--[==[\n" .. string.gsub(body, "%]==%]", "] ==]") .. "\n]==]\nreturn nil\n"
			m.Parent = folder
		end
		Selection:Set({ folder })
	end)
	if ok then
		ui.setStatus("The report is in ServerStorage.ZovoScanReports. Open it and copy the text.")
	end
end
local function setAuto(on)
	autoOn = on
	plugin:SetSetting("autoScan", on)
	if autoConn then
		autoConn:Disconnect()
		autoConn = nil
	end
	if on then
		autoConn = workspace.ChildAdded:Connect(function(child)
			-- only while editing, not in playtest servers and clients
			if not RunService:IsEdit() then
				return
			end
			task.wait(0.5) -- let the insert finish
			if child.Parent == nil then
				return
			end
			local report = TreeScan.scan({ child }, TreeScan.InstanceAdapter, {
				ignore = ignore,
				yield = function()
					task.wait()
				end,
			})
			if report.verdict == "unsafe" or report.verdict == "suspicious" then
				lastMode, lastRoots, lastReport = "selection", { child }, report
				dock.Enabled = true
				ui.render(report)
				ui.setStatus("You just inserted " .. child.Name .. ". " .. Report.summary(report))
			end
		end)
	end
	ui.setAuto(on)
end
function actions.toggleAuto()
	setAuto(not autoOn)
end

ui = Widget.mount(dock, {
	Instance = Instance,
	UDim2 = UDim2,
	UDim = UDim,
	Color3 = Color3,
	Enum = Enum,
	connect = function(b, fn)
		b.Activated:Connect(fn)
	end,
}, actions, Edition, palette())

if Edition.pro and autoOn then
	setAuto(true)
end

plugin.Unloading:Connect(function()
	if autoConn then
		autoConn:Disconnect()
	end
end)
