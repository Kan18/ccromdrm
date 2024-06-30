# ComputerCraft ROM-Assisted DRM
This repository contains a proof-of-concept for a DRM scheme in ComputerCraft using a file in rom/autorun. 

Short explanation:
- when the computer boots, after settings load but before user startup programs run, the code in `rom.lua` runs
- if the drm setting is enabled, it takes the ID and a hash of the `startup` file
- it overrides `http.request` and `http.websocket` to send the ID/hash in the header `CcRomDrm` if enabled, and prevent any false headers from being sent
- the startup downloads the protected program from the server, which validates the startup hash, ID, and IP

The code is a bit messy in its current state. To get it running, use a datapack to move `rom.lua` into `rom/autorun`, run `server.js` with node.js in the same folder as `script.lua` and modify the constants in the js if necessary, and install `startup.lua` as `startup` in a computer.