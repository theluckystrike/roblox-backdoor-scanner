--!nonstrict
-- Walks an instance tree and runs the Analyzer on every script.
-- Works on real Instances (Studio, or Lune's @lune/roblox) through `InstanceAdapter`,
-- and on plain tables in unit tests through `TableAdapter`.

local Analyzer = if script then require(script.Parent.Analyzer) else require("./Analyzer")
local Rules = if script then require(script.Parent.Rules) else require("./Rules")

local TreeScan = {}

export type Adapter = {
	children: (node: any) -> { any },
	name: (node: any) -> string,
	className: (node: any) -> string,
	isScript: (node: any) -> boolean,
	source: (node: any) -> string?,
	linkedSource: (node: any) -> string?,
}

local SCRIPT_CLASSES = { Script = true, LocalScript = true, ModuleScript = true }

TreeScan.InstanceAdapter = {
	children = function(node)
		local ok, kids = pcall(function()
			return node:GetChildren()
		end)
		return if ok then kids else {}
	end,
	name = function(node)
		return node.Name
	end,
	className = function(node)
		return node.ClassName
	end,
	isScript = function(node)
		return SCRIPT_CLASSES[node.ClassName] == true
	end,
	source = function(node)
		local ok, src = pcall(function()
			return node.Source
		end)
		return if ok and type(src) == "string" then src else nil
	end,
	linkedSource = function(node)
		local ok, v = pcall(function()
			return node.LinkedSource
		end)
		if not ok or v == nil then
			return nil
		end
		local s = tostring(v)
		if s == "" or s == "rbxasset://" or s == "nil" then
			return nil
		end
		return s
	end,
} :: Adapter

TreeScan.TableAdapter = {
	children = function(node)
		return node.children or {}
	end,
	name = function(node)
		return node.Name
	end,
	className = function(node)
		return node.ClassName
	end,
	isScript = function(node)
		return SCRIPT_CLASSES[node.ClassName] == true
	end,
	source = function(node)
		return node.Source
	end,
	linkedSource = function(node)
		return node.LinkedSource
	end,
} :: Adapter

export type ScriptResult = {
	node: any,
	path: string,
	className: string,
	findings: { any },
}

export type Report = {
	results: { ScriptResult },
	scripts: number,
	nodes: number,
	counts: { [string]: number },
	storeIssues: number,
	verdict: string,
	truncated: boolean,
}

local function hash(s: string): string
	-- cheap content key for duplicate detection (length + sampled bytes)
	local n = #s
	local acc = n
	local step = math.max(1, n // 64)
	for i = 1, n, step do
		acc = (acc * 31 + string.byte(s, i)) % 2147483647
	end
	return n .. ":" .. acc
end

local function makeFinding(ruleId: string, detail: string)
	local r = Rules.byId[ruleId]
	return { rule = ruleId, severity = r.severity, store = r.store, line = 0, detail = detail, snippet = "" }
end

-- opts.storeOnly  keep only Creator Store policy findings
-- opts.ignore     set of "path|rule" keys to drop
-- opts.yield      function called every 200 nodes (Studio passes task.wait)
-- opts.maxNodes   stop after this many nodes (default 500000)
-- opts.skip       function(node) -> true to leave a node and its children out
function TreeScan.scan(roots: { any }, adapter: Adapter?, opts: any?): Report
	local ad: Adapter = adapter or TreeScan.InstanceAdapter
	opts = opts or {}
	local ignore = opts.ignore or {}
	local maxNodes = opts.maxNodes or 500000
	local results: { ScriptResult } = {}
	local byHash: { [string]: { ScriptResult } } = {}
	local nodes, scripts = 0, 0
	local truncated = false

	local function visit(node, parentPath: string, parentClass: string?)
		if opts.skip and opts.skip(node) then
			return
		end
		if nodes >= maxNodes then
			truncated = true
			return
		end
		nodes += 1
		if opts.yield and nodes % 200 == 0 then
			opts.yield()
		end
		local name = ad.name(node)
		local path = if parentPath == "" then name else parentPath .. "." .. name
		local cls = ad.className(node)
		if ad.isScript(node) then
			scripts += 1
			local findings = {}
			local src = ad.source(node) or ""
			for _, f in Analyzer.analyze(src) do
				table.insert(findings, f)
			end
			local linked = ad.linkedSource(node)
			if linked then
				table.insert(findings, makeFinding("linked-source", "LinkedSource = " .. linked))
			end
			local low = string.lower(name)
			for _, v in Rules.virusNames do
				if string.find(low, v, 1, true) then
					table.insert(findings, makeFinding("virus-name", "named \"" .. name .. "\""))
					break
				end
			end
			if parentClass and Rules.oddParents[parentClass] then
				table.insert(findings, makeFinding("odd-parent", cls .. " inside a " .. parentClass))
			end
			local entry = { node = node, path = path, className = cls, findings = findings }
			table.insert(results, entry)
			if #src >= 40 then
				local h = hash(src)
				byHash[h] = byHash[h] or {}
				table.insert(byHash[h], entry)
			end
		end
		for _, child in ad.children(node) do
			visit(child, path, cls)
		end
	end

	for _, root in roots do
		visit(root, "", nil)
	end

	-- duplicates: 5 or more identical scripts that also have another finding
	for _, group in byHash do
		if #group >= 5 then
			local risky = false
			for _, f in group[1].findings do
				if Rules.rank[f.severity] >= 2 then
					risky = true
				end
			end
			if risky then
				for _, entry in group do
					table.insert(entry.findings, makeFinding("duplicate-script", #group .. " identical copies"))
				end
			end
		end
	end

	-- filter, count, verdict
	local counts = { critical = 0, high = 0, medium = 0, low = 0 }
	local storeIssues = 0
	local kept: { ScriptResult } = {}
	for _, entry in results do
		local fs = {}
		for _, f in entry.findings do
			local keep = (not opts.storeOnly or f.store) and not ignore[entry.path .. "|" .. f.rule]
			if keep then
				table.insert(fs, f)
				counts[f.severity] += 1
				if f.store then
					storeIssues += 1
				end
			end
		end
		if #fs > 0 then
			table.sort(fs, function(a, b)
				local ra, rb = Rules.rank[a.severity], Rules.rank[b.severity]
				if ra ~= rb then
					return ra > rb
				end
				return a.line < b.line
			end)
			entry.findings = fs
			table.insert(kept, entry)
		end
	end
	table.sort(kept, function(a, b)
		local ra, rb = Rules.rank[a.findings[1].severity], Rules.rank[b.findings[1].severity]
		if ra ~= rb then
			return ra > rb
		end
		return a.path < b.path
	end)

	local verdict
	if opts.storeOnly then
		verdict = if storeIssues == 0 then "ready" else "blocked"
	elseif counts.critical > 0 then
		verdict = "unsafe"
	elseif counts.high > 0 then
		verdict = "suspicious"
	elseif counts.medium > 0 then
		verdict = "review"
	else
		verdict = "clean"
	end

	return {
		results = kept,
		scripts = scripts,
		nodes = nodes,
		counts = counts,
		storeIssues = storeIssues,
		verdict = verdict,
		truncated = truncated,
	}
end

return TreeScan
