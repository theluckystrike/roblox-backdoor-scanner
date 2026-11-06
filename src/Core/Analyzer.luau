--!nonstrict
-- Static checks on one script source. Pure Luau, no Roblox APIs, so the same
-- code runs in Studio and in the Lune test runner.

local Lexer = if script then require(script.Parent.Lexer) else require("./Lexer")
local Rules = if script then require(script.Parent.Rules) else require("./Rules")

local Analyzer = {}

export type Finding = {
	rule: string,
	severity: string,
	store: boolean,
	line: number,
	detail: string,
	snippet: string,
}

local LONG_LINE = 2000
local LARGE_SCRIPT = 200000
local HIDDEN_GAP = 150
local ESCAPES_MIN = 12
local LONG_STRING = 2000

local function lineText(src: string, lexed, line: number): string
	local s = lexed.lineStarts[line]
	local e = lexed.lineStarts[line + 1]
	local text = string.sub(src, s, if e then e - 2 else #src)
	text = string.gsub(text, "^%s+", "")
	-- show code hidden behind long runs of spaces
	text = string.gsub(text, "[ \t][ \t]+", function(run)
		return if #run >= 20 then "  [" .. #run .. " spaces]  " else run
	end)
	if #text > 160 then
		text = string.sub(text, 1, 157) .. "..."
	end
	return text
end

local function lowerContainsName(value: string): string?
	local v = string.lower(value)
	for _, name in Rules.dangerousNames do
		if string.find(v, string.lower(name), 1, true) then
			return name
		end
	end
	return nil
end

-- Iterate positions of a pattern in `code`. Returns start, end, captures.
local function each(code: string, pattern: string)
	local init = 1
	return function()
		local res = { string.find(code, pattern, init) }
		if res[1] == nil then
			return nil
		end
		init = (res[2] :: number) + 1
		if init <= res[1] then
			init = res[1] + 1
		end
		return table.unpack(res)
	end
end

function Analyzer.analyze(src: string, opts: { maxFindings: number? }?): { Finding }
	local maxFindings = (opts and opts.maxFindings) or 200
	local lexed = Lexer.lex(src)
	local code = lexed.code
	local findings: { Finding } = {}
	local seen: { [string]: boolean } = {}
	local stringStarts = {}
	for _, lit in lexed.strings do
		stringStarts[lit.startPos] = lit
	end

	local function add(ruleId: string, pos: number, detail: string)
		if #findings >= maxFindings then
			return
		end
		local line = Lexer.lineOf(lexed, pos)
		local key = ruleId .. ":" .. line
		if seen[key] then
			return
		end
		seen[key] = true
		local rule = Rules.byId[ruleId]
		table.insert(findings, {
			rule = ruleId,
			severity = rule.severity,
			store = rule.store,
			line = line,
			detail = detail,
			snippet = lineText(src, lexed, line),
		})
	end

	-- 1. require by asset ID. Also through aliases such as `local r = require`.
	local requireNames = { "require" }
	for _, e, alias in each(code, "%f[%w_]([%a_][%w_]*)%s*=%s*require%f[^%w_]") do
		local nextChar = string.match(code, "^%s*(.)", e + 1)
		if alias ~= "require" and nextChar ~= "(" then
			table.insert(requireNames, alias)
		end
	end
	-- numbers of 6+ digits kept in names: `local id = 1234567`, `id: number = 1234567`, globals
	local idVars = {}
	for _, _, name, num in each(code, "%f[%w_]([%a_][%w_]*)%s*=%s*(%d%d%d%d%d%d+)%f[^%w_]") do
		idVars[name] = num
	end
	for _, _, name, num in each(code, "%f[%w_]([%a_][%w_]*)%s*:%s*[%a_][%w_%.]*%s*=%s*(%d%d%d%d%d%d+)%f[^%w_]") do
		idVars[name] = num
	end
	local hasBigNumber = string.find(code, "%f[%w_]%d%d%d%d%d%d+%f[^%w_]") ~= nil
	for _, rq in requireNames do
		local label = if rq == "require" then "require" else rq .. " (an alias of require)"
		for s, _, num in each(code, "%f[%w_]" .. rq .. "%s*%(%s*%(?%s*(%d[%w]*)") do
			add(if rq == "require" then "remote-require" else "remote-require-hidden", s, label .. "(" .. num .. ")")
		end
		-- require("123456") with a digit string
		for s, e in each(code, "%f[%w_]" .. rq .. "%s*%(%s*[\"'`]") do
			local lit = stringStarts[e]
			if lit and string.match(lit.value, "^%s*%d+%s*$") then
				add("remote-require-hidden", s, label .. "(\"" .. lit.value .. "\") is turned into an asset ID")
			end
		end
		for s in each(code, "%f[%w_]" .. rq .. "%s*%(%s*tonumber%f[^%w_]") do
			add("remote-require-hidden", s, label .. "(tonumber(...))")
		end
		-- require(id) where id holds a number, one pass over all calls
		for s, _, name in each(code, "%f[%w_]" .. rq .. "%s*%(%s*([%a_][%w_]*)%s*%)") do
			if idVars[name] then
				add("remote-require-hidden", s, label .. "(" .. name .. ") where " .. name .. " = " .. idVars[name])
			end
		end
		-- require(ids[1]) in a file that holds asset-sized numbers
		if hasBigNumber then
			for s, _, name in each(code, "%f[%w_]" .. rq .. "%s*%(%s*([%a_][%w_]*)%s*%[") do
				if name ~= "script" and name ~= "game" then
					add("remote-require-hidden", s, label .. "(" .. name .. "[...]) in a file with asset IDs")
				end
			end
		end
	end

	-- 2. loadstring, fenv, LoadAsset, LinkedSource
	for s in each(code, "%f[%w_]loadstring%f[^%w_]") do
		add("loadstring", s, "loadstring")
	end
	for s, _, fn in each(code, "%f[%w_]([gs]etfenv)%f[^%w_]") do
		add("fenv", s, fn)
	end
	for s, _, fn in each(code, "%f[%w_]([gs]et[rg]env)%f[^%w_]") do
		add("fenv", s, fn .. " (exploit API)")
	end
	for s, _, fn in each(code, "[:%.]%s*(LoadAsset%w*)%s*%(") do
		add("load-asset", s, fn)
	end
	for s in each(code, "[:%.]%s*GetObjects%s*%(") do
		add("load-asset", s, "GetObjects")
	end
	for s in each(code, "%f[%w_]LinkedSource%s*=[^=]") do
		add("linked-source", s, "LinkedSource is set")
	end

	-- 3. obfuscator markers in comments or code (never in strings)
	local commentsAndCode = lexed.comments .. "\n" .. code
	for _, marker in Rules.obfuscatorMarkers do
		if string.find(commentsAndCode, marker, 1, true) then
			local pos = string.find(src, marker, 1, true) or 1
			add("obfuscator-signature", pos, marker)
		end
	end

	-- 4. string literals: escapes, reversed names, joined names, long blobs, webhooks
	local strings = lexed.strings
	local hasReverse = string.find(code, "reverse", 1, true) ~= nil
	local chainUntil = 0
	for idx, lit in strings do
		-- escape blobs, but not plain UTF-8 text such as emoji written as \240\159...
		if lit.escapes >= ESCAPES_MIN and lit.escapes * 2 >= #lit.value and string.find(lit.value, "%a") then
			local name = lowerContainsName(lit.value)
			add("escape-obfuscation", lit.startPos,
				lit.escapes .. " escape codes" .. (if name then ", decodes to text with \"" .. name .. "\"" else ""))
		elseif lit.escapes > 0 then
			local name = lowerContainsName(lit.value)
			if name and not string.find(string.lower(lit.raw), string.lower(name), 1, true) then
				add("hidden-name", lit.startPos, "escaped string decodes to \"" .. name .. "\"")
			end
		end
		if hasReverse and #lit.value >= 4 then
			local rev = string.reverse(lit.value)
			for _, name in Rules.dangerousNames do
				if rev == name then
					add("hidden-name", lit.startPos, "\"" .. lit.value .. "\" reversed is \"" .. name .. "\"")
				end
			end
		end
		if #lit.value >= LONG_STRING and string.match(lit.value, "^[%w%+/=_%-%s\\]+$") then
			add("long-string", lit.startPos, #lit.value .. " characters of encoded data")
		end
		local low = string.lower(lit.value)
		if string.find(low, "discord%a*%.com/api/webhooks/%d+/") then
			add("webhook", lit.startPos, "Discord webhook URL")
		end
		-- joined pieces: "req" .. "uire". Each chain is read once (long chains stay linear).
		if idx < #strings and idx > chainUntil then
			local group = { lit.value }
			local j = idx
			while j < #strings do
				local between = string.sub(code, strings[j].endPos + 1, strings[j + 1].startPos - 1)
				if string.match(between, "^%s*%.%.%s*$") then
					table.insert(group, strings[j + 1].value)
					j += 1
				else
					break
				end
			end
			chainUntil = j
			if #group > 1 then
				local joined = table.concat(group)
				local name = lowerContainsName(joined)
				local inOne = false
				for _, piece in group do
					if name and string.find(string.lower(piece), string.lower(name), 1, true) then
						inOne = true
					end
				end
				if name and not inOne then
					add("hidden-name", lit.startPos, "pieces join to \"" .. joined .. "\"")
				end
			end
		end
	end

	-- 5. string.char with many numbers
	for s, _, args in each(code, "%f[%w_]string%.char%s*(%b())") do
		local nums = {}
		for num in string.gmatch(args, "%d+") do
			local v = tonumber(num)
			if v and v < 256 then
				table.insert(nums, string.char(v))
			end
		end
		if #nums >= 6 then
			local decoded = table.concat(nums)
			local name = lowerContainsName(decoded)
			if name then
				add("hidden-name", s, "string.char(...) decodes to \"" .. decoded .. "\"")
			else
				add("string-char", s, #nums .. " character codes")
			end
		end
	end

	-- 6. layout tricks: hidden code, long lines, size
	local lineNo = 0
	for line in string.gmatch(src .. "\n", "([^\n]*)\n") do
		lineNo += 1
		if #line >= LONG_LINE then
			add("long-line", lexed.lineStarts[lineNo], #line .. " characters on one line")
		end
		local gapStart = string.find(line, "%S[ \t]" .. string.rep("[ \t]", HIDDEN_GAP - 1) .. "[ \t]*%S")
		local leading = string.match(line, "^([ \t]*)%S")
		if gapStart or (leading and #leading >= HIDDEN_GAP * 2) then
			add("hidden-code", lexed.lineStarts[lineNo], "code after a long run of spaces")
		end
	end
	if #src >= LARGE_SCRIPT then
		add("large-script", 1, math.floor(#src / 1000) .. " KB")
	end

	-- 7. behaviour that is risky in a free model
	for s, _, fn in each(code, "[:%.]%s*(Prompt%w*Purchase)%s*%(") do
		add("purchase-prompt", s, fn)
	end
	for s, e in each(code, "[:%.]%s*Teleport%w*%s*%(") do
		local args = string.match(code, "^%s*(%b())", e) or string.sub(code, e, e + 40)
		if string.match(args, "%d%d%d%d%d%d") then
			add("teleport", s, "teleport to a fixed place ID")
		end
	end
	-- a local named `script` is not the running script
	local shadowed = string.find(code, "%f[%w_]local%s+function%s*[%w_]*%s*%(([^)]*)%f[%w_]script%f[^%w_]") ~= nil
	for _, e in each(code, "%f[%w_]local%s+script%f[^%w_]") do
		-- `local script = script` is still the running script
		if string.match(code, "^%s*=%s*([%w_]+)", e + 1) ~= "script" then
			shadowed = true
		end
	end
	for s in each(if shadowed then "" else code, "%f[%w_]script%.Parent%s*=%s*nil%f[^%w_]") do
		add("self-hide", s, "script.Parent = nil")
	end
	for s in each(if shadowed then "" else code, "%f[%w_]script%.Name%s*=[^=]") do
		add("self-hide", s, "script.Name is changed")
	end
	for s, _, id in each(code, "UserId%s*==%s*(%d%d%d%d%d+)") do
		add("hardcoded-user", s, "UserId == " .. id)
	end
	for s, _, id in each(code, "(%d%d%d%d%d+)%s*==%s*[%w_%.]*UserId") do
		add("hardcoded-user", s, id .. " == UserId")
	end
	-- HttpService calls. DataStore GetAsync is not HTTP, so the receiver must be HttpService.
	local httpVars = {}
	for _, _, name in each(src, "([%a_][%w_]*)%s*=%s*game%s*:%s*GetService%s*%(%s*[\"'`]HttpService[\"'`]%s*%)") do
		httpVars[name] = true
	end
	for s, _, recv, fn in each(code, "([%a_][%w_]*)%s*[:%.]%s*(%u%a+Async)%s*%(") do
		if (fn == "GetAsync" or fn == "PostAsync" or fn == "RequestAsync")
			and (httpVars[recv] or string.find(string.lower(recv), "http", 1, true)) then
			add("http", s, fn)
		end
	end
	for s, _, fn in each(src, "GetService%s*%(%s*[\"'`]HttpService[\"'`]%s*%)%s*:%s*(%u%a+Async)%s*%(") do
		add("http", s, fn)
	end

	table.sort(findings, function(a, b)
		local ra, rb = Rules.rank[a.severity], Rules.rank[b.severity]
		if ra ~= rb then
			return ra > rb
		end
		return a.line < b.line
	end)
	return findings
end

return Analyzer
