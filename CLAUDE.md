# StackWatch, a World of Warcraft addon (Midnight 12.1.5)

You are working on a shipped WoW retail addon that runs in a Mythic raid. A Lua error on a boss pull is the one failure that is not acceptable. Read this whole file before touching code.

## What this addon is

Boss debuff stack tracker with threshold colors. Built for The Twin Fangs (Eternal Venom, spell 1290336: caution at 5, danger at 8, death at 10) and usable on any stacking boss debuff. Owner: Ethan (Gotfleas, Guardian Druid). Shared with his raid guild through GitHub Releases and WowUp.

This folder IS the installed addon: `D:\Wow shit\World of Warcraft\_retail_\Interface\AddOns\StackWatch`. Edits take effect in game after `/reload` (new files or a changed .toc need a full client restart). WoW reads `StackWatch.toc` and loads the Lua files in the order listed there.

## Files

- `StackWatch.toc`: manifest. `## Interface: 120100, 120105`. Bump the Interface line every patch (12.1.5 = 120105). Bump `## Version` on every release and add a CHANGELOG entry.
- `Core.lua`: defaults, SavedVariables merge (`StackWatchDB`), events, slash commands (`/sw`), restriction helpers, rebuild scheduling.
- `Display.lua`: the movable anchor, the three AuraContainers, `ns.BuildLook` (shared by real buttons and the demo), sound registration.
- `Demo.lua`: `/sw test`, fake frames that cycle 0 to max stacks with the real look.
- `Options.lua`: Blizzard Settings API panel. Every setting calls `OnSettingChanged`, which rebuilds out of combat. `ns.RANGES` holds slider ranges; `ns.SetOption(key, value)` changes a value through the Blizzard setting object so every UI stays in sync.
- `Report.lua`: raid lead report. Records damage meter sessions at `ENCOUNTER_START`, then after `ENCOUNTER_END` and once no restriction is active, reads `C_DamageMeter` (AvoidableDamageTaken) and prints a summary to the raid leader's own chat. Never sends chat. Everything guarded with `issecretvalue` and `pcall`.
- `Hud.lua`: quick-settings window (`/sw`, addon compartment, right-click on the handle, click in Edit Mode). Hides on `PLAYER_REGEN_DISABLED`.
- `media/tick.ogg`: stack-gain sound.
- `tests/`: offline smoke test and WoW API stub. Not shipped (ignored by .pkgmeta). `tests/compat_check.mjs` (Node 18+, no deps) checks every Blizzard API, template and secure behavior the addon relies on against Gethe/wow-ui-source and compares the game interface version with the .toc: `node tests/compat_check.mjs [live|ptr|ptr2|beta]`. Add a line to its CHECKS list for every new API.
- `CLAUDE.md`: this file. Not shipped.
- `preview/stackwatch-preview.html`: interactive web preview of the look. Not shipped.
- `.pkgmeta`, `.github/workflows/release.yml`: BigWigs packager. Pushing a git tag like `v1.1.0` builds and attaches the zip to a GitHub Release. `BigWigsMods/packager@v2` reads the token from `GITHUB_OAUTH` (`GH_API_TOKEN` exists only on its master branch) and the job needs `permissions: contents: write`.
- `.github/workflows/tests.yml`: smoke test and live compat check on every push and PR.
- `.github/workflows/build-watch.yml`: daily. For every new build on Gethe's live, ptr, ptr2 or beta branch (test branches only when ahead of live) it runs the compat check and comments on the "Blizzard build watch" issue; failures open their own issue. Scheduled workflows run from `main` only.

All files share one namespace table: `local ADDON_NAME, ns = ...` at the top of every file.

## The rule that shapes everything: secret values

Since 12.0.0, during combat, boss encounters, Mythic+ and PvP, combat APIs hand addon code "secret" values. A secret can be stored, passed to functions, concatenated and handed to widget setters that accept secrets (SetText, SetValue, SetMinMaxValues, SetShown, SetAlpha, SetVertexColor, SetStatusBarColor). It cannot be used in arithmetic, comparisons, boolean tests, `#`, table keys, indexing or calls. Each of those is an immediate Lua error. Since 12.1.0 the entire aura system is secret in those contexts: `UNIT_AURA` payloads, every `AuraData` field except a few booleans, and all `C_UnitAuras` getters. `COMBAT_LOG_EVENT` cannot be registered at all.

Consequences for this codebase:

1. Never read a stack count, duration, health or cooldown and branch on it. If a feature needs "if stacks >= N then do X", it cannot be built. Say so instead of trying.
2. Everything the player sees in combat is drawn by Blizzard's secure code from configuration we set up out of combat. Our Lua runs at login, on settings changes, and on slash commands. It does not run during a pull.
3. Test helpers: `issecretvalue(v)`, `canaccessvalue(v)`, `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.X)`, event `ADDON_RESTRICTION_STATE_CHANGED` (fires before a restriction activates and after it deactivates; `IsAddOnRestrictionActive` is always false during that dispatch, so defer one frame with `C_Timer.After(0, ...)`).
4. Simulate restrictions at a training dummy with CVars: `/run C_CVar.SetCVar("addonEncounterRestrictionsForced", 1)` (also `addonCombatRestrictionsForced`, `addonChallengeModeRestrictionsForced`). Set them back to 0 afterwards; they persist in Config.wtf.

