# Work log

Progress notes so work can continue on any machine. Newest first. Not shipped (ignored by .pkgmeta).

## 2026-10-14 overnight session (branch `dev`, PR to `main`)

### Released

- v1.0.0 is live: https://github.com/Wraith-cmd/Stackwatch/releases/tag/v1.0.0
- Release workflow fix: BigWigs packager v2 reads `GITHUB_OAUTH`, not `GH_API_TOKEN`, and the job needs `permissions: contents: write`. The first v1.0.0 tag built the zip but skipped the upload; the tag was moved to the fixed commit before anyone could install it.

### Built on `dev` (version 1.1.0, NOT tagged or released)

| Feature | Status | Notes |
| --- | --- | --- |
| Move in Edit Mode | done, needs in-game test | Tracker and demo show while Edit Mode is open. Drag to move, click for settings. Uses Blizzard's `EditMode.Enter/Exit` callbacks, which run in a taint-safe wrapper. |
| Quick-settings HUD | done, needs in-game test | `/sw`, addon compartment, right-click the drag handle, or click in Edit Mode. Closes on combat start. Same settings path as the Blizzard panel. |
| Red X at danger | done, default off | Red X raid marker in both top corners of the icon at danger stacks ("X 8 X"). Shown by Blizzard's code like the red border, so it works mid-fight. Try it with `/sw test`. |
| Raid lead report | done, needs a real pull | After each boss, the raid leader sees the top avoidable damage spells and the 5 most-hit players in their own chat. `/sw report` shows the last one to anyone. Needs Blizzard's damage meter on. |
| Build watch | done, starts after merge | Daily GitHub Action. Every new live or PTR build gets checked; results go on the "Blizzard build watch" issue, failures open their own issue (GitHub emails you). |
| Tests on every push | done | Smoke test + live compatibility check run in GitHub Actions. |

### Review (Throne)

- Vision (code review) found 4 issues, all fixed. The main one: the session snapshot at ENCOUNTER_START ran without protection while the pull may already be restricted.
- Ultron (adversarial testing, about 70 cases) found 4 issues, 3 fixed and 1 logged:
  - Fixed: encounter handlers could error on an odd or secret damage meter list. Both are now wrapped, and every list entry is type-checked.
  - Fixed: hand-corrupted saved variables could stop the tracker at login. They are now repaired at load.
  - Fixed: leaving Edit Mode could stop a demo you started by hand.
  - Logged, not fixed: each rebuild while the demo is running creates a new demo frame tree (about 50 regions). WoW cannot free frames, rebuilds are debounced, and this only happens while changing settings with the demo on. Fine for now; reuse the demo frame if it ever matters.
- All repros are regression checks in the smoke test (88 checks).

### Not built, and why

- **Chat callout at 8 and 9 stacks** (red X + number in chat): impossible. The stack count is secret during the fight, so the addon cannot know it is at 8, and addon chat is blocked during encounters. The red X on your own icon is the closest legal version.
- **Voice or sound cue near or above a threshold**: impossible for the same reason. Blizzard's aura sound API only has three triggers: debuff added, stack gained, removed. No count. The existing "Sound on stack gain" option plays on every stack.
- **Report of where extra stacks come from**: the damage meter has no aura or stack data. The report uses avoidable damage taken per spell instead, which is where people get hit by mechanics.
- **"Slightly pulling from the background"**: not sure what this meant. Ask Ethan.

### Test in game before releasing 1.1.0

The new files (Hud.lua, Report.lua) need a full client restart, not just /reload.

1. `/sw` opens the HUD. Click + and - on each row, toggle each button. Open `/sw config` and confirm it shows the same values.
2. Esc > Edit Mode: the tracker shows with the demo. Drag it. Click it: HUD opens. Leave Edit Mode: handle and demo go away, lock state unchanged.
3. Turn on "Red X at danger" in the HUD, run `/sw test`, watch for X X at 8 and above.
4. At a training dummy with `addonEncounterRestrictionsForced` set to 1: confirm no Lua errors, the HUD closes on pull, and changes made in combat apply after.
5. Raid lead report: needs a real boss and you as raid leader with the damage meter on. Check the names, spell names and numbers look right. If it prints nothing or "no damage meter data", run `/sw status` and `/dump C_DamageMeter.GetAvailableCombatSessions()` after the pull and save the output.
6. Then: merge the PR, tag `v1.1.0`, push the tag.

### Open questions for Ethan

1. "Slightly pulling from the background": did you mean a see-through tracker (lower opacity), a backdrop behind it, or something else?
2. Should the red X markers be on by default?
3. Raid lead report: raid leader only (current), or also assistants?
