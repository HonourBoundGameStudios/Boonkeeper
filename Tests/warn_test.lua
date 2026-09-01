-- BoonkeeperWarn — the cast path, driven end to end against a fake client.
--
-- This file is the one piece of Boonkeeper that fires on a WoW event, and event wiring is normally
-- compile-verified only: nobody finds out that the handler's arguments are in the wrong order until
-- a raid night. It does not have to be that way. The client functions it uses are few and dull, so
-- they are faked here and the whole path runs outside the game — cast event in, chat line and badge
-- verdict out, through the real Compat, the real Core and the real Scan.
--
-- What this canNOT tell you is what the number LOOKS like, which is what the eye-verify is for.
--
-- Usage: lua Tests/warn_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")

H.start("BoonkeeperWarn")

-- ---------------------------------------------------------------------------
-- A fake client: units, their auras, and the two lookups the cast path needs
-- ---------------------------------------------------------------------------
local world = {}

function UnitExists(unit) return world[unit] ~= nil end
function UnitName(unit) return world[unit] and world[unit].name or nil end
function UnitInParty(unit) return world[unit] and world[unit].party or false end
function UnitInRaid(unit) return world[unit] and world[unit].raid or nil end

function UnitIsUnit(a, b)
    if a == b then return true end
    local u = world[a]
    if not u then return false end
    if u.isPlayer and b == "player" then return true end
    for _, token in ipairs(u.same or {}) do
        if token == b then return true end
    end
    return false
end

function GetTime() return world.now or 0 end

-- The real aura seam, not a stub of it: this client is C_UnitAuras (the in-client self-test recorded
-- as much on Era), so the cast path runs through the same normalisation the game will use.
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if filter ~= "HELPFUL" then return nil end
        local list = world[unit] and world[unit].auras
        return list and list[index] or nil
    end,
}

-- Ranks matter here only in that they must NOT: the map is keyed by name so one entry covers all of
-- them, and that is only true if the id is turned into a name first.
local SPELL_NAMES = {
    [139]  = "Renew",
    [6076] = "Renew",              -- a later rank, same name, same map entry
    [2061] = "Flash Heal",
    [17]   = "Power Word: Shield",
    [8092] = "Mind Blast",         -- mapped by nobody: a spell we hold no opinion about
}
_G.C_Spell = {
    GetSpellInfo = function(id)
        local name = SPELL_NAMES[id]
        return name and { name = name } or nil
    end,
}

