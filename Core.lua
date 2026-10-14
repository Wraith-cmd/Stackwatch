--[[
	StackWatch - Core.lua
	Saved variables, defaults, events, slash commands.

	Design rule for this whole addon (Midnight 12.1+):
	The addon never reads a debuff's stack count. Blizzard's AuraContainer
	system renders the number, the bar and the threshold overlays from
	secure code. Everything here is configuration and layout.
]]

local ADDON_NAME, ns = ...

ns.VERSION = "1.1.0"

-- Eternal Venom (The Twin Fangs, The Venomous Abyss). Spell 1290336 is the
-- debuff that carries the stacks on every difficulty (BigWigs keys on it).
ns.ETERNAL_VENOM = 1290336

ns.DEFAULTS = {
	-- Position and size
	point = "CENTER",
	relPoint = "CENTER",
	x = 0,
	y = -170,
	scale = 1.0,
	locked = true,

	-- Layout
	iconSize = 48,
	spacing = 6,
	maxIcons = 3,
	growth = "RIGHT",       -- "RIGHT" or "LEFT"

	-- Thresholds (Twin Fangs Mythic: death at 10, so 5 = plan your Feast, 8 = one mistake from dead)
	cautionStacks = 5,
	dangerStacks = 8,
	maxStacks = 10,

	-- Look
	showStackBar = true,
	showCooldownSwipe = true,
	showCountForOne = true,
	countFontScale = 0.55,  -- number height as a fraction of the icon
	borderSize = 2,
	tintIcon = true,
	dangerMarker = false,   -- red X raid markers beside the number at danger

	-- Filtering
	bossOnly = true,        -- only auras Blizzard flags as boss auras

	-- Raid leader report after each boss (printed only for the raid leader)
	raidReport = true,

	-- Sound
	soundOnStack = false,
	soundSpellIDs = { 1290336 },

	-- Colors (r, g, b)
	colors = {
		normal  = { 1.00, 1.00, 1.00 },
		caution = { 1.00, 0.58, 0.05 },
		danger  = { 1.00, 0.12, 0.12 },
		bar     = { 0.25, 0.80, 0.35 },
	},
}

-- Debuffs Blizzard flags never-secret and which should not clutter an
-- all-debuff display. (Sated, Exhaustion, Temporal Displacement, Fatigued,
-- Insanity.) Never-secret spells are the only ones an addon may filter by
-- ID on the player, which is exactly why this list is legal.
ns.NEVER_SECRET_JUNK = {
	[57724]  = true,
	[57723]  = true,
	[80354]  = true,
	[264689] = true,
	[390435] = true,
}

local function CopyDefaults(src, dst)
	if type(dst) ~= "table" then
		dst = {}
	end
	for k, v in pairs(src) do
		if type(v) == "table" then
			if v[1] ~= nil then
				-- List (for example soundSpellIDs): keep the user's list as is,
				-- only seed it when missing. Never re-insert removed entries.
				if type(dst[k]) ~= "table" then
					local copy = {}
					for i, item in ipairs(v) do
						copy[i] = item
					end
					dst[k] = copy
				end
			else
				dst[k] = CopyDefaults(v, dst[k])
			end
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local function Print(msg)
	print("|cff7fd1ffStackWatch|r: " .. tostring(msg))
end
ns.Print = Print

------------------------------------------------------------------------
-- Restriction helpers
------------------------------------------------------------------------

-- True while the game is applying combat, encounter, keystone or PvP
-- addon restrictions. Aura buttons cannot be reconfigured and aura sounds
-- cannot be registered during these windows.
function ns.IsRestricted()
	if InCombatLockdown() then
		return true
	end
	local RA = C_RestrictedActions
	local types = Enum and Enum.AddOnRestrictionType
	if RA and RA.IsAddOnRestrictionActive and types then
		if (types.Combat and RA.IsAddOnRestrictionActive(types.Combat))
			or (types.Encounter and RA.IsAddOnRestrictionActive(types.Encounter))
			or (types.ChallengeMode and RA.IsAddOnRestrictionActive(types.ChallengeMode))
			or (types.PvPMatch and RA.IsAddOnRestrictionActive(types.PvPMatch)) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------
-- Rebuild scheduling
------------------------------------------------------------------------

local rebuildPending = false
local rebuildTimer = nil

