--[[
	StackWatch - Options.lua
	Settings panel (Esc > Options > AddOns > StackWatch), built on Blizzard's
	Settings API. No libraries.
]]

local _, ns = ...

local INTEGER_KEYS = {
	iconSize = true, spacing = true, maxIcons = true, borderSize = true,
	cautionStacks = true, dangerStacks = true, maxStacks = true,
}

-- Slider ranges, shared by the settings panel and the quick-settings HUD.
-- { min, max, step }
ns.RANGES = {
	scale = { 0.5, 2.0, 0.05 },
	cautionStacks = { 1, 30, 1 },
	dangerStacks = { 1, 30, 1 },
	maxStacks = { 2, 30, 1 },
	iconSize = { 24, 96, 2 },
	spacing = { 0, 24, 1 },
	maxIcons = { 1, 6, 1 },
	countFontScale = { 0.3, 0.9, 0.05 },
	borderSize = { 0, 6, 1 },
}

-- Registered Blizzard setting objects by key, so other UI can change a
-- value through the setting and keep the settings panel in sync.
ns.settingObjects = {}

local function OnSettingChanged(key, value)
	local db = ns.db
	if INTEGER_KEYS[key] and type(value) == "number" then
		value = math.floor(value + 0.5)
	end
	db[key] = value
	if key == "locked" then
		ns.SetAnchorLocked(value)
	elseif key == "scale" then
		ns.ApplyAnchorPosition()
		if ns.demoActive then
			ns.RefreshDemo()
		end
	elseif key == "soundOnStack" then
		ns.UpdateSounds()
	else
		ns.RequestRebuild()
	end
end

-- Change one option from anywhere (HUD, slash commands). Goes through the
-- Blizzard setting when one exists so the panel shows the new value.
function ns.SetOption(key, value)
	local range = ns.RANGES[key]
	if range and type(value) == "number" then
		value = math.min(range[2], math.max(range[1], value))
		if range[3] >= 1 then
			value = math.floor(value + 0.5)
		else
			value = math.floor(value / range[3] + 0.5) * range[3]
		end
	end
	local setting = ns.settingObjects[key]
	if setting then
		setting:SetValue(value)
	else
		OnSettingChanged(key, value)
	end
end

function ns.SetupOptions()
	if ns.optionsCategory then
		return
	end
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end

	local db = ns.db
	local category, layout = Settings.RegisterVerticalLayoutCategory("StackWatch")
	ns.optionsCategory = category

	local function Header(text)
		if layout and CreateSettingsListSectionHeaderInitializer then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
		end
	end

	local function Bool(key, name, tooltip)
		local setting = Settings.RegisterAddOnSetting(category, "StackWatch_" .. key, key, db, Settings.VarType.Boolean, name, ns.DEFAULTS[key])
		setting:SetValueChangedCallback(function(_, value)
			OnSettingChanged(key, value)
		end)
		ns.settingObjects[key] = setting
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	local function Num(key, name, tooltip, suffix)
		local minValue, maxValue, step = ns.RANGES[key][1], ns.RANGES[key][2], ns.RANGES[key][3]
		local setting = Settings.RegisterAddOnSetting(category, "StackWatch_" .. key, key, db, Settings.VarType.Number, name, ns.DEFAULTS[key])
		setting:SetValueChangedCallback(function(_, value)
			OnSettingChanged(key, value)
		end)
		ns.settingObjects[key] = setting
		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and options.SetLabelFormatter then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
				if step >= 1 then
					return string.format("%d%s", math.floor(value + 0.5), suffix or "")
				end
				return string.format("%.2f%s", value, suffix or "")
			end)
		end
		Settings.CreateSlider(category, setting, options, tooltip)
	end

	local function Choice(key, name, tooltip, entries)
		local setting = Settings.RegisterAddOnSetting(category, "StackWatch_" .. key, key, db, Settings.VarType.String, name, ns.DEFAULTS[key])
		setting:SetValueChangedCallback(function(_, value)
			OnSettingChanged(key, value)
		end)
		ns.settingObjects[key] = setting
		local function GetOptions()
			local container = Settings.CreateControlTextContainer()
			for _, e in ipairs(entries) do
				container:Add(e[1], e[2], e[3])
			end
			return container:GetData()
		end
		Settings.CreateDropdown(category, setting, GetOptions, tooltip)
	end

	Header("Position")
	Bool("locked", "Lock position", "Uncheck to show a drag handle. Drag it where you want the tracker, then lock again. You can also type /sw unlock and /sw lock.")
	Num("scale", "Scale", "Overall scale of the tracker.", "x")
	Choice("growth", "Growth direction", "Which way extra icons are added when you carry more than one boss debuff.", {
		{ "RIGHT", "Grow right" },
		{ "LEFT", "Grow left" },
	})

	Header("Thresholds")
	Num("cautionStacks", "Caution at", "Stacks at which the icon and number turn orange. Twin Fangs Mythic default: 5.", " stacks")
	Num("dangerStacks", "Danger at", "Stacks at which the icon and number turn red. Twin Fangs Mythic default: 8 (death is 10).", " stacks")
	Num("maxStacks", "Bar maximum", "The stack count that fills the bar completely. Twin Fangs: 10.", " stacks")

	Header("Look")
	Num("iconSize", "Icon size", "Size of each icon in pixels.", " px")
	Num("spacing", "Icon spacing", "Gap between icons.", " px")
	Num("maxIcons", "Maximum icons", "How many boss debuffs to show at once. Permanent debuffs such as Eternal Venom always sort first.", "")
	Num("countFontScale", "Number size", "Height of the stack number as a fraction of the icon.", "")
	Num("borderSize", "Border thickness", "Thickness of the colored border at caution and danger.", " px")
	Bool("tintIcon", "Tint icon at thresholds", "Wash the icon with the threshold color in addition to the border and number.")
	Bool("dangerMarker", "Red X markers at danger", "Show the red X raid marker in both top corners of the icon at danger stacks, so it reads X 8 X. Only on your screen.")
	Bool("showStackBar", "Show stack bar", "A small bar under the icon that fills toward the bar maximum, with tick marks at your thresholds.")
	Bool("showCooldownSwipe", "Show duration swipe", "Cooldown swipe on debuffs that have a duration. Permanent debuffs show no swipe.")
	Bool("showCountForOne", "Show the number at 1 stack", "Off makes the number appear from 2 stacks, like Blizzard's own frames. On shows 1 as soon as the debuff lands.")

	Header("Filtering")
	Bool("bossOnly", "Boss debuffs only", "Only show debuffs the encounter flags as boss auras. Turn off to show every debuff on you (Sated and similar are filtered out).")

	Header("Raid lead")
	Bool("raidReport", "Report after each boss", "When you are the raid leader, print who took the most avoidable damage and from which spells after every boss pull. Only you see it; nothing is sent to the raid. Needs Blizzard's damage meter turned on. Anyone can type /sw report to see the last one.")

	Header("Sound")
	Bool("soundOnStack", "Sound on stack gain", "Play a short tick every time a tracked debuff gains a stack. Tracked spells: /sw sound list. Default list is Eternal Venom.")

	Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
	if ns.optionsCategory and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.optionsCategory:GetID())
	else
		ns.Print("options are not available yet.")
	end
end
