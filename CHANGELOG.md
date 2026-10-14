# Changelog

## 1.1.0 (unreleased)

- Edit Mode: the tracker shows with the demo running while Edit Mode is open. Drag it to move it, click it for settings.
- Quick-settings window: `/sw`, the addon compartment, a right-click on the drag handle, or a click in Edit Mode.
- Optional red X raid markers in the icon corners at danger stacks.
- Raid lead report: after each boss, the raid leader sees who took the most avoidable damage and from which spells. `/sw report` shows the last one. Uses Blizzard's damage meter after combat.
- `/sw status` shows the report setting and whether Blizzard's damage meter is on.

## 1.0.0 (2026-10-14)

- First release.
- Boss debuff icons with stack count, stack bar and tick marks.
- Threshold colors (caution and danger) driven entirely by Blizzard's aura system, so they keep working under Midnight's encounter restrictions.
- Demo mode (/sw test), drag handle (/sw unlock), settings panel (/sw config).
- Optional sound on stack gain through C_UnitAuras.AddAuraSound.
