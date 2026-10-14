--[[
	StackWatch - Report.lua
	After a boss encounter, the raid leader gets a short private summary of
	who took the most avoidable damage and from which spells. It is printed
	in the leader's own chat window only; nothing is sent to anyone.

	Data comes from Blizzard's damage meter (C_DamageMeter). Its getters are
	SecretWhenInCombat, so the report is built only after combat and every
	addon restriction has ended. The damage meter does not record debuff
	applications, so this shows where people are getting hit, not stack
	counts. Every value is checked with issecretvalue before it is used, and
	every API call is wrapped in pcall: nothing here may ever raise an error.

	Requires Blizzard's damage meter to be enabled (Options > Advanced >
	Enable Damage Meter, CVar damageMeterEnabled).
]]

local _, ns = ...

local TOP_PLAYERS = 5
local TOP_SPELLS = 3
local SPELLS_PER_PLAYER = 2

local pending          -- encounter waiting for its report
local knownSessions    -- session IDs that existed when the encounter started
ns.lastReport = nil    -- lines of the most recent report, for /sw report

local function Secret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- Plain number or nil. Secret or missing values come back as nil.
local function Num(v)
	if v == nil or Secret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

local function Str(v)
	if v == nil or Secret(v) or type(v) ~= "string" or v == "" then
		return nil
	end
	return v
end

local function Short(n)
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.0fK", n / 1e3)
	end
	return tostring(math.floor(n + 0.5))
end

local function SpellName(spellID)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	return Str(name) or ("spell " .. spellID)
end

local function Call(fn, ...)
	if not fn then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if ok then
		return result
	end
	return nil
end

local function DamageMeterReady()
	local DM = C_DamageMeter
	if not (DM and DM.GetCombatSessionFromID and Enum and Enum.DamageMeterType and Enum.DamageMeterType.AvoidableDamageTaken) then
		return false, "this client has no damage meter API."
	end
	if C_CVar and C_CVar.GetCVarBool and not C_CVar.GetCVarBool("damageMeterEnabled") then
		return false, "turn on Blizzard's damage meter (Options > Advanced > Enable Damage Meter) to get raid lead reports."
	end
	return true
end

local function SessionIDs()
	local ids = {}
	local list = Call(C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions)
	if type(list) ~= "table" then
		return ids
	end
	for _, s in ipairs(list) do
		local id, duration = Num(s.sessionID), Num(s.durationSeconds)
		if id then
			ids[id] = duration or -1
		end
	end
	return ids
end

-- The session for the encounter: among sessions that appeared after
-- ENCOUNTER_START, the one whose length is closest to the fight. Falls back
-- to the newest session.
local function FindSession(fightSeconds)
	local best, bestScore, newest
	for id, duration in pairs(SessionIDs()) do
		if not (knownSessions and knownSessions[id]) then
			if not newest or id > newest then
				newest = id
			end
			if duration >= 0 and fightSeconds then
				local score = math.abs(duration - fightSeconds)
				if not bestScore or score < bestScore then
					best, bestScore = id, score
				end
			end
		end
	end
	return best or newest
end

