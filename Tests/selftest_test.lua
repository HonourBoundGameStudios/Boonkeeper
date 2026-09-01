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
-- ---------------------------------------------------------------------------
-- Recording. A self-test whose result only ever reaches the chat frame can only be reported by
-- somebody retyping it. Folding the run into SavedVariables puts the answer on disk, where it
-- survives the /reload and can be read back exactly as the client produced it. The fold is pure,
-- so it is tested here rather than by reading a WTF file.
-- ---------------------------------------------------------------------------
local db = {}
SelfTest.Record(db, run, "2026-08-31 20:00:00")
H.ok(db.selfTest ~= nil, "the run is recorded into the database table")
H.eq(db.selfTest.at, "2026-08-31 20:00:00", "the record is stamped with when it ran")
H.eq(db.selfTest.passed, run.passed, "the record carries the pass count")
H.eq(db.selfTest.failed, run.failed, "the record carries the fail count")
H.eq(db.selfTest.skipped, run.skipped, "the record carries the skip count")
H.eq(#db.selfTest.lines, #run.lines, "every line is recorded, not just the failures")

-- The lines must be strings: SavedVariables is serialised Lua, and a line that arrives as a table
-- of flags is a line nobody can read without the code in front of them.
H.eq(type(db.selfTest.lines[1]), "string", "a recorded line is plain readable text")

-- A failure must be recognisable in the file without knowing the format, and must keep its detail —
-- that detail is the whole reason a failed line is worth reading.
local broken = setmetatable({ passed = 0, failed = 0, skipped = 0, lines = {} }, getmetatable(run))
broken.ok = nil
SelfTest.Record(db, { passed = 0, failed = 1, skipped = 0,
    lines = { { ok = false, text = "the caps are right", detail = "got 30, want 32" } } }, "now")
H.ok(db.selfTest.lines[1]:find("FAIL", 1, true) ~= nil, "a failed line is marked FAIL in the record")
H.ok(db.selfTest.lines[1]:find("got 30", 1, true) ~= nil, "a failed line keeps its detail")

-- Only the last run is kept. A history in SavedVariables grows without bound and nobody prunes it.
H.eq(#db.selfTest.lines, 1, "recording replaces the previous run rather than appending to it")

-- Recording must never be what breaks the addon: it runs at the end of a self-test, and a nil
-- database (SavedVariables not loaded yet) is a normal state, not an error.
H.ok(pcall(SelfTest.Record, nil, run, "now"), "recording with no database is a no-op, not an error")

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
