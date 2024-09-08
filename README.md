# ComputerCraft ROM-Assisted DRM
This repository contains a proof-of-concept for a DRM scheme in ComputerCraft using a file in rom/autorun. 

Short explanation:
- when the computer boots, after settings load but before user startup programs run, the code in `romdrm.lua` runs
- if the drm setting is enabled, it takes the ID and a hash of the `startup` file
- it overrides `http.request` and `http.websocket` to send the ID/hash in the header `CC-ROM-DRM` (if the CC-ROM-DRM header was already set), and prevent any false headers from being sent
- the startup downloads the protected program from the server, with the server validating the startup hash, ID, and IP

The code is a bit messy in its current state. To get it running, use a datapack to move `romdrm.lua` into `/rom/autorun` and move `sha256.lua` into `/rom/modules/main/drm/sha256.lua`, then run `server.js` with node.js in the same folder as `script.lua` and modify the constants in the js if necessary, and install `startup.lua` as `startup` in a computer.

This code is intended to be secure, and I am currently unaware of any vulnerabilities, but I haven't exhaustively tested the protection yet, so there are probably a few bugs I haven't discovered.

Note that the security model of this security scheme is based on the assumption that any arbitrary HTTP requests sent out from the server IP are sent from a ComputerCraft computer with the DRM installed in ROM. If another CC server, another computer mod, or any other ways to send HTTP requests are available from the same IP, this could potentially compromise the protected program.

Thanks to Anavrins for the SHA256 library!

All files in this repository except `sha256.lua` are licensed under the MIT license. See the LICENSE file.