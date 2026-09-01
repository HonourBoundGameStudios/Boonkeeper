-- BoonkeeperBroker — what Boonkeeper publishes to a LibDataBroker display (Sigil, Titan, any).
--
-- Sigil's own rule for a plugin with nothing to say is an em dash, "not a zero, not an empty string,
-- not its own name dressed up as data", because a wrong number is worse than no number. That is the
-- same rule this addon is built on, so the seam between them is where it must hold hardest: what we
-- publish to somebody else's bar is a number we are standing behind in public.
--
-- Three states that must stay distinct and never collapse into each other:
--   no target        — nobody is asking the question. Publish nothing; the display shows its own
--                      empty glyph. Fabricating a "0/32" here would be inventing a healthy raider.
--   unreadable unit  — the question was asked and we cannot answer. Publish "?".
--   readable unit    — the answer.
--
-- Usage: lua Tests/broker_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")
dofile("BoonkeeperCore.lua")
dofile("BoonkeeperBroker.lua")
local Core = Boonkeeper.Core
local Broker = Boonkeeper.Broker

H.start("BoonkeeperBroker")

H.ok(Broker ~= nil, "BoonkeeperBroker loads standalone — the published fields are pure")

local function auras(n, ...)
    local list = {}
    for i = 1, n do list[i] = { name = "Filler " .. i, isHelpful = true } end
    for _, name in ipairs({ ... }) do list[#list + 1] = { name = name, isHelpful = true } end
    return list
end

-- ---------------------------------------------------------------------------
-- The text on somebody else's bar
-- ---------------------------------------------------------------------------

-- Nothing targeted is not a reading of zero. Publishing nil lets the display render its own empty
-- state; publishing "0/32" would put a healthy raider on the bar who does not exist.
H.eq(Broker.Text(nil, false), nil, "no target publishes nothing at all, not a zero")
H.eq(Broker.Text(Core.Assess(auras(10)), false), nil, "no target wins even if we have a stale report")

local watch = Core.Assess(auras(28))
H.ok(Broker.Text(watch, true):find("28/32", 1, true) ~= nil, "a readable target publishes its count")
H.ok(Broker.Text(watch, true):find(Core.Colour("watch"), 1, true) ~= nil,
    "the published text carries the severity colour")

-- The one thing, at the seam. An unreadable unit must reach another addon's bar as a question mark.
local unknown = Core.Assess(nil)
H.ok(Broker.Text(unknown, true):find("?", 1, true) ~= nil, "an unreadable target publishes '?'")
H.ok(Broker.Text(unknown, true):find("%d") == nil, "an unreadable target publishes no digit")

-- ---------------------------------------------------------------------------
-- The icon tint
-- ---------------------------------------------------------------------------
-- Sigil reads iconR/iconG/iconB as 0-1 floats. Handing it 0-255 would wash every icon to white and
-- the severity would be invisible on the bar.
local r, g, b = Broker.IconColour("full")
H.ok(r and g and b, "a severity yields three components")
H.ok(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1, "components are 0-1 floats")
H.ok(r > g and r > b, "full tints red")

local cr = Broker.IconColour("clear")
local dr = Broker.IconColour("danger")
H.ok(cr ~= dr, "severities tint differently")
H.ok(Broker.IconColour("nonsense") ~= nil, "an unknown severity still yields a tint rather than nil")

-- ---------------------------------------------------------------------------
-- The tooltip
-- ---------------------------------------------------------------------------

local function joined(report, hasTarget)
    return table.concat(Broker.TooltipLines(report, hasTarget), "\n")
end

H.ok(joined(nil, false):find("No target", 1, true) ~= nil, "no target says so")

-- Never a bare "?" on a tooltip: the tooltip is the one place with room to say WHY, and "we cannot
-- read this unit" is the whole reason the addon is trustworthy.
local unknownTip = joined(unknown, true)
H.ok(unknownTip:find("cannot", 1, true) ~= nil, "an unreadable unit is explained, not just marked")
H.ok(unknownTip:find("%d/%d") == nil, "an unreadable unit's tooltip shows no count")

local tip = joined(watch, true)
H.ok(tip:find("28", 1, true) ~= nil, "the tooltip reports the count")
H.ok(tip:find("4", 1, true) ~= nil, "the tooltip reports the room left")

-- What the player actually loses is never "a buff", it is "that buff" — so it gets named.
local risky = joined(Core.Assess(auras(28, "Rallying Cry of the Dragonslayer")), true)
H.ok(risky:find("Rallying Cry of the Dragonslayer", 1, true) ~= nil,
    "the tooltip names the world buff at risk")

-- And a booned unit must not be described as at risk, or the warning stops meaning anything.
local booned = joined(Core.Assess(auras(28, "Chronoboon Displacement")), true)
H.ok(booned:find("Chronoboon", 1, true) ~= nil, "the tooltip says the buffs are stored")
H.ok(booned:find("At risk", 1, true) == nil, "a booned unit lists nothing at risk")

-- ---------------------------------------------------------------------------
-- The data object
-- ---------------------------------------------------------------------------
-- Built here rather than inside the LDB call so its shape is testable without the library.

local obj = Broker.NewObject()
H.eq(obj.type, "data source", "published as a data source, so the bar shows the number")
H.ok(obj.icon ~= nil, "the object carries an icon")
H.eq(obj.label, "Boonkeeper", "the object is nameable in a display's menu")
H.eq(type(obj.OnClick), "function", "clicking the bar entry does something")
H.eq(type(obj.OnTooltipShow), "function", "the entry has a tooltip")
-- Nothing has been scanned yet, so there is nothing to say. It must not open life claiming 0/32.
H.eq(obj.text, nil, "a freshly published object claims nothing")

H.done()
