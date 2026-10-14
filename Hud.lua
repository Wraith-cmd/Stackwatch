--[[
	StackWatch - Hud.lua
	Quick-settings window. Opens with /sw, the addon compartment, a
	right-click on the drag handle, or a click on the tracker in Edit Mode.

	Every change goes through ns.SetOption, the same path as the Blizzard
	settings panel, so both stay in sync and rebuilds stay out of combat.
	The window closes itself when combat starts.
]]

local _, ns = ...

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local WIDTH = 270
local ROW_H = 26
local PAD = 12

local hud

local function Label(parent, text, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
	fs:SetTextColor(0.9, 0.9, 0.9, 1)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function FormatValue(key, value)
	if ns.RANGES[key] and ns.RANGES[key][3] < 1 then
		return string.format("%.2f", value)
	end
	return tostring(math.floor(value + 0.5))
end

-- One "label  value  [-] [+]" row for a numeric option.
local function Stepper(parent, y, key, text)
	local row = {}
	local label = Label(parent, text)
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y - 5)

	local plus = Button(parent, "+", 26, function()
		ns.SetOption(key, ns.db[key] + ns.RANGES[key][3])
		hud.Refresh()
	end)
	plus:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y)

	local minus = Button(parent, "-", 26, function()
		ns.SetOption(key, ns.db[key] - ns.RANGES[key][3])
		hud.Refresh()
	end)
	minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)

	local value = Label(parent, "")
	value:SetJustifyH("RIGHT")
	value:SetPoint("RIGHT", minus, "LEFT", -8, 0)

	function row.Refresh()
		value:SetText(FormatValue(key, ns.db[key]))
	end
	return row
end

-- A button that flips a boolean option and names its current state.
local function Toggle(parent, key, onText, offText, width, onClick)
	local b
	b = Button(parent, "", width, function()
		if onClick then
			onClick()
		else
			ns.SetOption(key, not ns.db[key])
		end
		hud.Refresh()
	end)
	b.Refresh = function()
		b:SetText(ns.db[key] and onText or offText)
	end
	return b
end

local function BuildHud()
	hud = CreateFrame("Frame", "StackWatchHud", UIParent)
	hud:SetFrameStrata("DIALOG")
	hud:SetClampedToScreen(true)
	hud:SetMovable(true)
	hud:EnableMouse(true)
	hud:RegisterForDrag("LeftButton")
	hud:SetScript("OnDragStart", hud.StartMoving)
	hud:SetScript("OnDragStop", hud.StopMovingOrSizing)
	hud:SetPoint("CENTER", UIParent, "CENTER", 0, 120)

	-- Flat panel: dark fill, one-pixel border.
	local bg = hud:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(hud)
	bg:SetColorTexture(0.06, 0.06, 0.07, 0.94)
	local edgeColor = { 0.3, 0.3, 0.32 }
	local edges = {
		{ "TOPLEFT", "TOPRIGHT", nil, 1 },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, nil },
		{ "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
	}
	for _, e in ipairs(edges) do
		local t = hud:CreateTexture(nil, "BORDER")
		t:SetTexture(WHITE8)
		t:SetVertexColor(edgeColor[1], edgeColor[2], edgeColor[3], 1)
		t:SetPoint(e[1], hud, e[1], 0, 0)
		t:SetPoint(e[2], hud, e[2], 0, 0)
		if e[3] then
			t:SetWidth(e[3])
		else
			t:SetHeight(e[4])
		end
	end

	local title = Label(hud, "StackWatch", 14)
	title:SetTextColor(0.5, 0.82, 1, 1)
	title:SetPoint("TOPLEFT", hud, "TOPLEFT", PAD, -10)

	local close = CreateFrame("Button", nil, hud, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", hud, "TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function()
		hud:Hide()
	end)

	local rows = {}
	local y = -36
	local steppers = {
		{ "cautionStacks", "Caution at" },
		{ "dangerStacks", "Danger at" },
		{ "maxStacks", "Bar maximum" },
		{ "iconSize", "Icon size" },
		{ "maxIcons", "Maximum icons" },
		{ "scale", "Scale" },
	}
	for _, s in ipairs(steppers) do
		rows[#rows + 1] = Stepper(hud, y, s[1], s[2])
		y = y - ROW_H
	end

	y = y - 6
	local half = (WIDTH - PAD * 2 - 6) / 2

	local lock = Toggle(hud, "locked", "Unlock to move", "Lock position", half)
	lock:SetPoint("TOPLEFT", hud, "TOPLEFT", PAD, y)
	local demo = Toggle(hud, "demoActive", "Stop demo", "Start demo", half, function()
		ns.ToggleDemo()
	end)
	demo.Refresh = function()
		demo:SetText(ns.demoActive and "Stop demo" or "Start demo")
	end
	demo:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -PAD, y)
	y = y - ROW_H

	local filter = Toggle(hud, "bossOnly", "Showing: boss debuffs", "Showing: all debuffs", half)
	filter:SetPoint("TOPLEFT", hud, "TOPLEFT", PAD, y)
	local sound = Toggle(hud, "soundOnStack", "Stack sound: on", "Stack sound: off", half)
	sound:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -PAD, y)
	y = y - ROW_H

	local marker = Toggle(hud, "dangerMarker", "Red X at danger: on", "Red X at danger: off", half)
	marker:SetPoint("TOPLEFT", hud, "TOPLEFT", PAD, y)
	local report = Toggle(hud, "raidReport", "Lead report: on", "Lead report: off", half)
	report:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -PAD, y)
	y = y - ROW_H

	local all = Button(hud, "All settings", WIDTH - PAD * 2, function()
		hud:Hide()
		ns.OpenOptions()
	end)
	all:SetPoint("TOPLEFT", hud, "TOPLEFT", PAD, y - 4)
	y = y - ROW_H - 4

	local note = Label(hud, "Changes made in combat apply when combat ends.", 10)
	note:SetTextColor(0.6, 0.6, 0.6, 1)
	note:SetPoint("TOPLEFT", hud, "TOPLEFT", PAD, y - 2)
	y = y - 18

	hud:SetSize(WIDTH, -y + PAD - 4)

	local toggles = { lock, demo, filter, sound, marker, report }
	function hud.Refresh()
		for _, r in ipairs(rows) do
			r.Refresh()
		end
		for _, t in ipairs(toggles) do
			t.Refresh()
		end
	end

	hud:Hide()
end

function ns.ToggleHud()
	if not ns.db then
		return
	end
	if not hud then
		BuildHud()
	end
	if hud:IsShown() then
		hud:Hide()
	else
		hud.Refresh()
		hud:Show()
	end
end

function ns.HideHud()
	if hud then
		hud:Hide()
	end
end