## How the threshold colors work (do not "simplify" this)

Three identical `CustomAuraContainerTemplate` containers are stacked on the anchor. Each has one group: filter `"HARMFUL"`, `candidateFilters = { isBossAura = true }`, `sortMethod = AuraContainerSortMethod.ExpirationOnly`, `sortDirection = AuraContainerSortDirection.Reverse` (permanent auras first), same `maxFrameCount` and layout. Same inputs, same algorithm, so they always show the same auras in the same positions.

- Base layer: `SetIcon`, `SetDurationCooldown`, `SetApplicationCount` (with a NumericRuleFormatter: threshold 0 renders `" "`, threshold 1 renders `"%d"`), `SetApplicationBar` on a real StatusBar with `minApplications = 0`.
- Caution and danger layers: `SetApplicationBar` on an invisible full-size StatusBar ("gate") with `minApplications = threshold`. Blizzard's `CustomAuraButton:ApplyApplicationBar` runs `statusBar:SetShown(applications >= minApplications)` in secure code. The colored border, tint and number are children of the gate, so they appear only at or above the threshold. The comparison happens inside Blizzard's code, never in ours.

Facts verified against Blizzard's live 12.1.5 source (Gethe/wow-ui-source, branch `live`, readable at raw.githubusercontent.com; the GitHub API is blocked from Claude's cloud container but fine from this PC):

- One application bar and one application count per button. Multiple containers can show the same aura.
- `candidateFilters` keys: `includeSpellIDs`, `excludeSpellIDs`, `includeDispelTypes`, `excludeDispelTypes`, `maxDuration`, `processedAuraType`, booleans `isFromPlayerOrPlayerPet`, `isRoleAura`, `isPriorityAura`, `isStealable`, `nameplateShowAll`, `nameplateShowPersonal`, `canApplyAura`, `isBossAura`, `isBossOrRoleAura`. Nothing else; the validator asserts.
- Spell ID filters are ignored for harmful auras on the player unless the spell is `NeverSecret` (`C_Secrets.GetSpellAuraSecrecy`). Eternal Venom is `ContextuallySecret` (checked in game 14 Oct 2026), so `includeSpellIDs` would show nothing. Use `isBossAura`.
- All button configuration must happen inside the `initializeFrame` callback. Blizzard runs it via `securecallfunction` before applying `DenyTaintedAccessWhenAurasAreSecret`. Never keep references to aura buttons and never call methods on them later. Guard any such call with `button:CanBeAccessedInContext()` if you ever must.
- Buttons are pre-created in batches of 10. `maxIcons` is capped at 6 in Options so `initializeFrame` never runs mid-fight.
- Containers cannot be destroyed. A rebuild disables and hides the old ones (`SetEnabled(false)`, `Hide()`). Keep rebuilds debounced and out of combat.
- `AuraContainer` groups add the `UntrustedLayoutScriptExecution` forbidden aspect to the container: other frames cannot be anchored TO the container afterwards. Anchor the container to our frames, never the reverse.
- `C_UnitAuras.AddAuraSound(trigger, info)` is keyed on a spell ID and works for boss debuffs on the player. It is `HasRestrictions`: call it only when no restriction is active, and retry from `ADDON_RESTRICTION_STATE_CHANGED`. `throttleSeconds` max 5.
- Settings API signatures: `Settings.RegisterAddOnSetting(categoryTbl, variable, variableKey, variableTbl, variableType, name, defaultValue)`, `Settings.CreateSlider(category, setting, options, tooltip)`, `Settings.CreateColorSwatch(category, setting, tooltip, options)` (note the order), `setting:SetValueChangedCallback(function(setting, value) end)`.
- `FontString:SetFont(path, size, flags)` requires the flags string since 10.0 (use `""` for none).
- Edit Mode: `EditModeManagerFrameMixin:EnterEditMode/ExitEditMode` end with `EventRegistry:TriggerEvent("EditMode.Enter"/"EditMode.Exit")`. `CallbackRegistryMixin:TriggerEvent` runs function callbacks as `securecallfunction(func, owner, ...)` inside `secureexecuterange`, so our callbacks cannot taint Edit Mode. Edit Mode also calls `C_UnitAuras.SwitchAuraDataProvider()` on enter and `ResetAuraDataProvider()` on exit (fake aura data for preview).
- AddOn settings read and write `variableTbl[variableKey]` directly (`Blizzard_Settings_Shared/Blizzard_Setting.lua`), so `setting:SetValue(v)` from our own UI updates the db and fires the value-changed callback.
- `C_DamageMeter`: `GetAvailableCombatSessions()` returns `{ sessionID, name, durationSeconds }`. `GetCombatSessionFromID/FromType` and `GetCombatSessionSourceFromID/FromType(…, sourceGUID, sourceCreatureID)` are `SecretWhenInCombat` (combat restriction only). `combatSources[]` has `sourceGUID` and `name` (ConditionalSecret), `totalAmount`, `classFilename`, `isLocalPlayer`; `combatSpells[]` has `spellID`, `totalAmount`, `isAvoidable`. `Enum.DamageMeterType.AvoidableDamageTaken = 8`, `DamageTaken = 7`. CVar `damageMeterEnabled`. The damage meter has no aura or stack data at all.
- `UnitIsGroupLeader` is `SecretWhenUnitIdentityRestricted`: check `issecretvalue` before testing it.
- `C_ChatInfo.SendChatMessage` is `HasRestrictions`; `Enum.AddOnRestrictionType.Chat` blocks addon chat during encounters and possibly on raid maps. Do not build chat callouts.
- Raid marker textures: `Interface\TargetingFrame\UI-RaidTargetingIcon_N` (7 = red X), from `Blizzard_ChatFrameBase/Shared/ChatFrameConstants.lua`.
- Button templates verified in `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`: `UIPanelButtonTemplate`, `UIPanelCloseButton`. The stub rejects any other template until it is verified.

