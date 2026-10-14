// StackWatch compatibility check against Blizzard's live UI source.
//
// Downloads the Blizzard files StackWatch depends on from the
// Gethe/wow-ui-source mirror and confirms every API, event, enum, template
// and secure-code behavior the addon relies on is still there. Also compares
// the game's interface version with the .toc.
//
//   node tests/compat_check.mjs            check the live branch
//   node tests/compat_check.mjs ptr2       check another branch
//
// Exit code 0 = compatible, 1 = something needs attention. The report is
// printed as Markdown so CI can paste it into a GitHub issue.
// Node 18+ (global fetch). No dependencies.

import { readFileSync } from "node:fs";

const BRANCH = process.argv[2] || "live";
const RAW = `https://raw.githubusercontent.com/Gethe/wow-ui-source/${BRANCH}/`;
const DOCS = "Interface/AddOns/Blizzard_APIDocumentationGenerated/";

// Each check: file, a regex that must match, and why StackWatch needs it.
const CHECKS = [
	// Aura containers: the whole display
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua", /function\s+\w+:ApplyApplicationBar/, "threshold gates (ApplyApplicationBar)"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua", /SetShown\([^)]*>=\s*[^)]*minApplications/, "gates shown when applications >= minApplications (the threshold colors depend on this exact line)"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua", /function\s+\w+:SetIcon\b/, "SetIcon"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua", /function\s+\w+:SetDurationCooldown\b/, "SetDurationCooldown"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua", /function\s+\w+:SetApplicationCount\b/, "SetApplicationCount"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua", /function\s+\w+:SetApplicationBar\b/, "SetApplicationBar"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraButton.lua", /SetHideTooltipInCombat/, "SetHideTooltipInCombat"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua", /function\s+\w+:AddAuraGroup\b/, "AddAuraGroup"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua", /initializeFrame/, "initializeFrame callback"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua", /isBossAura/, "isBossAura candidate filter"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua", /excludeSpellIDs/, "excludeSpellIDs candidate filter (/sw all)"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerShared.lua", /ExpirationOnly/, "AuraContainerSortMethod.ExpirationOnly"],
	["Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerShared.lua", /Reverse/, "AuraContainerSortDirection.Reverse"],

	// Aura sounds, secrecy, restrictions
	[DOCS + "UnitAuraDocumentation.lua", /Name = "AddAuraSound"/, "C_UnitAuras.AddAuraSound"],
	[DOCS + "UnitAuraDocumentation.lua", /Name = "RemoveAuraSound"/, "C_UnitAuras.RemoveAuraSound"],
	[DOCS + "UnitAuraDocumentation.lua", /Name = "AuraIsPrivate"/, "C_UnitAuras.AuraIsPrivate (/sw status)"],
	[DOCS + "UnitAuraConstantsDocumentation.lua", /Name = "ApplicationsIncreased"/, "Enum.UnitAuraSoundTrigger.ApplicationsIncreased"],
	[DOCS + "SecretPredicateAPIDocumentation.lua", /Name = "GetSpellAuraSecrecy"/, "C_Secrets.GetSpellAuraSecrecy (/sw status)"],
	[DOCS + "RestrictedActionsDocumentation.lua", /Name = "IsAddOnRestrictionActive"/, "C_RestrictedActions.IsAddOnRestrictionActive"],
	[DOCS + "RestrictedActionsDocumentation.lua", /ADDON_RESTRICTION_STATE_CHANGED/, "ADDON_RESTRICTION_STATE_CHANGED event"],
	[DOCS + "StringUtilDocumentation.lua", /Name = "CreateNumericRuleFormatter"/, "C_StringUtil.CreateNumericRuleFormatter (count formatter)"],
	[DOCS + "EncounterInfoDocumentation.lua", /ENCOUNTER_END/, "ENCOUNTER_END event (raid lead report)"],
	[DOCS + "DamageMeterDocumentation.lua", /Name = "GetCombatSessionFromType"/, "C_DamageMeter.GetCombatSessionFromType (raid lead report)"],

	// Settings panel
	["Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua", /function Settings\.RegisterAddOnSetting\(categoryTbl, variable, variableKey, variableTbl, variableType, name, defaultValue\)/, "Settings.RegisterAddOnSetting signature"],
	["Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua", /function Settings\.CreateSlider\(/, "Settings.CreateSlider"],
	["Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua", /function Settings\.CreateCheckbox\(/, "Settings.CreateCheckbox"],
	["Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua", /function Settings\.CreateDropdown\(/, "Settings.CreateDropdown"],

	// Edit Mode, HUD templates, markers
	["Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua", /TriggerEvent\("EditMode\.Enter"\)/, "EditMode.Enter callback"],
	["Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua", /TriggerEvent\("EditMode\.Exit"\)/, "EditMode.Exit callback"],
	["Interface/AddOns/Blizzard_SharedXMLBase/CallbackRegistry.lua", /secureexecuterange\(funcs/, "EventRegistry callbacks run through secureexecuterange (no taint into Edit Mode)"],
	["Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml", /name="UIPanelButtonTemplate"/, "UIPanelButtonTemplate (HUD)"],
	["Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml", /name="UIPanelCloseButton"/, "UIPanelCloseButton (HUD)"],
	["Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameConstants.lua", /UI-RaidTargetingIcon_7/, "red X raid marker texture path"],
];

// Candidate filter keys the smoke-test stub validates. If Blizzard adds or
// removes one, the stub (and maybe the addon) needs a look.
const KNOWN_FILTER_KEYS = [
	"includeSpellIDs", "excludeSpellIDs", "includeDispelTypes", "excludeDispelTypes", "maxDuration",
	"processedAuraType", "isFromPlayerOrPlayerPet", "isRoleAura", "isPriorityAura", "isStealable",
	"nameplateShowAll", "nameplateShowPersonal", "canApplyAura", "isBossAura", "isBossOrRoleAura",
];

const cache = new Map();
async function get(path) {
	if (cache.has(path)) return cache.get(path);
	let text = null;
	for (let attempt = 0; attempt < 3 && text === null; attempt++) {
		const res = await fetch(RAW + path);
		if (res.ok) text = await res.text();
		else if (res.status === 404) break;
	}
	cache.set(path, text);
	return text;
}

function interfaceFromVersion(v) {
	const [major, minor, patch] = v.split(".").map(Number);
	return major * 10000 + minor * 100 + patch;
}

const failures = [];
const warnings = [];

const version = (await get("version.txt"))?.trim();
if (!version) {
	console.log(`Could not read version.txt on branch "${BRANCH}".`);
	process.exit(1);
}
const gameInterface = interfaceFromVersion(version);
const toc = readFileSync(new URL("../StackWatch.toc", import.meta.url), "utf8");
const tocInterfaces = (toc.match(/^## Interface:\s*(.+)$/m)?.[1] || "").split(",").map((s) => Number(s.trim()));
if (!tocInterfaces.includes(gameInterface)) {
	failures.push(`Game interface ${gameInterface} (build ${version}) is not in StackWatch.toc (\`## Interface: ${tocInterfaces.join(", ")}\`). The addon will show as out of date until the .toc is bumped.`);
}

for (const [file, pattern, why] of CHECKS) {
	const text = await get(file);
	if (text === null) failures.push(`Missing file \`${file}\` (needed for: ${why})`);
	else if (!pattern.test(text)) failures.push(`\`${file}\` no longer matches ${pattern} (needed for: ${why})`);
}

const container = await get("Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua");
if (container) {
	// Keys accessed as candidateFilters.<key> or options.<key> inside the validator.
	const found = new Set([...container.matchAll(/candidateFilters\.(\w+)/g)].map((m) => m[1]));
	const added = [...found].filter((k) => !KNOWN_FILTER_KEYS.includes(k));
	if (added.length) warnings.push(`New candidateFilters keys in Blizzard's container: ${added.join(", ")}. Update tests/wow_stub.lua.`);
}

console.log(`## StackWatch compatibility: ${BRANCH} ${version}\n`);
if (failures.length === 0) console.log("All checks passed.\n");
for (const f of failures) console.log(`- FAIL: ${f}`);
for (const w of warnings) console.log(`- WARN: ${w}`);
console.log(`\n${CHECKS.length} source checks, interface ${gameInterface}.`);
process.exit(failures.length ? 1 : 0);
