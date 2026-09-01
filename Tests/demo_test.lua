-- BoonkeeperDemo — the scenarios behind the test panel.
--
-- The panel exists to eye-verify the label without standing in Naxxramas at 28 buffs. That makes it,
-- by construction, a machine for putting a number on screen that is not true — the one thing this
-- addon must never do. The guard is that the panel does not fabricate a report: it builds a
-- synthetic AURA LIST and hands it to the same Core.Assess the live scan uses, so what a tester sees
-- is what the real pipeline produces. These tests hold that line: every scenario is asserted through
-- Core, not against a hand-written expectation of what Core would have said.
--
-- Usage: lua Tests/demo_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")
dofile("BoonkeeperCore.lua")
dofile("BoonkeeperDemo.lua")
local Core = Boonkeeper.Core
local Demo = Boonkeeper.Demo

H.start("BoonkeeperDemo")

-- The module must load with no WoW API present. The panel is built lazily inside Toggle() precisely
-- so that this file stays exercisable outside the client; a CreateFrame at the top level would end
-- that and the scenarios would go untested.
H.ok(Demo ~= nil, "BoonkeeperDemo loads standalone — no WoW API at load time")

-- Every scenario is a button, so every scenario needs a key and something to write on it.
H.ok(#Demo.SCENARIOS > 0, "there is at least one scenario")
local complete = true
for _, s in ipairs(Demo.SCENARIOS) do
    if type(s.key) ~= "string" or type(s.label) ~= "string" then complete = false end
end
H.ok(complete, "every scenario has a key and a button label")

-- The severity each button claims to demonstrate, asserted through the real assessment.
local function severityOf(key)
    return Core.Assess(Demo.Build(key)).severity
end

H.eq(severityOf("empty"), "clear", "empty: a fresh unit is clear")
H.eq(severityOf("clear"), "clear", "clear: plenty of room")
H.eq(severityOf("watch"), "watch", "watch: room is getting short")
H.eq(severityOf("danger"), "danger", "danger: do not cast the optional thing")
H.eq(severityOf("full"), "full", "full: the next buff drops the oldest one")

-- The two states most worth looking at, because they are the addon's actual argument: the same
-- headroom reads differently depending on what the unit is carrying.
H.eq(severityOf("precious"), "danger", "precious: a live world buff escalates a watch to a danger")
H.eq(severityOf("booned"), "watch", "booned: stored buffs are safe, so it stays a watch")

-- The "?" path has to be demonstrable too — it is the state a tester is least likely to reach by
-- accident and the one the whole design rests on.
local unknown = Core.Assess(Demo.Build("unknown"))
H.eq(unknown.known, false, "unknown: an unreadable unit is not known")
H.eq(Core.Label(unknown), "?", "unknown: renders a question mark")

-- Each press must build its own list. A shared table would let one press mutate what the next press
-- shows, and the panel would start lying about which scenario is on screen.
local first = Demo.Build("watch")
first[#first + 1] = { name = "Meddling", isHelpful = true }
H.eq(#Demo.Build("watch"), #first - 1, "each build returns a fresh list, not a shared one")

-- Only our own buttons call this, so an unknown key is a programming error and must be loud rather
-- than silently rendering as an unreadable unit — which is a real state and would look like a pass.
H.errors(function() Demo.Build("no such scenario") end, "an unknown scenario key raises")

-- The fourth state has to be reachable from the panel too, and it is the one a tester could NEVER
-- summon otherwise: it needs a capped raider and a cast at them. Green on 32/32 is the reading most
-- likely to look like a bug on sight, which is exactly why it must be eye-verified deliberately
-- rather than met for the first time in a raid.
local freeReport = Core.Assess(Demo.Build("free"))
H.eq(freeReport.severity, "full", "free: the count underneath is genuinely full")
H.eq(Core.CastSeverity(freeReport, Demo.Verdict("free")), "free", "free: but the cast reads as free")
H.ok(Core.Text(freeReport, Demo.Verdict("free")):find("32/32", 1, true) ~= nil,
     "free: and the number still states 32/32 rather than pretending there is room")

-- Every other button is the count alone. A verdict left hanging on a scenario that is not about one
-- would recolour a state the tester believes they are judging on its own terms.
H.eq(Demo.Verdict("full"), nil, "the plain full scenario carries no verdict")
H.eq(Demo.Verdict("unknown"), nil, "nor does the unreadable one")
H.errors(function() Demo.Verdict("no such scenario") end, "an unknown scenario key raises here too")

H.done()
