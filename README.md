# StackWatch

Boss debuff stack tracker for World of Warcraft: Midnight (12.1.5).

Shows the boss debuffs on you as big icons with the stack count, a stack bar, and threshold colors: orange at a caution count, red at a danger count. Built for The Twin Fangs (Eternal Venom: caution 5, danger 8, dead at 10) and useful on any fight with a stacking boss debuff.

Because of Midnight's addon rules, no addon can read your stack count during a boss fight. StackWatch does not try. Blizzard's own aura display system draws the number, fills the bar and switches the colors inside the game client. The addon only describes what the display should look like. That is why it cannot break the moment you pull, and why it costs nothing while you play: there is no code running during the fight.

## Install

1. Download the latest `StackWatch-x.y.z.zip`.
2. Open it. It contains one folder, `StackWatch`.
3. Put that folder in `World of Warcraft\_retail_\Interface\AddOns\`.
4. If the game is open, type `/reload`.

Auto updates: add this repository's URL in WowUp ("Install from URL"), or install from Wago or CurseForge once it is listed there.

## Use

- `/sw test` runs a demo that cycles 0 to 10 stacks in the real position, so you can place it and tune sizes before the pull.
- `/sw unlock` shows a drag handle. Drag, then `/sw lock`.
- `/sw config` opens the settings panel (also under Esc > Options > AddOns > StackWatch).
- `/sw status` prints diagnostics (restriction state, thresholds, whether the aura is private).
- `/sw all` shows every debuff on you instead of only boss debuffs. `/sw boss` switches back.
- `/sw sound` toggles a short tick every time a tracked debuff gains a stack. `/sw sound add <spellID>` tracks more spells. Default: Eternal Venom (1290336).

Everything in the settings panel applies live, out of combat. Changes made during a fight apply the moment combat ends.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| Lock position | on | Hides the drag handle |
| Scale | 1.0 | Overall size |
| Growth direction | right | Where extra icons go |
| Caution at | 5 | Orange border, tint and number |
| Danger at | 8 | Red border, tint and number |
| Bar maximum | 10 | Stack count that fills the bar |
| Icon size | 48 | Pixels |
| Icon spacing | 6 | Pixels |
| Maximum icons | 3 | Permanent debuffs (Eternal Venom) always sort first |
| Number size | 0.55 | Fraction of the icon |
| Border thickness | 2 | Pixels |
| Tint icon at thresholds | on | Color wash over the icon |
| Show stack bar | on | Bar under the icon with tick marks at the thresholds |
| Show duration swipe | on | Cooldown swipe on timed debuffs |
| Show the number at 1 stack | on | Off hides the number until 2 stacks |
| Boss debuffs only | on | Off shows every debuff on you |
| Sound on stack gain | off | Short tick on every stack gained |

## How it works (for the curious)

Three identical Blizzard `AuraContainer` frames sit on top of each other, all filtered to boss debuffs on you and sorted the same way, so they always show the same debuffs in the same spots.

- The base layer draws the icon, number, swipe and stack bar.
- The caution layer's only "application bar" is an invisible full-size StatusBar. Blizzard shows that bar when stacks reach the caution count and hides it otherwise (`CustomAuraButton:ApplyApplicationBar` does `statusBar:SetShown(applications >= minApplications)` in secure code). The orange border, tint and number are children of that bar, so they appear with it.
- The danger layer does the same at the danger count, in red, drawn on top.

The addon never compares, stores or reads a stack count. Everything that configures the aura buttons happens once at login inside Blizzard's `initializeFrame` callback, which is the window Blizzard provides for exactly this.

## Performance

No OnUpdate handlers. No combat log. No per-frame Lua during a fight. The addon registers four events (login, combat end, restriction changes, its own loading) and is otherwise idle. The demo mode runs a 0.7 second ticker only while it is on.

## Known limits

- Stack thresholds cannot trigger addon logic (no "say something at 8 stacks"). That is a Blizzard rule, not a bug.
- The stack-gain sound plays on every gain, not only at thresholds, for the same reason.
- Whether a given debuff counts as a "boss aura" is decided by the encounter designers. If a fight's key debuff does not show up, use `/sw all`.

## License

MIT. See LICENSE.
