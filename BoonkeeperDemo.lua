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
--   2. Demo mode cannot be active while the panel is hidden — closing it restores live data (see
--      the OnHide below). You cannot be looking at a fake number without the panel saying so.
--   3. The buttons do NOT fabricate a report. They build a synthetic aura list and hand it to the
--      same Core.Assess the live scan feeds, so a tester sees what the real pipeline produces
--      rather than a mock-up of it. Tests/demo_test.lua asserts every scenario through Core.
--
-- The scenario builders are pure and tested. The panel is compile-verified only, which is why it is
-- built lazily inside Toggle(): a CreateFrame at the top level would stop this file loading under
-- plain Lua and the scenarios would go untested with it.

Boonkeeper = Boonkeeper or {}

local Core = Boonkeeper.Core

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
-- The panel. Compile-verified only — no line below has ever executed.
-- ---------------------------------------------------------------------------

local PANEL_W, PANEL_H = 190, 300
local BUTTON_H, BUTTON_GAP = 22, 3

local function apply(key)
    local Display = Boonkeeper.Display
    if not Display or not Display.SetDemo then return end
    Display.SetDemo(true, Demo.Build(key))
end

local function buildPanel()
    -- Classic Era runs the modern engine, where a plain frame has no SetBackdrop — it lives on
    -- BackdropTemplate. Asking for a template the client does not have would error at CreateFrame,
    -- so fall back to a bare frame and simply go without a border.
    local template = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local panel = CreateFrame("Frame", "BoonkeeperDemoPanel", UIParent, template)
    -- A new frame is shown by default, so without this the first Toggle() would find it already
    -- shown, hide it, and report "closed" — the first /boon test would look like it did nothing.
    panel:Hide()
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile   = "Interface\DialogFrame\UI-DialogBox-Background",
            edgeFile = "Interface\DialogFrame\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Boonkeeper test")

    -- Says out loud that the target frame is currently lying. The panel being on screen IS the
    -- guard, so it has to read as one rather than as a title bar.
    local warn = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warn:SetPoint("TOP", title, "BOTTOM", 0, -4)
    warn:SetText("|cffff8000Target frame shows FAKE data|r")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local anchor = warn
    for _, scenario in ipairs(Demo.SCENARIOS) do
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(PANEL_W - 40, BUTTON_H)
        button:SetPoint("TOP", anchor, "BOTTOM", 0, -BUTTON_GAP)
        button:SetText(scenario.label)
        button:SetScript("OnClick", function() apply(scenario.key) end)
        anchor = button
    end

    -- Guard 2. Closing the panel is the one gesture a tester will reach for, so it must be the
    -- gesture that restores live data — not a separate button they can forget to press.
    panel:SetScript("OnHide", function()
        local Display = Boonkeeper.Display
        if Display and Display.SetDemo then Display.SetDemo(false, nil) end
    end)

    -- Escape closes it, which routes through OnHide and restores live data. Making the reflex
    -- gesture the safe one matters more here than it would for an ordinary window.
    if type(_G.UISpecialFrames) == "table" then
        table.insert(_G.UISpecialFrames, "BoonkeeperDemoPanel")
    end

    Demo.panel = panel
    return panel
end

--- Show or hide the test panel. Hiding it restores live data; see guard 2.
function Demo.Toggle()
    local panel = Demo.panel or buildPanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
    return panel:IsShown()
end

Boonkeeper.Demo = Demo
return Demo
