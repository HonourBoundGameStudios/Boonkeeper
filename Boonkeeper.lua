-- Boonkeeper — how much room is left on the people you are about to heal.
--
-- Bootstrap only: load order, SavedVariables handoff, slash commands. Everything that decides
-- anything lives in a module beside this one, and the one that decides the thing that matters
-- (BoonkeeperCore) is pure and tested under plain Lua — see Tests/.
--
-- Classic Era holds 32 buffs per player and drops the OLDEST one past that, so a reflex Renew on a
-- capped raider can cost them a world buff that took an evening to collect. Boonkeeper puts the
-- number where you are already looking, before you cast.

local ADDON = ...

Boonkeeper = Boonkeeper or {}

local Probe = Boonkeeper.Probe
local Demo = Boonkeeper.Demo
local About = Boonkeeper.About

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fd3ffBoonkeeper|r " .. msg)
end

local function help()
    say("commands:")
    say("  |cffffd100/boon probe|r — dump what aura data this client will actually give us")
    say("  |cffffd100/boon test|r — Test tab: walk the target label through every state")
    say("  |cffffd100/boon about|r — the Boonkeeper window: About tab and the self-test button")
    say("  |cffffd100/boon selftest|r — run the checks now and print them here")
    say("  |cffffd100/boon help|r — this list")
end

SLASH_BOONKEEPER1 = "/boon"
SLASH_BOONKEEPER2 = "/boonkeeper"
SlashCmdList["BOONKEEPER"] = function(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "probe" then
        Probe.Run()
    elseif cmd == "test" then
        -- Said every time, not once: the panel makes the target frame lie, and a tester who walks
        -- away from an open panel must not later read that number as real.
        if Demo.Toggle() then
            say("test panel open — |cffff8000the target frame now shows FAKE data|r. Close it to go live.")
        else
            say("test panel closed — live data restored.")
        end
    elseif cmd == "about" then
        About.Toggle()
    elseif cmd == "selftest" or cmd == "test-run" then
        About.RunSelfTest()
    else
        help()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
-- LibDataBroker reaches us from whichever addon shipped it, and that addon may load after this one.
-- PLAYER_LOGIN is the first moment every addon is guaranteed loaded, so the broker is published
-- there rather than at ADDON_LOADED, where LibStub may not exist yet.
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if Boonkeeper.Broker then Boonkeeper.Broker.Publish() end
        return
    end
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    BoonkeeperDB = BoonkeeperDB or { version = 1 }
    say("loaded. |cffffd100/boon probe|r in a raid to check what this client will show us.")
end)
