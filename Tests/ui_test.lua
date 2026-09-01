-- BoonkeeperUI — the tabbed window other modules plug into.
--
-- The window itself can only be judged in the client, but WHICH TABS EXIST and in what order is a
-- plain registry, and it is the half that fails silently: a tab whose module forgot to register is
-- not an error anywhere, it is simply a feature the player cannot find. That is the same failure
-- mode as a module missing from the .toc, and it gets the same kind of guard.
--
-- Usage: lua Tests/ui_test.lua   (run from the project root)

-- Only Core and the container to begin with: the registry assertions below count tabs, so a module
-- that registers one at load must not be present yet or it would be counted as a test fixture.
local H = dofile("Tests/harness.lua")
dofile("BoonkeeperCore.lua")
dofile("BoonkeeperUI.lua")
local UI = Boonkeeper.UI

H.start("BoonkeeperUI")

-- The container must load with no WoW API. The window is built lazily on first open precisely so
-- this stays true; a CreateFrame at the top level would take the registry down with it.
H.ok(UI ~= nil, "BoonkeeperUI loads standalone — the registry is pure")

-- ---------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------

local function noop() end

UI.RegisterTab("alpha", "Alpha", noop)
UI.RegisterTab("beta", "Beta", noop)

H.eq(#UI.TABS, 2, "registered tabs are collected")
H.eq(UI.TABS[1].key, "alpha", "registration order is preserved — it is the tab order")
H.eq(UI.TABS[2].key, "beta", "the second tab follows the first")
H.eq(UI.Tab("beta").label, "Beta", "a tab can be looked up by key")
H.eq(UI.Tab("nope"), nil, "an unknown key looks up as nil")
H.eq(UI.TabIndex("beta"), 2, "a tab knows its position, which is what the tab buttons need")
H.eq(UI.TabIndex("nope"), nil, "an unknown key has no position")

-- Two tabs under one key would make TabIndex ambiguous and leave one of them unreachable. That is
-- a programming error at load time, so it must be loud rather than quietly dropped.
H.errors(function() UI.RegisterTab("alpha", "Alpha again", noop) end, "a duplicate tab key raises")

-- A tab with nothing to draw would open as an empty panel that looks like a broken addon.
H.errors(function() UI.RegisterTab("gamma", "Gamma", nil) end, "a tab with no builder raises")
H.errors(function() UI.RegisterTab(nil, "Nameless", noop) end, "a tab with no key raises")

-- ---------------------------------------------------------------------------
-- The tabs this addon actually ships
-- ---------------------------------------------------------------------------
-- Loaded after the registry assertions so the test tabs above cannot mask a module that failed to
-- register. This is the guard for "the feature is simply not in the window".
dofile("BoonkeeperSelfTest.lua")
dofile("BoonkeeperAbout.lua")
dofile("BoonkeeperDemo.lua")

H.ok(UI.Tab("about") ~= nil, "BoonkeeperAbout registers its tab at load")
H.ok(UI.Tab("test") ~= nil, "BoonkeeperDemo's test tab is registered")

-- About before Test: the window opens on the first tab, and what this addon is should greet
-- somebody ahead of a panel of fake numbers.
H.ok(UI.TabIndex("about") < UI.TabIndex("test"), "About sits before Test")

H.done()
