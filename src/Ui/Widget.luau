--!nonstrict
-- Builds the scanner panel. All Roblox types come in through `rt`, so the same
-- module can be built in Studio and in Lune (@lune/roblox) for tests.
--
-- rt = { Instance, UDim2, UDim, Color3, Enum, connect = function(button, fn) }
-- actions = { scanSelection, scanPlace, preflight, open(entry, f), select(entry),
--             disable(entry), delete(entry), ignore(entry, f), export(), toggleAuto() }

local Rules = if script then require(script.Parent.Parent.Core.Rules) else require("../Core/Rules")
local Report = if script then require(script.Parent.Parent.Core.Report) else require("../Core/Report")

local Widget = {}

local MAX_ROWS = 300

local SEVERITY_COLOR = {
	critical = { 214, 48, 49 },
	high = { 225, 112, 35 },
	medium = { 205, 160, 20 },
	low = { 110, 130, 150 },
}

function Widget.mount(container, rt, actions, edition, palette)
	local I, U2, U, C3, E = rt.Instance, rt.UDim2, rt.UDim, rt.Color3, rt.Enum
	palette = palette or {}
	local bg = palette.background or C3.fromRGB(46, 46, 46)
	local fg = palette.text or C3.fromRGB(230, 230, 230)
	local dim = palette.dimText or C3.fromRGB(160, 160, 160)
	local btnBg = palette.button or C3.fromRGB(70, 70, 70)
	local accent = palette.accent or C3.fromRGB(0, 120, 215)
	local rgb = function(t)
		return C3.fromRGB(t[1], t[2], t[3])
	end

	local function label(parent, name, text, size, color, bold)
		local l = I.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextColor3 = color or fg
		l.TextSize = size or 14
		l.Font = if bold then E.Font.SourceSansBold else E.Font.SourceSans
		l.TextXAlignment = E.TextXAlignment.Left
		l.TextWrapped = true
		l.AutomaticSize = E.AutomaticSize.Y
		l.Size = U2.new(1, 0, 0, 0)
		l.Parent = parent
		return l
	end
	local function button(parent, name, text, onClick, primary)
		local b = I.new("TextButton")
		b.Name = name
		b.Text = text
		b.TextSize = 14
		b.Font = E.Font.SourceSans
		b.TextColor3 = if primary then C3.fromRGB(255, 255, 255) else fg
		b.BackgroundColor3 = if primary then accent else btnBg
		b.BorderSizePixel = 0
		b.AutomaticSize = E.AutomaticSize.X
		b.Size = U2.new(0, 0, 0, 24)
		local pad = I.new("UIPadding")
		pad.PaddingLeft = U.new(0, 8)
		pad.PaddingRight = U.new(0, 8)
		pad.Parent = b
		b.LayoutOrder = #parent:GetChildren()
		b.Parent = parent
		rt.connect(b, onClick)
		return b
	end
	local function row(parent, name, order)
		local f = I.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Size = U2.new(1, 0, 0, 0)
		f.AutomaticSize = E.AutomaticSize.Y
		f.LayoutOrder = order or 0
		local l = I.new("UIListLayout")
		l.FillDirection = E.FillDirection.Horizontal
		l.Padding = U.new(0, 6)
		l.Wraps = true
		l.SortOrder = E.SortOrder.LayoutOrder
		l.Parent = f
		f.Parent = parent
		return f
	end
	local function column(parent, name, order)
		local f = I.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Size = U2.new(1, 0, 0, 0)
		f.AutomaticSize = E.AutomaticSize.Y
		f.LayoutOrder = order or 0
		local l = I.new("UIListLayout")
		l.Padding = U.new(0, 4)
		l.SortOrder = E.SortOrder.LayoutOrder
		l.Parent = f
		f.Parent = parent
		return f
	end

	local root = I.new("ScrollingFrame")
	root.Name = "ScannerRoot"
	root.Size = U2.new(1, 0, 1, 0)
	root.BackgroundColor3 = bg
	root.BorderSizePixel = 0
	root.ScrollBarThickness = 8
	root.CanvasSize = U2.new(0, 0, 0, 0)
	root.AutomaticCanvasSize = E.AutomaticSize.Y
	local pad = I.new("UIPadding")
	pad.PaddingLeft = U.new(0, 8)
	pad.PaddingRight = U.new(0, 12)
	pad.PaddingTop = U.new(0, 8)
	pad.PaddingBottom = U.new(0, 8)
	pad.Parent = root
	local layout = I.new("UIListLayout")
	layout.Padding = U.new(0, 8)
	layout.SortOrder = E.SortOrder.LayoutOrder
	layout.Parent = root
	root.Parent = container

	local top = row(root, "Actions", 1)
	button(top, "ScanSelection", "Scan selection", actions.scanSelection, true)
	button(top, "ScanPlace", "Scan whole place", actions.scanPlace)
	button(top, "Preflight", "Creator Store check", actions.preflight)

	local status = label(root, "Status", "Select a model and click Scan selection, or scan the whole place.", 14, dim)
	status.LayoutOrder = 2

	local list = column(root, "Results", 3)

	local footer = column(root, "Footer", 4)
	local function renderFooter(autoOn)
		for _, c in footer:GetChildren() do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		if edition.pro then
			local pr = row(footer, "ProTools", 1)
			button(pr, "Export", "Export report", actions.export)
			button(pr, "AutoScan", if autoOn then "Auto-scan on insert is on" else "Auto-scan on insert is off", actions.toggleAuto)
		else
			local up = label(footer, "ProNote",
				"Pro adds auto-scan when you insert a model, report export to CSV and ignore lists saved per place. " ..
				"Scanning stays free. Pro is " .. edition.proPrice .. " one time on the Creator Store.", 13, dim)
			up.LayoutOrder = 1
			local box = I.new("TextBox")
			box.Name = "ProLink"
			box.Text = edition.proUrl
			box.TextEditable = false
			box.ClearTextOnFocus = false
			box.TextSize = 13
			box.Font = E.Font.Code
			box.TextColor3 = fg
			box.BackgroundColor3 = btnBg
			box.BorderSizePixel = 0
			box.TextXAlignment = E.TextXAlignment.Left
			box.Size = U2.new(1, 0, 0, 22)
			box.LayoutOrder = 2
			box.Parent = footer
		end
		local about = label(footer, "About", edition.name .. " " .. edition.version .. " by Zovo. MIT license.", 12, dim)
		about.LayoutOrder = 3
	end
	renderFooter(false)

	local api = {}
	api.root = root

	function api.setStatus(text: string)
		status.Text = text
	end

	function api.setAuto(on: boolean)
		renderFooter(on)
	end

	function api.render(report)
		for _, c in list:GetChildren() do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		status.Text = Report.summary(report)
		status.TextColor3 = if report.verdict == "clean" or report.verdict == "ready" then fg
			else rgb(SEVERITY_COLOR[if report.counts.critical > 0 then "critical" elseif report.counts.high > 0 then "high" else "medium"])
		local shown = 0
		for i, entry in report.results do
			if shown >= MAX_ROWS then
				local more = label(list, "More", "More results are not shown. Fix the ones above and scan again.", 13, dim)
				more.LayoutOrder = i
				break
			end
			local card = column(list, "Entry" .. i, i)
			local head = label(card, "Path", entry.path .. "  (" .. entry.className .. ")", 14, fg, true)
			head.LayoutOrder = 0
			local acts = row(card, "EntryActions", 1)
			button(acts, "Select", "Select", function()
				actions.select(entry)
			end)
			if entry.className ~= "ModuleScript" then
				button(acts, "Disable", "Disable", function()
					actions.disable(entry)
				end)
			end
			button(acts, "Delete", "Delete", function()
				actions.delete(entry)
			end)
			for j, f in entry.findings do
				shown += 1
				local rule = Rules.byId[f.rule]
				local fr = column(card, "Finding" .. j, 1 + j)
				local tag = label(fr, "Title", string.upper(f.severity) .. "  " .. rule.title ..
					(if f.store then "  (Creator Store rule)" else ""), 14, rgb(SEVERITY_COLOR[f.severity]), true)
				tag.LayoutOrder = 0
				local where = if f.line > 0 then "Line " .. f.line .. ". " else ""
				local det = label(fr, "Detail", where .. f.detail .. (if f.snippet ~= "" then "\n" .. f.snippet else ""), 13, fg)
				det.LayoutOrder = 1
				det.Font = E.Font.Code
				local why = label(fr, "Why", rule.why .. " " .. rule.fix, 13, dim)
				why.LayoutOrder = 2
				local fa = row(fr, "FindingActions", 3)
				button(fa, "Open", if f.line > 0 then "Open at line " .. f.line else "Open", function()
					actions.open(entry, f)
				end)
				button(fa, "Ignore", "Ignore", function()
					actions.ignore(entry, f)
				end)
			end
		end
		if #report.results == 0 then
			local ok = label(list, "Empty", if report.verdict == "ready"
				then "No Creator Store rule problems in the selection."
				else "No risky code found in " .. report.scripts .. " scripts.", 14, fg)
			ok.LayoutOrder = 1
		end
	end

	return api
end

return Widget
