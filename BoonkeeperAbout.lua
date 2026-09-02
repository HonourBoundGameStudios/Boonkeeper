-- BoonkeeperAbout — who made this addon, and a button that proves it still works.
--
-- Two tabs. "About" is the studio page every Honour Bound addon carries: the logo, what the addon
-- is, the version, and the Steam curator link. "Self-test" is the button. Everything below the pure
-- core is compile-verified only: whether TargetFrameTextureFrame exists under that name on Era,
-- whether the aura API returns the shape BoonkeeperCompat guessed, whether the label was ever
-- created. Those cannot be answered from outside the game, so they ship as BoonkeeperSelfTest and
-- the Self-test tab runs them on demand.
--
-- Tabs in BoonkeeperUI rather than windows of their own: modules here register content and are
-- handed a frame to draw into, so the addon has one window instead of one per feature.
--
-- Compile-verified only itself, which is the joke and also the reason the results are echoed to
-- chat as well as shown here: if the tab's own layout is broken, the chat copy still gets read.

Boonkeeper = Boonkeeper or {}

local UI = Boonkeeper.UI

local About = {}

-- The studio block is the same on every Honour Bound addon; only the addon card below it differs.
local STUDIO_LOGO = "Interface\\AddOns\\Boonkeeper\\Media\\HBGS-Logo"
local STUDIO_URL = "https://store.steampowered.com/curator/44062210-Honour-Bound-Game-Studios/"
local STUDIO_TAGLINE = "|cffbfbfbfGames and tools, made with honour.|r"
local STUDIO_BLURB = "Honour Bound Game Studios is an independent studio crafting games and "
    .. "player-first tools. Boonkeeper is one of our community add-ons, built for the healer "
    .. "who has to decide in a heartbeat whether one more buff is one too many."

local BLURB = "Shows how much buff room is left on the people you heal, so a reflex Renew never "
    .. "knocks a world buff off. Classic Era holds 32 buffs and drops the OLDEST past that. "
    .. "|cffaaaaaaA unit whose auras cannot be read shows '?' rather than a number: a count we "
    .. "cannot stand behind would be a confident lie at the moment you decide whether to cast.|r"

local TEXT_W = 380

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fd3ffBoonkeeper|r " .. msg)
end

-- Turn a result into the block of text the tab shows: the headline, then every line that is not a
-- plain pass, then the informational ones worth keeping in front of you.
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

--- Draw whatever we last learned into the tab, if the tab has been built.
local function refresh()
    if not About.results then return end
    -- Falls back to the last run rather than to the empty prompt: leaving the tab and coming back
    -- must not throw away the failures you opened it to read.
    About.results:SetText(summarise(About.lastRun))
    About.content:SetHeight(math.max(1, About.results:GetStringHeight()))
end

--- Run the self-test, print it to chat, and summarise it on the tab.
function About.RunSelfTest()
    local SelfTest = Boonkeeper.SelfTest
    if not SelfTest then
        say("|cffff2020self-test module missing|r — BoonkeeperSelfTest.lua is not loaded.")
        return
    end

    local run = SelfTest.Run()
    About.lastRun = run

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
        say("  |cffaaaaaaall checks green. /boon about, Self-test tab, for the detail.|r")
    end

    refresh()
    return run
end

-- A one-pixel line the width of the text column, so the studio block, the addon card and the link
-- read as three things rather than one run of centred text.
local function rule(content, anchor, gap)
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetSize(TEXT_W, 1)
    line:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    line:SetColorTexture(0.6, 0.6, 0.6, 0.5)
    return line
end

local function centred(content, template, anchor, gap, text)
    local fs = content:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    fs:SetWidth(TEXT_W)
    fs:SetJustifyH("CENTER")
    fs:SetText(text)
    return fs
end

