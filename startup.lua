-- install as startup
if not os.isDRMEnabled() then
    -- set necessary settings
    settings.set("ccromdrm.enabled", true)
    settings.set("shell.allow_startup", true)
    settings.set("shell.allow_disk_startup", false)
    settings.set("motd.enable", false) -- this is not necessary but it was getting annoying

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
local response, err, errHandle = http.get(url)

if response then
    os.disableDRM()
    local data = response.readAll()
    response.close()

    local func = load(data, "script.lua")
    local success, err = pcall(func)
    if not success then
        printError(err)
    end
else
    printError(err)
    if errHandle then printError(errHandle.readAll()) errHandle.close() end
end