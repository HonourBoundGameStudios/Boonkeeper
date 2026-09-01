-- BoonkeeperSelfTest — the checks that ship with the addon and run inside the client.
--
-- Tests/ covers the pure judgement thoroughly and cannot cover anything else: it runs under plain
-- Lua, where there is no TargetFrame to find, no aura API to call, and no way to discover that this
-- client returns a shape BoonkeeperCompat did not expect. Those questions are open (see
-- Process/Bugs.md) and only the client can close them, so they ship as checks behind a button.
--
-- Two suites:
--   PURE   — a smoke test of the shipped logic, re-run in the real runtime. Deliberately NOT a copy
--            of Tests/core_test.lua; it covers the load-bearing invariants only. The offline suite
--            remains the gate, and this does not replace it.
--   CLIENT — the things only a live client knows. Skipped, never failed, when there is no API.
--
-- Guarded by Tests/selftest_test.lua, which breaks Core on purpose and demands this notice. A
-- self-test that cannot go red is a green light wired to nothing.

Boonkeeper = Boonkeeper or {}

local SelfTest = {}

-- ---------------------------------------------------------------------------
-- A harness small enough to ship
-- ---------------------------------------------------------------------------

local Run = {}
Run.__index = Run

function Run:ok(condition, text, detail)
    if condition then
        self.passed = self.passed + 1
        self.lines[#self.lines + 1] = { ok = true, text = text }
    else
        self.failed = self.failed + 1
        -- The detail is the whole value of a failure line: "target frame anchor" tells you nothing,
        -- "target frame anchor: TargetFrameTextureFrame is nil" tells you what to go and look at.
        self.lines[#self.lines + 1] = { ok = false, text = text, detail = detail }
    end
end

function Run:eq(got, want, text)
    self:ok(got == want, text, string.format("got %s, want %s", tostring(got), tostring(want)))
end

function Run:skip(text)
    self.skipped = self.skipped + 1
    self.lines[#self.lines + 1] = { ok = true, skipped = true, text = text }
end

-- ---------------------------------------------------------------------------
-- PURE — the shipped logic, in whatever runtime we are actually in
-- ---------------------------------------------------------------------------

local function pureChecks(r)
    local Core = Boonkeeper.Core
    r:ok(Core ~= nil, "BoonkeeperCore loaded")
    if not Core then return end

    -- The caps are the root of every number on screen. Wrong here and everything downstream lies.
    r:eq(Core.CAP.HELPFUL, 32, "helpful cap is 32")
    r:eq(Core.CAP.HARMFUL, 16, "harmful cap is 16")

    local function auras(n, ...)
        local list = {}
        for i = 1, n do list[i] = { name = "Filler " .. i, isHelpful = true } end
        for _, name in ipairs({ ... }) do list[#list + 1] = { name = name, isHelpful = true } end
        return list
    end

    r:eq(Core.Assess(auras(10)).headroom, 22, "headroom counts down from the cap")
    r:eq(Core.Assess(auras(10)).severity, "clear", "plenty of room reads clear")
    r:eq(Core.Assess(auras(28)).severity, "watch", "short on room reads watch")
    r:eq(Core.Assess(auras(30)).severity, "danger", "nearly out reads danger")
    r:eq(Core.Assess(auras(32)).severity, "full", "at the cap reads full")
    r:eq(Core.Assess(auras(40)).headroom, 0, "headroom never goes negative")

    -- The addon's actual argument: the same headroom means different things depending on what the
    -- unit is carrying, and a Chronoboon makes the warning moot.
    r:eq(Core.Assess(auras(28, "Rallying Cry of the Dragonslayer")).severity, "danger",
        "a live world buff escalates a watch to a danger")
    r:eq(Core.Assess(auras(28, "Chronoboon Displacement")).severity, "watch",
        "a booned unit is not escalated")

    -- THE one thing. An unreadable unit must never produce a number.
    r:eq(Core.Assess(nil).known, false, "an unseen unit is not known")
    r:eq(Core.Label(Core.Assess(nil)), "?", "an unseen unit renders a question mark, never a zero")
    r:ok(Core.Text(Core.Assess(nil)):find("%d") == nil, "the rendered question mark contains no digit")

    local Demo = Boonkeeper.Demo
    r:ok(Demo ~= nil, "BoonkeeperDemo loaded")
    if Demo then
        r:eq(Core.Assess(Demo.Build("full")).severity, "full", "the test panel's FULL really is full")
    end
end

-- ---------------------------------------------------------------------------
-- CLIENT — what only a live client can answer. These are the open questions.
-- ---------------------------------------------------------------------------

local function clientChecks(r)
    -- A module missing here means the .toc did not load it: the feature is simply absent, with no
    -- error anywhere. That failure is invisible in the game and obvious from this line.
    for _, name in ipairs({ "Compat", "Core", "Scan", "Display", "Demo" }) do
        r:ok(Boonkeeper[name] ~= nil, "module loaded: Boonkeeper." .. name)
    end

    -- The anchors SEE-1 hangs its label on. If these names are wrong on Era, the number is drawn
    -- into nowhere and the only symptom is that nothing appears.
    r:ok(_G.TargetFrame ~= nil, "TargetFrame exists")
    r:ok(_G.TargetFrameTextureFrame ~= nil, "TargetFrameTextureFrame exists (the label's parent)")
    r:ok(_G.TargetFramePortrait ~= nil, "TargetFramePortrait exists (the label's anchor)")

    local Compat, Scan = Boonkeeper.Compat, Boonkeeper.Scan
    if not (Compat and Scan) then return end

    -- Which aura API this client actually resolved to. Not pass/fail — it is the fact you need in
    -- hand when a count looks wrong, and it is not knowable from outside the game.
    local api = (_G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataByIndex) and "C_UnitAuras"
        or "legacy UnitAura"
    r:ok(true, "aura API in use: " .. api)

    -- You are always readable, so the player is the one unit where a nil scan means we are broken
    -- rather than that Blizzard withheld the data.
    local mine = Scan.Auras("player", "HELPFUL")
    r:ok(type(mine) == "table", "the player's own aura list is readable")

    -- The shape BoonkeeperCompat promises everyone else. A tuple that moved between expansions
    -- shows up right here as a nil name, and nowhere else until a count is silently wrong.
    if type(mine) == "table" and #mine > 0 then
        r:ok(type(mine[1].name) == "string", "an aura carries a string name")
    else
        r:skip("no buffs on you — buff yourself and re-run to check the aura shape")
    end

    r:eq(Scan.Assess("player", "HELPFUL").known, true, "the player assesses as known")

    -- The unknown path exercised against the real client rather than against a nil we passed in
    -- ourselves. This is the path the whole design rests on.
    r:eq(Scan.Assess("boonkeeper-no-such-unit", "HELPFUL").known, false,
        "a nonexistent unit assesses as unknown, not as zero")

    local Display = Boonkeeper.Display
    if Display and Display.UpdateTarget then
        Display.UpdateTarget()
        r:ok(Display.targetText ~= nil, "the target label was created")
    end

    -- Answers the open .toc question by showing you the number to compare against, since the addon
    -- cannot read its own .toc at runtime.
    if _G.GetBuildInfo then
        local _, _, _, interface = GetBuildInfo()
        r:ok(true, "client interface number: " .. tostring(interface) .. " (## Interface must match)")
    end
end

--- Run the self-test. Client checks are skipped, not failed, when there is no WoW API.
function SelfTest.Run()
    local r = setmetatable({ passed = 0, failed = 0, skipped = 0, lines = {} }, Run)

    pureChecks(r)

    -- CreateFrame is the cheapest proof that we are inside the game.
    if type(_G.CreateFrame) == "function" then
        clientChecks(r)
    else
        r:skip("client checks skipped — not running inside WoW")
    end

    return r
end

Boonkeeper.SelfTest = SelfTest
return SelfTest
