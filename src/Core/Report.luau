--!nonstrict
-- Text forms of a scan report: a summary line, plain text and CSV.

local Rules = if script then require(script.Parent.Rules) else require("./Rules")

local Report = {}

local VERDICT_TEXT = {
	clean = "No risky code found",
	review = "Nothing dangerous, some code to review",
	suspicious = "Suspicious code found",
	unsafe = "Dangerous code found",
	ready = "Ready for the Creator Store",
	blocked = "Not ready for the Creator Store",
}
Report.VERDICT_TEXT = VERDICT_TEXT

function Report.summary(report): string
	local c = report.counts
	local base = string.format("%s. %d scripts checked, %d critical, %d high, %d medium, %d low.",
		VERDICT_TEXT[report.verdict], report.scripts, c.critical, c.high, c.medium, c.low)
	if report.verdict == "blocked" then
		base ..= string.format(" %d issues break the Creator Store asset rules.", report.storeIssues)
	end
	if report.truncated then
		base ..= " The scan stopped early because the place is very large."
	end
	return base
end

function Report.toText(report): string
	local out = { Report.summary(report), "" }
	for _, entry in report.results do
		table.insert(out, entry.path .. " (" .. entry.className .. ")")
		for _, f in entry.findings do
			local rule = Rules.byId[f.rule]
			local where = if f.line > 0 then "line " .. f.line .. ", " else ""
			table.insert(out, string.format("  [%s] %s. %s%s", string.upper(f.severity), rule.title, where, f.detail))
		end
	end
	return table.concat(out, "\n")
end

local function csvCell(s: string): string
	s = tostring(s)
	-- formula injection guard for spreadsheet apps
	if string.match(s, "^[=+%-@]") then
		s = "'" .. s
	end
	if string.find(s, "[,\"\n]") then
		s = "\"" .. string.gsub(s, "\"", "\"\"") .. "\""
	end
	return s
end

function Report.toCsv(report): string
	local out = { "path,class,severity,rule,store_rule,line,detail" }
	for _, entry in report.results do
		for _, f in entry.findings do
			table.insert(out, table.concat({
				csvCell(entry.path), csvCell(entry.className), f.severity, f.rule,
				if f.store then "yes" else "no", tostring(f.line), csvCell(f.detail),
			}, ","))
		end
	end
	return table.concat(out, "\n")
end

return Report
