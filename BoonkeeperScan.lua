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

-- Era's group sizes. The roster walk below is bounded by these rather than by GetNumGroupMembers,
-- which is one more client function whose behaviour here nobody has stood in a raid and confirmed.
local MAX_PARTY = 4
local MAX_RAID = 40

--- Does `unit` name somebody who is also on our roster, reached by a different handle?
---
--- The unit you TARGET is handed to us as "target", never as "raid7", and whether the client will
--- resolve that arbitrary token back to a group member is exactly the question nobody has been able
--- to answer without standing in a raid. So we do not ask it: we walk the roster tokens we named
--- ourselves and compare identities with `UnitIsUnit`, which the in-client self-test has already
--- shown works on Era. Slower, and it cannot be wrong in the direction that matters.
local function inGroupByIdentity(unit)
    -- Cost control before correctness has anything to do: solo, there is no roster to walk, and
    -- SEE-3 will be asking this question once per nameplate per update.
    local prefix, limit
    if UnitExists("raid1") then
        prefix, limit = "raid", MAX_RAID
    elseif UnitExists("party1") then
        prefix, limit = "party", MAX_PARTY
    else
        return false
    end

    for index = 1, limit do
        local token = prefix .. index
        -- Roster tokens are contiguous, so the first gap is the end of the group — walking all 40
        -- for a five-man would cost thirty-five pointless comparisons per unit per update.
        if not UnitExists(token) then break end
        if UnitIsUnit(unit, token) then return true end
    end
    return false
end

--- Is this a unit the client is documented to serve a COMPLETE aura list for?
---
--- Yourself, your party, your raid — and nobody else, until PROBE-1 says what a stranger's list
--- actually contains. Note this is deliberately NARROWER than "we got some auras back": a stranger's
--- list arrives too, and looks perfectly ordinary, and may be missing the world buff that was the
--- whole reason to look. Guessing wide here is how the addon ends up stating a number it cannot
--- stand behind.
---
--- The failure this is arranged against is the quiet one. If `UnitInParty`/`UnitInRaid` will not
--- resolve "target", then every raid member you cast on reads as untrusted and shows `?` — the addon
--- doing nothing at all in the one situation it exists for, with no error and no wrong number to
--- notice. They stay as the cheap first answer; `inGroupByIdentity` is what makes the gate correct
--- whether or not they cooperate.
function Scan.Trusted(unit)
    if not unit then return false end
    -- `UnitInRaid` yields a raid INDEX, so each answer is forced to a boolean rather than passed on:
    -- raid index 0 does not exist today, but a truthy number leaking out of a yes/no question is the
    -- kind of thing that survives until the one client where it does not.
    if UnitIsUnit(unit, "player") then return true end
    if UnitInParty(unit) then return true end
    if UnitInRaid(unit) then return true end
    if inGroupByIdentity(unit) then return true end
    return false
end

--- The unit token for a player named `name`, or nil if they are not somebody we can read.
---
--- The cast event names its target by NAME, and every question we can ask about auras is asked with
--- a token. This is the join, and it is allowed to fail: a cast at somebody off our roster resolves
--- to nothing, and nothing is exactly what should then be said about them.
---
--- "target" is tried before the roster on purpose. The same body is both "target" and "raid2", and
--- the badge is drawn on the target frame — resolving to the roster handle would land the verdict
--- on a frame nobody is looking at.
function Scan.UnitByName(name)
    if type(name) ~= "string" or name == "" then return nil end

    for _, token in ipairs({ "target", "player" }) do
        if UnitExists(token) and UnitName(token) == name then return token end
    end

    local prefix, limit
    if UnitExists("raid1") then
        prefix, limit = "raid", MAX_RAID
    elseif UnitExists("party1") then
        prefix, limit = "party", MAX_PARTY
    else
        return nil
    end

    for index = 1, limit do
        local token = prefix .. index
        -- Contiguous tokens: the first gap is the end of the group, as in the roster walk above.
        if not UnitExists(token) then break end
        if UnitName(token) == name then return token end
    end
    return nil
end

--- Did WE put this aura here?
---
--- Three answers, and the third is the one worth the code: a client that names no source leaves us
--- unable to tell our own Renew from another priest's, and nil has to survive as nil all the way to
--- the verdict. Asking `UnitIsUnit` rather than comparing to "player" is what makes a source of
--- "raid7" resolve to us — the same aliasing the trust gate above is built around.
---
--- Only the player, not the pet: a pet's aura is the pet's, and recasting our own spell would not
--- overwrite it. Counting it as ours would call a cast free that takes a slot.
local function castByPlayer(aura)
    local source = aura.sourceUnit
    if not source then return nil end
    return UnitIsUnit(source, "player") == true
end

--- Would casting this on `unit` take a new helpful slot? → { cost = "free" | "slot" | "unknown" }
---
--- The whole judgement is Core's; this supplies the two things Core cannot know — whether the list
--- may be believed, and which source tokens are us.
function Scan.CastCost(unit, spell)
    return Core.CastCost(Scan.Auras(unit, "HELPFUL"), spell, {
        trusted = Scan.Trusted(unit),
        isMine = castByPlayer,
    })
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