local function DoRebuild()
	rebuildPending = false
	ns.BuildDisplay()
	ns.UpdateSounds()
	if ns.demoActive then
		ns.RefreshDemo()
	end
end

-- Called by the options panel on every change. Debounced so dragging a
-- slider does not rebuild thirty times. Deferred past combat.
function ns.RequestRebuild()
	if rebuildTimer then
		rebuildTimer:Cancel()
		rebuildTimer = nil
	end
	rebuildTimer = C_Timer.NewTimer(0.4, function()
		rebuildTimer = nil
		if ns.IsRestricted() then
			rebuildPending = true
			return
		end
		DoRebuild()
	end)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		StackWatchDB = CopyDefaults(ns.DEFAULTS, StackWatchDB)
		ns.db = StackWatchDB
		self:UnregisterEvent("ADDON_LOADED")

	elseif event == "PLAYER_LOGIN" then
		ns.BuildDisplay()
		ns.UpdateSounds()
		if ns.SetupOptions then
			ns.SetupOptions()
		end
		ns.RegisterEditMode()

	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Keep the screen clear on the pull. Changes made in the HUD are
		-- already saved; rebuilds wait for combat to end anyway.
		if ns.HideHud then
			ns.HideHud()
		end

	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Covers a /reload or login that happened mid-combat: nothing was
		-- built then, so build now.
		if (rebuildPending or not ns.displayBuilt) and not ns.IsRestricted() then
			DoRebuild()
		end
		ns.EnsureSounds()
		ns.TryPendingReport()

	elseif event == "ENCOUNTER_START" then
		ns.OnEncounterStart(arg1, ...)

	elseif event == "ENCOUNTER_END" then
		ns.OnEncounterEnd(arg1, ...)

	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		-- Fired before a restriction activates and after it deactivates.
		-- IsAddOnRestrictionActive() is always false during this dispatch,
		-- so defer one frame before deciding anything.
		C_Timer.After(0, function()
			if not ns.IsRestricted() then
				if rebuildPending or not ns.displayBuilt then
					DoRebuild()
				end
				ns.EnsureSounds()
				ns.TryPendingReport()
			end
		end)
	end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

local function Usage()
	Print("v" .. ns.VERSION .. " commands:")
	print("  /sw             open the quick-settings window")
	print("  /sw config      open the full settings panel")
	print("  /sw unlock      show the drag handle (drag it, then /sw lock)")
	print("  /sw lock        hide the drag handle")
	print("  /sw test        toggle the demo (cycles 0 to max stacks)")
	print("  /sw reset       reset position to screen center")
	print("  /sw boss        show boss debuffs only (default)")
	print("  /sw all         show every debuff on you")
	print("  /sw sound       toggle the stack-gain sound")
	print("  /sw sound add <spellID> / remove <spellID> / list")
	print("  /sw report      show the last boss fight's avoidable damage report")
	print("  /sw status      print diagnostics for raid night")
end

local function SetLocked(locked)
	ns.db.locked = locked
	if ns.SetAnchorLocked then
		ns.SetAnchorLocked(locked)
	end
	Print(locked and "locked." or "unlocked. Drag the handle, then type /sw lock.")
end

local function SoundCommand(rest)
	local db = ns.db
	local sub, id = rest:match("^(%a+)%s*(%d*)")
	id = tonumber(id)
	if (sub == "add" or sub == "remove") and not id then
		Print("usage: /sw sound " .. sub .. " <spellID>")
		return
	end
	if sub == "add" and id then
		for _, v in ipairs(db.soundSpellIDs) do
			if v == id then
				Print("spell " .. id .. " is already on the sound list.")
				return
			end
		end
		table.insert(db.soundSpellIDs, id)
		Print("added spell " .. id .. " to the sound list.")
		ns.UpdateSounds()
	elseif sub == "remove" and id then
		for i, v in ipairs(db.soundSpellIDs) do
			if v == id then
				table.remove(db.soundSpellIDs, i)
				Print("removed spell " .. id .. " from the sound list.")
				ns.UpdateSounds()
				return
			end
		end
		Print("spell " .. id .. " is not on the sound list.")
	elseif sub == "list" then
		Print("sound on stack gain is " .. (db.soundOnStack and "ON" or "OFF") .. " for:")
		for _, v in ipairs(db.soundSpellIDs) do
			local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(v)
			print("  " .. v .. "  " .. tostring(name or "?"))
		end
	else
		db.soundOnStack = not db.soundOnStack
		Print("sound on stack gain " .. (db.soundOnStack and "ON" or "OFF") .. ".")
		ns.UpdateSounds()
	end
