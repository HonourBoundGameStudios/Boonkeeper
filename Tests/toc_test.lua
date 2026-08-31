-- The .toc and the files it loads.
--
-- Two failures here are silent and only show up at runtime, both of them expensive: a module that
-- exists but is not listed simply never loads (and the feature is just "missing"), and a listed file
-- that does not exist stops the addon dead at load. Neither is caught by the core tests, because
-- neither is a question about behaviour.
--
-- Usage: lua Tests/toc_test.lua   (run from the project root)

local H = dofile("Tests/harness.lua")

H.start("Boonkeeper.toc")

local function readToc(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local files, order, headers = {}, {}, {}
    for line in f:lines() do
        -- Strip a UTF-8 BOM and the CR of a CRLF file; both are invisible, and both would turn a
        -- legitimate filename into one that does not exist.
        line = line:gsub("^\239\187\191", ""):gsub("\r$", ""):match("^%s*(.-)%s*$")
        local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
        if key then
            headers[key] = value
        elseif line ~= "" and line:sub(1, 1) ~= "#" then
            files[line] = true
            order[#order + 1] = line
        end
    end
    f:close()
    return files, order, headers
end

local listed, order, headers = readToc("Boonkeeper.toc")

-- ---------------------------------------------------------------------------
-- Headers
-- ---------------------------------------------------------------------------
-- A stale or malformed interface number marks the addon out of date and, on some clients, stops it
-- loading at all. 11509 is Classic Era; check it against the live client each patch.
H.ok(headers["Interface"] and headers["Interface"]:match("^%d%d%d%d%d+$"),
    "## Interface is a bare build number")
H.ok(headers["SavedVariables"] == "BoonkeeperDB", "## SavedVariables names our table")
H.ok(headers["Version"] and headers["Version"]:match("^%d+%.%d+%.%d+$"), "## Version is semver")

-- ---------------------------------------------------------------------------
-- The file list
-- ---------------------------------------------------------------------------
for _, name in ipairs(order) do
    local f = io.open(name, "r")
    H.ok(f ~= nil, "listed file exists: " .. name)
    if f then f:close() end
end

-- The bootstrap must load last: every other module publishes into the Boonkeeper namespace and the
-- bootstrap reads it at load time, so a reordering here fails as a nil index in the game and
-- nowhere else.
H.eq(order[#order], "Boonkeeper.lua", "the bootstrap loads last")

-- Every module in the repo must be listed. This is the guard for the failure that looks like
-- nothing at all: a new file, saved, deployed, and silently never loaded.
local pipe = io.popen(package.config:sub(1, 1) == "\\" and "dir /b *.lua" or "ls *.lua")
for name in pipe:lines() do
    name = name:gsub("\r$", "")
    H.ok(listed[name], "module is listed in the .toc: " .. name)
end
pipe:close()

H.done()