## Workflow for every change

1. Read the relevant Blizzard source before using any API you have not used in this repo. Do not guess signatures. Download with `curl -L https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/<path>`. Key files: `Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua`, `Blizzard_CustomAuraButton.lua`, `Blizzard_AuraContainerUtil.lua`, `Blizzard_AuraContainerShared.lua`, `Blizzard_FrameXMLUtil/AuraUtil.lua`, `Blizzard_Settings_Shared/Blizzard_Settings.lua`, and the `Blizzard_APIDocumentationGenerated/*Documentation.lua` tables (these list `SecretArguments`, `HasRestrictions` and `SecretWhen*` predicates per function).
2. Keep all logic out of combat. Anything that changes frames goes through `ns.RequestRebuild()`, which defers past restrictions.
3. Run the smoke test and `node tests/compat_check.mjs` and make both pass: `python -m pip install lupa` once, then `python -c "from lupa import lua51; lua51.LuaRuntime().execute(open('tests/smoke.lua').read())"` from this folder. Add a check for every new feature. If you use a new API, add it to `tests/wow_stub.lua` with the same validation Blizzard performs.
4. Test in game: `/reload`, then `/sw test`, `/sw status`, `/sw config`, and each slash command. Enable Lua errors with `/console scriptErrors 1` or keep BugSack. Then test with `addonEncounterRestrictionsForced` set to 1 at a dummy.
5. Keep it light: no `OnUpdate` handlers outside the demo, no polling, no per-frame work. Prefer `RegisterUnitEvent` over `RegisterEvent` for unit events. Check cost in game with `C_AddOnProfiler.GetAddOnMetric("StackWatch", Enum.AddOnProfilerMetric.RecentAverageTime)`.
6. Bump `## Version` and `CHANGELOG.md`, commit, and tag `vX.Y.Z` to release. The workflow needs no secrets for GitHub Releases. For Wago or CurseForge, add `WAGO_API_TOKEN` or `CF_API_TOKEN` as repository secrets and `## X-Wago-ID` or `## X-Curse-Project-ID` lines to the .toc.

## Style

- Plain Lua, no libraries (Ace3 is not needed for this size). Tabs for indentation, matching the existing files.
- One concern per file. New features that add a visual element go in `Display.lua` through `ns.BuildLook` so the demo stays in sync.
- Every new user-facing option gets: a default in `ns.DEFAULTS`, a control in `Options.lua`, handling in the rebuild path, and a line in README's settings table.
- Never use em dashes in text the user sees.
- Do not add WeakAuras-style "logic on aura state". It cannot work and the user knows why.

## Things that are still unverified in the live game

- Whether Eternal Venom is flagged `isBossAura`. If it does not show on the first Twin Fangs pull, `/sw all` is the fallback. Then consider making `bossOnly = false` the default or adding a per-encounter preset using `ENCOUNTER_START` (encounter ID 3421 for The Twin Fangs; `ENCOUNTER_START` is not secret).
- Raid lead report: whether `GetAvailableCombatSessions()` has the boss fight as a new session right after `ENCOUNTER_END` (we pick the new session whose length is closest to the fight), whether `ConditionalSecret` names come back readable after combat, and whether the damage meter records data with its window hidden.
- Edit Mode: whether Blizzard's fake aura data (`SwitchAuraDataProvider`) also draws in our AuraContainers behind the demo. Harmless either way, but check it looks clean.
- Whether a NumericRuleFormatter breakpoint with a `" "` format renders blank as intended. If non-stacking debuffs show a stray character, switch `showCountForOne` default to false.

## Ideas on the roadmap (ask Ethan before building)

- Per-encounter threshold presets (Normal 6/9, Heroic and Mythic 5/8).
- Threat display for tanks: `UnitThreatSituation("player", "target")` is generally not secret for player-versus-target queries, so a threat badge is feasible; threat percentages are secret for most other unit pairs.
- Profile export strings for the guild (LibSerialize + LibDeflate, or a plain colon-separated string).
