-- Does every file the game will load actually compile?
--
-- Most of Boonkeeper is covered by the core tests because the deciding part is pure. The rest — the
-- scan, the probe, the bootstrap — calls into the WoW API and cannot RUN outside the client, so
-- nothing else here has ever even compiled it. A missing `end` in BoonkeeperProbe.lua would
-- otherwise reach the game. Compiling is not testing, but it is the difference between finding a
-- typo now and finding it after a /reload in a raid.
--
-- Usage: lua Tests/load_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")

H.start("compiles")

local pipe = io.popen(package.config:sub(1, 1) == "\\" and "dir /b *.lua" or "ls *.lua")
for name in pipe:lines() do
    name = name:gsub("\r$", "")
    local chunk, err = loadfile(name)
    H.ok(chunk ~= nil, name .. " compiles" .. (chunk and "" or (": " .. tostring(err))))
end
pipe:close()

-- The pure core must load with no WoW API present at all. If it ever stops doing so, something that
-- makes a decision has quietly moved into the client, where it can only be tested by playing.
local ok = pcall(dofile, "BoonkeeperCore.lua")
H.ok(ok, "BoonkeeperCore loads standalone — the pure seam is still pure")

H.done()
