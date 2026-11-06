-- False-positive check: scans every .lua/.luau file under a folder and counts findings by rule.
-- Run: lune run scripts/corpus.luau <folder>
local fs = require("@lune/fs")
local process = require("@lune/process")
local Analyzer = require("../src/Core/Analyzer")
local root = process.args[1]
local files, byRule, examples = 0, {}, {}
local function walk(dir)
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			if name ~= "node_modules" and name ~= ".git" then
				walk(p)
			end
		elseif string.match(name, "%.luau?$") then
			files += 1
			for _, f in Analyzer.analyze(fs.readFile(p)) do
				byRule[f.rule] = (byRule[f.rule] or 0) + 1
				examples[f.rule] = examples[f.rule] or {}
				if #examples[f.rule] < 3 then
					table.insert(examples[f.rule], string.sub(p, #root + 2) .. ":" .. f.line .. "  " .. f.detail)
				end
			end
		end
	end
end
walk(root)
print("files scanned", files)
for rule, n in byRule do
	print(string.format("%-22s %4d   %s", rule, n, table.concat(examples[rule], " | ")))
end
