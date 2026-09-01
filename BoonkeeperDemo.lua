-- BoonkeeperDemo — a panel that walks the target label through every state it can be in.
--
-- WHY THIS EXISTS: the label's appearance can only be judged with eyes on the client, and the states
-- worth judging (28 buffs and a live Rallying Cry) cannot be summoned on demand in a raid. The
-- standing order is to eye-verify from more than one state; without this, "more than one state"
-- means waiting for Naxxramas to produce one.
--
-- WHY IT IS DANGEROUS: this addon must never show a number it cannot stand behind, and a demo mode
-- is a machine for doing exactly that. Three guards, all load-bearing:
--
--   1. Nothing here is ever written to BoonkeeperDB. Demo state cannot survive a /reload.
--   2. Demo mode cannot be active while this tab is off screen. The guard hangs on the tab
--      content's OnHide, which fires when you switch tabs AND when you close the window, so
--      neither gesture can leave a fake number on your target frame. You cannot be looking at a
--      fake number without the tab that produced it being in front of you saying so.
--   3. The buttons do NOT fabricate a report. They build a synthetic aura list and hand it to the
--      same Core.Assess the live scan feeds, so a tester sees what the real pipeline produces
--      rather than a mock-up of it. Tests/demo_test.lua asserts every scenario through Core.
--
-- The scenario builders are pure and tested. The panel is compile-verified only, which is why it is
-- built lazily inside Toggle(): a CreateFrame at the top level would stop this file loading under
-- plain Lua and the scenarios would go untested with it.

Boonkeeper = Boonkeeper or {}

local Core = Boonkeeper.Core
local UI = Boonkeeper.UI

local Demo = {}

-- Filler buffs stand in for the anonymous mass of a raider's aura list — Marks, Fortitudes, food.
-- Named separately from the interesting ones so a scenario reads as "27 things plus the one that
-- matters" rather than as a magic number.
local function filler(n, ...)
    local list = {}
    for i = 1, n do
        list[i] = { name = "Filler " .. i, isHelpful = true }
    end
    for _, name in ipairs({ ... }) do
        list[#list + 1] = { name = name, isHelpful = true }
    end
    return list
end

-- Ordered, because they are buttons and the order is the tour: empty to full, with the two
-- world-buff cases sitting next to each other where the difference between them is visible.
Demo.SCENARIOS = {
    { key = "empty",    label = "Empty (0/32)",    build = function() return filler(0) end },
    { key = "clear",    label = "Clear (10/32)",   build = function() return filler(10) end },
    { key = "watch",    label = "Watch (28/32)",   build = function() return filler(28) end },
    { key = "precious", label = "World buff up",   build = function()
        return filler(28, "Rallying Cry of the Dragonslayer")
    end },
    { key = "booned",   label = "Booned (safe)",   build = function()
        return filler(28, "Chronoboon Displacement")
    end },
    { key = "danger",   label = "Danger (30/32)",  build = function() return filler(30) end },
    { key = "full",     label = "FULL (32/32)",    build = function() return filler(32) end },
    -- nil, not an empty list: "we cannot read this unit" is a different fact from "this unit has no
    -- buffs", and the whole design rests on the difference. This button is how you see it.
    { key = "unknown",  label = "Unreadable (?)",  build = function() return nil end },
}

local byKey = {}
for _, scenario in ipairs(Demo.SCENARIOS) do
    byKey[scenario.key] = scenario
end

--- The synthetic aura list for a scenario, or nil for the unreadable-unit case.
---
--- Raises on an unknown key. Only our own buttons call this, so a bad key is a programming error,
--- and returning nil would render as an unreadable unit — a real state, which would look like a pass.
function Demo.Build(key)
    local scenario = byKey[key]
    if not scenario then
        error("BoonkeeperDemo: no such scenario '" .. tostring(key) .. "'", 2)
    end
    -- Built fresh on every press: a shared table would let one press mutate what the next one shows.
    return scenario.build()
end

-- ---------------------------------------------------------------------------
-- The tab. Compile-verified only — no line below has ever executed.
-- ---------------------------------------------------------------------------

local BUTTON_W, BUTTON_H, BUTTON_GAP = 170, 22, 3

local function apply(key)
    local Display = Boonkeeper.Display
    if not Display or not Display.SetDemo then return end
    Display.SetDemo(true, Demo.Build(key))
end

--- Build the Test tab into the frame the container hands us. Called once, on first view.
local function buildTab(content)
    local warn = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warn:SetPoint("TOPLEFT")
    warn:SetPoint("TOPRIGHT")
    warn:SetJustifyH("LEFT")
    -- Says out loud that the target frame is currently lying. This tab being in front of you IS
    -- the guard, so it has to read as one rather than as a heading.
    warn:SetText("|cffff8000While this tab is open the target frame shows FAKE data.|r")

    local blurb = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", warn, "BOTTOMLEFT", 0, -6)
    blurb:SetPoint("RIGHT")
    blurb:SetJustifyH("LEFT")
    blurb:SetText("|cffaaaaaaPress a state and watch the number under your target's portrait. "
        .. "Leaving this tab restores live data.|r")

    local anchor = blurb
    for _, scenario in ipairs(Demo.SCENARIOS) do
        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetSize(BUTTON_W, BUTTON_H)
        button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -BUTTON_GAP)
        button:SetText(scenario.label)
        button:SetScript("OnClick", function() apply(scenario.key) end)
        anchor = button
    end

    local live = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    live:SetSize(BUTTON_W, BUTTON_H)
    live:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    live:SetText("Back to live data")
    live:SetScript("OnClick", function()
        local Display = Boonkeeper.Display
        if Display and Display.SetDemo then Display.SetDemo(false, nil) end
    end)

    -- Guard 2, and the reason this hangs on the CONTENT rather than on the window: OnHide fires
    -- both when the window closes and when you switch to another tab. Either way you have stopped
    -- looking at the thing that says the number is fake, so the number stops being fake.
    content:SetScript("OnHide", function()
        local Display = Boonkeeper.Display
        if Display and Display.SetDemo then Display.SetDemo(false, nil) end
    end)
end

--- Open or close the window on the Test tab.
function Demo.Toggle()
    if not UI then return false end
    return UI.Toggle("test")
end

if UI then UI.RegisterTab("test", "Test", buildTab) end

Boonkeeper.Demo = Demo
return Demo