end

local function Status()
	local db = ns.db
	Print("v" .. ns.VERSION .. " status")
	print("  restricted now: " .. tostring(ns.IsRestricted()))
	local RA, types = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if RA and RA.IsAddOnRestrictionActive and types then
		local active = {}
		for name, value in pairs(types) do
			if RA.IsAddOnRestrictionActive(value) then
				active[#active + 1] = name
			end
		end
		table.sort(active)
		print("  active restriction types: " .. (#active > 0 and table.concat(active, ", ") or "none"))
	end
	print("  filter: " .. (db.bossOnly and "boss debuffs only" or "all debuffs"))
	print("  thresholds: caution " .. db.cautionStacks .. ", danger " .. db.dangerStacks .. ", max " .. db.maxStacks)
	print("  icons: " .. db.maxIcons .. " x " .. db.iconSize .. "px, growth " .. db.growth .. ", scale " .. db.scale)
	print("  sound on stack gain: " .. (db.soundOnStack and "ON" or "OFF") .. " (" .. #ns.activeSoundIDs .. " registered" .. (ns.soundsDirty and ", pending" or "") .. ")")
	local spell = ns.ETERNAL_VENOM
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
	print("  Eternal Venom (" .. spell .. "): " .. tostring(name or "name not cached yet"))
	if C_UnitAuras and C_UnitAuras.AuraIsPrivate then
		print("  private aura: " .. tostring(C_UnitAuras.AuraIsPrivate(spell)))
	end
	if C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel then
		local level = C_Secrets.GetSpellAuraSecrecy(spell)
		local label = "unknown"
		for k, v in pairs(Enum.SecrecyLevel) do
			if v == level then
				label = k
			end
		end
		print("  aura secrecy: " .. label)
	end
	local meterOn = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("damageMeterEnabled")
	print("  raid lead report: " .. (db.raidReport and "ON" or "OFF") .. ", Blizzard damage meter " .. (meterOn and "enabled" or "DISABLED (report needs it)"))
	print("  containers built: " .. tostring(ns.displayBuilt))
end

SLASH_STACKWATCH1 = "/sw"
SLASH_STACKWATCH2 = "/stackwatch"
SlashCmdList["STACKWATCH"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd or ""
	if cmd == "" or cmd == "hud" then
		if ns.ToggleHud then
			ns.ToggleHud()
		end
	elseif cmd == "config" or cmd == "options" then
		if ns.OpenOptions then
			ns.OpenOptions()
		end
	elseif cmd == "unlock" then
		SetLocked(false)
	elseif cmd == "lock" then
		SetLocked(true)
	elseif cmd == "test" or cmd == "demo" then
		ns.ToggleDemo()
	elseif cmd == "reset" then
		ns.db.point, ns.db.relPoint, ns.db.x, ns.db.y = ns.DEFAULTS.point, ns.DEFAULTS.relPoint, ns.DEFAULTS.x, ns.DEFAULTS.y
		if ns.ApplyAnchorPosition then
			ns.ApplyAnchorPosition()
		end
		Print("position reset.")
	elseif cmd == "boss" then
		ns.db.bossOnly = true
		Print("showing boss debuffs only" .. (ns.IsRestricted() and " (applies after combat)." or "."))
		ns.RequestRebuild()
	elseif cmd == "all" then
		ns.db.bossOnly = false
		Print("showing all debuffs" .. (ns.IsRestricted() and " (applies after combat)." or "."))
		ns.RequestRebuild()
	elseif cmd == "sound" then
		SoundCommand(rest or "")
	elseif cmd == "report" then
		ns.ShowLastReport()
	elseif cmd == "status" then
		Status()
	else
		Usage()
	end
end

-- AddOn compartment (the minimap dropdown of addons)
function StackWatch_OnAddonCompartmentClick()
	if ns.ToggleHud then
		ns.ToggleHud()
	elseif ns.OpenOptions then
		ns.OpenOptions()
	end
end