--- Build the studio page. Called once, on first view.
local function buildAbout(content)
    local logo = content:CreateTexture(nil, "ARTWORK")
    logo:SetSize(72, 72)
    logo:SetPoint("TOP", content, "TOP", 0, -4)
    logo:SetTexture(STUDIO_LOGO)

    local studio = centred(content, "GameFontNormalLarge", logo, 6, "Honour Bound Game Studios")
    local tagline = centred(content, "GameFontNormal", studio, 2, STUDIO_TAGLINE)
    local blurb = centred(content, "GameFontHighlightSmall", tagline, 8, STUDIO_BLURB)

    -- The addon card: name, version, what it does. The version is the same string /boon version
    -- prints, so the two can be read against each other when a build is in doubt.
    local rule1 = rule(content, blurb, 10)
    local name = centred(content, "GameFontNormalLarge", rule1, 8, "|cff8fd3ffBoonkeeper|r")
    local version = Boonkeeper.Compat and Boonkeeper.Compat.Version() or "unknown"
    local ver = centred(content, "GameFontHighlightSmall", name, 2,
        "|cffbfbfbfVersion " .. version .. "  \194\183  Classic Era|r")
    local desc = centred(content, "GameFontHighlightSmall", ver, 6, BLURB)

    -- The link, in a box rather than as text, because frame text cannot be selected and a link
    -- nobody can copy is decoration. Typing into it reverts, so it stays copyable.
    local rule2 = rule(content, desc, 10)
    local linkLabel = centred(content, "GameFontNormal", rule2, 8, "|cffffd100Find our games on Steam|r")
    local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    box:SetSize(TEXT_W - 20, 22)
    box:SetPoint("TOP", linkLabel, "BOTTOM", 0, -6)
    box:SetAutoFocus(false)
    box:SetText(STUDIO_URL)
    box:SetCursorPosition(0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(STUDIO_URL); self:HighlightText() end
    end)
    centred(content, "GameFontDisableSmall", box, 2, "click the link, then Ctrl-C")

    local foot = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", content, "BOTTOM", 0, 0)
    foot:SetText("Boonkeeper v" .. version .. "  \194\183  \194\169 Honour Bound Game Studios")
end

--- Build the Self-test tab into the frame the container hands us. Called once, on first view.
local function buildSelfTest(content)
    local runButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    runButton:SetSize(150, 24)
    runButton:SetPoint("TOPLEFT", 0, 0)
    runButton:SetText("Run self-test")
    runButton:SetScript("OnClick", About.RunSelfTest)

    local demoButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    demoButton:SetSize(150, 24)
    demoButton:SetPoint("LEFT", runButton, "RIGHT", 8, 0)
    demoButton:SetText("Test panel")
    demoButton:SetScript("OnClick", function()
        if Boonkeeper.UI then Boonkeeper.UI.Show("test") end
    end)

    -- Scrolled, because a failing run can be longer than the tab and the failures are the part you
    -- must be able to reach.
    local scroll = CreateFrame("ScrollFrame", "BoonkeeperAboutScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -36)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)

    local inner = CreateFrame("Frame", nil, scroll)
    inner:SetSize(360, 1)
    scroll:SetScrollChild(inner)

    local results = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    results:SetPoint("TOPLEFT")
    results:SetWidth(360)
    results:SetJustifyH("LEFT")
    results:SetJustifyV("TOP")

    About.results = results
    About.content = inner
    refresh()
end

--- Open the window on the About tab, or on the Self-test tab when there is a run to read.
function About.Show(run)
    if run then About.lastRun = run end
    if UI then UI.Show(run and "selftest" or "about") end
    refresh()
end

--- Open or close the window on the About tab.
function About.Toggle()
    if not UI then return false end
    local shown = UI.Toggle("about")
    refresh()
    return shown
end

if UI then
    UI.RegisterTab("about", "About", buildAbout)
    UI.RegisterTab("selftest", "Self-test", buildSelfTest)
end

Boonkeeper.About = About
return About
