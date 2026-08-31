-- BoonkeeperCore — PURE: how full a unit's aura slots are, and how alarmed to be about it.
--
-- Nothing in here touches the WoW API. It takes a plain list of auras and returns a plain report;
-- BoonkeeperScan is the only file allowed to obtain that list from the client, and the display files
-- only render the report. That split is the whole point: the question Boonkeeper answers is asked
-- mid-fight, when being wrong costs somebody their Rallying Cry, and a judgement that lives inside
-- the client can only be tested by getting it wrong in Naxxramas.
--
-- Tested by Tests/core_test.lua, which runs under plain Lua 5.1 outside the game.

-- One namespace global (Code Style: prefix any unavoidable global with the addon name). The
-- addon-private `...` table can't be shared with Tests/, which loads each module with dofile().
Boonkeeper = Boonkeeper or {}

local Core = {}

-- ---------------------------------------------------------------------------
-- The caps
-- ---------------------------------------------------------------------------
-- Classic Era holds 32 helpful and 16 harmful auras per unit. Past the helpful cap the OLDEST buff
-- is dropped, which is why a Renew can cost somebody a world buff; past the harmful cap a new
-- debuff simply does not land. Both numbers are flavour facts, not preferences — a client that
-- changes them changes this table and nothing else.

Core.CAP = { HELPFUL = 32, HARMFUL = 16 }

-- How much room left before each step of alarm. Headroom, not count: the count is only interesting
-- relative to the ceiling, and the ceiling differs between buffs and debuffs.
Core.WATCH_AT  = 5   -- headroom <= 5 → worth a glance
Core.DANGER_AT = 2   -- headroom <= 2 → do not cast the optional thing

-- ---------------------------------------------------------------------------
-- Precious auras
-- ---------------------------------------------------------------------------
-- The cost of overflowing is never "a buff fell off" — it is "*that* buff fell off". These are the
-- Classic Era world buffs: hours of somebody's evening, unrecoverable, and exactly what a reflex
-- Renew knocks loose. Matched by name because that is what the client hands us for another player.

local PRECIOUS = {
    ["Rallying Cry of the Dragonslayer"] = true,   -- Onyxia / Nefarian head
    ["Warchief's Blessing"]              = true,   -- Rend head
    ["Songflower Serenade"]              = true,   -- Felwood
    ["Spirit of Zandalar"]               = true,   -- Zul'Gurub
    ["Fengus' Ferocity"]                 = true,   -- Dire Maul tribute
    ["Mol'dar's Moxie"]                  = true,
    ["Slip'kik's Savvy"]                 = true,
    ["Traces of Silithyst"]              = true,
}

-- Sayge's fortunes are one buff with seven names, so they are matched by prefix rather than listed.
local PRECIOUS_PREFIX = { "Sayge's Dark Fortune of" }

-- The Chronoboon stores a player's world buffs away where nothing can knock them off. A unit
-- carrying it is "booned", and the whole warning is moot for them — which is precisely why the guild
-- rule is phrased as "no Renew while UNbooned".
local BOON_STORE = { ["Chronoboon Displacement"] = true }

--- Is this aura one we would be sorry to lose?
function Core.IsPrecious(name)
    if type(name) ~= "string" then return false end
    if PRECIOUS[name] then return true end
    for _, prefix in ipairs(PRECIOUS_PREFIX) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--- Is this the aura that means "my world buffs are stored, cast freely"?
function Core.IsBoonStore(name)
    return type(name) == "string" and BOON_STORE[name] == true
end

-- ---------------------------------------------------------------------------
-- The assessment
-- ---------------------------------------------------------------------------

local function severityFor(headroom)
    if headroom <= 0 then return "full" end
    if headroom <= Core.DANGER_AT then return "danger" end
    if headroom <= Core.WATCH_AT then return "watch" end
    return "clear"
end

--- Assess(auras, opts) → report
---
--- `auras` is an array of { name = string, isHelpful = boolean }; nil means we could not see this
--- unit's auras at all, which is a different thing from seeing that it has none and is reported as
--- such (`known = false`). Never fabricate a zero — an unseen unit gets a question mark.
---
--- `opts.filter` is "HELPFUL" (default) or "HARMFUL" and selects both which auras count and which
--- cap they count against.
function Core.Assess(auras, opts)
    opts = opts or {}
    local filter = opts.filter or "HELPFUL"
    local wantHelpful = filter ~= "HARMFUL"
    local cap = opts.cap or Core.CAP[filter] or Core.CAP.HELPFUL

    local report = {
        known    = auras ~= nil,
        count    = 0,
        cap      = cap,
        headroom = cap,
        severity = "clear",
        precious = {},
        booned   = false,
    }
    if not auras then
        return report
    end

    for _, aura in ipairs(auras) do
        -- A missing isHelpful reads as helpful: every aura the client hands us for a friendly unit
        -- through the helpful filter is one, and guessing "harmful" would silently undercount.
        local isHelpful = aura.isHelpful ~= false
        if isHelpful == wantHelpful then
            report.count = report.count + 1
            if Core.IsBoonStore(aura.name) then
                report.booned = true
            elseif Core.IsPrecious(aura.name) then
                report.precious[#report.precious + 1] = aura.name
            end
        end
    end

    -- Clamp at zero. The server has been seen reporting more auras than the cap for the frame in
    -- which one is being dropped, and "-1 slots left" on a nameplate is worse than "0".
    report.headroom = math.max(0, cap - report.count)
    report.severity = severityFor(report.headroom)

    -- One step of escalation, and only one: a live world buff turns "worth a glance" into "don't".
    -- It never de-escalates, and it cannot push past full, which is already the top.
    if report.severity == "watch" and not report.booned and #report.precious > 0 then
        report.severity = "danger"
    end

    return report
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------

-- Deliberately not the four status colours of a health bar: this is read out of the corner of the
-- eye while healing, so clear is dim and full is loud.
local COLOUR = {
    clear  = "aaaaaa",
    watch  = "ffd100",
    danger = "ff8000",
    full   = "ff2020",
}

--- The short label that goes on a nameplate or unit frame: used/cap, or "?" when we cannot see.
function Core.Label(report)
    if not report or not report.known then return "?" end
    return string.format("%d/%d", report.count, report.cap)
end

--- Hex colour for a severity. An unrecognised severity falls back to `clear` rather than nil, so a
--- future severity can never blank a label out.
function Core.Colour(severity)
    return COLOUR[severity] or COLOUR.clear
end

Boonkeeper.Core = Core
return Core
