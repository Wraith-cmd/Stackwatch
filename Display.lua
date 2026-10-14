--[[
	StackWatch - Display.lua
	The movable anchor, the three AuraContainers, the per-button look, and
	the stack-gain sound registration.

	How the threshold colors work without reading any stack count:

	Three identical AuraContainers are stacked on top of each other and
	filtered and sorted the same way, so they always show the same debuffs
	in the same order.

	  Layer "base"    draws the icon, the number, the swipe and the stack bar.
	  Layer "caution" draws an orange border, tint and number. Its only
	                  application bar is a full-size invisible StatusBar that
	                  Blizzard shows when applications >= cautionStacks and
	                  hides otherwise, so the orange layer appears and
	                  disappears with the stacks. The comparison happens in
	                  Blizzard's secure code (CustomAuraButton:ApplyApplicationBar
	                  does statusBar:SetShown(applications >= minApplications)).
	  Layer "danger"  same trick with dangerStacks and red, drawn above caution.

	Nothing here ever touches a secret value.
]]

local ADDON_NAME, ns = ...

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local SOUND_FILE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\tick.ogg"
local LAYER_LEVEL = { base = 2, caution = 12, danger = 22 }

ns.containers = {}
ns.activeSoundIDs = {}
ns.soundsDirty = false
ns.displayBuilt = false
ns.growthLeftSupported = (AnchorUtil ~= nil and AnchorUtil.FlowDirection ~= nil)

local anchor

------------------------------------------------------------------------
-- Shared look. Used by the real aura buttons and by the demo.
-- Returns a table of regions so the caller can bind them to the button.
------------------------------------------------------------------------

local function ApplyFont(fs, fontSize)
	fs:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	fs:SetJustifyH("CENTER")
	fs:SetJustifyV("MIDDLE")
end

local function Metrics()
	local db = ns.db
	local size = db.iconSize
	local barH = db.showStackBar and math.max(4, math.floor(size * 0.14 + 0.5)) or 0
	local totalH = size + ((barH > 0) and (barH + 2) or 0)
	local fontSize = math.max(8, math.floor(size * db.countFontScale + 0.5))
	return size, barH, totalH, fontSize
end
ns.Metrics = Metrics

function ns.BuildLook(f, layer)
	local db = ns.db
	local c = db.colors
	local size, barH, totalH, fontSize = Metrics()
	local look = { size = size, barH = barH, totalH = totalH }

	f:SetSize(size, totalH)

	if layer == "base" then
		-- Black frame behind the icon
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(0, 0, 0, 0.85)
		bg:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
		bg:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", size + 1, -size - 1)

		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		icon:SetSize(size, size)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		look.icon = icon

		if db.showCooldownSwipe then
			local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
			cd:SetAllPoints(icon)
			cd:SetUsingParentLevel(true) -- keep the swipe under the number
			cd:SetDrawEdge(false)
			cd:SetDrawBling(false)
			cd:SetHideCountdownNumbers(true)
			cd:SetReverse(true)
			look.cooldown = cd
		end

		local count = f:CreateFontString(nil, "OVERLAY")
		ApplyFont(count, fontSize)
		count:SetPoint("CENTER", icon, "CENTER", 0, 0)
		count:SetTextColor(c.normal[1], c.normal[2], c.normal[3], 1)
		look.count = count

		if barH > 0 then
			local bar = CreateFrame("StatusBar", nil, f)
			bar:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -2)
			bar:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 0, -2)
			bar:SetHeight(barH)
			bar:SetStatusBarTexture(WHITE8)
			bar:SetStatusBarColor(c.bar[1], c.bar[2], c.bar[3], 1)
			bar:SetMinMaxValues(0, db.maxStacks)
			bar:SetValue(0)

			local bbg = bar:CreateTexture(nil, "BACKGROUND")
			bbg:SetAllPoints(bar)
			bbg:SetColorTexture(0, 0, 0, 0.7)

			-- Threshold tick marks, colored, so you can read the bar at a glance
			local function Tick(stacks, color)
				if stacks <= 0 or stacks >= db.maxStacks then
					return
				end
				local t = bar:CreateTexture(nil, "OVERLAY")
				t:SetColorTexture(color[1], color[2], color[3], 1)
				t:SetWidth(1)
				t:SetPoint("TOP", bar, "TOPLEFT", math.floor(size * stacks / db.maxStacks + 0.5), 0)
				t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", math.floor(size * stacks / db.maxStacks + 0.5), 0)
			end
			Tick(db.cautionStacks, c.caution)
			Tick(db.dangerStacks, c.danger)

			look.bar = bar
		end

	else
		local color = (layer == "danger") and c.danger or c.caution
		local b = db.borderSize

		-- The gate: an invisible StatusBar covering the button. Blizzard shows
		-- it only while applications >= minApplications. Everything colored
		-- for this layer is a child of the gate, so it appears with it.
		local gate = CreateFrame("StatusBar", nil, f)
		gate:SetAllPoints(f)
		gate:SetStatusBarTexture(WHITE8)
		gate:SetStatusBarColor(0, 0, 0, 0)
		gate:GetStatusBarTexture():SetAlpha(0)
		gate:SetMinMaxValues(0, 1)
		gate:SetValue(0)
		look.gate = gate

		if b > 0 then
			local edges = {}
			for i = 1, 4 do
				local e = gate:CreateTexture(nil, "OVERLAY")
				e:SetColorTexture(color[1], color[2], color[3], 1)
				edges[i] = e
			end
			-- top
			edges[1]:SetPoint("TOPLEFT", gate, "TOPLEFT", -b, b)
			edges[1]:SetPoint("TOPRIGHT", gate, "TOPLEFT", size + b, b)
			edges[1]:SetHeight(b)
			-- bottom (just under the icon, above the bar)
			edges[2]:SetPoint("TOPLEFT", gate, "TOPLEFT", -b, -size)
			edges[2]:SetPoint("TOPRIGHT", gate, "TOPLEFT", size + b, -size)
			edges[2]:SetHeight(b)
			-- left
			edges[3]:SetPoint("TOPLEFT", gate, "TOPLEFT", -b, b)
			edges[3]:SetPoint("BOTTOMLEFT", gate, "TOPLEFT", -b, -size - b)
			edges[3]:SetWidth(b)
			-- right
			edges[4]:SetPoint("TOPRIGHT", gate, "TOPLEFT", size + b, b)
			edges[4]:SetPoint("BOTTOMRIGHT", gate, "TOPLEFT", size + b, -size - b)
			edges[4]:SetWidth(b)
			look.edges = edges
		end

		if db.tintIcon then
			local tint = gate:CreateTexture(nil, "ARTWORK")
			tint:SetColorTexture(color[1], color[2], color[3], 0.22)
			tint:SetPoint("TOPLEFT", gate, "TOPLEFT", 0, 0)
			tint:SetSize(size, size)
			look.tint = tint
		end

		local count = gate:CreateFontString(nil, "OVERLAY")
		ApplyFont(count, fontSize)
		count:SetPoint("CENTER", gate, "TOPLEFT", size / 2, -size / 2)
		count:SetTextColor(color[1], color[2], color[3], 1)
		look.count = count
	end

	return look
