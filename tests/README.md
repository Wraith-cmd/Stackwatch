# Tests

`tests/smoke.lua` loads the addon into a small stub of the WoW 12.1.5 API
(`tests/wow_stub.lua`) that enforces the same argument validation Blizzard's
Blizzard_CustomAuraContainer.lua and Blizzard_CustomAuraButton.lua perform,
then walks login, every slash command, every setting, combat deferral and the
aura show/hide logic.

Run from the addon folder (the repo root) with any Lua 5.1 interpreter:

    lua5.1 tests/smoke.lua

or through Python with lupa (pip install lupa):

    python -c "from lupa import lua51; lua51.LuaRuntime().execute(open('tests/smoke.lua').read())"

Add a check for every new feature. If the stub lacks an API you start using,
add it to wow_stub.lua with the same validation Blizzard's source performs.
