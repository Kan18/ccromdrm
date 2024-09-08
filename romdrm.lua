-- ComputerCraft ROM-assisted DRM

-- By hashing the startup file and attaching its hash in an HTTP header, we can
-- allow external servers to verify the code currently running, allowing use
-- cases such as serving a program and preventing it from being copied.
-- Read the README for more information.

-- The header name under which the "DRM value" (ID + hash) is sent.
-- Note that HTTP header names are case insensitive, and different HTTP servers
-- might change the case of the header.
-- Programs will need to set any value under this header to send the DRM value.
local DRM_HEADER_NAME = "CC-ROM-DRM"

-- The setting which must be set to a truthy value to allow the DRM value to be
-- calculated.
local DRM_ENABLED_SETTING = "ccromdrm.enabled"

-- We localize any functions used in any code that runs after startup,
-- because user code might attempt to overwrite these functions in the
-- global environment and modify our code's behavior. sha256 only runs
-- during startup, so we don't care about it being potentially modified.
local error, next, pcall, rawget, type, upper, yield =
    error, next, pcall, rawget, type, string.upper, coroutine.yield

local digest = dofile("/rom/modules/main/drm/sha256.lua").digest

-- This function creates the "DRM value" which is sent as an HTTP header if the
-- relevant settings are enabled. It will error if there was an issue.
local function getDRMValue()
    if not settings.get(DRM_ENABLED_SETTING) then return nil end
    -- We check various settings which essentially confirm that the file in
    -- `startup` is the first user code to be executed on this computer.
    -- Interestingly, .settings can be modified such that it returns different
    -- results on different boots (using `("%s"):format({})` to get randomness)
    -- but we're only checking what the settings are for this boot, so that
    -- doesn't matter.
    -- Also, note that we're running before startup is. If startup has a syntax
    -- error, it will fail to run, but hopefully people's external servers will
    -- not be accepting hashes of syntactically invalid Lua scripts.

    if not settings.get("shell.allow_startup") then
        error("must enable shell.allow_startup")
    end

    if settings.get("shell.allow_disk_startup") then
        error("must disable shell.allow_disk_startup")
    end

    if (not fs.exists("startup")) or fs.isDir("startup") then
        error("startup must be a file")
    end

    local startupFile = fs.open("startup", "r")
    local startupText = startupFile.readAll()
    startupFile.close()

    -- Concatenate the computer ID and hash with dashes.
    -- Previous ideas involved using some kind of cryptographic key to sign the
    -- value, allowing user programs to potentially send it themselves over
    -- other communication mediums. However, this was generally more complex.
    return ("DRM-%d-%s"):format(
        os.getComputerID(),
        digest(startupText):toHex()
    )
end

-- The important part of the program. Basically, it is not possible to debug a
-- coroutine.wrapped function (you can't get the orig func or its upvalues).
-- We return a helper function that allows the function to throw errors, since
-- if we errored from the wrapped function it would sadly stop being callable.
-- This version of protectFunc doesn't support yielding functions (peripherals,
-- etc.) although it is possible with a bit more work. This is basically an
-- alternative to things like dbprotect, but with more simplicity.
local function protectFunc(func)
    -- Localize the functions so they can call each other:
    local accept, call
    -- accept takes in the return from pcall the last time the function was
    -- called, then yields it (giving it to propagateErrors as the return from
    -- wrappedFunc). Afterwards, when wrappedFunc is called again, the yield
    -- call here will return, and accept will pass the return value of yield
    -- into call.
    function accept(...) return call(yield(...)) end

    -- call takes in the arguments for a function call, then passes it over to
    -- pcall. After pcall returns, call will send the return values of pcall to
    -- accept.
    function call(...) return accept(pcall(func, ...)) end

    -- wrappedFunc itself is accessible by other programs messing with upvalues
    -- but accept/call/func, importantly, are not accessible externally.
    local wrappedFunc = coroutine.wrap(call)

    -- We redefine this here so that hostile programs can't mess with the error
    -- upvalue for the other parts of this program, since processResults and
    -- propagateErrors are accessible externally. Of course, a program could
    -- mess with them such that they don't work, but at that point you might
    -- as well just set them to nil and be done with it.
    local error2 = error

    -- processResults takes the return values of pcall and either returns the
    -- function's return values (without the success bool) or throws an error.
    local function processResults(success, ...)
        if success then return ... else return error2(..., 2) end
    end

    -- propagateResults calls wrappedFunc and then gives the results over to
    -- processResults to either return the values or throw an error.
    local function propagateErrors(...)
        return processResults(wrappedFunc(...))
    end

    -- And yes, I could've written accept/call/processResults/propagateErrors
    -- in other ways, but I wanted to avoid table.unpack/table.pack for
    -- aesthetic purposes.
    return propagateErrors
