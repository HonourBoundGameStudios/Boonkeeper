-- BoonkeeperUI — one tabbed window, and the registry of what goes in it.
--
-- Modules do not own windows; they register a tab and are handed a frame to draw into. That is the
-- difference between an addon with one settings window and an addon with four floating panels the
-- player has to arrange, and it is why the Options tab (SHIP-1) will be a registration rather than
-- another CreateFrame somewhere.
--
-- The registry is pure and tested: WHICH tabs exist and in what order is the half of this that
-- fails silently. A tab whose module forgot to register is not an error anywhere — it is a feature
-- the player simply cannot find. The window itself is compile-verified only, which is why the frame
-- is built lazily on first open: a CreateFrame at load would take the registry down with it and
-- Tests/ui_test.lua could not run at all.

Boonkeeper = Boonkeeper or {}

local UI = {}

local FRAME_NAME = "BoonkeeperUIFrame"
local PANEL_W, PANEL_H = 440, 460

-- Ordered, because the order is the tab order. Keyed lookup is derived from it rather than kept
-- alongside it, so the two can never disagree.
UI.TABS = {}

--- Register a tab. `build(content, tab)` is called once, lazily, with the frame to draw into.
---
--- Raises rather than warns: every caller is one of our own modules at load time, and a tab that
--- quietly fails to register is indistinguishable from a feature that was never written.
function UI.RegisterTab(key, label, build)
    if type(key) ~= "string" or key == "" then
        error("BoonkeeperUI.RegisterTab: a tab needs a key", 2)
    end
    if type(build) ~= "function" then
        error("BoonkeeperUI.RegisterTab: tab '" .. key .. "' has no builder", 2)
    end
    if UI.Tab(key) then
        -- Two tabs under one key would leave one of them unreachable and make TabIndex ambiguous.
        error("BoonkeeperUI.RegisterTab: duplicate tab key '" .. key .. "'", 2)
    end
    UI.TABS[#UI.TABS + 1] = { key = key, label = label or key, build = build }
    return UI.TABS[#UI.TABS]
end

--- The tab registered under a key, or nil.
function UI.Tab(key)
    for _, tab in ipairs(UI.TABS) do
        if tab.key == key then return tab end
    end
    return nil
end

--- A tab's position, which is the ID its tab button carries, or nil if it is not registered.
function UI.TabIndex(key)
    for index, tab in ipairs(UI.TABS) do
        if tab.key == key then return index end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The window. Compile-verified only — no line below has ever executed.
-- ---------------------------------------------------------------------------

local function buildTabButton(frame, index, tab)
    -- PanelTemplates_SetTab finds its buttons by the global name <frame>Tab<n>, so these have to be
    -- named even though nothing else looks them up.
    local name = FRAME_NAME .. "Tab" .. index

    -- CharacterFrameTabButtonTemplate is the Classic tab look. Asking for a template the client
    -- does not have errors inside CreateFrame, so fall back to a plain button: uglier, but the
    -- window still opens and every tab is still reachable.
    local template = "CharacterFrameTabButtonTemplate"
    local ok, button = pcall(CreateFrame, "Button", name, frame, template)
    if not ok or not button then
        button = CreateFrame("Button", name, frame, "UIPanelButtonTemplate")
        button:SetSize(96, 22)
    end

    button:SetID(index)
    button:SetText(tab.label)
    button:SetScript("OnClick", function(self)
        UI.SelectTab(self:GetID())
    end)

    if index == 1 then
        -- UI-DialogBox-Border draws its visible line ~11px inside the frame's edge, with a
        -- transparent margin outside it. Anchored at the frame's true bottom, the tab tops float in
        -- that margin with a visible gap; +7 tucks them up against the drawn border instead.
        button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 7)
    else
        button:SetPoint("LEFT", _G[FRAME_NAME .. "Tab" .. (index - 1)], "RIGHT", -14, 0)
    end

    if _G.PanelTemplates_TabResize then PanelTemplates_TabResize(button, 0) end
    return button
end

local function buildFrame()
    local template = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent, template)
    -- A new frame is shown by default; without this the first Toggle would hide it instead of
    -- opening it, and the first press would look like the addon did nothing.
    frame:Hide()
    frame:SetSize(PANEL_W, PANEL_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    -- The same words /boon version prints, so a tester comparing the two never sees them disagree.
    local version = Boonkeeper.Compat and Boonkeeper.Compat.Version() or "unknown"
    title:SetText("|cff8fd3ffBoonkeeper|r  " .. version)

    -- One content frame per tab, all stacked in the same place, one shown at a time. Each tab's
    -- content is built on first view rather than up front, so opening the window costs one tab.
    for index, tab in ipairs(UI.TABS) do
        local content = CreateFrame("Frame", nil, frame)
        content:SetPoint("TOPLEFT", 20, -44)
        content:SetPoint("BOTTOMRIGHT", -20, 16)
        content:Hide()
        tab.content = content
        tab.button = buildTabButton(frame, index, tab)
    end

    if _G.PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(frame, #UI.TABS) end
    if type(_G.UISpecialFrames) == "table" then
        table.insert(_G.UISpecialFrames, FRAME_NAME)
    end

    UI.frame = frame
    return frame
end

--- Show tab `index`, hiding the others.
---
--- Hiding a tab's content fires its OnHide, which is how the test tab knows to stop faking the
--- target number. Switching tabs has to count as leaving it, not just closing the window.
function UI.SelectTab(index)
    local frame = UI.frame or buildFrame()
    index = index or 1

    for i, tab in ipairs(UI.TABS) do
        -- Tabs are materialised once, in buildFrame, so a tab registered after the window was first
        -- opened has no content frame. Registration happens at load and this should never be true;
        -- skipping beats a nil index inside a click handler mid-fight.
        if not tab.content then
            -- nothing to show for this one
        elseif i == index then
            if not tab.built then
                tab.build(tab.content, tab)
                tab.built = true
            end
            tab.content:Show()
        else
            tab.content:Hide()
        end
    end

    if _G.PanelTemplates_SetTab then PanelTemplates_SetTab(frame, index) end
    UI.selected = index
    return index
end

--- Open the window, optionally on a named tab.
function UI.Show(key)
    local frame = UI.frame or buildFrame()
    frame:Show()
    UI.SelectTab(key and UI.TabIndex(key) or UI.selected or 1)
    return frame
end

--- Open the window on a tab, or close it if that tab is already the one on screen.
function UI.Toggle(key)
    local frame = UI.frame
    local index = key and UI.TabIndex(key)
    if frame and frame:IsShown() and (not index or index == UI.selected) then
        frame:Hide()
        return false
    end
    UI.Show(key)
    return true
end

Boonkeeper.UI = UI
return UI
