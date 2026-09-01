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
-- To the RIGHT of the portrait, not below it. Below is where Blizzard puts the target-of-target
-- frame, and the two collided on sight (Admiral, first eye-verify). Right of the portrait is the
-- outer edge of the target frame, which carries no Blizzard UI at all — and it keeps the number
-- beside the face you are looking at rather than under it.
local ANCHOR_POINT, ANCHOR_TO = "LEFT", "RIGHT"
local OFFSET_X, OFFSET_Y = 4, 0
local FONT_TEMPLATE = "NumberFontNormal"

-- The badge behind the number: dark fill, thin gold edge. Built from plain textures rather than a
-- backdrop, deliberately — SetBackdrop lives on BackdropTemplate on the modern engine Era runs, and
-- four coloured textures need no template at all and cannot be missing on any client.
local PAD_X, PAD_Y = 5, 2
local BORDER = 1
local BG_COLOUR     = { 0, 0, 0, 0.75 }
local BORDER_COLOUR = { 0.85, 0.70, 0.25, 1 }

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

    local badge = CreateFrame("Frame", nil, host)
    badge:SetPoint(ANCHOR_POINT, anchor, ANCHOR_TO, OFFSET_X, OFFSET_Y)
    -- Above the portrait border art the host frame draws, or the badge is painted over.
    badge:SetFrameLevel(host:GetFrameLevel() + 2)
    badge:Hide()

    -- SetColorTexture is the modern name; SetTexture(r,g,b,a) is the one Era inherited. Trying the
    -- new one first and falling back keeps this off BoonkeeperCompat, which exists for questions
    -- about aura data rather than for one texture call.
    local function fill(texture, colour)
        if texture.SetColorTexture then
            texture:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
        else
            texture:SetTexture(colour[1], colour[2], colour[3], colour[4])
        end
    end

    local bg = badge:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(badge)
    fill(bg, BG_COLOUR)

    -- Four edges rather than one border texture: a border file would need an art asset and a
    -- corner-correct edgeSize, and this is a rectangle one pixel thick.
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", 0, 0, nil, BORDER },
        { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, nil, BORDER },
        { "TOPLEFT", "BOTTOMLEFT", 0, 0, BORDER, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 0, 0, BORDER, nil },
    }) do
        local line = badge:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1], badge, edge[1])
        line:SetPoint(edge[2], badge, edge[2])
        if edge[5] then line:SetWidth(edge[5]) end
        if edge[6] then line:SetHeight(edge[6]) end
        fill(line, BORDER_COLOUR)
    end

    local text = badge:CreateFontString(nil, "OVERLAY", FONT_TEMPLATE)
    text:SetPoint("CENTER", badge, "CENTER", 0, 0)

    Display.targetBadge = badge
    Display.targetText = text
    return text
end

--- Put a string on the badge and size the badge to it.
---
--- Sized on every update because the strings differ in width by a lot — "?" against "32/32" — and a
--- fixed badge would either crop the widest or leave a slab of black around the narrowest.
local function setLabel(text, value)
    text:SetText(value)
    local badge = Display.targetBadge
    if not badge then return end
    badge:SetSize(text:GetStringWidth() + (PAD_X * 2), text:GetStringHeight() + (PAD_Y * 2))
    badge:Show()
end

local function hideLabel()
    if Display.targetBadge then Display.targetBadge:Hide() end
end

--- Point the label at a synthetic aura list instead of the live target, or back at the live target.
---
--- Runtime only: this is deliberately never written to BoonkeeperDB, so a demo cannot survive a
--- /reload. BoonkeeperDemo owns the other half of the guarantee — demo mode cannot be active while
--- its panel is hidden, so a fake number is never on screen without something saying so.
---
--- `auras` may legitimately be nil (the unreadable-unit case), which is why the flag is separate.
--- `verdict` is optional and demonstrates the fourth state: full, and this cast is still free.
function Display.SetDemo(active, auras, verdict)
    Display.demoActive = active and true or false
    Display.demoAuras = auras
    Display.demoVerdict = verdict
    Display.UpdateTarget()
end

-- How long a cast verdict keeps colouring the badge. Long enough to be read while the cast bar is
-- still up, short enough that it is gone before the next decision — a stale "free" sitting on the
-- badge would be answering a question the healer has stopped asking.
local VERDICT_SECONDS = 4

--- Colour the badge by what the cast just sent would cost, rather than by the count alone.
---
--- Only ever a recolour, and only for the unit on the frame: a verdict about somebody else would be
--- painted onto the face of the person we are looking at. Core decides what it means; this decides
--- nothing but how long it stays.
function Display.SetVerdict(verdict, unit)
    if unit and not UnitIsUnit(unit, "target") then return end
    Display.verdict = verdict

    -- Each verdict owns its own expiry. Without the generation check the timer from a cast four
    -- seconds ago would wipe the verdict of the cast half a second ago.
    local generation = (Display.verdictGeneration or 0) + 1
    Display.verdictGeneration = generation
    Display.UpdateTarget()

    local timer = _G.C_Timer
    if not (timer and timer.After) then return end
    timer.After(VERDICT_SECONDS, function()
        if Display.verdictGeneration ~= generation then return end
        Display.verdict = nil
        Display.UpdateTarget()
    end)
end

--- Redraw the target label from what we can see of the target right now.
function Display.UpdateTarget()
    -- Ahead of the label, and ahead of the early return below. A player running a unit-frame
    -- replacement has no Blizzard TargetFrame to draw on — and is exactly the sort of player who
    -- runs a broker bar. Behind that return, their bar entry would never have updated at all.
    --
    -- It rescans rather than reusing the demo's synthetic list, and is skipped by the demo branch:
    -- a bar entry can sit anywhere on screen, far from the Test tab that says the number is fake,
    -- so it keeps telling the truth even while the target frame is pretending.
    local Broker = Boonkeeper.Broker
    if Broker and Broker.Update then Broker.Update() end

    local text = targetLabel()
    if not text then return end

    -- Ahead of the target check on purpose: the point of the demo is to judge the label solo, with
    -- nothing targeted, rather than hunting for a raider carrying 28 buffs.
    if Display.demoActive then
        setLabel(text, Core.Text(Core.Assess(Display.demoAuras, { filter = "HELPFUL" }),
                                 Display.demoVerdict))
        return
    end

    if not UnitExists("target") then
        hideLabel()
        return
    end

    setLabel(text, Core.Text(Scan.Assess("target", "HELPFUL"), Display.verdict))
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
    -- A verdict belongs to the body it was cast at. Retargeting must drop it rather than repaint it
    -- onto somebody else's face, which would be the addon vouching for a cast nobody made.
    if event == "PLAYER_TARGET_CHANGED" then
        Display.verdict = nil
        Display.verdictGeneration = (Display.verdictGeneration or 0) + 1
    end
    Display.UpdateTarget()
end)

Boonkeeper.Display = Display
return Display