end

-- Now we actually compute the DRM value.
local success, DRMValue = pcall(getDRMValue)

if not success then
    -- It's worth informing the user about an error here because an error would
    -- have only happened if DRM_ENABLED_SETTING was true, so the computer is
    -- probably supposed to have DRM enabled.
    printError("DRM failed to load:", DRMValue)
    -- At the same time, we want to tell the user how to stop the error.
    printError(("Unset %s setting to silence."):format(DRM_ENABLED_SETTING))
    DRMValue = nil
end

-- Functions to allow programs to interact with DRM.

-- Gets the DRM value which will be applied to HTTP requests. If this function
-- hadn't existed, programs would have had to make an HTTP request to check it.
os.getDRMValue = protectFunc(function()
    return DRMValue
end)

os.isDRMEnabled = protectFunc(function()
    return not not DRMValue
end)

-- Sets the DRM value which will be applied to HTTP requests to nil.
os.disableDRM = protectFunc(function()
    DRMValue = nil
end)

-- Helper function for getting the index of an upvalue.
local function upvalueIndex(func, name)
    local i, currentName = 0, nil
    repeat
        i = i + 1
        currentName = debug.getupvalue(func, i)
    until not currentName or currentName == name
    return i, select(2, debug.getupvalue(func, i))
end

-- Function that clones all headers into a new table. If any match the DRM
-- header name, correctly set the DRM header in the headers table. There might
-- be some edge-cases in this function with regards to whitespace or special
-- characters, but I tested it for a while and couldn't find anything.
local function fixHeaders(headersTable)
    if type(headersTable) ~= "table" then
        return headersTable
    end

    local newHeaders = {}
    local setDRMHeader = false

    for header, value in next, headersTable do
        if type(header) == "string"
            and upper(header) == upper(DRM_HEADER_NAME) then
            setDRMHeader = true
        else
            newHeaders[header] = value
        end
    end

    if setDRMHeader then
        newHeaders[DRM_HEADER_NAME] = DRMValue
    end

    return newHeaders
end

-- Now we overwrite the HTTP functions that could potentially send headers. We
-- need to do this even if DRM is disabled, because otherwise

local nativeRequestIdx, nativeHTTPRequest =
    upvalueIndex(http.request, 'nativeHTTPRequest')
local nativeWebsocketIdx, nativeWebsocket =
    upvalueIndex(http.websocket, 'nativeWebsocket')

if not nativeHTTPRequest or not nativeWebsocket then
    printError("Warning: DRM failed to find upvalue indexes, CC:T update?")
end

debug.setupvalue(
    http.request,
    nativeRequestIdx,
    protectFunc(function(url, post, headers, binary)
        -- We try to avoid modifying the table that the user code gives us, as
        -- that can lead to potential issues. Instead, we just modify a copy.
        if type(url) == "table" then
            url = {
                url = rawget(url, "url"),
                body = rawget(url, "body"),
                headers = fixHeaders(rawget(url, "headers")),
                binary = rawget(url, "binary"),
                method = rawget(url, "method"),
                redirect = rawget(url, "redirect"),
                timeout = rawget(url, "timeout")
            }
        else
            headers = fixHeaders(headers)
        end
        return nativeHTTPRequest(url, post, headers, binary)
    end)
)

debug.setupvalue(
    http.websocket,
    nativeWebsocketIdx,
    protectFunc(function(url, headers)
        if type(url) == "table" then
            url = {
                url = rawget(url, "url"),
                headers = fixHeaders(rawget(url, "headers")),
                timeout = rawget(url, "timeout")
            }
        else
            headers = fixHeaders(headers)
        end
        return nativeWebsocket(url, headers)
    end)
)
