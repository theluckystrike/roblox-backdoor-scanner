--!strict
-- Small Luau lexer. It does not build tokens. It returns:
--   code     the source with comments and string contents replaced by spaces
--            (quotes and newlines stay, so positions and line numbers match the source)
--   strings  every string literal with its decoded value and position
-- The scanner matches calls on `code`, so text inside strings and comments
-- is never mistaken for a call.

local Lexer = {}

export type StringLit = {
	raw: string,
	value: string,
	startPos: number,
	endPos: number,
	escapes: number,
}

export type Lexed = {
	code: string,
	strings: { StringLit },
	comments: string,
	lineStarts: { number },
}

local function blank(s: string): string
	-- keep newlines so line numbers stay correct
	return (string.gsub(s, "[^\n]", " "))
end

-- Decode Luau escapes in a short string body. Unknown escapes keep the char.
local function decode(body: string): (string, number)
	local out = table.create(#body)
	local escapes = 0
	local i = 1
	local n = #body
	while i <= n do
		local c = string.sub(body, i, i)
		if c ~= "\\" then
			table.insert(out, c)
			i += 1
		else
			local d = string.sub(body, i + 1, i + 1)
			escapes += 1
			if d == "n" then
				table.insert(out, "\n"); i += 2
			elseif d == "t" then
				table.insert(out, "\t"); i += 2
			elseif d == "r" then
				table.insert(out, "\r"); i += 2
			elseif d == "a" or d == "b" or d == "f" or d == "v" then
				table.insert(out, " "); i += 2
			elseif d == "x" then
				local hex = string.match(body, "^%x%x", i + 2)
				if hex then
					table.insert(out, string.char(tonumber(hex, 16) :: number)); i += 4
				else
					table.insert(out, "x"); i += 2
				end
			elseif string.match(d, "%d") then
				local digits = string.match(body, "^%d%d?%d?", i + 1) :: string
				local v = tonumber(digits) :: number
				if v <= 255 then
					table.insert(out, string.char(v))
				end
				i += 1 + #digits
			elseif d == "u" then
				local hex = string.match(body, "^{(%x+)}", i + 2)
				if hex then
					local cp = tonumber(hex, 16) :: number
					table.insert(out, if cp < 128 then string.char(cp) else "?")
					i += 4 + #hex
				else
					table.insert(out, "u"); i += 2
				end
			elseif d == "z" then
				i += 2
				while i <= n and string.match(string.sub(body, i, i), "%s") do
					i += 1
				end
			else
				table.insert(out, d); i += 2
			end
		end
	end
	return table.concat(out), escapes
end
Lexer.decode = decode

-- Returns the level of a long bracket opening at position i ("[[", "[=[", ...) or nil.
local function longBracketLevel(src: string, i: number): number?
	local eqs = string.match(src, "^%[(=*)%[", i)
	if eqs then
		return #eqs
	end
	return nil
end

function Lexer.lex(src: string): Lexed
	local parts = {}
	local strings: { StringLit } = {}
	local comments = {}
	local n = #src
	local i = 1
	local flushFrom = 1
	local interp: { number } = {} -- brace depth inside each open `{` of an interpolated string

	local function flushTo(pos: number)
		if pos >= flushFrom then
			table.insert(parts, string.sub(src, flushFrom, pos))
		end
	end

	while i <= n do
		local c = string.sub(src, i, i)
		if c == "-" and string.sub(src, i + 1, i + 1) == "-" then
			flushTo(i - 1)
			local level = longBracketLevel(src, i + 2)
			local stop: number
			if level then
				local close = "]" .. string.rep("=", level) .. "]"
				local s, e = string.find(src, close, i + 4 + level, true)
				stop = if e then e else n
				local _ = s
			else
				local nl = string.find(src, "\n", i, true)
				stop = if nl then nl - 1 else n
			end
			table.insert(comments, string.sub(src, i, stop))
			table.insert(parts, blank(string.sub(src, i, stop)))
			i = stop + 1
			flushFrom = i
		elseif c == "\"" or c == "'" then
			flushTo(i - 1)
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					-- a backslash before CRLF continues the string over both chars
					j += if string.sub(src, j + 1, j + 2) == "\r\n" then 3 else 2
				elseif d == c then
					break
				elseif d == "\n" then
					break -- unfinished string, stop at line end
				else
					j += 1
				end
			end
			if j > n then
				j = n
			end
			local body = string.sub(src, i + 1, j - 1)
			local value, escapes = decode(body)
			table.insert(strings, { raw = body, value = value, startPos = i, endPos = j, escapes = escapes })
			table.insert(parts, c .. blank(body) .. (if j > i then string.sub(src, j, j) else ""))
			i = j + 1
			flushFrom = i
		elseif c == "`" or (c == "}" and #interp > 0 and interp[#interp] == 0) then
			-- interpolated string segment. `{` returns to code until the matching `}`.
			if c == "}" then
				table.remove(interp)
			end
			flushTo(i - 1)
			local j = i + 1
			local term = nil
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == "`" or d == "{" or d == "\n" then
					term = d
					break
				else
					j += 1
				end
			end
			local bodyEnd = math.min(j - 1, n)
			local body = string.sub(src, i + 1, bodyEnd)
			local value, escapes = decode(body)
			table.insert(strings, { raw = body, value = value, startPos = i, endPos = math.min(j, n), escapes = escapes })
			table.insert(parts, c .. blank(body))
			if term == "`" or term == "{" then
				table.insert(parts, term)
				if term == "{" then
					table.insert(interp, 0)
				end
				i = j + 1
			else
				i = bodyEnd + 1 -- newline or end of file stays code
			end
			flushFrom = i
		elseif (c == "{" or c == "}") and #interp > 0 then
			interp[#interp] += if c == "{" then 1 else -1
			i += 1
		elseif c == "[" and longBracketLevel(src, i) then
			local level = longBracketLevel(src, i) :: number
			flushTo(i - 1)
			local close = "]" .. string.rep("=", level) .. "]"
			local openLen = level + 2
			local _, e = string.find(src, close, i + openLen, true)
			local stop = if e then e else n
			local bodyStart = i + openLen
			local bodyEnd = stop - openLen
			local body = string.sub(src, bodyStart, bodyEnd)
			table.insert(strings, { raw = body, value = body, startPos = i, endPos = stop, escapes = 0 })
			table.insert(parts, string.rep(" ", openLen) .. blank(body) .. string.rep(" ", stop - bodyEnd))
			i = stop + 1
			flushFrom = i
		else
			i += 1
		end
	end
	flushTo(n)

	local code = table.concat(parts)
	local lineStarts = { 1 }
	local pos = 1
	while true do
		local nl = string.find(src, "\n", pos, true)
		if not nl then
			break
		end
		table.insert(lineStarts, nl + 1)
		pos = nl + 1
	end
	return { code = code, strings = strings, comments = table.concat(comments, "\n"), lineStarts = lineStarts }
end

-- Line number (1-based) of a byte position, by binary search.
function Lexer.lineOf(lexed: Lexed, pos: number): number
	local starts = lexed.lineStarts
	local lo, hi = 1, #starts
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if starts[mid] <= pos then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

return Lexer
