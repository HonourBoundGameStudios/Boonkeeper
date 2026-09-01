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
-- Trust. Blizzard only serves a full aura list for you and your group; for anyone
-- else the list we are handed may be TRUNCATED, and a truncated list reported as a
-- count is the confident lie this addon exists not to tell. An untrusted list is
-- therefore not data to be counted — it is the same as not seeing the unit at all.
-- ---------------------------------------------------------------------------
local untrusted = Core.Assess(auras(28), { trusted = false })
H.eq(untrusted.known, false, "an untrusted list is not knowledge")
H.eq(untrusted.count, 0, "an untrusted list contributes no count")
H.eq(Core.Label(untrusted), "?", "an untrusted unit shows a question mark, never its truncated count")
H.ok(Core.Text(untrusted):find("%d") == nil, "an untrusted unit renders no digit at all")

-- Precious buffs are found by walking the list, so an untrusted list must not report them either:
-- "no world buffs seen" from a truncated list is as wrong as a low count from one.
H.eq(#untrusted.precious, 0, "an untrusted list names no precious auras")
H.eq(untrusted.booned, false, "an untrusted list cannot claim the unit is booned")

-- Callers holding a list they already vouched for (the demo panel, the probe dump) say nothing and
-- keep counting: the gate belongs at the one seam that touches the live client.
H.eq(Core.Assess(auras(28), { trusted = true }).count, 28, "an explicitly trusted list is counted")
H.eq(Core.Assess(auras(28)).count, 28, "an unstated trust still counts — absent is not false")

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
H.eq(Core.Label(Core.Assess(auras(28))), "28/32", "the label is used/cap")
H.eq(Core.Label(Core.Assess(nil)), "?", "an unknown unit shows a question mark, never a fake zero")
H.ok(Core.Colour("danger") ~= Core.Colour("clear"), "severities are visually distinguishable")
H.ok(Core.Colour("nonsense") ~= nil, "an unknown severity still yields a colour rather than nil")

-- Core.Text is what actually reaches a FontString: the label already wearing its colour. The frame
-- files must not build this themselves — pasting a colour onto a number is a decision about whether
-- the player is being told "fine" or "stop", and it belongs where it can be tested.
local watchText = Core.Text(Core.Assess(auras(28)))
H.ok(watchText:find("28/32", 1, true) ~= nil, "the rendered text carries the label")
H.ok(watchText:find(Core.Colour("watch"), 1, true) ~= nil, "the rendered text wears the severity colour")

-- What the player actually reads, with the colour escapes taken off. Asserting "no digit" against
-- the whole string would be asserting something about the colour HEX as well — true today only
-- because "aaaaaa" happens to have no digits in it, and a silent lie the day a colour changes.
local function visible(text)
    return (text:gsub("|cff%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- An unterminated |c escape bleeds its colour into every string drawn after it in the same frame,
-- which is how one addon recolours another's unit frame. Always close it.
H.ok(watchText:sub(1, 4) == "|cff", "the rendered text opens a colour escape")
H.ok(watchText:sub(-2) == "|r", "the rendered text closes its colour escape")

-- The "?" path all the way through to the pixels: an unreadable unit must never render a digit.
local unknownText = Core.Text(Core.Assess(nil))
H.ok(unknownText:find("?", 1, true) ~= nil, "an unreadable unit renders a question mark")
H.ok(visible(unknownText):find("%d") == nil, "an unreadable unit renders no digit at all")

-- Frames hand us whatever they have while they are being recycled; a nil report is a normal thing
-- to be asked to draw, not an error in combat.
H.eq(Core.Text(nil), unknownText, "a missing report renders as unknown, not as an error")

-- ---------------------------------------------------------------------------
-- Would THIS cast take a new slot? (WARN-2)
-- ---------------------------------------------------------------------------
-- The question is never "is this spell risky". It is whether this cast, on this target, consumes a
-- slot that is not already spent — and the same spell answers it both ways depending on what the
-- target is already carrying. So the caller states the helpful aura the cast would apply and Core
-- reads the target's list, rather than anybody keeping a table of opinions about spells.

local MINE = { name = "Renew", isHelpful = true, sourceUnit = "player" }
local THEIRS = { name = "Renew", isHelpful = true, sourceUnit = "party3" }
local ANON = { name = "Renew", isHelpful = true }   -- the client did not say who cast it

local full = auras(32)

-- Case 1: a spell that applies no helpful aura never touches the pool. `applies = false` is the
-- caller saying so — and it is the ONE case that holds without reading the target at all, which is
-- why it is answered before trust, before the list, even at 32/32.
H.eq(Core.CastCost(full, { applies = false }).cost, "free",
     "a spell that applies no helpful aura is free at 32/32")
H.eq(Core.CastCost(nil, { applies = false }, { trusted = false }).cost, "free",
     "and free even on a unit we cannot read at all")

-- Case 2: a refresh overwrites the slot it already occupies; a first application takes a new one.
H.eq(Core.CastCost({ MINE }, { applies = "Renew" }).cost, "free",
     "refreshing my own Renew costs nothing")
H.eq(Core.CastCost(auras(20), { applies = "Renew" }).cost, "slot",
     "a Renew on somebody not carrying one takes a new slot")

-- Each caster's HoT is its own aura in Classic: another priest's Renew is not mine to overwrite.
H.eq(Core.CastCost({ THEIRS }, { applies = "Renew" }).cost, "slot",
     "another priest's Renew does not make mine free")
H.eq(Core.CastCost({ THEIRS, MINE }, { applies = "Renew" }).cost, "free",
     "but mine among theirs still is")

-- The honest third answer. An aura whose caster the client would not name might be mine and might
-- not, and "might be mine" reported as free is the addon telling somebody a slot is spare at the
-- exact moment it is not.
H.eq(Core.CastCost({ ANON }, { applies = "Renew" }).cost, "unknown",
     "an aura with no named caster cannot be claimed as my refresh")
H.eq(Core.CastCost({ ANON, MINE }, { applies = "Renew" }).cost, "free",
     "unless one of them is definitely mine")

-- Case 3: Power Word: Shield. The debuff it leaves lands in the HARMFUL pool and is irrelevant
-- here; the shield itself is a helpful aura and does take a slot. Reasoning from Weakened Soul —
-- present, harmful, and not what the spell applies — must not make the cast look free.
local shielded = { { name = "Weakened Soul", isHelpful = false, sourceUnit = "player" } }
H.eq(Core.CastCost(shielded, { applies = "Power Word: Shield" }).cost, "slot",
     "Weakened Soul is not the shield: the shield still costs a slot")
H.eq(Core.CastCost({ { name = "Power Word: Shield", isHelpful = true, sourceUnit = "player" } },
                   { applies = "Power Word: Shield" }).cost, "free",
     "a shield already up from me is a refresh")

-- Everything else that cannot be answered is answered as unknown, never guessed.
H.eq(Core.CastCost(nil, { applies = "Renew" }).cost, "unknown",
     "an unreadable unit yields no verdict")
H.eq(Core.CastCost(full, { applies = "Renew" }, { trusted = false }).cost, "unknown",
     "nor does a list we may not vouch for — a missing Renew may simply be truncated away")
H.eq(Core.CastCost(full, nil).cost, "unknown",
     "a spell we hold no aura mapping for is unknown, not assumed harmless")
H.eq(Core.CastCost(full, {}).cost, "unknown",
     "and a mapping that states nothing is the same silence")

-- Who counts as "me" is a client question (a raider is "player" and "raid7" at once), so Core takes
-- the answer rather than pretending to know it. The default is exact-token, which errs towards
-- "costs a slot" — the safe direction for a warning.
local byToken = Core.CastCost({ { name = "Renew", isHelpful = true, sourceUnit = "raid7" } },
                              { applies = "Renew" },
                              { isMine = function(aura) return aura.sourceUnit == "raid7" end })
H.eq(byToken.cost, "free", "the caller decides which source tokens are the player")


-- ---------------------------------------------------------------------------
-- The fourth state: full, and this cast is still free
-- ---------------------------------------------------------------------------
-- 32/32 in alarm red is the right thing to show somebody about to Renew and the wrong thing to show
-- the same healer about to Flash Heal — the count has not changed, but "don't" has become "go
-- ahead". A verdict therefore recolours the number; it never rewrites it.

local fullReport = Core.Assess(auras(32))
H.eq(fullReport.severity, "full", "the setup is a target with no room at all")

H.eq(Core.CastSeverity(fullReport, { cost = "free" }), "free",
     "a free cast on a full target is not a warning")
H.eq(Core.CastSeverity(fullReport, { cost = "slot" }), "full",
     "a cast that takes a slot leaves the alarm exactly as it was")
H.eq(Core.CastSeverity(fullReport, { cost = "unknown" }), "full",
     "and a verdict we could not reach changes nothing — silence never de-escalates")
H.eq(Core.CastSeverity(fullReport, nil), "full",
     "no verdict at all is the plain count, which is what every surface shows today")

-- It is a recolour and only a recolour: a free cast does not make a full target look emptier.
local freeText = Core.Text(fullReport, { cost = "free" })
H.ok(freeText:find("32/32", 1, true) ~= nil, "the free state still states the real count")
H.ok(freeText:find(Core.Colour("free"), 1, true) ~= nil, "the free state wears its own colour")
H.ok(Core.Colour("free") ~= Core.Colour("full"), "free and full cannot be confused at a glance")
H.ok(Core.Colour("free") ~= Core.Colour("clear"), "nor free and clear")

-- A spell that applies no helpful aura is free on a unit we cannot count at all, and saying so is
-- honest: the "?" stays a "?" — we still will not claim a number — but the colour says cast it.
local unknownFree = Core.Text(Core.Assess(nil), { cost = "free" })
H.ok(unknownFree:find("?", 1, true) ~= nil, "an unreadable unit still renders a question mark")
H.ok(visible(unknownFree):find("%d") == nil, "and still no digit")
H.ok(unknownFree:find(Core.Colour("free"), 1, true) ~= nil, "but a free cast on it reads as free")

-- ---------------------------------------------------------------------------
-- Which aura does this spell apply?
-- ---------------------------------------------------------------------------
-- The one genuinely spell-shaped fact, kept in a table because it is a fact: what a cast puts on
-- the target. Everything else is read from the target's list. An unmapped spell must answer
-- "we do not know" rather than "harmless" — a table that silently clears every spell nobody
-- bothered to list is the same confident lie as a made-up count.

H.eq(Core.Spell("Renew").applies, "Renew", "Renew applies Renew")
H.eq(Core.Spell("Power Word: Fortitude").applies, "Power Word: Fortitude", "a buff applies itself")
H.eq(Core.Spell("Flash Heal").applies, false, "a direct heal applies no helpful aura at all")
H.eq(Core.Spell("Dispel Magic").applies, false, "nor does a dispel")
H.eq(Core.Spell("Resurrection").applies, false, "nor a resurrection")

-- Power Word: Shield is the spell every "safe list" gets backwards. The shield is helpful and takes
-- a slot; Weakened Soul is the harmful one everybody notices and is not what this table records.
H.eq(Core.Spell("Power Word: Shield").applies, "Power Word: Shield",
     "Power Word: Shield applies the shield, not Weakened Soul")
H.eq(Core.Spell("Weakened Soul"), nil, "the debuff is not a spell we cast")

-- Silence is the safe answer, and it has to stay silence. A spell nobody has mapped — another
-- class's, a localised client's name for one of ours, an addon-cast macro — reaches CastCost as
-- nil and comes back "unknown", which shows the plain count and warns about nothing.
H.eq(Core.Spell("Wild Growth"), nil, "a spell we never mapped is unmapped, not harmless")
H.eq(Core.Spell("Rénovation"), nil, "a localised name we do not carry is unmapped too")
H.eq(Core.Spell(nil), nil, "no spell name is no mapping")
H.eq(Core.Spell(42), nil, "and neither is nonsense")

H.eq(Core.CastCost(auras(32), Core.Spell("Flash Heal")).cost, "free",
     "the map feeds the verdict: Flash Heal on a full target is free")
H.eq(Core.CastCost(auras(32), Core.Spell("Wild Growth")).cost, "unknown",
     "and an unmapped spell reaches the verdict as unknown")

H.done()
