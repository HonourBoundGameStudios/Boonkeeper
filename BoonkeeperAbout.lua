-- BoonkeeperAbout — what this addon is, and a button that proves it still works.
--
-- The button is the point. Everything below the pure core is compile-verified only: whether
-- TargetFrameTextureFrame exists under that name on Era, whether the aura API returns the shape
-- BoonkeeperCompat guessed, whether the label was ever created. Those cannot be answered from
-- outside the game, so they ship as BoonkeeperSelfTest and this tab runs them on demand.
--
-- A tab in BoonkeeperUI rather than a window of its own: modules here register content and are
-- handed a frame to draw into, so the addon has one window instead of one per feature.
--
-- Compile-verified only itself, which is the joke and also the reason the results are echoed to
-- chat as well as shown here: if the tab's own layout is broken, the chat copy still gets read.

Boonkeeper = Boonkeeper or {}

local UI = Boonkeeper.UI

local About = {}

local BLURB = "Shows how much buff room is left on the people you heal, so a reflex Renew never "
    .. "knocks a world buff off. Classic Era holds 32 buffs and drops the OLDEST past that.\n\n"
    .. "|cffaaaaaaA unit whose auras cannot be read shows '?' rather than a number. That is "
    .. "deliberate: a count we cannot stand behind would be a confident lie at the exact moment "
    .. "you are deciding whether to cast.|r"

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
        say("  |cffaaaaaaall checks green. /boon about for the detail.|r")
    end

    refresh()
    return run
end

--- Build the About tab into the frame the container hands us. Called once, on first view.
local function buildTab(content)
    local blurb = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT")
    blurb:SetPoint("TOPRIGHT")
    blurb:SetJustifyH("LEFT")
    blurb:SetJustifyV("TOP")
    blurb:SetText(BLURB)

    local runButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    runButton:SetSize(150, 24)
    runButton:SetPoint("TOPLEFT", 0, -104)
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
    scroll:SetPoint("TOPLEFT", 0, -140)
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

--- Open the window on the About tab.
function About.Show(run)
    if run then About.lastRun = run end
    if UI then UI.Show("about") end
    refresh()
end

--- Open or close the window on the About tab.
function About.Toggle()
    if not UI then return false end
    local shown = UI.Toggle("about")
    refresh()
    return shown
end

if UI then UI.RegisterTab("about", "About", buildTab) end

Boonkeeper.About = About
return About
