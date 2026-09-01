-- BoonkeeperBroker — publishes the target's headroom as a LibDataBroker data object.
--
-- A display like Sigil hosts other addons' broker objects: publish one and it appears on the bar,
-- with no plugin API to implement on either side. Gear Journey and Weapon Journey dock the same way.
--
-- NO LIBRARY IS SHIPPED. CLAUDE.md says no libraries and no build step, and vendoring LibStub to
-- put a number on a bar would be a poor trade. Instead this is a SOFT dependency: if something in
-- the session has already loaded LibDataBroker-1.1 — a display like Sigil necessarily has — we hand
-- it an object. If nothing has, we publish nothing and say nothing. Boonkeeper still works; there is
-- simply nowhere for the number to go.
--
-- THE RULE AT THIS SEAM: publishing to somebody else's bar is standing behind a number in public,
-- and Sigil's own doctrine agrees — a plugin with nothing to say shows an em dash, "not a zero, not
-- an empty string". So three states stay distinct and never collapse:
--
--   no target        nobody is asking. Publish nothing; the display draws its own empty glyph.
--                    A "0/32" here would be inventing a healthy raider who does not exist.
--   unreadable unit  the question was asked and we cannot answer. Publish "?".
--   readable unit    the answer.
--
-- The fields are pure and tested (Tests/broker_test.lua); only the registration touches the client.

Boonkeeper = Boonkeeper or {}

local Core = Boonkeeper.Core

local Broker = {}

Broker.NAME = "Boonkeeper"
Broker.ICON = "Interface\\Icons\\Spell_Holy_WordFortitude"

--- The text to publish, or nil when there is nothing to say.
---
--- nil rather than an empty string: LDB consumers are entitled to render their own empty state, and
--- Sigil's is an em dash. Ours is not the place to decide what somebody else's bar looks like idle.
function Broker.Text(report, hasTarget)
    if not hasTarget then return nil end
    return Core.Text(report)
end

--- A severity as three 0-1 colour components for the display's icon tint.
---
--- LDB's iconR/iconG/iconB are floats. Handing a consumer 0-255 washes every icon to white, and the
--- severity — the only reason to tint it — disappears.
function Broker.IconColour(severity)
    local hex = Core.Colour(severity)
    local function part(i)
        return (tonumber(hex:sub(i, i + 1), 16) or 255) / 255
    end
    return part(1), part(3), part(5)
end

--- The tooltip, as lines.
---
--- The tooltip is the one surface with room to say WHY, so the unreadable case is explained here
--- rather than left as a bare question mark. It is also where "that buff" gets named: what the
--- player stands to lose is never "a buff", and a tooltip listing Rallying Cry by name is the
--- difference between a warning and a decoration.
function Broker.TooltipLines(report, hasTarget)
    local lines = { "|cff8fd3ffBoonkeeper|r" }

    if not hasTarget then
        lines[#lines + 1] = "|cffaaaaaaNo target.|r"
        return lines
    end

    if not report or not report.known then
        lines[#lines + 1] = "|cffff8000This unit's auras cannot be read.|r"
        lines[#lines + 1] = "|cffaaaaaaBoonkeeper shows '?' rather than a count it cannot stand"
            .. " behind.|r"
        return lines
    end

    lines[#lines + 1] = string.format("Buff slots: |cff%s%d/%d|r",
        Core.Colour(report.severity), report.count, report.cap)
    lines[#lines + 1] = string.format("Room left: |cff%s%d|r",
        Core.Colour(report.severity), report.headroom)

    if report.booned then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cff40ff40Chronoboon: world buffs are stored — safe to cast.|r"
    elseif #report.precious > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffff8000At risk:|r"
        for _, name in ipairs(report.precious) do
            lines[#lines + 1] = "  " .. name
        end
    end

    return lines
end

--- The data object, built here rather than inside the LDB call so its shape is testable.
---
--- Published as a data source, not a launcher: a launcher is an icon and a click, and the whole
--- point is the live number. It still answers a click by opening the window.
function Broker.NewObject()
    return {
        type  = "data source",
        label = Broker.NAME,
        icon  = Broker.ICON,
        -- No text yet. Nothing has been scanned, so there is nothing to claim — and a bar entry
        -- that opens life reading "0/32" is exactly the confident lie this addon exists to avoid.
        text  = nil,
        OnClick = function(_, button)
            local UI = Boonkeeper.UI
            if not UI then return end
            -- Right-click straight to the test tab: on a bar, that is the gesture for "show me what
            -- this thing does", and it is also how the display itself gets eye-verified.
            UI.Show(button == "RightButton" and "test" or "about")
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip then return end
            for _, line in ipairs(Broker.lastTooltip or Broker.TooltipLines(nil, false)) do
                tooltip:AddLine(line)
            end
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Wiring. Compile-verified only — no line below has ever executed.
-- ---------------------------------------------------------------------------

--- Push the current target's state into the published object.
---
--- Called from the same places the target label updates. Writing the fields on the object is what
--- notifies every display: LDB's proxy fires a callback per assignment, so a display redraws
--- without Boonkeeper knowing any display exists.
function Broker.Update()
    local obj = Broker.object
    if not obj then return end

    local Scan = Boonkeeper.Scan
    local hasTarget = UnitExists("target") and true or false
    local report = hasTarget and Scan and Scan.Assess("target", "HELPFUL") or nil

    -- Held for the tooltip, which is called later and cannot rescan: a tooltip that rescans would
    -- read a different moment than the number the player is hovering over.
    Broker.lastTooltip = Broker.TooltipLines(report, hasTarget)

    local text = Broker.Text(report, hasTarget)
    obj.text = text
    if report and report.known then
        obj.iconR, obj.iconG, obj.iconB = Broker.IconColour(report.severity)
    else
        obj.iconR, obj.iconG, obj.iconB = nil, nil, nil
    end
end

--- Register with LibDataBroker if anything in this session provides it.
---
--- Silent when it is absent. A missing display is not an error and not worth a line of chat: the
--- player who has no broker bar never asked for one.
function Broker.Publish()
    if Broker.object then return Broker.object end

    local stub = _G.LibStub
    if not stub or type(stub.GetLibrary) ~= "function" then return nil end

    -- The `true` is "silent": GetLibrary raises for a missing library otherwise, and another
    -- addon's absent dependency must never be an error thrown from ours.
    local ok, ldb = pcall(stub.GetLibrary, stub, "LibDataBroker-1.1", true)
    if not ok or not ldb or type(ldb.NewDataObject) ~= "function" then return nil end

    local object = Broker.NewObject()
    -- Registering twice under one name is a library error, so a reload that re-runs this must find
    -- the existing object rather than make a second one.
    local existing = ldb.GetDataObjectByName and ldb:GetDataObjectByName(Broker.NAME)
    Broker.object = existing or ldb:NewDataObject(Broker.NAME, object)

    Broker.Update()
    return Broker.object
end

Boonkeeper.Broker = Broker
return Broker
