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
---
--- `opts.trusted = false` says the caller cannot vouch that this list is COMPLETE. Blizzard only
--- serves a full aura list for you and your group; for anyone else what arrives may be truncated,
--- and a truncated list counted out loud is the confident lie this addon exists not to tell. So an
--- untrusted list is treated exactly as no list at all — not counted, not searched for world buffs,
--- reported as `known = false`. Absent is not false: a caller holding a list it built itself (the
--- demo panel, the probe) says nothing and keeps counting. The gate lives at BoonkeeperScan, the
--- one seam that touches the live client.
function Core.Assess(auras, opts)
    opts = opts or {}
    local filter = opts.filter or "HELPFUL"
    local wantHelpful = filter ~= "HARMFUL"
    local cap = opts.cap or Core.CAP[filter] or Core.CAP.HELPFUL
    local trusted = opts.trusted ~= false

    local report = {
        known    = auras ~= nil and trusted,
        count    = 0,
        cap      = cap,
        headroom = cap,
        severity = "clear",
        precious = {},
        booned   = false,
    }
    if not report.known then
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
-- Would this cast take a new slot?
-- ---------------------------------------------------------------------------
-- The count says how close the target is to losing a buff. It does not say whether YOUR next cast
-- is what pushes them over, and those are different questions: at 32/32 a Flash Heal is free, a
-- Renew on somebody already carrying yours is free, and a Renew on anybody else costs them their
-- oldest world buff. Same target, same instant, three answers — so this is decided per cast against
-- the target's actual list, not from a table of spells somebody once called risky.
--
-- The caller states the aura the cast would APPLY. That keeps the one genuinely spell-shaped fact
-- (Power Word: Shield applies a shield, not the Weakened Soul everybody notices) outside the
-- judgement, where it can be checked in the client, and leaves nothing here to be opinion.

-- What each cast APPLIES. Not "is this spell risky" — that question has no answer without the
-- target's list, which is the whole point of CastCost below. `false` means the cast puts no helpful
-- aura on anybody, so it can never take a helpful slot; a string is the name of the aura it does
-- apply, matched against what the target is already carrying.
--
-- Priest only, because that is the class this addon was asked for, and only the casts whose answer
-- is a fact rather than a recollection. Damage spells are absent on purpose: they land on enemies,
-- where the helpful pool is not the question.
--
-- Everything NOT in this table answers "unknown", and that is the table's safety property rather
-- than a gap in it. Another class's spell, a localised client's name for one of ours, a rank nobody
-- listed — all of them show the plain count and clear nothing. A wrong `false` here would be the
-- one dangerous entry: it would call a cast free that takes a slot. So a spell is listed only when
-- it is certain, and the list stays short.
local SPELL_AURA = {
    -- Applies no helpful aura. Safe at 32/32, on anybody, always.
    ["Lesser Heal"]       = false,
    ["Heal"]              = false,
    ["Greater Heal"]      = false,
    ["Flash Heal"]        = false,
    ["Prayer of Healing"] = false,
    ["Holy Nova"]         = false,
    ["Desperate Prayer"]  = false,
    ["Dispel Magic"]      = false,
    ["Cure Disease"]      = false,
    ["Resurrection"]      = false,

    -- Applies a helpful aura, which is its own name in every case below. Whether that COSTS a slot
    -- is still decided against the target: on somebody already carrying ours it is a refresh.
    ["Renew"]                        = "Renew",
    -- The shield is helpful and takes a slot. Weakened Soul is the harmful one everybody notices,
    -- and reasoning from it is how a safe-list clears the one spell it should not.
    ["Power Word: Shield"]           = "Power Word: Shield",
    ["Power Word: Fortitude"]        = "Power Word: Fortitude",
    ["Prayer of Fortitude"]          = "Prayer of Fortitude",
    ["Divine Spirit"]                = "Divine Spirit",
    ["Shadow Protection"]            = "Shadow Protection",
    ["Prayer of Shadow Protection"]  = "Prayer of Shadow Protection",
    ["Fear Ward"]                    = "Fear Ward",
    ["Abolish Disease"]              = "Abolish Disease",
    ["Inner Fire"]                   = "Inner Fire",
    ["Fade"]                         = "Fade",
}

--- Spell(name) → { applies = <aura name> | false }, or nil for a spell we hold no mapping for.
---
--- Keyed by name rather than by spell id so that every rank of Renew is one entry. The cost is that
--- a non-English client names its spells differently and matches nothing — which yields no verdict
--- at all, the same as any unmapped spell, and never a wrong one.
function Core.Spell(name)
    if type(name) ~= "string" then return nil end
    local applies = SPELL_AURA[name]
    if applies == nil then return nil end
    return { applies = applies }
end

--- Was this aura put there by the player?
---
--- Exact token match, and deliberately nothing cleverer: a raider is "player" and "raid7" at the
--- same time, and only the client can say so. Getting it wrong this way answers "not mine", which
--- costs a warning nobody needed; getting it wrong the other way tells somebody a slot is spare
--- when it is not. Callers that can ask the client pass their own `isMine`.
local function sourceIsPlayer(aura)
    local source = aura.sourceUnit
    if source == nil then return nil end
    return source == "player"
