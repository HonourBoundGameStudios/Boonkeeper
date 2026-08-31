-- BoonkeeperCore — the whole judgement, exercised outside the game.
--
-- Everything Boonkeeper actually *decides* lives in BoonkeeperCore: how many aura slots a unit has
-- used, how much room is left, and how alarmed to be about it. None of that touches the WoW API, so
-- all of it is observable here rather than only in a raid, which is the one place it is expensive to
-- be wrong.
--
-- Usage: lua Tests/core_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")
dofile("BoonkeeperCore.lua")
local Core = Boonkeeper.Core

H.start("BoonkeeperCore")

-- Build an aura list: n filler buffs, plus any extra named ones appended.
local function auras(n, ...)
    local list = {}
    for i = 1, n do
        list[i] = { name = "Filler " .. i, isHelpful = true }
    end
    for _, name in ipairs({ ... }) do
        list[#list + 1] = { name = name, isHelpful = true }
    end
    return list
end

-- ---------------------------------------------------------------------------
-- The caps. Classic Era: 32 helpful, 16 harmful. Wrong here and every number
-- downstream is wrong, so they are asserted rather than trusted.
-- ---------------------------------------------------------------------------
H.eq(Core.CAP.HELPFUL, 32, "helpful cap is 32")
H.eq(Core.CAP.HARMFUL, 16, "harmful cap is 16")

-- ---------------------------------------------------------------------------
-- Counting and headroom
-- ---------------------------------------------------------------------------
local r = Core.Assess(auras(10))
H.eq(r.count, 10, "counts the helpful auras")
H.eq(r.cap, 32, "defaults to the helpful cap")
H.eq(r.headroom, 22, "headroom is cap minus count")
H.eq(r.severity, "clear", "ten buffs is nothing to worry about")

H.eq(Core.Assess({}).count, 0, "an empty list counts zero")
H.eq(Core.Assess({}).headroom, 32, "an empty list is all headroom")
H.eq(Core.Assess(nil).count, 0, "a nil list is not an error — an unseen unit reads as unknown")
H.eq(Core.Assess(nil).known, false, "a nil list reports itself as not known")
H.eq(Core.Assess({}).known, true, "an empty list IS known: the unit genuinely has no buffs")

-- Headroom never goes negative. The server has been seen to report more auras than the cap during
-- the frame a buff is being dropped; "-1 slots left" on someone's nameplate is worse than "0".
local over = Core.Assess(auras(35))
H.eq(over.headroom, 0, "headroom clamps at zero rather than going negative")
H.eq(over.count, 35, "the raw count is still reported honestly")
H.eq(over.severity, "full", "over the cap is full")

-- The filter picks which cap applies. A boss's 16 debuff slots are the same question.
local d = Core.Assess({ { name = "Corrosive Poison", isHelpful = false } }, { filter = "HARMFUL" })
H.eq(d.count, 1, "counts harmful auras when asked for them")
H.eq(d.cap, 16, "harmful uses the 16-slot cap")
H.eq(Core.Assess(auras(5), { filter = "HARMFUL" }).count, 0, "helpful auras do not fill debuff slots")

-- ---------------------------------------------------------------------------
-- Severity — the thing that is actually readable mid-fight
-- ---------------------------------------------------------------------------
H.eq(Core.Assess(auras(26)).severity, "clear", "6 slots left is still clear")
H.eq(Core.Assess(auras(27)).severity, "watch", "5 slots left is worth watching")
H.eq(Core.Assess(auras(30)).severity, "danger", "2 slots left is dangerous")
H.eq(Core.Assess(auras(32)).severity, "full", "at the cap is full")

-- ---------------------------------------------------------------------------
-- Precious buffs and the Chronoboon
-- ---------------------------------------------------------------------------
-- This is the whole reason the addon exists: the cost of overflowing is not "a buff fell off", it is
-- "Rallying Cry fell off". A world buff present with little headroom escalates one step.
H.ok(Core.IsPrecious("Rallying Cry of the Dragonslayer"), "a world buff is precious")
H.ok(Core.IsPrecious("Songflower Serenade"), "Songflower is precious")
H.ok(not Core.IsPrecious("Renew"), "a heal-over-time is not precious")
H.ok(not Core.IsPrecious(nil), "a nameless aura is not precious and is not an error")

local risky = Core.Assess(auras(27, "Rallying Cry of the Dragonslayer"))
H.eq(risky.count, 28, "the world buff counts toward the cap like anything else")
H.eq(risky.severity, "danger", "a live world buff escalates a watch to a danger")
H.eq(risky.precious[1], "Rallying Cry of the Dragonslayer", "names what is at risk")

-- Booned: the world buffs are stored in the Chronoboon, so there is nothing precious to knock off
-- and the count is only a count again. "Unbooned" is exactly when the warning matters.
local booned = Core.Assess(auras(27, "Chronoboon Displacement"))
H.eq(booned.booned, true, "the Chronoboon aura marks the unit as booned")
H.eq(booned.severity, "watch", "a booned unit is not escalated — the buffs are already safe")
H.eq(#booned.precious, 0, "stored world buffs are not listed as at risk")

-- Escalation only ever goes up, and never past full.
H.eq(Core.Assess(auras(10, "Songflower Serenade")).severity, "clear",
    "plenty of headroom stays clear even with a world buff up")
H.eq(Core.Assess(auras(31, "Songflower Serenade")).severity, "full", "full cannot escalate further")

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
H.eq(Core.Label(Core.Assess(auras(28))), "28/32", "the label is used/cap")
H.eq(Core.Label(Core.Assess(nil)), "?", "an unknown unit shows a question mark, never a fake zero")
H.ok(Core.Colour("danger") ~= Core.Colour("clear"), "severities are visually distinguishable")
H.ok(Core.Colour("nonsense") ~= nil, "an unknown severity still yields a colour rather than nil")

H.done()
