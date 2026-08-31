-- BoonkeeperProbe — the experiment, not the product.
--
-- Everything Boonkeeper displays rests on one assumption that cannot be settled by reading the API
-- documentation: how much of another unit's aura list the client will actually hand an addon.
-- Blizzard serves full data for yourself and group members, but "full" for a 32-buff raider and
-- "full" for a boss carrying sixteen other people's debuffs are different claims, and a truncated
-- list read as a count is a confident lie at the exact moment someone is deciding whether to cast.
--
-- So: `/boon probe`, run once in a raid, prints what is really visible. It reports raw numbers and
-- says plainly which of them it cannot vouch for. Delete this file the day the answer is in
-- Research/ and nothing depends on the question any more.

Boonkeeper = Boonkeeper or {}

local Scan = Boonkeeper.Scan
local Core = Boonkeeper.Core

local Probe = {}

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fd3ffBoonkeeper|r " .. msg)
end

-- One line per unit: what we can see, and from whom. `foreign` is the count of auras cast by
-- somebody other than us — the number that decides whether a boss debuff counter is possible at all,
-- because if it is always zero we can only ever see our own.
local function report(label, unit)
    if not UnitExists(unit) then return end

    local helpful = Scan.Auras(unit, "HELPFUL")
    local harmful = Scan.Auras(unit, "HARMFUL")
    local foreign = 0
    for _, aura in ipairs(harmful or {}) do
        local source = aura.sourceUnit
        if source and not UnitIsUnit(source, "player") and not UnitIsUnit(source, "pet") then
            foreign = foreign + 1
        end
    end

    say(string.format(
        "%s (%s): buffs %s, debuffs %s, debuffs from others %d",
        label,
        UnitName(unit) or "?",
        Core.Label(Core.Assess(helpful, { filter = "HELPFUL" })),
        Core.Label(Core.Assess(harmful, { filter = "HARMFUL" })),
        foreign))
end

--- Dump what the client will tell us about everyone in range. Run it in a raid, on a boss pull, and
--- paste the output into Process/Bugs.md against PROBE-1.
function Probe.Run()
    say("probe — aura visibility. API: " ..
        (_G.C_UnitAuras and "C_UnitAuras" or "legacy UnitAura") ..
        ", flavour id " .. tostring(_G.WOW_PROJECT_ID))

    report("you", "player")
    report("target", "target")

    local group = IsInRaid() and "raid" or "party"
    local size = GetNumGroupMembers() or 0
    if size == 0 then
        say("not in a group — the group half of the probe needs a raid to mean anything")
        return
    end

    -- The group is the whole point: if these counts read plausibly (people with world buffs sitting
    -- in the twenties, not everyone pinned at the same small number), other players are readable.
    for i = 1, size do
        local unit = group .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            report(group .. i, unit)
        end
    end

    say("if every group member reports the same buff count, the list is truncated and the " ..
        "nameplate number must not ship. Record the result against PROBE-1.")
end

Boonkeeper.Probe = Probe
return Probe
