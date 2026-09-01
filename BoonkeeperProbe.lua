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

-- Is this aura one WE put there? Three answers, not two: yes, no, and "the client did not say".
-- A nil source is the case that matters, because a cast warning that reads "unknown" as "not mine"
-- is merely cautious, while one that reads it as "mine" tells somebody a slot is free when it is
-- not.
local function mine(aura)
    local source = aura.sourceUnit
    if not source then return nil end
    -- UnitIsUnit on a stale source token is a normal thing to be told nothing about, not an error.
    return UnitIsUnit(source, "player") == true or UnitIsUnit(source, "pet") == true
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
        if mine(aura) == false then
            foreign = foreign + 1
        end
    end

    -- WARN-2 asks "would this cast take a NEW slot", and can only answer it if the client names the
    -- caster of an aura on somebody else. Nobody has stood in a raid and checked that it does, so
    -- the probe counts the three answers separately: `named` is how often we were told anything at
    -- all, and it is `unknown` (named subtracted from the count) that decides whether the feature
    -- is possible. `timed` does the same job for WARN-3 — permanent auras report duration 0 and
    -- cannot be ranked by application time, so a unit whose buffs are mostly untimed is one whose
    -- drop order we could never predict.
    local named, ours, timed = 0, 0, 0
    for _, aura in ipairs(helpful or {}) do
        local isMine = mine(aura)
        if isMine ~= nil then
            named = named + 1
            if isMine then ours = ours + 1 end
        end
        if aura.duration and aura.duration > 0 and aura.expirationTime then
            timed = timed + 1
        end
    end

    -- The probe deliberately counts a list Scan.Assess would refuse: finding out whether an
    -- untrusted list is complete is the entire experiment. `trusted` is printed so the recorded
    -- output can be read back against what the display showed at the time — an untrusted line here
    -- is a unit the target frame was showing "?" for.
    say(string.format(
        "%s (%s): buffs %s, debuffs %s, debuffs from others %d, trusted %s",
        label,
        UnitName(unit) or "?",
        Core.Label(Core.Assess(helpful, { filter = "HELPFUL" })),
        Core.Label(Core.Assess(harmful, { filter = "HARMFUL" })),
        foreign,
        Scan.Trusted(unit) and "yes" or "NO"))
    say(string.format(
        "    buffs with a named caster %d of %d (%d ours), with a live timer %d",
        named, #(helpful or {}), ours, timed))
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
    say("if a group member's buffs report no named caster, WARN-2 cannot tell a free refresh " ..
        "from a new slot on anyone but you. Record that against WARN-2a.")
end

Boonkeeper.Probe = Probe
return Probe
