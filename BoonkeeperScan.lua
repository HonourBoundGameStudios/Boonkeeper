-- BoonkeeperScan — the only file that obtains an aura list from the live client.
--
-- It hands BoonkeeperCore plain tables and takes back a report. Nothing here decides anything.
--
-- The load-bearing unknown this file is built around: Blizzard only serves full aura data for
-- yourself and your party/raid members. For anyone else we may see a truncated list or nothing, and
-- a truncated list that we *report as a count* would be a confident lie at exactly the moment
-- somebody is deciding whether to cast. So an unreadable unit returns nil, Core reports
-- `known = false`, and the display shows "?" — never a number we cannot stand behind.
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

--- The report for a unit: what Core makes of what we can see.
function Scan.Assess(unit, filter)
    filter = filter or "HELPFUL"
    return Core.Assess(Scan.Auras(unit, filter), { filter = filter })
end

Boonkeeper.Scan = Scan
return Scan