end

------------------------------------------------------------------------
-- Anchor
------------------------------------------------------------------------

function ns.ApplyAnchorPosition()
	if not anchor then
		return
	end
	local db = ns.db
	anchor:ClearAllPoints()
	anchor:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
	anchor:SetScale(db.scale)
end

local function SavePosition(self)
	local point, _, relPoint, x, y = self:GetPoint(1)
	if point then
		local db = ns.db
		db.point, db.relPoint = point, relPoint
		db.x, db.y = math.floor(x + 0.5), math.floor(y + 0.5)
	end
end

function ns.SetAnchorLocked(locked)
	if not anchor then
		return
	end
	anchor.handle:SetShown(not locked)
	anchor.handle:EnableMouse(not locked)
end

local function CreateAnchor()
	anchor = CreateFrame("Frame", "StackWatchAnchor", UIParent)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetFrameLevel(10)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)

	-- The drag handle is a separate frame drawn above the aura containers so
	-- dragging works even while a debuff is on screen.
	local handle = CreateFrame("Frame", "StackWatchDragHandle", anchor)
	handle:SetAllPoints(anchor)
	handle:SetFrameLevel(anchor:GetFrameLevel() + 60)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function()
		if not ns.db.locked then
			anchor:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		anchor:StopMovingOrSizing()
		SavePosition(anchor)
	end)
	handle:Hide()
	handle:EnableMouse(false)
	anchor.handle = handle

	local bg = handle:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(handle)
	bg:SetColorTexture(0.1, 0.6, 1.0, 0.45)

	local label = handle:CreateFontString(nil, "OVERLAY")
	ApplyFont(label, 11)
	label:SetPoint("BOTTOM", handle, "TOP", 0, 3)
	label:SetText("StackWatch  (drag, then /sw lock)")

	ns.anchor = anchor
end

------------------------------------------------------------------------
-- Containers
------------------------------------------------------------------------

local function GetCountOptions()
	local db = ns.db
	if db.showCountForOne and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
		if not ns.countFormatter then
			-- Non-stacking auras report 0 applications; show nothing for them
			-- and the plain number from 1 up.
			local fmt = C_StringUtil.CreateNumericRuleFormatter()
			fmt:AddBreakpoint({ threshold = 0, format = " " })
			fmt:AddBreakpoint({ threshold = 1, format = "%d" })
			ns.countFormatter = fmt
		end
		return { formatter = ns.countFormatter }
	end
	return nil
end

local function GetCandidateFilters()
	local db = ns.db
	if db.bossOnly then
		return { isBossAura = true }
	end
	return { excludeSpellIDs = ns.NEVER_SECRET_JUNK }
end

