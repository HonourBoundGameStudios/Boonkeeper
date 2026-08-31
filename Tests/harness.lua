-- Minimal standalone test harness for Boonkeeper's pure-Lua core.
-- Runs outside the WoW client (plain `lua`) so the aura assessment can be observed without standing
-- in a raid. That seam is the point: a judgement that only exists inside the client can only be
-- tested by standing in Naxxramas and getting it wrong.
--
-- Usage: lua Tests/<name>_test.lua   (run from the project root)

local H = { passed = 0, failed = 0, name = "tests" }

local function fail(msg)
    H.failed = H.failed + 1
    print(string.format("  NOT OK %d - %s", H.passed + H.failed, msg))
end

local function pass(msg)
    H.passed = H.passed + 1
    print(string.format("  ok %d - %s", H.passed + H.failed, msg))
end

function H.ok(cond, msg)
    if cond then pass(msg) else fail(msg) end
end

function H.eq(got, want, msg)
    if got == want then
        pass(msg)
    else
        fail(string.format("%s (got %s, want %s)", msg, tostring(got), tostring(want)))
    end
end

-- Run fn under pcall; expect it to error (RED-style guard checks).
function H.errors(fn, msg)
    local ok = pcall(fn)
    H.ok(not ok, msg)
end

function H.start(name)
    H.name = name
    print("# " .. name)
end

-- Print summary and exit non-zero if anything failed (CI-friendly).
function H.done()
    print(string.format("# %s: %d passed, %d failed", H.name, H.passed, H.failed))
    if H.failed > 0 then os.exit(1) end
    os.exit(0)
end

return H
