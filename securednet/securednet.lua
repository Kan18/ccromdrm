-- SecuRednet by 6_4
-- Prevents some rednet security vulnerabilities (spoofing IDs, receiving others' messages)
-- Must be first script run in rom/autorun; you can name it something like "00securednet.lua"
-- Sorry this is a bit messy rn (it's mostly just a mashup of code from other projects), will cleanup later

local yield = coroutine.yield
local status = coroutine.status
local resume = coroutine.resume
local wrap = coroutine.wrap
local create = coroutine.create
local pcall = pcall
local next = next
local error = error

local WHITELISTED_REPEATER_ID = -12345

-- I wrote this function a year ago and I don't really remember what's happening here lol
-- It's basically like protectFunc from romdrm.lua except it passes through events
-- Note that the events could be modified externally unless running at the top level coroutine

-- Since we're already adding a coroutine on top of user code (to filter events out), we
-- could also just do something kinda like phoenix's system calls where the peripheral call
-- goes through an event anyways
local function protectFunc(func)
    local accept, call

    function accept(...) return call(yield(...)) end

    function call(...) return accept(pcall(func, ...)) end

    local newWrapped = wrap(function()
        repeat
            local f = wrap(accept)
        until yield(f(f))
    end)

    local waiting = {}

    local error2 = error
    local yield2 = yield

    local call2, accept2

    function accept2(wrapped, first, ...)
        if first == true or first == false then
            waiting[wrapped] = true
            if first then return ... else error2(..., 2) end
        else
            return call2(wrapped, yield2(first))
        end
    end

    function call2(wrapped, ...)
        return accept2(wrapped, wrapped(...))
    end

    return function(...)
        local wrapped = next(waiting)
        if not wrapped then
            wrapped = newWrapped()
        else
            waiting[wrapped] = nil
        end

        return call2(wrapped, ...)
    end
end


local function upvalueIndex(func, name)
    local i, currentName = 0, nil
    repeat
        i = i + 1
        currentName = debug.getupvalue(func, i)
    until not currentName or currentName == name
    return i, select(2, debug.getupvalue(func, i))
end

local computerID = os.getComputerID()

if computerID == WHITELISTED_REPEATER_ID then
    return
end

local type, rawget = type, rawget

local _, native = upvalueIndex(peripheral.call, 'native')

local nativeCall = native.call
if debug.getinfo(nativeCall).what == "Lua" then
    -- running second time
    return
end

native.call = protectFunc(function(...)
    local _, method, _, _, data = ...
    if method == "callRemote" then 
        _, _, _, method, _, _, data = ...
    end
    if method == "transmit" then
        if type(data) == "table" and rawget(data, "nMessageID") then
            if rawget(data, "nSender") ~= computerID then
                error("nSender must use correct ID")
            end
        end
    end
    return nativeCall(...)
end)

debug.setupvalue(rednet.run, upvalueIndex(rednet.run, 'started'), false)

local _G = _G
-- Copy BIOS structure to retain compatibility with user program TLCO functions
-- _ENV stuff possibly might have issues with Lua 5.1?
local function fakeBIOS()
    _ENV = _G

    local ok, err = pcall(parallel.waitForAny,
        function()
            local sShell
            if term.isColour() and settings.get("bios.use_multishell") then
                sShell = "rom/programs/advanced/multishell.lua"
            else
                sShell = "rom/programs/shell.lua"
            end
            os.run({}, sShell)
            os.run({}, "rom/programs/shutdown.lua")
        end,
        rednet.run
    )

    term.redirect(term.native())
    if not ok then
        printError(err)
        _ENV.pcall(function() -- we use _ENV here to avoid localized pcall
            term.setCursorBlink(false)
            print("Press any key to continue")
            os.pullEvent("key")
        end)
    end

    os.shutdown()
end

local run = os.run
os.run = function(_, _)  -- prevent rom/programs/shutdown.lua from running
    _G.os.run = run
end

local shutdown = os.shutdown
os.shutdown = function() -- run on final line of bios.lua
    _G.os.shutdown = shutdown

    local CHANNEL_BROADCAST = rednet.CHANNEL_BROADCAST

    local coro = create(fakeBIOS)
    local success, filter
    local function cresume(...)
        local ev, _, _, _, data = ...
        if ev == "modem_message" and type(data) == "table" then
            local recipient = data.nRecipient
            if data.nMessageID
                and recipient ~= computerID
                and recipient ~= CHANNEL_BROADCAST then
                return -- ignore the event
            end
        end
        success, filter = resume(coro, ...)
    end
    cresume()
    repeat until cresume(
        yield(filter)
    ) or status(coro) ~= "suspended"

    if not success then error(filter) end
end

shell.run = function() end -- prevent startup.lua from starting up anything else
shell.exit()
-- multishell will yield for event because shell doesn't get cullProcessed on first resume
if multishell then
    debug.setupvalue(multishell.getCount, upvalueIndex(multishell.getCount, "tProcesses"), {})
end
_ENV = nil
