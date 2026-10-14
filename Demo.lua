--[[
	StackWatch - Demo.lua
	/sw test builds a fake tracker in the real position with the real look
	and cycles the stack count from 0 to max, so you can position it, judge
	the sizes and show the raid lead what it does without pulling a boss.

	The demo uses plain frames, not AuraContainers, so it works anywhere
	(town, dummy, in a raid lobby) and never touches the aura system.
]]

local _, ns = ...

ns.demoActive = false

local demo         -- the demo frame tree
local ticker       -- C_Timer ticker
local stacks = 0

local function GetVenomIcon()
	local iconID
	if C_Spell and C_Spell.GetSpellTexture then
		iconID = C_Spell.GetSpellTexture(ns.ETERNAL_VENOM)
	end
	return iconID or 134400 -- question mark icon
end

local function BuildDemo()
	local db = ns.db
	local size, _, totalH = ns.Metrics()

	demo = CreateFrame("Frame", nil, ns.anchor or UIParent)
	demo:SetFrameStrata("MEDIUM")
	demo:SetFrameLevel((ns.anchor and ns.anchor:GetFrameLevel() or 10) + 40)
	demo:SetSize(size, totalH)
	if ns.anchor then
		if db.growth == "LEFT" and ns.growthLeftSupported then
			demo:SetPoint("TOPRIGHT", ns.anchor, "TOPRIGHT", 0, 0)
		else
			demo:SetPoint("TOPLEFT", ns.anchor, "TOPLEFT", 0, 0)
		end
	else
		demo:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
	end

	demo.layers = {}
	for _, layer in ipairs({ "base", "caution", "danger" }) do
		local f = CreateFrame("Frame", nil, demo)
		f:SetPoint("TOPLEFT", demo, "TOPLEFT", 0, 0)
		f:SetFrameLevel(demo:GetFrameLevel() + ((layer == "base") and 1 or (layer == "caution") and 5 or 9))
		local look = ns.BuildLook(f, layer)
		look.frame = f
		demo.layers[layer] = look
	end

	demo.layers.base.icon:SetTexture(GetVenomIcon())

	local hint = demo:CreateFontString(nil, "OVERLAY")
	hint:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
	hint:SetPoint("TOP", demo, "BOTTOM", 0, -4)
	hint:SetTextColor(0.7, 0.85, 1, 1)
	hint:SetText("demo: /sw test to stop")
	demo.hint = hint
end

local function SetDemoStacks(n)
	local db = ns.db
	local base, caution, danger = demo.layers.base, demo.layers.caution, demo.layers.danger

	local text = (n > 1 or (n == 1 and db.showCountForOne)) and tostring(n) or ""
	base.count:SetText(text)
	caution.count:SetText(text)
	danger.count:SetText(text)

	if base.bar then
		base.bar:SetMinMaxValues(0, db.maxStacks)
		base.bar:SetValue(n)
	end

	-- Mirror exactly what Blizzard's ApplyApplicationBar does for the gates.
	caution.gate:SetShown(n >= db.cautionStacks)
	danger.gate:SetShown(n >= db.dangerStacks)

	base.frame:SetShown(n > 0)
end

local function Step()
	stacks = stacks + 1
	if stacks > ns.db.maxStacks then
		stacks = 0
	end
	SetDemoStacks(stacks)
end

function ns.RefreshDemo()
	if not ns.demoActive then
		return
	end
	ns.StopDemo()
	ns.StartDemo()
end

function ns.StartDemo()
	if ns.demoActive then
		return
	end
	BuildDemo()
	stacks = 0
	SetDemoStacks(0)
	ticker = C_Timer.NewTicker(0.7, Step)
	ns.demoActive = true
	ns.Print("demo running. Thresholds: caution at " .. ns.db.cautionStacks .. ", danger at " .. ns.db.dangerStacks .. ".")
end

function ns.StopDemo()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if demo then
		demo:Hide()
		demo = nil
	end
	ns.demoActive = false
end

function ns.ToggleDemo()
	if ns.demoActive then
		ns.StopDemo()
		ns.Print("demo stopped.")
	else
		ns.StartDemo()
	end
end
