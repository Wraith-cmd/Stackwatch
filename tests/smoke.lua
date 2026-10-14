-- Offline smoke test for StackWatch. Run from the addon folder (repo root):
--   lua tests/smoke.lua        (any Lua 5.1 compatible interpreter)
package.path = "tests/?.lua;" .. package.path
local stub = require("wow_stub")

local printed = {}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local function check(cond, msg)
	if not cond then
		realPrint("FAIL: " .. msg)
		for _, l in ipairs(stub.log) do realPrint("  log: " .. l) end
		os.exit(1)
	end
	realPrint("ok   " .. msg)
end

-- Load the files in the order the .toc lists them
local files = {}
for line in io.lines("StackWatch.toc") do
	line = line:gsub("%c$", "")
	if line:match("%.lua$") then files[#files + 1] = line end
end
local ns = stub.LoadAddon(".", "StackWatch", files)
check(ns.VERSION and #files >= 5, "all " .. #files .. " files load in TOC order")

-- Fresh install: no saved variables
StackWatchDB = nil
stub.FireEvent("ADDON_LOADED", "StackWatch")
check(type(StackWatchDB) == "table" and StackWatchDB.cautionStacks == 5 and StackWatchDB.dangerStacks == 8, "defaults merged into a fresh StackWatchDB")

-- Existing saved variables keep user values and gain new keys
StackWatchDB = { iconSize = 60, colors = { caution = { 1, 0, 1 } } }
ns.db = nil
stub.frames[1]._events["ADDON_LOADED"] = true
stub.FireEvent("ADDON_LOADED", "StackWatch")
check(StackWatchDB.iconSize == 60 and StackWatchDB.colors.caution[1] == 1 and StackWatchDB.colors.danger ~= nil and StackWatchDB.maxStacks == 10, "existing settings preserved, missing keys filled")

-- Login builds the display and the options panel
stub.FireEvent("PLAYER_LOGIN")
check(ns.displayBuilt == true, "PLAYER_LOGIN builds the display")
check(#stub.containers == 3, "three AuraContainers created (base, caution, danger)")
check(stub.categoryRegistered == true, "options category registered with Blizzard Settings")
check(ns.anchor ~= nil and ns.anchor.handle._mouse == false and ns.anchor.handle:IsShown() == false, "anchor exists and starts locked (handle hidden)")

-- Every container got the same group definition
for i, c in ipairs(stub.containers) do
	local g = c._groups.stacks
	check(g and g.filter == "HARMFUL" and g.options.candidateFilters.isBossAura == true, "container " .. i .. " filters HARMFUL + isBossAura")
	check(g.options.sortMethod == AuraContainerSortMethod.ExpirationOnly and g.options.sortDirection == AuraContainerSortDirection.Reverse, "container " .. i .. " sorts permanent debuffs first")
	check(c._unit == "player" and c._enabled == true, "container " .. i .. " bound to player and enabled")
end

-- Base layer buttons have icon, cooldown, count, bar. Overlay buttons have gate + count.
local base = stub.containers[1]._groups.stacks.frames[1]
check(base._icon and base._cd and base._count and base._bar, "base button bound icon, cooldown, count and stack bar")
check(base._barOptions.minApplications == 0 and base._barOptions.maxApplications == 10, "base bar covers 0..10")
local caution = stub.containers[2]._groups.stacks.frames[1]
local danger = stub.containers[3]._groups.stacks.frames[1]
check(caution._bar and caution._barOptions.minApplications == 5, "caution gate shows at 5 stacks")
check(danger._bar and danger._barOptions.minApplications == 8, "danger gate shows at 8 stacks")
check(caution._icon == nil and danger._icon == nil, "overlay layers do not draw a second icon")

-- Simulate the aura system: Eternal Venom at 1, 5, 7, 8, 10 stacks
local function apply(stacks)
	local auras = stacks > 0 and { { applications = stacks, icon = 136187 } } or {}
	for _, c in ipairs(stub.containers) do c:_Apply(auras) end
end
apply(1)
check(base:IsShown() and tostring(base._count:GetText()) == "1" and caution._bar:IsShown() == false, "1 stack: icon shown, number 1, no caution")
apply(5)
check(caution._bar:IsShown() == true and danger._bar:IsShown() == false and tostring(base._count:GetText()) == "5", "5 stacks: caution on, danger off")
apply(7)
check(caution._bar:IsShown() == true and danger._bar:IsShown() == false, "7 stacks: still caution only")
apply(8)
check(danger._bar:IsShown() == true and tostring(danger._count:GetText()) == "8", "8 stacks: danger on, red number")
apply(10)
check(base._bar:GetValue() == 10 and danger._bar:IsShown(), "10 stacks: bar full, danger on")
apply(0)
check(base:IsShown() == false and caution._bar:IsShown() == false and danger._bar:IsShown() == false, "no aura: everything hidden")
-- Non-stacking boss debuff reports 0 applications and must not print "0"
for _, c in ipairs(stub.containers) do c:_Apply({ { applications = 0, icon = 1 } }) end
check(base:IsShown() and tostring(base._count:GetText()):match("^%s*$") ~= nil, "non-stacking debuff: icon shown, no number")

-- Slash commands
local slash = SlashCmdList["STACKWATCH"]
slash("unlock")
check(ns.db.locked == false and ns.anchor.handle._mouse == true and ns.anchor.handle:IsShown(), "/sw unlock shows the drag handle")
slash("lock")
check(ns.db.locked == true and ns.anchor.handle._mouse == false, "/sw lock hides the drag handle")
slash("test")
check(ns.demoActive == true, "/sw test starts the demo")
stub.RunTimers()
stub.RunTimers()
check(ns.demoActive == true, "demo ticks without error")
slash("test")
check(ns.demoActive == false, "/sw test again stops the demo")
slash("all")
stub.RunTimers()
check(stub.containers[#stub.containers]._groups.stacks.options.candidateFilters.excludeSpellIDs ~= nil, "/sw all rebuilds with never-secret junk excluded")
slash("boss")
stub.RunTimers()
check(stub.containers[#stub.containers]._groups.stacks.options.candidateFilters.isBossAura == true, "/sw boss rebuilds with boss filter")
slash("sound")
check(ns.db.soundOnStack == true and #ns.activeSoundIDs == 1, "/sw sound registers the Eternal Venom stack sound")
slash("sound add 1310360")
check(#ns.activeSoundIDs == 2, "/sw sound add registers a second spell")
slash("sound remove 1310360")
check(#ns.activeSoundIDs == 1, "/sw sound remove unregisters it")
slash("sound add")
check(#ns.activeSoundIDs == 1 and ns.db.soundOnStack == true, "/sw sound add without an id prints usage, changes nothing")
-- Sound list edited in combat is applied after combat
stub.inCombat = true
slash("sound add 1310102")
check(#ns.activeSoundIDs == 1 and ns.soundsDirty == true, "sound list change in combat is marked pending")
stub.inCombat = false
stub.FireEvent("PLAYER_REGEN_ENABLED")
check(#ns.activeSoundIDs == 2 and ns.soundsDirty == false, "pending sound change applied after combat")
slash("sound remove 1310102")
-- Removing the last sound spell must survive a relog (list defaults are not re-merged)
table.remove(ns.db.soundSpellIDs, 1)
stub.frames[1]._events["ADDON_LOADED"] = true
stub.FireEvent("ADDON_LOADED", "StackWatch")
check(#ns.db.soundSpellIDs == 0, "empty sound list stays empty after reload")
table.insert(ns.db.soundSpellIDs, 1290336)
ns.UpdateSounds()
slash("sound list")
slash("status")
slash("reset")
slash("config")
check(stub.opened == "cat_StackWatch", "/sw config opens the settings category")
slash("help")

-- Settings panel: every registered setting accepts a change and triggers the right path
local count = 0
for key, s in pairs(stub.settings) do
	count = count + 1
	local v = s:GetValue()
	if s.type == "boolean" then s:SetValue(not v) s:SetValue(v)
	elseif s.type == "number" then s:SetValue(v + 1) s:SetValue(v)
	else s:SetValue(v) end
end
stub.RunTimers()
check(count >= 15, "settings registered: " .. count)

-- Growth left path
stub.settings.growth:SetValue("LEFT")
stub.RunTimers()
check(stub.containers[#stub.containers]._points[1][1] == "TOPRIGHT", "growth LEFT anchors containers to TOPRIGHT")
stub.settings.growth:SetValue("RIGHT")
stub.RunTimers()

-- Combat deferral: rebuild requested in combat happens after combat
stub.inCombat = true
local before = #stub.containers
stub.settings.iconSize:SetValue(40)
stub.RunTimers()
check(#stub.containers == before, "rebuild deferred while in combat")
stub.inCombat = false
stub.FireEvent("PLAYER_REGEN_ENABLED")
check(#stub.containers == before + 3, "rebuild runs after PLAYER_REGEN_ENABLED")

-- Encounter restriction: sounds re-register only after the restriction lifts
stub.restricted[Enum.AddOnRestrictionType.Encounter] = true
ns.UpdateSounds()
check(#ns.activeSoundIDs == 1, "UpdateSounds is a no-op during an encounter")
stub.restricted[Enum.AddOnRestrictionType.Encounter] = nil
stub.FireEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Encounter, Enum.AddOnRestrictionState.Inactive)
stub.RunTimers()
check(#ns.activeSoundIDs == 1, "sounds re-registered after the encounter ends")

-- Old containers were disabled, not leaked as active
local active = 0
for _, c in ipairs(stub.containers) do if c._enabled then active = active + 1 end end
check(active == 3, "exactly three containers active after rebuilds")

-- Edit Mode: handle and demo appear, saved lock state untouched, all restored on exit
check(stub.callbacks["EditMode.Enter"] and stub.callbacks["EditMode.Exit"], "Edit Mode callbacks registered")
ns.db.locked = true
ns.SetAnchorLocked(true)
stub.TriggerCallback("EditMode.Enter")
check(ns.anchor.handle:IsShown() and ns.anchor.handle._mouse == true and ns.demoActive == true, "Edit Mode shows the drag handle and the demo")
check(ns.db.locked == true, "Edit Mode does not change the saved lock")
ns.anchor.handle._script_OnMouseDown(ns.anchor.handle, "LeftButton")
ns.anchor.handle._script_OnMouseUp(ns.anchor.handle, "LeftButton")
local hudFrame
for _, f in ipairs(stub.frames) do if f._name == "StackWatchHud" then hudFrame = f end end
check(hudFrame and hudFrame:IsShown(), "click on the tracker in Edit Mode opens the HUD")
ns.anchor.handle._script_OnMouseDown(ns.anchor.handle, "LeftButton")
ns.anchor.handle._script_OnDragStart(ns.anchor.handle)
ns.anchor.handle._script_OnDragStop(ns.anchor.handle)
ns.anchor.handle._script_OnMouseUp(ns.anchor.handle, "LeftButton")
check(hudFrame:IsShown(), "dragging the tracker does not toggle the HUD")
stub.TriggerCallback("EditMode.Exit")
check(not ns.anchor.handle:IsShown() and ns.anchor.handle._mouse == false and ns.demoActive == false, "leaving Edit Mode hides the handle and stops the demo")
-- A demo the player started stays on through Edit Mode
slash("test")
stub.TriggerCallback("EditMode.Enter")
stub.TriggerCallback("EditMode.Exit")
check(ns.demoActive == true, "Edit Mode leaves a manually started demo running")
slash("test")

-- HUD buttons
local function findButton(text, nth)
	local n = 0
	local function walk(o)
		for _, c in ipairs(o._children) do
			if c._type == "Button" and c._text == text then
				n = n + 1
				if n == (nth or 1) then return c end
			end
			local r = walk(c)
			if r then return r end
		end
	end
	return walk(hudFrame)
end
local cautionBefore = ns.db.cautionStacks
findButton("+", 1)._script_OnClick()
stub.RunTimers()
check(ns.db.cautionStacks == cautionBefore + 1, "HUD + raises caution stacks")
local built = #stub.containers
findButton("-", 1)._script_OnClick()
stub.RunTimers()
check(ns.db.cautionStacks == cautionBefore and #stub.containers == built + 3, "HUD - lowers it and rebuilds through the settings path")
for _ = 1, 40 do findButton("-", 1)._script_OnClick() end
check(ns.db.cautionStacks == 1, "HUD clamps to the slider minimum")
ns.SetOption("cautionStacks", 5)
local scaleBefore = ns.db.scale
findButton("+", 6)._script_OnClick()
check(math.abs(ns.db.scale - (scaleBefore + 0.05)) < 0.001, "HUD scale step is 0.05")
ns.SetOption("scale", scaleBefore)
local markerBtn = findButton("Red X at danger: off")
check(markerBtn ~= nil, "HUD shows the red X toggle")
markerBtn._script_OnClick()
stub.RunTimers()
local dangerBtn = stub.containers[#stub.containers]._groups.stacks.frames[1]
check(ns.db.dangerMarker == true and dangerBtn._bar and #dangerBtn._bar._children >= 7, "red X markers built on the danger gate")
local markers = 0
for _, c in ipairs(dangerBtn._bar._children) do if c._tex == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" then markers = markers + 1 end end
check(markers == 2, "two red X markers at danger")
ns.SetOption("dangerMarker", false)
stub.RunTimers()
stub.FireEvent("PLAYER_REGEN_DISABLED")
check(not hudFrame:IsShown(), "HUD closes when combat starts")
slash("")
check(hudFrame:IsShown(), "/sw with no arguments opens the HUD")
slash("")
check(not hudFrame:IsShown(), "/sw again closes it")

-- Raid leader report
stub.spellNames[901] = "Venom Spray"
stub.spellNames[902] = "Fang Sweep"
local function fight(sessionID, data, opts)
	opts = opts or {}
	stub.now = 1000
	stub.FireEvent("ENCOUNTER_START", 3421, "The Twin Fangs", 16, 20)
	stub.inCombat = true
	stub.restricted[Enum.AddOnRestrictionType.Encounter] = true
	stub.meter.sessions[#stub.meter.sessions + 1] = { id = sessionID, duration = 272 }
	stub.meter.data[sessionID] = data
	stub.now = 1272
	stub.FireEvent("ENCOUNTER_END", 3421, "The Twin Fangs", 16, 20, opts.success or 0, {})
	stub.RunTimers() -- the 3 second retry fires while still restricted
	if opts.stayInCombat then return end
	stub.inCombat = false
	stub.restricted[Enum.AddOnRestrictionType.Encounter] = nil
	stub.FireEvent("PLAYER_REGEN_ENABLED")
end
local raidData = {
	{ guid = "Player-1-0001", name = "Gotfleas", spells = { [901] = 120000, [902] = 40000 } },
	{ guid = "Player-1-0002", name = "Tankyboi", spells = { [901] = 900000 } },
	{ guid = "Player-1-0003", name = "Clean", spells = {} },
	{ guid = "Creature-0-1-2-3-4-5", name = "Boss", spells = { [902] = 5000000 } },
}
local function printedSince(n) return table.concat(printed, "\n", n + 1) end

stub.inRaid, stub.isLeader = true, true
local mark = #printed
fight(11, raidData)
local out = printedSince(mark)
check(out:find("The Twin Fangs %(wipe, 4:32%)") ~= nil, "leader gets the report after the fight")
check(out:find("Venom Spray") and out:find("1.0M, 2 players"), "report sums the top source across players")
check(out:find("1%. Tankyboi") and out:find("2%. Gotfleas"), "report ranks the most-hit players")
check(not out:find("Boss") and not out:find("Clean"), "report skips creatures and players with no avoidable damage")

mark = #printed
stub.isLeader = false
fight(12, raidData)
check(printedSince(mark) == "", "non-leaders see nothing automatically")
slash("report")
check(printedSince(mark):find("Tankyboi") ~= nil, "/sw report shows the last report to anyone")

stub.isLeader = true
mark = #printed
fight(13, raidData, { stayInCombat = true })
check(printedSince(mark) == "", "no report while combat restrictions are active")
stub.inCombat = false
stub.restricted[Enum.AddOnRestrictionType.Encounter] = nil
stub.FireEvent("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Encounter, Enum.AddOnRestrictionState.Inactive)
stub.RunTimers()
check(printedSince(mark):find("Tankyboi") ~= nil, "report appears once restrictions lift")

mark = #printed
stub.meterSecret = true
fight(14, raidData)
stub.meterSecret = false
check(printedSince(mark):find("nobody took avoidable damage") ~= nil, "secret damage meter values are skipped without an error")

mark = #printed
stub.cvars.damageMeterEnabled = false
fight(15, raidData)
stub.cvars.damageMeterEnabled = true
check(printedSince(mark):find("Enable Damage Meter") ~= nil, "tells the leader to turn on the damage meter")

mark = #printed
ns.SetOption("raidReport", false)
fight(16, raidData, { success = 1 })
check(printedSince(mark) == "", "report option off: nothing printed")
slash("report")
check(printedSince(mark):find("kill") ~= nil, "kills are labeled as kills")
ns.SetOption("raidReport", true)

-- The meter may open the fight's session at combat start, before
-- ENCOUNTER_START, and the pull may already be restricted then.
mark = #printed
stub.meter.sessions[#stub.meter.sessions + 1] = { id = 20, duration = 40 }
stub.meter.data[20] = { { guid = "Player-1-0009", name = "TrashPuller", spells = { [902] = 1 } } }
stub.meter.sessions[#stub.meter.sessions + 1] = { id = 21, duration = 272 }
stub.meter.data[21] = raidData
stub.now = 1000
stub.inCombat = true
stub.restricted[Enum.AddOnRestrictionType.Encounter] = true
stub.FireEvent("ENCOUNTER_START", 3421, "The Twin Fangs", 16, 20)
stub.now = 1272
stub.FireEvent("ENCOUNTER_END", 3421, "The Twin Fangs", 16, 20, 0, {})
stub.inCombat = false
stub.restricted[Enum.AddOnRestrictionType.Encounter] = nil
stub.FireEvent("PLAYER_REGEN_ENABLED")
out = printedSince(mark)
check(out:find("Tankyboi") and not out:find("TrashPuller"), "restricted ENCOUNTER_START: report still finds the fight's session by length")
stub.inRaid, stub.isLeader = false, false

-- Addon compartment entry point
StackWatch_OnAddonCompartmentClick()

realPrint("ALL CHECKS PASSED (" .. #printed .. " chat lines printed)")
