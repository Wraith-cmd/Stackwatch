-- Minimal WoW 12.1.5 API stub for offline smoke-testing StackWatch.
-- It mirrors the argument validation Blizzard performs in
-- Blizzard_CustomAuraContainer.lua / Blizzard_CustomAuraButton.lua so that
-- wrong option tables or wrong object types fail here, not in the raid.

local stub = {}
local log = {}
stub.log = log
local function note(fmt, ...) log[#log + 1] = string.format(fmt, ...) end

----------------------------------------------------------------------
-- Globals
----------------------------------------------------------------------
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
QUESTION_MARK_ICON = 134400
SlashCmdList = {}
Enum = {
	AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
	AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
	StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
	UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 },
	SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 },
}
AuraContainerSortMethod = { Default = 0, BigDefensive = 1, UnitFrameDebuff = 2, ImportantOnly = 3, Expiration = 4, ExpirationOnly = 5, Name = 6, NameOnly = 7, AuraInstanceIDOnly = 8 }
AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }, FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }

stub.inCombat = false
stub.restricted = {}
function InCombatLockdown() return stub.inCombat end
C_RestrictedActions = { IsAddOnRestrictionActive = function(t) return stub.restricted[t] == true end }
C_Secrets = { GetSpellAuraSecrecy = function(id) return Enum.SecrecyLevel.ContextuallySecret end }
C_Spell = { GetSpellTexture = function(id) return 136187 end, GetSpellName = function(id) return "Eternal Venom" end }

local soundSerial = 0
stub.sounds = {}
C_UnitAuras = {
	AuraIsPrivate = function(id) return false end,
	AddAuraSound = function(trigger, info)
		assert(type(trigger) == "number", "trigger must be a number")
		assert(type(info) == "table", "sound info must be a table")
		assert(type(info.unitToken) == "string", "unitToken must be a string")
		assert(type(info.spellID) == "number", "spellID must be a number")
		assert(info.soundFileName or info.soundFileID, "need soundFileName or soundFileID")
		assert(info.throttleSeconds == nil or (info.throttleSeconds >= 0 and info.throttleSeconds <= 5), "throttleSeconds 0..5")
		assert(not stub.inCombat and not next(stub.restricted), "AddAuraSound called while restricted")
		soundSerial = soundSerial + 1
		stub.sounds[soundSerial] = info
		note("AddAuraSound %d spell %d", soundSerial, info.spellID)
		return soundSerial
	end,
	RemoveAuraSound = function(id) assert(stub.sounds[id], "RemoveAuraSound unknown id") stub.sounds[id] = nil end,
}

