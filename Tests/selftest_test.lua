-- BoonkeeperSelfTest — the checks that ship inside the addon.
--
-- The offline suite in Tests/ cannot reach the questions that are actually open: whether
-- TargetFrameTextureFrame exists on this client, whether the real aura API returns the shape
-- BoonkeeperCompat guessed, whether the label was ever created. Those need a live client, so they
-- ship as a self-test with a button behind it.
--
-- What THIS file guards is the self-test itself. A self-test that cannot fail is worse than no
-- self-test: it is a green light wired to nothing. So the last assertions here break Core on purpose
-- and demand that the self-test notices.
--
-- Usage: lua Tests/selftest_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")
dofile("BoonkeeperCore.lua")
dofile("BoonkeeperDemo.lua")
dofile("BoonkeeperSelfTest.lua")
local Core = Boonkeeper.Core
local SelfTest = Boonkeeper.SelfTest

H.start("BoonkeeperSelfTest")

H.ok(SelfTest ~= nil, "BoonkeeperSelfTest loads standalone — it must run outside the client too")

local run = SelfTest.Run()
H.ok(run ~= nil, "Run() returns a result")
H.ok(run.passed > 0, "Run() actually performed checks")
H.eq(run.failed, 0, "the shipped self-test passes against the shipped logic")
-- A skip is a line but is neither a pass nor a fail: counting it as a pass would let a client check
-- that never ran read as a client check that succeeded, which is the failure this whole file exists
-- to prevent.
H.eq(#run.lines, run.passed + run.failed + run.skipped, "every check produced a reportable line")

-- Outside the client there is no WoW API, so the client checks must be skipped rather than counted
-- as failures — otherwise this file could never be green and the gate would be useless.
H.ok(run.skipped > 0, "the client-only checks are skipped outside the client, not failed")

-- Every line needs text a human can act on. "FAILED" with no name is a dead end at the exact moment
-- somebody is trying to work out what is wrong with their install.
local labelled = true
for _, line in ipairs(run.lines) do
    if type(line.text) ~= "string" or line.text == "" then labelled = false end
end
H.ok(labelled, "every reported line carries a description")

-- ---------------------------------------------------------------------------
-- The part that matters: it must be able to go red.
-- ---------------------------------------------------------------------------
local realCap = Core.CAP.HELPFUL
Core.CAP.HELPFUL = 99   -- a wrong cap makes every number the addon shows wrong
local broken = SelfTest.Run()
Core.CAP.HELPFUL = realCap

H.ok(broken.failed > 0, "a broken cap is caught — the self-test is wired to something")
H.ok(broken.passed < run.passed, "the broken run reports fewer passes than the good one")

-- And it must go green again once the breakage is undone, or the failure above proves nothing
-- except that the second run is always red.
H.eq(SelfTest.Run().failed, 0, "restoring the cap restores the green")

H.done()
