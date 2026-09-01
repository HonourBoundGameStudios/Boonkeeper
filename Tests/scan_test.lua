-- BoonkeeperScan — which units we are willing to claim a number for.
--
-- Scan is the one file that touches the live client, so most of it can only be compile-verified.
-- One decision inside it is worth more than that: whether this unit is one Blizzard is documented
-- to serve a COMPLETE aura list for. Get it wrong and the addon states a count built from a
-- truncated list — the exact failure the whole design is arranged to avoid. So the four unit API
-- calls it rests on are stubbed here and the decision is exercised outside the game.
--
-- Usage: lua Tests/scan_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")
dofile("BoonkeeperCore.lua")

H.start("BoonkeeperScan")

-- ---------------------------------------------------------------------------
-- A fake client. `world` names the unit token we are asking about and what the
-- game would say about it.
-- ---------------------------------------------------------------------------
local world = {}

local calls = { UnitExists = 0, UnitIsUnit = 0 }

function UnitExists(unit)
    calls.UnitExists = calls.UnitExists + 1
    return world[unit] ~= nil
end

-- Two unit tokens can name the same player: "target" and "raid2" are one body with two handles.
-- `same` is how this fake says so, because that aliasing is the whole subject of the roster walk.
function UnitIsUnit(a, b)
    calls.UnitIsUnit = calls.UnitIsUnit + 1
    if a == b then return true end
    local u = world[a]
    if not u then return false end
    if u.isPlayer and b == "player" then return true end
    for _, token in ipairs(u.same or {}) do
        if token == b then return true end
    end
    return false
end

function UnitName(unit) return world[unit] and world[unit].name or nil end

function UnitInParty(unit) return world[unit] and world[unit].party or false end
function UnitInRaid(unit) return world[unit] and world[unit].raid or nil end

-- Twenty-eight buffs: enough that a count would read "watch" and be believed.
Boonkeeper.Compat = {
    GetAura = function(unit, index, filter)
        if filter ~= "HELPFUL" or index > 28 then return nil end
        return { name = "Filler " .. index, isHelpful = true }
    end,
}

dofile("BoonkeeperScan.lua")
local Scan = Boonkeeper.Scan
local Core = Boonkeeper.Core

-- ---------------------------------------------------------------------------
-- Who we trust
-- ---------------------------------------------------------------------------
world["player"]    = { isPlayer = true }
world["party1"]    = { party = true }
world["raid7"]     = { raid = 7 }
world["target"]    = {}                    -- a stranger we happen to have targeted
world["nameplate1"] = {}

H.eq(Scan.Trusted("player"), true, "we serve ourselves a full list")
H.eq(Scan.Trusted("party1"), true, "party members are served fully")
H.eq(Scan.Trusted("raid7"), true, "raid members are served fully")
H.eq(Scan.Trusted("target"), false, "a stranger is not")
H.eq(Scan.Trusted("nameplate1"), false, "nor is a passing nameplate")
H.eq(Scan.Trusted(nil), false, "no unit is not a trusted unit")

-- Trusted() answers a yes/no question and must return one: `UnitInRaid` yields a raid INDEX, and an
-- index leaking out of here would be truthy in Lua but wrong in every comparison downstream.
H.eq(type(Scan.Trusted("raid7")), "boolean", "trust is a boolean, not a raid index")

-- ---------------------------------------------------------------------------
-- What that does to the number
-- ---------------------------------------------------------------------------
local mine = Scan.Assess("player", "HELPFUL")
H.eq(mine.known, true, "our own auras are knowledge")
H.eq(mine.count, 28, "and are counted")

-- The defect SEE-7 fixes: this stranger's list arrives, all 28 of it, and is still not a number we
-- can stand behind, because nothing tells us it was not cut short.
local stranger = Scan.Assess("target", "HELPFUL")
H.eq(stranger.known, false, "a stranger's list is never claimed as a count")
H.eq(Core.Label(stranger), "?", "a stranger shows a question mark")

H.eq(Scan.Assess("boonkeeper-no-such-unit", "HELPFUL").known, false, "a unit that is not there is unknown")

