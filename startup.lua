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
local response, err, errHandle = http.get(url, { ["CC-ROM-DRM"] = true })

-- In case the program errors/crashes to a shell or has been spoofed somehow,
-- we disable DRM so that it can't download anything else from the server:
os.disableDRM()

if not response then
    if errHandle then
        printError(errHandle.readAll())
        errHandle.close()
    end
    return printError(err)
end

local programText = response.readAll()
response.close()

local func, err = load(programText, "script.lua")
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
