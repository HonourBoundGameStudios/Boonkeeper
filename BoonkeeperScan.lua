-- BoonkeeperScan — the only file that obtains an aura list from the live client.
--
-- It hands BoonkeeperCore plain tables and takes back a report. Nothing here decides anything.
--
-- The load-bearing unknown this file is built around: Blizzard only serves full aura data for
-- yourself and your party/raid members. For anyone else we may see a truncated list or nothing, and
-- a truncated list that we *report as a count* would be a confident lie at exactly the moment
-- somebody is deciding whether to cast.
--
-- Two ways a unit therefore ends up as "?": an unreadable one returns nil from Scan.Auras, and an
-- untrusted one (Scan.Trusted below) has its list refused by Core even though the list arrived. The
-- second is the subtle one — the data looks fine, which is exactly the problem.
-- BoonkeeperProbe exists to settle empirically what is actually readable; see Process/Bugs.md.

Boonkeeper = Boonkeeper or {}

local Compat = Boonkeeper.Compat
local Core = Boonkeeper.Core

local Scan = {}

-- Walk no further than this. The cap is 32, but a client that returned auras forever would freeze
-- the game inside a nameplate update, so the loop is bounded rather than trusting the terminator.
local MAX_INDEX = 64

--- Every aura of one kind on a unit, or nil if the unit cannot be read.
function Scan.Auras(unit, filter)
    if not unit or not UnitExists(unit) then return nil end
    filter = filter or "HELPFUL"

    local list = {}
    for index = 1, MAX_INDEX do
        local aura = Compat.GetAura(unit, index, filter)
        if not aura then break end
        list[#list + 1] = aura
    end
    return list
end

--- Is this a unit the client is documented to serve a COMPLETE aura list for?
---
--- Yourself, your party, your raid — and nobody else, until PROBE-1 says what a stranger's list
--- actually contains. Note this is deliberately NARROWER than "we got some auras back": a stranger's
--- list arrives too, and looks perfectly ordinary, and may be missing the world buff that was the
--- whole reason to look. Guessing wide here is how the addon ends up stating a number it cannot
--- stand behind.
function Scan.Trusted(unit)
    if not unit then return false end
    -- `UnitInRaid` yields a raid INDEX, so each answer is forced to a boolean rather than passed on:
    -- raid index 0 does not exist today, but a truthy number leaking out of a yes/no question is the
    -- kind of thing that survives until the one client where it does not.
    if UnitIsUnit(unit, "player") then return true end
    if UnitInParty(unit) then return true end
    if UnitInRaid(unit) then return true end
    return false
end

--- The report for a unit: what Core makes of what we can see, and of whether we may believe it.
function Scan.Assess(unit, filter)
    filter = filter or "HELPFUL"
    return Core.Assess(Scan.Auras(unit, filter), {
        filter = filter,
        trusted = Scan.Trusted(unit),
    })
end

Boonkeeper.Scan = Scan
return Scan
