-- BoonkeeperAbout — what this addon is, and a button that proves it still works.
--
-- The button is the point. Everything below the pure core is compile-verified only: whether
-- TargetFrameTextureFrame exists under that name on Era, whether the aura API returns the shape
-- BoonkeeperCompat guessed, whether the label was ever created. Those cannot be answered from
-- outside the game, so they ship as BoonkeeperSelfTest and this panel runs them on demand.
--
-- Compile-verified only itself, which is the joke and also the reason the results are echoed to
-- chat as well as shown here: if the panel's own layout is broken, the chat copy still gets read.

Boonkeeper = Boonkeeper or {}

local About = {}

local PANEL_W, PANEL_H = 420, 430
local BLURB = "Shows how much buff room is left on the people you heal, so a reflex Renew never "
    .. "knocks a world buff off. Classic Era holds 32 buffs and drops the OLDEST past that.\n\n"
    .. "|cffaaaaaaA unit whose auras cannot be read shows '?' rather than a number. That is "
    .. "deliberate: a count we cannot stand behind would be a confident lie at the exact moment "
    .. "you are deciding whether to cast.|r"

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fd3ffBoonkeeper|r " .. msg)
end

--- Run the self-test, print it to chat, and summarise it on the panel.
function About.RunSelfTest()
    local SelfTest = Boonkeeper.SelfTest
    if not SelfTest then
        say("|cffff2020self-test module missing|r — BoonkeeperSelfTest.lua is not loaded.")
        return
    end

    local run = SelfTest.Run()

    say(string.format("self-test: |cff40ff40%d passed|r, %s|r, |cffaaaaaa%d skipped|r",
        run.passed,
        (run.failed > 0 and string.format("|cffff2020%d FAILED", run.failed) or "|cff40ff400 failed"),
        run.skipped))

    -- Failures and skips only, in chat. A wall of green scrolls the useful lines away, and the
    -- useful lines are the ones that are not green.
    for _, line in ipairs(run.lines) do
        if not line.ok then
            say("  |cffff2020FAIL|r " .. line.text .. (line.detail and (" — " .. line.detail) or ""))
        elseif line.skipped then
            say("  |cffaaaaaaskip|r " .. line.text)
        end
    end
    if run.failed == 0 then
        say("  |cffaaaaaaall checks green. /boon about for the detail.|r")
    end

    About.lastRun = run
    About.Show(run)
    return run
end

-- Turn a result into the block of text the panel shows: the headline, then every line that is not
-- a plain pass, then the informational ones worth keeping in front of you.
local function summarise(run)
    if not run then
        return "|cffaaaaaaPress |cffffd100Run self-test|r|cffaaaaaa to check this install "
            .. "against the live client.|r"
    end

    local out = {}
    out[#out + 1] = string.format("|cff40ff40%d passed|r   %s   |cffaaaaaa%d skipped|r",
        run.passed,
        (run.failed > 0 and string.format("|cffff2020%d FAILED|r", run.failed) or "|cff40ff400 failed|r"),
        run.skipped)
    out[#out + 1] = " "

    for _, line in ipairs(run.lines) do
        if not line.ok then
            out[#out + 1] = "|cffff2020FAIL|r " .. line.text
                .. (line.detail and ("\n     |cffaaaaaa" .. line.detail .. "|r") or "")
        elseif line.skipped then
            out[#out + 1] = "|cffaaaaaaskip " .. line.text .. "|r"
        elseif line.text:find("interface number") or line.text:find("aura API") then
            -- Not pass/fail: these two report what the client actually is, which is exactly what
            -- you need in hand when a number looks wrong.
            out[#out + 1] = "|cffffd100info|r " .. line.text
        end
    end

    if run.failed == 0 then
        out[#out + 1] = " "
        out[#out + 1] = "|cff40ff40Everything green.|r"
    end
    return table.concat(out, "\n")
end

local function buildPanel()
    local template = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local panel = CreateFrame("Frame", "BoonkeeperAboutPanel", UIParent, template)
    -- A new frame is shown by default; without this the first Toggle would hide it instead.
    panel:Hide()
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    -- Read from the .toc rather than repeated here: a version that disagrees with the manifest is
    -- worse than no version, because it is the number somebody will quote in a bug report.
    local version = Boonkeeper.Compat and Boonkeeper.Compat.Metadata("Version") or "?"
    title:SetText("|cff8fd3ffBoonkeeper|r  " .. version)

    local blurb = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", 24, -48)
    blurb:SetPoint("TOPRIGHT", -24, -48)
    blurb:SetJustifyH("LEFT")
    blurb:SetJustifyV("TOP")
    blurb:SetText(BLURB)

    local runButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    runButton:SetSize(150, 24)
    runButton:SetPoint("TOPLEFT", 24, -150)
    runButton:SetText("Run self-test")
    runButton:SetScript("OnClick", About.RunSelfTest)

    local demo = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    demo:SetSize(150, 24)
    demo:SetPoint("LEFT", runButton, "RIGHT", 8, 0)
    demo:SetText("Test panel")
    demo:SetScript("OnClick", function()
        if Boonkeeper.Demo then Boonkeeper.Demo.Toggle() end
    end)

    -- Scrolled, because a failing run can be longer than the panel and the failures are the part
    -- you must be able to reach.
    local scroll = CreateFrame("ScrollFrame", "BoonkeeperAboutScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -186)
    scroll:SetPoint("BOTTOMRIGHT", -40, 22)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_W - 80, 1)
    scroll:SetScrollChild(content)

    local results = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    results:SetPoint("TOPLEFT")
    results:SetWidth(PANEL_W - 80)
    results:SetJustifyH("LEFT")
    results:SetJustifyV("TOP")

    panel.results = results
    panel.content = content

    if type(_G.UISpecialFrames) == "table" then
        table.insert(_G.UISpecialFrames, "BoonkeeperAboutPanel")
    end

    About.panel = panel
    return panel
end

--- Show the panel, optionally displaying a self-test result.
function About.Show(run)
    local panel = About.panel or buildPanel()
    -- Falls back to the last run rather than to the empty prompt: closing and reopening the panel
    -- must not throw away the failures you opened it to read.
    panel.results:SetText(summarise(run or About.lastRun))
    -- The scroll child must be told how tall its text turned out, or a long run cannot be scrolled.
    panel.content:SetHeight(math.max(1, panel.results:GetStringHeight()))
    panel:Show()
    return panel
end

--- Show or hide the About panel.
function About.Toggle()
    local panel = About.panel
    if panel and panel:IsShown() then
        panel:Hide()
        return false
    end
    About.Show()
    return true
end

Boonkeeper.About = About
return About
