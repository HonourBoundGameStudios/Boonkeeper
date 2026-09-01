-- BoonkeeperDisplay — the number, put where the healer is already looking.
--
-- This file owns the label widgets and nothing else. It asks BoonkeeperScan what it can see, asks
-- BoonkeeperCore what that means, and draws the string Core hands back. It makes no judgement of
-- its own: no counting, no colouring, no deciding that a unit is "probably fine". Everything here
-- is compile-verified only until somebody logs in, which is exactly why none of it may decide.
--
-- The target frame first (SEE-1): the smallest possible surface, the unit you are about to cast on,
-- and the one case Blizzard is documented to serve fully — a party or raid member you have
-- targeted. Anything we cannot read still renders "?" rather than a number, by way of Core.Text.

Boonkeeper = Boonkeeper or {}

local Core = Boonkeeper.Core
local Scan = Boonkeeper.Scan

local Display = {}

-- Nudge these to move the number. Kept as named constants because the anchor is the one thing here
-- that can only be judged with eyes on the client, and it should be adjustable without reading the
-- logic underneath it.
local OFFSET_X, OFFSET_Y = 0, -2
local FONT_TEMPLATE = "NumberFontNormal"

--- The FontString for the target frame, created on first use.
---
--- Parented to TargetFrameTextureFrame when it exists: that frame draws the portrait border art, so
--- a string parented to TargetFrame itself is painted underneath it and simply never appears.
local function targetLabel()
    if Display.targetText then return Display.targetText end

    local host = _G.TargetFrameTextureFrame or _G.TargetFrame
    -- Unit frame replacements delete or never create the Blizzard target frame. That is a supported
    -- way to play, not an error: we simply have nowhere to draw, and say nothing.
    if not host then return nil end

    local anchor = _G.TargetFramePortrait or host
    local text = host:CreateFontString(nil, "OVERLAY", FONT_TEMPLATE)
    text:SetPoint("TOP", anchor, "BOTTOM", OFFSET_X, OFFSET_Y)
    text:Hide()

    Display.targetText = text
    return text
end

--- Point the label at a synthetic aura list instead of the live target, or back at the live target.
---
--- Runtime only: this is deliberately never written to BoonkeeperDB, so a demo cannot survive a
--- /reload. BoonkeeperDemo owns the other half of the guarantee — demo mode cannot be active while
--- its panel is hidden, so a fake number is never on screen without something saying so.
---
--- `auras` may legitimately be nil (the unreadable-unit case), which is why the flag is separate.
function Display.SetDemo(active, auras)
    Display.demoActive = active and true or false
    Display.demoAuras = auras
    Display.UpdateTarget()
end

--- Redraw the target label from what we can see of the target right now.
function Display.UpdateTarget()
    local text = targetLabel()
    if not text then return end

    -- Ahead of the target check on purpose: the point of the demo is to judge the label solo, with
    -- nothing targeted, rather than hunting for a raider carrying 28 buffs.
    if Display.demoActive then
        text:SetText(Core.Text(Core.Assess(Display.demoAuras, { filter = "HELPFUL" })))
        text:Show()
        return
    end

    if not UnitExists("target") then
        text:Hide()
        return
    end

    text:SetText(Core.Text(Scan.Assess("target", "HELPFUL")))
    text:Show()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
-- A /reload does not re-fire PLAYER_TARGET_CHANGED for the target you are already holding, so
-- without this the label stays blank until you retarget — which is both the whole developing loop
-- and what a raider sees after reloading mid-fight.
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Filtered to the target: UNIT_AURA is one of the loudest events in a 40-player raid, and an
-- unfiltered registration would run this on every aura tick of every unit in Naxxramas.
if watcher.RegisterUnitEvent then
    watcher:RegisterUnitEvent("UNIT_AURA", "target")
else
    watcher:RegisterEvent("UNIT_AURA")
end
watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "target" then return end
    Display.UpdateTarget()
end)

Boonkeeper.Display = Display
return Display
