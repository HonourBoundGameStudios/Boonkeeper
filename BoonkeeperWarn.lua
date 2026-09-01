-- BoonkeeperWarn — the moment of the cast.
--
-- Everything else in this addon answers "how full is this person". This file answers the question
-- that was actually being asked all along: is the thing you just pressed what costs them a world
-- buff. It decides none of it. Core says what the spell applies (Core.Spell), what the cast would
-- cost (Core.CastCost, via Scan for the client half) and whether that is worth saying out loud
-- (Core.ShouldWarn); this file only listens for the cast and passes on the answer.
--
-- UNIT_SPELLCAST_SENT is the earliest the client will tell us, and it fires as the cast is sent —
-- so for anything with a cast bar there is still time to stop, and for an instant there is not.
-- That is honest and it is still worth having: knowing you just spent somebody's Rallying Cry is
-- how the next pull goes differently.
--
-- Compile-verified only until somebody logs in, which is exactly why it makes no judgement.

Boonkeeper = Boonkeeper or {}

local Compat = Boonkeeper.Compat
local Core = Boonkeeper.Core
local Scan = Boonkeeper.Scan

local Warn = {}

-- One warning per target per spell inside this window. A healer holding down a Renew macro at a
-- capped raider must not be told about it eight times — the second line is already noise, and noise
-- is how the line that matters gets read past. This can only ever SUPPRESS a warning we already
-- decided to give; it never invents one, so the judgement stays in Core.
local REPEAT_SECONDS = 6
local lastKey, lastAt = nil, 0

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fd3ffBoonkeeper|r " .. msg)
end

--- The warning itself: loud, specific about what is certain, silent about what is not.
---
--- It names the world buffs the unit is carrying because we have seen them. It does NOT name which
--- one drops: past the cap the server drops the oldest, and whether the client tells us which that
--- is has never been established (WARN-3). Naming one would be the one thing this addon must never
--- do, at the loudest possible moment.
local function warningText(unit, spellName, report)
    local name = UnitName(unit) or "them"
    local carrying = table.concat(report.precious, ", ")
    return string.format(
        "|cffff2020%s on %s: they are at %d/%d.|r This takes a new slot, so one of their buffs " ..
        "drops. World buffs up: |cffffd100%s|r.",
        spellName, name, report.count, report.cap, carrying)
end

--- Handle one cast the player just sent.
---
--- Every step here is allowed to give up, and giving up means saying nothing at all: an unmapped
--- spell, a target off our roster, a list we may not vouch for. Silence is the correct output for
--- all of them — the alternative is a warning built on something we do not know.
function Warn.OnCastSent(caster, targetName, _, spellId)
    if caster ~= "player" then return end

    local spellName = Compat.SpellName(spellId)
    local spell = Core.Spell(spellName)
    if not spell then return end

    local unit = Scan.UnitByName(targetName)
    -- A cast the client names no target for lands on the caster — Inner Fire, Fade, a buff pressed
    -- with nobody selected. Our own list is the one Blizzard is documented to serve completely, so
    -- this is the case we can always answer, and the one where the world buffs are ours to lose.
    if not unit and (targetName == nil or targetName == "") then unit = "player" end
    if not unit then return end

    local verdict = Scan.CastCost(unit, spell)
    local report = Scan.Assess(unit, "HELPFUL")

    -- The badge first, because it is the cheap half and it is true whatever the verdict says: a
    -- free cast turns the number green even at 32/32, which is the whole point of the fourth state.
    if Boonkeeper.Display then
        Boonkeeper.Display.SetVerdict(verdict, unit)
    end

    if not Core.ShouldWarn(report, verdict) then return end

    local key = (UnitName(unit) or "?") .. "/" .. (spell.applies or "")
    local now = GetTime and GetTime() or 0
    if key == lastKey and (now - lastAt) < REPEAT_SECONDS then return end
    lastKey, lastAt = key, now

    say(warningText(unit, spellName, report))
end

local watcher = CreateFrame("Frame")
-- Filtered to our own casts. UNIT_SPELLCAST_SENT for a forty-player raid is one of the loudest
-- events in the game, and every unit but "player" would be discarded a line later anyway.
if watcher.RegisterUnitEvent then
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
else
    watcher:RegisterEvent("UNIT_SPELLCAST_SENT")
end
watcher:SetScript("OnEvent", function(_, _, caster, targetName, castGUID, spellId)
    Warn.OnCastSent(caster, targetName, castGUID, spellId)
end)

Boonkeeper.Warn = Warn
return Warn