end

--- CastCost(auras, spell, opts) → { cost = "free" | "slot" | "unknown" }
---
--- `spell.applies` is the name of the helpful aura this cast would put on the target, or `false`
--- for a cast that applies none at all (a direct heal, a dispel, a resurrection). A spell we hold
--- no mapping for — nil, or a table that states nothing — is "unknown": an unmapped spell assumed
--- harmless is the addon quietly clearing a cast it knows nothing about.
---
--- `opts.trusted = false` and a nil list both mean the same thing they mean everywhere else: we
--- cannot vouch that this list is complete, so an absent Renew may simply have been truncated away
--- and no verdict is available. `opts.isMine(aura)` returns true, false, or nil for "the client did
--- not say", and nil must survive as "unknown" — an aura that MIGHT be mine, reported as a free
--- refresh, is exactly the confident lie this addon exists not to tell.
function Core.CastCost(auras, spell, opts)
    opts = opts or {}
    local applies = spell and spell.applies

    -- Answered before the list, and before trust: a spell that adds no helpful aura cannot cost a
    -- helpful slot on ANY target, readable or not, full or empty. It is the only case that is a
    -- property of the spell alone.
    if applies == false then return { cost = "free" } end
    if type(applies) ~= "string" then return { cost = "unknown" } end
    if auras == nil or opts.trusted == false then return { cost = "unknown" } end

    local isMine = opts.isMine or sourceIsPlayer
    local anonymous = false

    for _, aura in ipairs(auras) do
        -- Helpful only. Weakened Soul shares a cast with Power Word: Shield and sits in the other
        -- pool entirely; matching it would call the shield free on the one spell this gets wrong.
        if aura.isHelpful ~= false and aura.name == applies then
            local ours = isMine(aura)
            -- A refresh overwrites the slot it already holds. One certainly-mine match settles it,
            -- so keep walking past an unnamed one rather than giving up on the first doubt: each
            -- caster's HoT is its own aura, and theirs may be sitting in front of mine.
            if ours == true then return { cost = "free" } end
            if ours == nil then anonymous = true end
        end
    end

    if anonymous then return { cost = "unknown" } end
    return { cost = "slot" }
end

--- ShouldWarn(report, verdict) → is a spoken warning both true and worth the interruption?
---
--- The badge can afford caution — an amber number costs nobody anything. A line of chat mid-fight
--- cannot: it has to be right, and rare, or it is noise by the night it matters. So this is held to
--- the case where the loss is CERTAIN and expensive: the target is AT the cap, this cast takes a
--- new slot, something precious is in the pool that can be pushed out, and it is not stored in a
--- Chronoboon.
---
--- Headroom 0 and not merely "danger". With one slot left nothing is evicted yet, so the warning
--- would be false — and a warning that cries wolf one cast early is one nobody reads on the cast
--- where it is true.
function Core.ShouldWarn(report, verdict)
    if not report or not report.known then return false end
    if not verdict or verdict.cost ~= "slot" then return false end
    if report.headroom > 0 then return false end
    if report.booned then return false end
    return #report.precious > 0
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
    -- The fourth state is not a fifth step of alarm — it is the opposite, and it sits OUTSIDE the
    -- clear→full ramp on purpose. Green because it is the only reading that means "go", and it has
    -- to be unmistakable from red at the corner of the eye, at speed, mid-fight.
    free   = "40e070",
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

--- How the number should read given what THIS cast would cost.
---
--- A free cast takes the number out of the alarm ramp entirely: 32/32 in red is right for a Renew
--- and wrong for a Flash Heal, and the healer reading it is deciding between exactly those two.
--- Nothing else moves. A cast that takes a slot leaves the count's own severity alone — it is
--- already saying "don't" — and an unreachable verdict changes nothing at all, because a warning
--- that quietly softens when we stop being able to see is the failure this addon is built against.
function Core.CastSeverity(report, verdict)
    if verdict and verdict.cost == "free" then return "free" end
    if report and report.known then return report.severity end
    return "clear"
end

--- The label already wearing its colour — what a FontString is actually given.
---
--- Kept here rather than in the frame files so that "what does the player see" stays one tested
--- decision instead of one per surface. A nil report renders as unknown: frames ask us to draw
--- while they are being recycled, and that is a normal thing to be asked, not an error mid-fight.
---
--- `verdict` is optional and only ever recolours: the count itself stays whatever we can honestly
--- claim, "?" included. A free cast on a unit we cannot read is a real and useful thing to say —
--- "no idea how full they are, and it does not matter for this one".
function Core.Text(report, verdict)
    local severity = Core.CastSeverity(report, verdict)
    -- The escape is closed here, always. An unterminated |c bleeds its colour into every string
    -- drawn after it in the same frame — which is how one addon ends up recolouring another's.
    return string.format("|cff%s%s|r", Core.Colour(severity), Core.Label(report))
end

Boonkeeper.Core = Core
return Core