-- The probe must keep seeing the raw truth: it exists to find out what this client actually hands
-- us for a stranger, which is impossible if the trust gate has already emptied the list.
H.eq(#Scan.Auras("target", "HELPFUL"), 28, "the raw scan still reports what the client gave us")

-- ---------------------------------------------------------------------------
-- The client we are not allowed to assume (SEE-8)
--
-- Every assertion above hands `UnitInParty`/`UnitInRaid` a token those functions already agree
-- about. The live question is the one no test has ever asked: what happens when the client REFUSES
-- to resolve an arbitrary token — when "target" names raid member #2 and `UnitInRaid("target")`
-- answers nil anyway. Under the old gate every raid member you targeted read as untrusted and the
-- addon showed `?` in the one situation it exists for, silently, with nothing wrong on screen to
-- notice. So trust must not rest on that resolution: it falls back to walking the roster with
-- `UnitIsUnit`, which the in-client self-test has already answered for.
-- ---------------------------------------------------------------------------
world["target"].same = { "raid2" }         -- the same player, reached by a second handle
world["raid1"] = {}
world["raid2"] = {}
world["raid3"] = {}
world["stranger"] = {}

H.eq(Scan.Trusted("target"), true, "a raid member you targeted is trusted even if UnitInRaid will not say so")
H.eq(Scan.Trusted("stranger"), false, "and a real stranger in the same raid still is not")
H.eq(type(Scan.Trusted("target")), "boolean", "the roster walk answers with a boolean too")

-- The gate is what the display believes, so the walk has to reach it, not just Trusted().
local targeted = Scan.Assess("target", "HELPFUL")
H.eq(targeted.known, true, "and so the targeted raid member finally gets a number")
H.eq(targeted.count, 28, "the number being the one the client served")

-- Same refusal, one rank down: a party of two, `UnitInParty("target")` unhelpful.
world["raid1"], world["raid2"], world["raid3"] = nil, nil, nil
world["party1"] = {}
world["target"].same = { "party1" }
H.eq(Scan.Trusted("target"), true, "a party member you targeted is trusted the same way")
H.eq(Scan.Trusted("stranger"), false, "the stranger is unchanged by the party")

-- Solo, the walk must not happen at all: SEE-3 will ask this question once per nameplate per
-- update, and a forty-token sweep per unit is how a raid frame drops to a slideshow.
world["party1"] = nil
calls.UnitIsUnit = 0
H.eq(Scan.Trusted("stranger"), false, "solo, a stranger is still a stranger")
H.ok(calls.UnitIsUnit <= 1, "and answering cost no roster sweep (" .. calls.UnitIsUnit .. " UnitIsUnit calls)")

-- ---------------------------------------------------------------------------
-- Whose Renew is that? (WARN-2)
--
-- Core decides whether a cast takes a new slot, but it cannot decide who "me" is: the client hands
-- back a source token, and only the client knows that "raid7" and "player" are the same body. That
-- resolution is the one part of the verdict that touches the live API, so it lives here — and it
-- has to survive the client refusing to answer, which is the same refusal SEE-8 is built around.
-- ---------------------------------------------------------------------------
local castAuras = {}
Boonkeeper.Compat.GetAura = function(unit, index, filter)
    if filter ~= "HELPFUL" then return nil end
    return castAuras[index]
end

world["party1"] = {}
world["raid7"] = { raid = 7, same = { "player" } }   -- us, reached by our roster handle

-- A Renew the client credits to our roster token, not to "player". Core's own default would call
-- this somebody else's and warn about a cast that is actually free; asking the client is the fix.
castAuras = { { name = "Renew", isHelpful = true, sourceUnit = "raid7" } }
H.eq(Scan.CastCost("party1", { applies = "Renew" }).cost, "free",
     "our own Renew is ours whichever token the client credits it to")

castAuras = { { name = "Renew", isHelpful = true, sourceUnit = "party3" } }
H.eq(Scan.CastCost("party1", { applies = "Renew" }).cost, "slot",
     "another priest's Renew still costs a new slot")

castAuras = { { name = "Renew", isHelpful = true } }
H.eq(Scan.CastCost("party1", { applies = "Renew" }).cost, "unknown",
     "and an unattributed Renew is not claimed as ours")

-- The trust gate reaches the verdict too: a list that may have been truncated cannot prove an
-- absence, and "no Renew on them" from a cut-short list is how the warning goes quiet when it
-- matters. But a cast that applies no helpful aura is still free on that same unreadable stranger.
-- `target` is aliased to a party member by now, so the untrusted unit is the stranger.
castAuras = {}
H.eq(Scan.CastCost("stranger", { applies = "Renew" }).cost, "unknown",
     "an untrusted list cannot prove the target is missing our Renew")
H.eq(Scan.CastCost("stranger", { applies = false }).cost, "free",
     "but a spell that applies no helpful aura is free on anybody")
H.eq(Scan.CastCost("boonkeeper-no-such-unit", { applies = "Renew" }).cost, "unknown",
     "a unit that is not there yields no verdict")

-- ---------------------------------------------------------------------------
-- Who did we just cast on? (WARN-2)
--
-- UNIT_SPELLCAST_SENT names the target by NAME, and every question we can answer about auras is
-- asked with a unit token. This is the join, and it is allowed to fail: a cast at somebody out of
-- our roster resolves to nothing, and nothing is exactly what should then be said about them.
-- ---------------------------------------------------------------------------
for token in pairs(world) do world[token] = nil end
world["player"] = { isPlayer = true, name = "Admiral" }
world["target"] = { name = "Krydon", same = { "raid2" } }
world["raid1"]  = { name = "Ghislaine", raid = 1 }
world["raid2"]  = { name = "Krydon", raid = 2 }

H.eq(Scan.UnitByName("Ghislaine"), "raid1", "a raid member is found by name")
H.eq(Scan.UnitByName("Admiral"), "player", "and so are we")

-- The unit you are looking at is the one the badge draws, so "target" must win over the roster
-- handle for the same body — otherwise the verdict lands on a frame nobody is watching.
H.eq(Scan.UnitByName("Krydon"), "target", "the targeted body resolves to target, not to raid2")

H.eq(Scan.UnitByName("Onyxia"), nil, "somebody off our roster resolves to nothing")
H.eq(Scan.UnitByName(""), nil, "a cast with no target names nobody")
H.eq(Scan.UnitByName(nil), nil, "and neither does no name at all")

H.done()
