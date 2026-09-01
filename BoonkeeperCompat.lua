-- BoonkeeperCompat — the ONLY file allowed to branch on the game flavour or on which aura API a
-- client happens to have.
--
-- Classic Era 1.15.9 turned UnitBuff/UnitDebuff into deprecation shims over C_UnitAuras, and the two
-- return completely different shapes: C_UnitAuras hands back one table, the old globals hand back a
-- flat tuple whose field order has changed across expansions. Resolving that here once means every
-- other file sees a single shape — { name, spellId, icon, sourceUnit, isHelpful, duration,
-- expirationTime } — and never asks which client it is on.
--
-- `duration` and `expirationTime` are carried exactly as the client gives them, nil included. A
-- permanent aura reports duration 0 and an unreadable one reports nothing at all, and those are
-- different facts: substituting a 0 for a missing timer would let WARN-3 rank an aura it cannot
-- actually place in time. Same for `sourceUnit` — "cast by nobody we can name" must not be allowed
-- to read as "cast by you", which is the difference between a free refresh and a lost world buff.

Boonkeeper = Boonkeeper or {}

local Compat = {}

local projectId = _G.WOW_PROJECT_ID
Compat.IS_ERA      = projectId == _G.WOW_PROJECT_CLASSIC
Compat.IS_MAINLINE = projectId == _G.WOW_PROJECT_MAINLINE
Compat.IS_CLASSIC  = not Compat.IS_MAINLINE

local unitAuras = _G.C_UnitAuras

--- Read one aura off a unit by index, normalised.
---
--- Returns nil when there is no aura at that index — which is also how a caller knows to stop
--- walking. Never raises: an unknown unit token is a normal thing to be handed while frames are
--- being recycled, and it must read as "nothing there", not as an error in combat.
function Compat.GetAura(unit, index, filter)
    if unitAuras and unitAuras.GetAuraDataByIndex then
        local data = unitAuras.GetAuraDataByIndex(unit, index, filter)
        if not data or not data.name then return nil end
        return {
            name           = data.name,
            spellId        = data.spellId,
            icon           = data.icon,
            sourceUnit     = data.sourceUnit,
            isHelpful      = filter ~= "HARMFUL",
            duration       = data.duration,
            expirationTime = data.expirationTime,
        }
    end

    local legacy = _G.UnitAura
    if not legacy then return nil end
    -- Classic's tuple: name, icon, count, dispelType, duration, expirationTime, source, ...
    local name, icon, _, _, duration, expirationTime, source, _, _, spellId =
        legacy(unit, index, filter)
    if not name then return nil end
    return {
        name           = name,
        spellId        = spellId,
        icon           = icon,
        sourceUnit     = source,
        isHelpful      = filter ~= "HARMFUL",
        duration       = duration,
        expirationTime = expirationTime,
    }
end

--- One field from our own .toc (Version, Author, Notes...), or nil.
---
--- GetAddOnMetadata moved into C_AddOns and the bare global is a deprecation shim that some clients
--- no longer carry. A version string is not worth an error, so an unavailable API reads as nil.
function Compat.Metadata(field)
    local addons = _G.C_AddOns
    if addons and addons.GetAddOnMetadata then
        return addons.GetAddOnMetadata("Boonkeeper", field)
    end
    if _G.GetAddOnMetadata then
        return GetAddOnMetadata("Boonkeeper", field)
    end
    return nil
end

Boonkeeper.Compat = Compat
return Compat