local function BuildReport(info)
	local ready, why = DamageMeterReady()
	if not ready then
		return { why }
	end
	local DM = C_DamageMeter
	local meterType = Enum.DamageMeterType.AvoidableDamageTaken

	local sessionID = FindSession(info.seconds)
	local session
	if sessionID then
		session = Call(DM.GetCombatSessionFromID, sessionID, meterType)
	elseif Enum.DamageMeterSessionType then
		session = Call(DM.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, meterType)
	end
	if Secret(session) or type(session) ~= "table" or type(session.combatSources) ~= "table" or Secret(session.combatSources) then
		return { "no damage meter data for " .. info.name .. "." }
	end

	local players = {}
	local spells = {}
	for _, src in ipairs(session.combatSources) do
		local total = Num(src.totalAmount)
		local guid = src.sourceGUID
		local isPlayer = not Secret(guid) and type(guid) == "string" and guid:find("^Player%-") ~= nil
		if total and total > 0 and isPlayer then
			local p = { name = Str(src.name) or "?", total = total, spells = {} }
			local detail
			if sessionID then
				detail = Call(DM.GetCombatSessionSourceFromID, sessionID, meterType, guid, nil)
			else
				detail = Call(DM.GetCombatSessionSourceFromType, Enum.DamageMeterSessionType.Current, meterType, guid, nil)
			end
			if type(detail) == "table" and type(detail.combatSpells) == "table" and not Secret(detail.combatSpells) then
				for _, sp in ipairs(detail.combatSpells) do
					local id, amount = Num(sp.spellID), Num(sp.totalAmount)
					if id and amount and amount > 0 then
						p.spells[#p.spells + 1] = { id = id, amount = amount }
						local agg = spells[id]
						if not agg then
							agg = { id = id, amount = 0, hit = 0 }
							spells[id] = agg
						end
						agg.amount = agg.amount + amount
						agg.hit = agg.hit + 1
					end
				end
				table.sort(p.spells, function(a, b) return a.amount > b.amount end)
			end
			players[#players + 1] = p
		end
	end

	local result = info.success and "kill" or "wipe"
	local length = info.seconds and string.format(", %d:%02d", math.floor(info.seconds / 60), math.floor(info.seconds % 60)) or ""
	local lines = { info.name .. " (" .. result .. length .. "): avoidable damage taken" }
	if #players == 0 then
		lines[#lines + 1] = "  nobody took avoidable damage."
		return lines
	end

	local spellList = {}
	for _, s in pairs(spells) do
		spellList[#spellList + 1] = s
	end
	table.sort(spellList, function(a, b) return a.amount > b.amount end)
	lines[#lines + 1] = "  Top sources:"
	for i = 1, math.min(TOP_SPELLS, #spellList) do
		local s = spellList[i]
		lines[#lines + 1] = string.format("    %s  %s, %d player%s", SpellName(s.id), Short(s.amount), s.hit, s.hit == 1 and "" or "s")
	end

	table.sort(players, function(a, b) return a.total > b.total end)
	lines[#lines + 1] = "  Most hit:"
	for i = 1, math.min(TOP_PLAYERS, #players) do
		local p = players[i]
		local parts = {}
		for j = 1, math.min(SPELLS_PER_PLAYER, #p.spells) do
			parts[#parts + 1] = SpellName(p.spells[j].id) .. " " .. Short(p.spells[j].amount)
		end
		lines[#lines + 1] = string.format("    %d. %s  %s%s", i, p.name, Short(p.total), #parts > 0 and ("  (" .. table.concat(parts, ", ") .. ")") or "")
	end
	return lines
end

local function PrintReport(lines)
	ns.Print(lines[1])
	for i = 2, #lines do
		print(lines[i])
	end
end

local function IsRaidLeader()
	if not (IsInRaid and IsInRaid()) then
		return false
	end
	local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
	return not Secret(leader) and leader == true
end

-- Called after combat and after restriction changes. Builds the pending
-- report once nothing is restricted any more.
function ns.TryPendingReport()
	if not pending or ns.IsRestricted() then
		return
	end
	local info = pending
	pending = nil
	local ok, lines = pcall(BuildReport, info)
	if not ok or type(lines) ~= "table" then
		return
	end
	ns.lastReport = lines
	if info.show then
		PrintReport(lines)
	end
end

function ns.OnEncounterStart(encounterID, encounterName)
	ns.encounterStartTime = GetTime and GetTime() or nil
	knownSessions = nil
	if DamageMeterReady() then
		knownSessions = SessionIDs()
	end
end

function ns.OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
	local seconds
	if ns.encounterStartTime and GetTime then
		seconds = GetTime() - ns.encounterStartTime
	end
	ns.encounterStartTime = nil
	pending = {
		name = Str(encounterName) or "Encounter",
		success = (Num(success) == 1),
		seconds = seconds,
		-- Everyone keeps the report for /sw report; only the leader sees it
		-- automatically.
		show = ns.db.raidReport and IsRaidLeader(),
	}
	-- Combat usually ends a moment after ENCOUNTER_END; the regen and
	-- restriction events retry. This covers the case where nothing fires.
	C_Timer.After(3, ns.TryPendingReport)
end

function ns.ShowLastReport()
	if ns.lastReport then
		PrintReport(ns.lastReport)
	else
		ns.Print("no encounter report yet. One is made after each boss fight.")
	end
end
