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
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	local function Num(key, name, tooltip, minValue, maxValue, step, suffix)
		local setting = Settings.RegisterAddOnSetting(category, "StackWatch_" .. key, key, db, Settings.VarType.Number, name, ns.DEFAULTS[key])
		setting:SetValueChangedCallback(function(_, value)
			OnSettingChanged(key, value)
		end)
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
	Num("scale", "Scale", "Overall scale of the tracker.", 0.5, 2.0, 0.05, "x")
	Choice("growth", "Growth direction", "Which way extra icons are added when you carry more than one boss debuff.", {
		{ "RIGHT", "Grow right" },
		{ "LEFT", "Grow left" },
	})

	Header("Thresholds")
	Num("cautionStacks", "Caution at", "Stacks at which the icon and number turn orange. Twin Fangs Mythic default: 5.", 1, 30, 1, " stacks")
	Num("dangerStacks", "Danger at", "Stacks at which the icon and number turn red. Twin Fangs Mythic default: 8 (death is 10).", 1, 30, 1, " stacks")
	Num("maxStacks", "Bar maximum", "The stack count that fills the bar completely. Twin Fangs: 10.", 2, 30, 1, " stacks")

	Header("Look")
	Num("iconSize", "Icon size", "Size of each icon in pixels.", 24, 96, 2, " px")
	Num("spacing", "Icon spacing", "Gap between icons.", 0, 24, 1, " px")
	Num("maxIcons", "Maximum icons", "How many boss debuffs to show at once. Permanent debuffs such as Eternal Venom always sort first.", 1, 6, 1, "")
	Num("countFontScale", "Number size", "Height of the stack number as a fraction of the icon.", 0.3, 0.9, 0.05, "")
	Num("borderSize", "Border thickness", "Thickness of the colored border at caution and danger.", 0, 6, 1, " px")
	Bool("tintIcon", "Tint icon at thresholds", "Wash the icon with the threshold color in addition to the border and number.")
	Bool("showStackBar", "Show stack bar", "A small bar under the icon that fills toward the bar maximum, with tick marks at your thresholds.")
	Bool("showCooldownSwipe", "Show duration swipe", "Cooldown swipe on debuffs that have a duration. Permanent debuffs show no swipe.")
	Bool("showCountForOne", "Show the number at 1 stack", "Off makes the number appear from 2 stacks, like Blizzard's own frames. On shows 1 as soon as the debuff lands.")

	Header("Filtering")
	Bool("bossOnly", "Boss debuffs only", "Only show debuffs the encounter flags as boss auras. Turn off to show every debuff on you (Sated and similar are filtered out).")

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
