-- BoonkeeperCompat — the one shape every other file is allowed to see.
--
-- Compat is the only file that branches on which aura API a client happens to have, and the two
-- APIs return completely different things: C_UnitAuras hands back a table, the old globals a flat
-- tuple whose field order has changed across expansions. Miscount that tuple and a field silently
-- becomes the wrong field — `duration` read out of the `count` slot is a plausible-looking number
-- that is simply false, which is the one thing this addon must never show. So both branches are
-- driven here, outside the client, against a fake of each API.
--
-- Usage: lua Tests/compat_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")

H.start("BoonkeeperCompat")

-- One aura, described once, so the two API fakes below cannot drift apart and quietly agree on
-- something neither client actually returns.
local RENEW = {
    name           = "Renew",
    spellId        = 25222,
    icon           = 135953,
    sourceUnit     = "party2",
    duration       = 15,
    expirationTime = 1234.5,
}

-- ---------------------------------------------------------------------------
-- The modern branch: C_UnitAuras.GetAuraDataByIndex
-- ---------------------------------------------------------------------------
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if unit ~= "party2" or index ~= 1 then return nil end
        return {
            name           = RENEW.name,
            spellId        = RENEW.spellId,
            icon           = RENEW.icon,
            sourceUnit     = RENEW.sourceUnit,
            duration       = RENEW.duration,
            expirationTime = RENEW.expirationTime,
        }
    end,
}

dofile("BoonkeeperCompat.lua")
local Compat = Boonkeeper.Compat

local aura = Compat.GetAura("party2", 1, "HELPFUL")
H.ok(aura ~= nil, "C_UnitAuras: an aura that is there comes back")
H.eq(aura.name, RENEW.name, "C_UnitAuras: name")
H.eq(aura.spellId, RENEW.spellId, "C_UnitAuras: spellId")
H.eq(aura.icon, RENEW.icon, "C_UnitAuras: icon")
H.eq(aura.isHelpful, true, "C_UnitAuras: HELPFUL is helpful")

-- WARN-2 turns entirely on "is this MY Renew", and WARN-3 on when an aura was applied. Both are
-- unanswerable if the seam drops the fields, and both are answered WRONG if it invents them.
H.eq(aura.sourceUnit, RENEW.sourceUnit, "C_UnitAuras: sourceUnit is carried")
H.eq(aura.duration, RENEW.duration, "C_UnitAuras: duration is carried")
H.eq(aura.expirationTime, RENEW.expirationTime, "C_UnitAuras: expirationTime is carried")

H.eq(Compat.GetAura("party2", 2, "HELPFUL"), nil, "C_UnitAuras: past the end is nil, not an empty table")

-- A client that serves an aura with no source (or no timer) must produce nil, never a stand-in.
-- "Unknown caster" and "cast by nobody" have to stay distinguishable from "cast by you", because
-- WARN-2 reads the difference as free-to-cast versus costs-a-slot.
_G.C_UnitAuras.GetAuraDataByIndex = function()
    return { name = "Mystery", spellId = 1 }
end
local sparse = Compat.GetAura("party2", 1, "HELPFUL")
H.eq(sparse.sourceUnit, nil, "an unknown caster stays unknown")
H.eq(sparse.duration, nil, "no duration is nil, not zero")
H.eq(sparse.expirationTime, nil, "no expiration is nil, not zero")

-- ---------------------------------------------------------------------------
-- The legacy branch: the UnitAura tuple
-- ---------------------------------------------------------------------------
-- Compat reads the API once at load, so the older client is a second load with C_UnitAuras absent.
_G.C_UnitAuras = nil
_G.UnitAura = function(unit, index, filter)
    if unit ~= "party2" or index ~= 1 then return nil end
    -- name, icon, count, dispelType, duration, expirationTime, source, isStealable,
    -- nameplateShowPersonal, spellId
    return RENEW.name, RENEW.icon, 3, nil, RENEW.duration, RENEW.expirationTime,
           RENEW.sourceUnit, false, false, RENEW.spellId
end

dofile("BoonkeeperCompat.lua")
Compat = Boonkeeper.Compat

local legacy = Compat.GetAura("party2", 1, "HELPFUL")
H.ok(legacy ~= nil, "legacy: an aura that is there comes back")
H.eq(legacy.name, RENEW.name, "legacy: name")
H.eq(legacy.spellId, RENEW.spellId, "legacy: spellId")
H.eq(legacy.icon, RENEW.icon, "legacy: icon")
H.eq(legacy.sourceUnit, RENEW.sourceUnit, "legacy: sourceUnit is carried")
H.eq(legacy.duration, RENEW.duration, "legacy: duration is carried out of the right tuple slot")
H.eq(legacy.expirationTime, RENEW.expirationTime, "legacy: expirationTime is carried")
H.eq(legacy.isHelpful, true, "legacy: HELPFUL is helpful")

local harmful = (function()
    _G.UnitAura = function() return "Weakened Soul", 1, 1, nil, 15, 99, "player", false, false, 6788 end
    return Compat.GetAura("party2", 1, "HARMFUL")
end)()
H.eq(harmful.isHelpful, false, "legacy: HARMFUL is not helpful")

_G.UnitAura = nil
H.eq(Compat.GetAura("party2", 1, "HELPFUL"), nil, "a client with no aura API at all reads as nothing there")

H.done()