C_StringUtil = {
	CreateNumericRuleFormatter = function()
		local f = { breakpoints = {} }
		function f:AddBreakpoint(bp)
			assert(type(bp) == "table" and type(bp.threshold) == "number" and type(bp.format) == "string", "bad breakpoint")
			local _, n = bp.format:gsub("%%[%d%.]*[dfs]", "")
			assert(n <= 1, "at most one numeric specifier without components")
			self.breakpoints[#self.breakpoints + 1] = bp
		end
		function f:FormatNumber(n)
			local best
			for _, bp in ipairs(self.breakpoints) do if n >= bp.threshold and (not best or bp.threshold >= best.threshold) then best = bp end end
			assert(best, "no breakpoint for value " .. tostring(n))
			if best.format:find("%%") then return string.format(best.format, n) end
			return best.format
		end
		return f
	end,
}

-- Timers run immediately or on demand
stub.timers = {}
C_Timer = {
	After = function(delay, fn) stub.timers[#stub.timers + 1] = { fn = fn } end,
	NewTimer = function(delay, fn)
		local t = { fn = fn }
		function t:Cancel() self.cancelled = true end
		stub.timers[#stub.timers + 1] = t
		return t
	end,
	NewTicker = function(delay, fn)
		local t = { fn = fn, ticker = true }
		function t:Cancel() self.cancelled = true end
		stub.timers[#stub.timers + 1] = t
		return t
	end,
}
function stub.RunTimers()
	local pending = stub.timers
	stub.timers = {}
	for _, t in ipairs(pending) do
		if not t.cancelled then
			t.fn()
			if t.ticker then stub.timers[#stub.timers + 1] = t end
		end
	end
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local Object = {}
Object.__index = Object
local serial = 0

local function NewObject(objType, parent, name)
	serial = serial + 1
	local o = setmetatable({ _type = objType, _parent = parent, _name = name, _shown = true, _points = {}, _children = {}, _level = parent and (parent._level + 1) or 0, _events = {} }, Object)
	if parent then parent._children[#parent._children + 1] = o end
	return o
end

local function IsDescendantOf(obj, owner)
	local p = obj._parent
	while p do
		if p == owner then return true end
		p = p._parent
	end
	return false
end

function Object:IsObjectType(t)
	if self._type == t then return true end
	if t == "Frame" and (self._type == "StatusBar" or self._type == "Cooldown" or self._type == "AuraContainer" or self._type == "AuraButton" or self._type == "Button") then return true end
	if t == "Region" and self._type ~= "AnimationGroup" then return true end
	return false
end
function Object:GetObjectType() return self._type end
function Object:GetName() return self._name end
function Object:GetDebugName() return self._name or ("anon " .. self._type) end
function Object:GetParent() return self._parent end
function Object:SetSize(w, h) assert(type(w) == "number" and type(h) == "number", "SetSize needs numbers") self._w, self._h = w, h end
function Object:SetWidth(w) self._w = w end
function Object:SetHeight(h) self._h = h end
function Object:GetSize() return self._w or 0, self._h or 0 end
function Object:SetPoint(point, rel, relPoint, x, y)
	assert(type(point) == "string", "SetPoint: point must be a string")
	if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
	if rel ~= nil then assert(type(rel) == "table" and rel._type, "SetPoint: relativeTo must be a frame") end
	self._points[#self._points + 1] = { point, rel, relPoint, x or 0, y or 0 }
end
function Object:SetAllPoints(rel) self._points[#self._points + 1] = { "ALL", rel } end
function Object:ClearAllPoints() self._points = {} end
function Object:GetPoint(i) local p = self._points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
function Object:Show() self._shown = true end
function Object:Hide() self._shown = false end
function Object:SetShown(s) self._shown = s and true or false end
function Object:IsShown() return self._shown end
function Object:SetScale(s) assert(type(s) == "number") self._scale = s end
function Object:SetFrameStrata(s) self._strata = s end
function Object:SetFrameLevel(l) assert(type(l) == "number") self._level = l end
function Object:GetFrameLevel() return self._level end
function Object:SetMovable(b) self._movable = b end
function Object:SetClampedToScreen(b) end
function Object:RegisterForDrag(...) end
function Object:EnableMouse(b) self._mouse = b end
function Object:StartMoving() end
function Object:StopMovingOrSizing() end
function Object:SetScript(name, fn) assert(fn == nil or type(fn) == "function") self["_script_" .. name] = fn end
function Object:RegisterEvent(ev) self._events[ev] = true end
function Object:UnregisterEvent(ev) self._events[ev] = nil end
function Object:IsEventRegistered(ev) return self._events[ev] == true end
function Object:CreateTexture(name, layer, template, subLevel)
	if subLevel ~= nil then assert(type(subLevel) == "number" and subLevel >= -8 and subLevel <= 7, "texture subLevel must be -8..7") end
	local t = NewObject("Texture", self, name) t._layer = layer return t
end
function Object:SetVertexColor(r, g, b, a) assert(type(r) == "number" and type(g) == "number" and type(b) == "number") end
function Object:SetMouseClickEnabled(b) end
function Object:CreateFontString(name, layer) local f = NewObject("FontString", self, name) f._layer = layer return f end
-- Texture
function Object:SetColorTexture(r, g, b, a) assert(self._type == "Texture") end
function Object:SetTexture(t) self._tex = t end
function Object:SetTexCoord(...) end
function Object:SetAlpha(a) assert(type(a) == "number") end
-- FontString
function Object:SetFont(path, size, flags) assert(type(path) == "string" and type(size) == "number" and type(flags) == "string", "SetFont(path, size, flags) is required in 10.0+") end
function Object:SetShadowColor() end
function Object:SetShadowOffset() end
function Object:SetJustifyH() end
function Object:SetJustifyV() end
function Object:SetTextColor(r, g, b, a) assert(type(r) == "number" and type(g) == "number" and type(b) == "number") end
function Object:SetText(t) self._text = t end
function Object:GetText() return self._text end
-- StatusBar
function Object:SetStatusBarTexture(t) assert(self._type == "StatusBar") self._fill = NewObject("Texture", self) end
function Object:GetStatusBarTexture() return self._fill end
function Object:SetStatusBarColor(r, g, b, a) assert(self._type == "StatusBar") end
function Object:SetMinMaxValues(a, b) assert(self._type == "StatusBar") self._min, self._max = a, b end
function Object:SetValue(v) assert(self._type == "StatusBar") self._value = v end
function Object:GetValue() return self._value end
-- Cooldown
function Object:SetDrawEdge() end
function Object:SetDrawBling() end
function Object:SetHideCountdownNumbers() end
function Object:SetReverse() end
function Object:SetUsingParentLevel(b) assert(type(b) == "boolean") end

----------------------------------------------------------------------
-- AuraContainer / AuraButton emulation with Blizzard's validation
----------------------------------------------------------------------
local function IsNonNegativeNumber(v) return type(v) == "number" and v >= 0 end

local function ValidateCandidateFilters(cf)
	assert(cf == nil or type(cf) == "table", "candidateFilters must be a table or nil.")
	if cf == nil then return end
	for _, k in ipairs({ "includeSpellIDs", "excludeSpellIDs", "includeDispelTypes", "excludeDispelTypes" }) do
		if cf[k] ~= nil then assert(type(cf[k]) == "table", k .. " must be a table or nil") end
	end
	if cf.maxDuration ~= nil then assert(IsNonNegativeNumber(cf.maxDuration)) end
	for _, k in ipairs({ "isFromPlayerOrPlayerPet", "isRoleAura", "isPriorityAura", "isStealable", "nameplateShowAll", "nameplateShowPersonal", "canApplyAura", "isBossAura", "isBossOrRoleAura" }) do
		if cf[k] ~= nil then assert(type(cf[k]) == "boolean", k .. " must be a boolean or nil.") end
	end
	for k in pairs(cf) do
		local known = { includeSpellIDs = 1, excludeSpellIDs = 1, includeDispelTypes = 1, excludeDispelTypes = 1, maxDuration = 1, processedAuraType = 1, isFromPlayerOrPlayerPet = 1, isRoleAura = 1, isPriorityAura = 1, isStealable = 1, nameplateShowAll = 1, nameplateShowPersonal = 1, canApplyAura = 1, isBossAura = 1, isBossOrRoleAura = 1 }
		assert(known[k], "unknown candidateFilters key: " .. tostring(k))
	end
end

local function ValidateLayout(l)
	if l == nil then return end
	assert(type(l) == "table", "layout must be a table or nil.")
	for _, k in ipairs({ "elementSpacing", "lineSpacing", "groupSpacing", "groupLineSpacing" }) do
		if l[k] ~= nil then assert(type(l[k]) == "number", k .. " must be a number.") end
	end
	if l.forceNewLine ~= nil then assert(type(l.forceNewLine) == "boolean") end
	if l.elementWidth ~= nil then assert(IsNonNegativeNumber(l.elementWidth), "elementWidth must be a non-negative number.") end
	if l.elementHeight ~= nil then assert(IsNonNegativeNumber(l.elementHeight), "elementHeight must be a non-negative number.") end
	if l.layoutIndex ~= nil then assert(type(l.layoutIndex) == "number") end
end

local VALID_FILTERS = { HELPFUL = 1, HARMFUL = 1, PLAYER = 1, RAID = 1, RAID_PLAYER_DISPELLABLE = 1, RAID_IN_COMBAT = 1, CANCELABLE = 1, INCLUDE_NAME_PLATE_ONLY = 1, MAW = 1, EXTERNAL_DEFENSIVE = 1, BIG_DEFENSIVE = 1, CROWD_CONTROL = 1, IMPORTANT = 1, DISPELLABLE = 1 }
local function ValidateFilterString(s)
	assert(type(s) == "string" and s ~= "", "filter string required")
	for token in s:gmatch("[^|]+") do
		token = token:gsub("^!", "")
		assert(VALID_FILTERS[token], "invalid aura filter token: " .. token)
	end
end

local function ValidateDisplayOptions(o)
	if o.templateNames ~= nil then assert(type(o.templateNames) == "table") end
	if o.initializeFrame ~= nil then assert(type(o.initializeFrame) == "function", "initializeFrame must be a function or nil.") end
	ValidateCandidateFilters(o.candidateFilters)
	local sm = o.sortMethod or 0
	local sd = o.sortDirection or 0
	local okm, okd = false, false
	for _, v in pairs(AuraContainerSortMethod) do if v == sm then okm = true end end
	for _, v in pairs(AuraContainerSortDirection) do if v == sd then okd = true end end
	assert(okm, "sortMethod must be a valid AuraContainerSortMethod.")
	assert(okd, "sortDirection must be a valid AuraContainerSortDirection.")
end

local function ValidateInbound(obj, owner, requiredType)
	assert(type(obj) == "table" and obj._type, "bad object in function call")
	assert(obj:IsObjectType(requiredType), string.format("bad object (expected %s, got %s)", requiredType, obj._type))
	assert(IsDescendantOf(obj, owner), "bad object in function call (must be a direct or indirect descendant of owner)")
end

local AuraButton = setmetatable({}, { __index = Object })
AuraButton.__index = AuraButton
function AuraButton:SetIcon(tex) ValidateInbound(tex, self, "Texture") self._icon = tex end
function AuraButton:SetDurationCooldown(cd) ValidateInbound(cd, self, "Cooldown") self._cd = cd end
function AuraButton:SetApplicationCount(fs, options)
	ValidateInbound(fs, self, "FontString")
	if options ~= nil then
		assert(type(options) == "table", "options must be a table")
		if options.formatter ~= nil then assert(type(options.formatter) == "table" and options.formatter.FormatNumber, "formatter must be a NumericFormatter") end
	end
	self._count = fs
	self._countOptions = options
end
function AuraButton:SetApplicationBar(bar, options)
	ValidateInbound(bar, self, "StatusBar")
	assert(type(options) == "table" and type(options.maxApplications) == "number", "maxApplications is required")
	if options.minApplications ~= nil then assert(type(options.minApplications) == "number") end
	if options.interpolation ~= nil then assert(options.interpolation == 0 or options.interpolation == 1) end
	self._bar = bar
	self._barOptions = options
end
function AuraButton:CanBeAccessedInContext() return true end
function AuraButton:SetHideTooltipInCombat(b) assert(type(b) == "boolean", "SetHideTooltipInCombat needs a boolean") end

-- Simulate Blizzard applying aura data to a button
function AuraButton:_Apply(auraData)
	local applications = auraData and auraData.applications or 0
	if self._bar then
		local minA = self._barOptions.minApplications or 0
		self._bar:SetMinMaxValues(minA, math.max(self._barOptions.maxApplications, 1))
		self._bar:SetValue(applications)
		self._bar:SetShown(applications >= minA)
	end
	if self._count then
		local text = ""
		if auraData then
			if self._countOptions and self._countOptions.formatter then
				text = self._countOptions.formatter:FormatNumber(applications)
			elseif applications > 1 then
				text = applications
			end
		end
		self._count:SetText(text)
	end
	if self._icon and auraData then self._icon:SetTexture(auraData.icon) end
	self:SetShown(auraData ~= nil)
end

local AuraContainer = setmetatable({}, { __index = Object })
AuraContainer.__index = AuraContainer
stub.containers = {}
function AuraContainer:AddAuraGroup(groupKey, filterString, options)
	assert(type(groupKey) == "string" and groupKey ~= "", "groupKey must be a non-empty string.")
	ValidateFilterString(filterString)
	assert(not self._groups[groupKey], "aura group already exists")
	assert(type(options) == "table", "options must be a table")
	ValidateDisplayOptions(options)
	ValidateLayout(options.layout)
	assert(options.maxFrameCount == nil or (type(options.maxFrameCount) == "number" and options.maxFrameCount >= 0), "maxFrameCount must be a non-negative integer or infinity.")
	local group = { key = groupKey, filter = filterString, options = options, frames = {} }
	-- Blizzard pre-creates a batch of 10 frames and runs initializeFrame on each
	for i = 1, 10 do
		local btn = setmetatable(NewObject("AuraButton", self), AuraButton)
		if options.initializeFrame then options.initializeFrame(btn) end
		group.frames[i] = btn
	end
	self._groups[groupKey] = group
	note("AddAuraGroup %s on %s (max %s, boss=%s)", groupKey, self._name, tostring(options.maxFrameCount), tostring(options.candidateFilters and options.candidateFilters.isBossAura))
end
function AuraContainer:AddAuraSlot(slotKey, filterString, options)
	ValidateFilterString(filterString)
	assert(type(options) == "table")
	ValidateDisplayOptions(options)
	local btn = setmetatable(NewObject("AuraButton", self), AuraButton)
	if options.initializeFrame then options.initializeFrame(btn) end
	self._slots[slotKey] = btn
	return btn
end
function AuraContainer:SetUnit(u) assert(type(u) == "string") self._unit = u end
function AuraContainer:SetEnabled(e) assert(type(e) == "boolean") self._enabled = e end
function AuraContainer:SetFlowLayoutAnchorPoint(p) assert(type(p) == "string") end
function AuraContainer:SetFlowLayoutGrowthDirection(h, v)
	local ok = { [-1] = true, [1] = true }
	assert(ok[h] and ok[v], "growth direction must be valid")
end
-- Simulate the aura system handing a list of auras to every group
function AuraContainer:_Apply(auras)
	for _, group in pairs(self._groups) do
		local shown = 0
		for i, btn in ipairs(group.frames) do
			local aura = auras[i]
			if aura and shown < (group.options.maxFrameCount or math.huge) then
				btn:_Apply(aura)
				shown = shown + 1
			else
				btn:_Apply(nil)
			end
		end
	end
end

function CreateFrame(frameType, name, parent, template)
	assert(type(frameType) == "string", "CreateFrame: frameType must be a string")
	if frameType == "AuraContainer" then
		assert(template == "CustomAuraContainerTemplate", "AuraContainer needs CustomAuraContainerTemplate")
		local c = setmetatable(NewObject("AuraContainer", parent, name), AuraContainer)
		c._groups, c._slots = {}, {}
		stub.containers[#stub.containers + 1] = c
		return c
	end
	if frameType == "Cooldown" then
		assert(template == "CooldownFrameTemplate", "Cooldown should use CooldownFrameTemplate")
	end
	assert(frameType == "Frame" or frameType == "StatusBar" or frameType == "Cooldown" or frameType == "Button", "unexpected frame type " .. frameType)
	if frameType == "Button" then
		-- Templates verified in Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml
		assert(template == nil or template == "UIPanelButtonTemplate" or template == "UIPanelCloseButton", "unverified button template " .. tostring(template))
	else
		assert(template == nil or template == "CooldownFrameTemplate", "unverified frame template " .. tostring(template))
	end
	return NewObject(frameType, parent, name)
end
UIParent = NewObject("Frame", nil, "UIParent")

----------------------------------------------------------------------
-- Settings API stub mirroring Blizzard_Settings.lua signatures
----------------------------------------------------------------------
stub.settings = {}
local Category = {}
Category.__index = Category
function Category:GetID() return self.id end
local Layout = {}
Layout.__index = Layout
function Layout:AddInitializer(init) self.inits[#self.inits + 1] = init end

Settings = {
	VarType = { Boolean = "boolean", String = "string", Number = "number" },
	RegisterVerticalLayoutCategory = function(name)
		assert(type(name) == "string")
		return setmetatable({ id = "cat_" .. name, name = name }, Category), setmetatable({ inits = {} }, Layout)
	end,
	RegisterAddOnSetting = function(categoryTbl, variable, variableKey, variableTbl, variableType, name, defaultValue)
		assert(getmetatable(categoryTbl) == Category, "categoryTbl must be a category")
		assert(type(variable) == "string", "variable must be a string")
		assert(type(variableKey) == "string", "variableKey must be a string")
		assert(type(variableTbl) == "table", "'variableTbl' argument must be a table.")
		assert(variableType == "boolean" or variableType == "number" or variableType == "string", "bad variableType")
		assert(type(name) == "string", "name must be a string")
		assert(type(defaultValue) == variableType, "default type mismatch for " .. variableKey)
		assert(variableTbl[variableKey] == nil or type(variableTbl[variableKey]) == variableType, "stored value type mismatch for " .. variableKey)
		local s = { variable = variable, key = variableKey, tbl = variableTbl, type = variableType }
		function s:SetValueChangedCallback(cb) assert(type(cb) == "function") self.cb = cb end
		function s:SetValue(v) self.tbl[self.key] = v if self.cb then self.cb(self, v) end end
		function s:GetValue() return self.tbl[self.key] end
		stub.settings[variableKey] = s
		return s
	end,
	RegisterAddOnCategory = function(cat) assert(getmetatable(cat) == Category) stub.categoryRegistered = true end,
	OpenToCategory = function(id) assert(type(id) == "string") stub.opened = id end,
	CreateSliderOptions = function(minValue, maxValue, rate)
		local o = { minValue = minValue, maxValue = maxValue, steps = (rate and (maxValue - minValue) / rate) or 100 }
		function o:SetLabelFormatter(labelType, value) assert(labelType ~= nil) self.formatter = value end
		return o
	end,
	CreateControlTextContainer = function()
		local c = { data = {} }
		function c:Add(value, label, tooltip) assert(value ~= nil and type(label) == "string") self.data[#self.data + 1] = { value = value, label = label } end
		function c:GetData() return self.data end
		return c
	end,
	CreateCheckbox = function(category, setting, tooltip) assert(setting and setting.type == "boolean", "checkbox needs a boolean setting") end,
	CreateSlider = function(category, setting, options, tooltip)
		assert(setting and setting.type == "number", "slider needs a number setting")
		assert(type(options) == "table" and options.minValue and options.maxValue, "slider needs options")
		if options.formatter then assert(type(options.formatter(options.minValue)) == "string") end
	end,
	CreateDropdown = function(category, setting, optionsFunc, tooltip)
		assert(setting and setting.type == "string", "dropdown needs a string setting")
		assert(type(optionsFunc) == "function")
		local data = optionsFunc()
		assert(#data > 0)
	end,
}
-- EventRegistry (Blizzard_SharedXMLBase/CallbackRegistry.lua). Edit Mode
-- triggers "EditMode.Enter" / "EditMode.Exit" (Blizzard_EditMode/Shared/EditModeManager.lua).
stub.callbacks = {}
EventRegistry = {
	RegisterCallback = function(self, event, func, owner, ...)
		assert(self == EventRegistry, "RegisterCallback must be called with a colon")
		assert(type(event) == "string", "CallbackRegistryMixin::RegisterCallback 'event' requires string type.")
		assert(type(func) == "function", "CallbackRegistryMixin::RegisterCallback 'func' requires function type.")
		assert(type(owner) ~= "number", "'owner' as number is reserved internally.")
		stub.callbacks[event] = stub.callbacks[event] or {}
		stub.callbacks[event][owner or func] = func
	end,
}
function stub.TriggerCallback(event, ...)
	for owner, func in pairs(stub.callbacks[event] or {}) do func(owner, ...) end
end

MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3 } }
function CreateSettingsListSectionHeaderInitializer(text) assert(type(text) == "string") return { header = text } end

----------------------------------------------------------------------
-- Addon loading helpers
----------------------------------------------------------------------
stub.frames = {}
local realCreateFrame = CreateFrame
function CreateFrame(...)
	local f = realCreateFrame(...)
	stub.frames[#stub.frames + 1] = f
	return f
end

function stub.FireEvent(event, ...)
	for _, f in ipairs(stub.frames) do
		if f._events[event] and f._script_OnEvent then
			f._script_OnEvent(f, event, ...)
		end
	end
end

function stub.LoadAddon(dir, addonName, files)
	local ns = {}
	for _, file in ipairs(files) do
		local chunk, err = loadfile(dir .. "/" .. file)
		assert(chunk, err)
		chunk(addonName, ns)
	end
	return ns
end

return stub