local function InitButton(button, layer)
	local db = ns.db
	local look = ns.BuildLook(button, layer)

	-- No boss debuff tooltips popping while you hover the tracker mid-pull.
	if button.SetHideTooltipInCombat then
		button:SetHideTooltipInCombat(true)
	end

	if layer == "base" then
		button:SetIcon(look.icon)
		if look.cooldown then
			button:SetDurationCooldown(look.cooldown)
		end
		button:SetApplicationCount(look.count, GetCountOptions())
		if look.bar then
			button:SetApplicationBar(look.bar, {
				minApplications = 0,
				maxApplications = db.maxStacks,
				interpolation = Enum.StatusBarInterpolation.Immediate,
			})
		end
	else
		local threshold = (layer == "danger") and db.dangerStacks or db.cautionStacks
		button:SetApplicationCount(look.count, GetCountOptions())
		button:SetApplicationBar(look.gate, {
			minApplications = threshold,
			maxApplications = math.max(db.maxStacks, threshold),
			interpolation = Enum.StatusBarInterpolation.Immediate,
		})
	end
end

local containerSerial = 0

local function CreateContainer(layer)
	local db = ns.db
	local size, _, totalH = Metrics()
	containerSerial = containerSerial + 1

	local c = CreateFrame("AuraContainer", "StackWatchContainer" .. layer .. containerSerial, anchor, "CustomAuraContainerTemplate")
	c:SetSize(1, 1)
	c:SetFrameLevel(anchor:GetFrameLevel() + LAYER_LEVEL[layer])

	if db.growth == "LEFT" and ns.growthLeftSupported then
		c:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
		c:SetFlowLayoutAnchorPoint("TOPRIGHT")
		c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down)
	else
		c:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
	end

	c:SetUnit("player")
	c:AddAuraGroup("stacks", "HARMFUL", {
		maxFrameCount = db.maxIcons,
		candidateFilters = GetCandidateFilters(),
		-- Permanent debuffs first (Eternal Venom never expires), then longest remaining.
		sortMethod = AuraContainerSortMethod.ExpirationOnly,
		sortDirection = AuraContainerSortDirection.Reverse,
		initializeFrame = function(button)
			InitButton(button, layer)
		end,
		layout = {
			elementSpacing = db.spacing,
			elementWidth = size,
			elementHeight = totalH,
		},
	})

	c:SetEnabled(true)
	return c
end

function ns.BuildDisplay()
	local db = ns.db
	if not db then
		return
	end
	if ns.IsRestricted() then
		return
	end

	if not anchor then
		CreateAnchor()
	end
	local size, _, totalH = Metrics()
	anchor:SetSize(size, totalH)
	ns.ApplyAnchorPosition()
	ns.SetAnchorLocked(db.locked)

	-- Retire the previous set. Frames cannot be destroyed; disabling them
	-- unregisters their events so they cost nothing.
	for _, old in ipairs(ns.containers) do
		old:SetEnabled(false)
		old:Hide()
	end
	ns.containers = {}

	for _, layer in ipairs({ "base", "caution", "danger" }) do
		ns.containers[#ns.containers + 1] = CreateContainer(layer)
	end
	ns.displayBuilt = true
end

------------------------------------------------------------------------
-- Sound on stack gain
-- C_UnitAuras.AddAuraSound is keyed on a spell ID directly and is the one
-- per-spell hook that works for a boss debuff on the player. It cannot be
-- called while restrictions are active, so registration is retried from
-- ADDON_RESTRICTION_STATE_CHANGED in Core.lua.
------------------------------------------------------------------------

-- Re-register only when the sound is wanted and nothing is registered
-- (for example after an encounter blocked the registration).
function ns.EnsureSounds()
	local db = ns.db
	if db and (ns.soundsDirty or (db.soundOnStack and #ns.activeSoundIDs == 0)) then
		ns.UpdateSounds()
	end
end

function ns.UpdateSounds()
	local db = ns.db
	if not db then
		return
	end
	if not (C_UnitAuras and C_UnitAuras.AddAuraSound and Enum and Enum.UnitAuraSoundTrigger) then
		return
	end
	if ns.IsRestricted() then
		-- Remember that the list changed; EnsureSounds retries after combat.
		ns.soundsDirty = true
		return
	end
	ns.soundsDirty = false

	for _, id in ipairs(ns.activeSoundIDs) do
		C_UnitAuras.RemoveAuraSound(id)
	end
	ns.activeSoundIDs = {}

	if not db.soundOnStack then
		return
	end

	for _, spellID in ipairs(db.soundSpellIDs) do
		local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.ApplicationsIncreased, {
			unitToken = "player",
			spellID = spellID,
			soundFileName = SOUND_FILE,
			outputChannel = "Master",
			throttleSeconds = 0.5,
		})
		if ok and id then
			ns.activeSoundIDs[#ns.activeSoundIDs + 1] = id
		elseif not ok then
			ns.soundsDirty = true
		end
	end
end
