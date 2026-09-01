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

function UnitExists(unit) return world[unit] ~= nil end
function UnitIsUnit(a, b) return a == b or (world[a] and world[a].isPlayer and b == "player") or false end
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

H.done()
