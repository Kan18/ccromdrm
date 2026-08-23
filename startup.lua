-- Install this script as startup, not startup.lua
if not os.isDRMEnabled() then
    -- We set the necessary settings here.
    settings.set("ccromdrm.enabled", true)
    settings.set("shell.allow_startup", true)
    settings.set("shell.allow_disk_startup", false)
    -- This is not necessary but the motd was getting annoying.
    settings.set("motd.enable", false)

    local prog = shell.getRunningProgram()

    if prog ~= "startup" then
        if fs.exists("startup") then fs.move("startup", "startup.old") end
        fs.move(prog, "startup")
    end

    settings.save()
    os.reboot()
end

print("Downloading program...")
print()
local url = "http://localhost:3000/script.lua"

local callSuccess, requestStarted, requestError = pcall(
    http.request,
    url,
    nil,
    { ["CC-ROM-DRM"] = true }
)

if not callSuccess then
    os.disableDRM()
    return printError(requestStarted)
elseif not requestStarted then
    os.disableDRM()
    return printError(requestError)
end

local response, err, errHandle
local terminated = false

while true do
    local event, eventURL, param1, param2 = os.pullEventRaw()

    if event == "terminate" then
        -- The request has already started, so wait for and discard its response
        -- instead of leaving it for an interactive shell to receive.
        terminated = true
    elseif eventURL == url then
        if event == "http_success" then
            response = param1
            break
        elseif event == "http_failure" then
            err, errHandle = param1, param2
            break
        end
    end
end

-- In case the program errors/crashes to a shell or has been spoofed somehow,
-- we disable DRM so that it can't download anything else from the server:
os.disableDRM()

if terminated then
    if response then response.close() end
    if errHandle then errHandle.close() end
    return printError("Terminated")
end

if not response then
    if errHandle then
        printError(errHandle.readAll())
        errHandle.close()
    end
    return printError(err)
end

local programText = response.readAll()
response.close()

local func, err = load(programText, "script.lua", "t", _ENV)
-- Remove the program text from memory in case the program gives the user a
-- shell, in which case it could otherwise be extracted via debug.getlocal
programText, response = nil, nil
if not func then
    return printError(err)
end

local success, err = pcall(func)
if not success then
    printError(err)
end