local said = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) said[#said + 1] = msg end }

-- The frame the module registers its event on. Captured rather than discarded, because the whole
-- point of testing this file is the wiring — the handler is reached through the script the module
-- actually set, with the arguments the game actually passes.
local registered = { events = {} }
function CreateFrame()
    return {
        RegisterUnitEvent = function(_, event, unit) registered.events[event] = unit end,
        RegisterEvent = function(_, event) registered.events[event] = "any" end,
        SetScript = function(_, which, fn) registered[which] = fn end,
    }
end

dofile("BoonkeeperCompat.lua")
dofile("BoonkeeperCore.lua")
dofile("BoonkeeperScan.lua")

-- A Display stand-in that only records. The real one draws, which is the part no test can judge.
local painted = {}
Boonkeeper.Display = {
    SetVerdict = function(verdict, unit) painted[#painted + 1] = { verdict = verdict, unit = unit } end,
}

dofile("BoonkeeperWarn.lua")

-- ---------------------------------------------------------------------------
-- The wiring itself
-- ---------------------------------------------------------------------------
H.eq(registered.events["UNIT_SPELLCAST_SENT"], "player",
     "the cast event is registered, and filtered to our own casts")
H.ok(registered.OnEvent ~= nil, "and something is listening to it")

-- ---------------------------------------------------------------------------
-- A capped raider carrying a world buff — the case the addon exists for
-- ---------------------------------------------------------------------------
local function buffs(n, ...)
    local list = {}
    for i = 1, n do list[i] = { name = "Filler " .. i } end
    for _, name in ipairs({ ... }) do list[#list + 1] = { name = name } end
    return list
end

world["player"] = { isPlayer = true, name = "Admiral", auras = buffs(3) }
world["raid1"]  = { raid = 1, name = "Admiral", same = { "player" } }
world["raid2"]  = { raid = 2, name = "Krydon" }
world["target"] = { name = "Krydon", same = { "raid2" },
                    auras = buffs(31, "Rallying Cry of the Dragonslayer") }

local function cast(spellId, targetName, caster)
    said, painted = {}, {}
    -- Through the registered script, not by calling the function directly: if the handler ever takes
    -- the event's arguments in the wrong order, it has to fail HERE rather than in a raid.
    registered.OnEvent(nil, "UNIT_SPELLCAST_SENT", caster or "player", targetName, "cast-1", spellId)
end

cast(139, "Krydon")
H.eq(#said, 1, "Renew on a capped raider carrying a world buff is warned about")
H.ok(said[1]:find("32/32", 1, true) ~= nil, "the warning states the count it is standing on")
H.ok(said[1]:find("Rallying Cry of the Dragonslayer", 1, true) ~= nil,
     "and names the world buff that is at risk")
H.eq(painted[1] and painted[1].verdict.cost, "slot", "and the badge is told the cast takes a slot")
H.eq(painted[1] and painted[1].unit, "target", "for the unit on the frame")

-- A later rank of the same spell is the same spell. Keying the map by name is what makes that true,
-- and it is only true if the id was turned into a name first.
world.now = 20
cast(6076, "Krydon")
H.eq(#said, 1, "a later rank of Renew warns exactly the same")

-- ---------------------------------------------------------------------------
-- The ways a cast is free, and none of them may warn
-- ---------------------------------------------------------------------------
cast(2061, "Krydon")
H.eq(#said, 0, "Flash Heal on the same capped raider says nothing")
H.eq(painted[1] and painted[1].verdict.cost, "free", "and the badge reads free at 32/32")

-- Our own Renew already on them: a refresh overwrites the slot it already holds. The client credits
-- it to our ROSTER token, which is the case Core's own default would get wrong.
-- Thirty fillers, the world buff, and our Renew: thirty-two, with something precious in the pool.
world["target"].auras = buffs(30, "Rallying Cry of the Dragonslayer")
world["target"].auras[32] = { name = "Renew", sourceUnit = "raid1" }
cast(139, "Krydon")
H.eq(#said, 0, "refreshing our own Renew warns about nothing")
H.eq(painted[1] and painted[1].verdict.cost, "free",
     "and reads free even though the client credited it to our roster token")

-- Another priest's Renew is a different aura in a different slot.
world["target"].auras[32] = { name = "Renew", sourceUnit = "raid3" }
world.now = 40
cast(139, "Krydon")
H.eq(#said, 1, "another priest's Renew does not make ours free")

-- ---------------------------------------------------------------------------
-- Silence, in all the shapes it has to take
-- ---------------------------------------------------------------------------
world["target"].auras = buffs(31, "Rallying Cry of the Dragonslayer")

cast(8092, "Krydon")
H.eq(#said, 0, "a spell we hold no mapping for warns about nothing")
H.eq(#painted, 0, "and does not even colour the badge — we have no opinion to paint")

cast(139, "Krydon", "raid2")
H.eq(#said, 0, "somebody else's cast is not our business")

cast(139, "Onyxia")
H.eq(#said, 0, "a cast at somebody off our roster says nothing")

-- A stranger you have TARGETED. Their list arrives, all thirty-two of it, and is still not
-- something to warn from: nothing tells us it was not cut short before the buff that mattered.
local krydon = world["target"]
world["target"] = { name = "Passerby", auras = buffs(31, "Songflower Serenade") }
cast(139, "Passerby")
H.eq(#said, 0, "a stranger's list, which may be truncated, is never warned from")
H.eq(painted[1] and painted[1].verdict.cost, "unknown", "and the verdict for them is unknown")
world["target"] = krydon

-- The Chronoboon is the whole reason the guild rule says "no Renew while UNbooned".
world["target"].auras = buffs(30, "Rallying Cry of the Dragonslayer", "Chronoboon Displacement")
cast(139, "Krydon")
H.eq(#said, 0, "a booned raider is not warned about")

-- ---------------------------------------------------------------------------
-- Noise control
-- ---------------------------------------------------------------------------
world["target"].auras = buffs(31, "Rallying Cry of the Dragonslayer")
world.now = 100
cast(139, "Krydon")
H.eq(#said, 1, "the first cast warns")

world.now = 102
cast(139, "Krydon")
H.eq(#said, 0, "a held-down macro two seconds later does not warn again")

world.now = 120
cast(139, "Krydon")
H.eq(#said, 1, "but a fresh decision later does")

-- The throttle is per spell and per target: a different body is a different decision and must not be
-- swallowed by the last one.
world["raid3"] = { raid = 3, name = "Ghislaine", auras = buffs(31, "Warchief's Blessing") }
world.now = 121
cast(139, "Ghislaine")
H.eq(#said, 1, "the same spell at somebody else is its own warning")

-- ---------------------------------------------------------------------------
-- What the warning refuses to say
-- ---------------------------------------------------------------------------
-- Past the cap the server drops the OLDEST buff, and whether the client tells us which that is has
-- never been established (WARN-3). So the warning names everything at risk and picks nothing: if it
-- ever starts naming one, that is a prediction of SERVER behaviour nobody has run the experiment for.
world["target"].auras = buffs(30, "Rallying Cry of the Dragonslayer", "Songflower Serenade")
world.now = 200
cast(139, "Krydon")
H.eq(#said, 1, "two world buffs up is still one warning")
H.ok(said[1]:find("Rallying Cry of the Dragonslayer", 1, true) ~= nil, "which names the first")
H.ok(said[1]:find("Songflower Serenade", 1, true) ~= nil, "and the second")
H.ok(said[1]:lower():find("oldest") == nil, "and does not claim to know which one drops")

H.done()
