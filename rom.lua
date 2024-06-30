-- install in rom/autorun/
local function sha256()
    -- SHA-256, HMAC and PBKDF2 functions in ComputerCraft
    -- By Anavrins
    -- MIT License
    -- Pastebin: https://pastebin.com/6UV4qfNF
    -- Usage: https://pastebin.com/q2SQ7eRg
    -- Last updated: Nov 13 2021
    -- Modified to remove HMAC, PBKDF2 functions

    local mod32 = 2^32
    local band    = bit32 and bit32.band or bit.band
    local bnot    = bit32 and bit32.bnot or bit.bnot
    local bxor    = bit32 and bit32.bxor or bit.bxor
    local blshift = bit32 and bit32.lshift or bit.blshift
    local upack   = unpack

    local function rrotate(n, b)
    	local s = n/(2^b)
    	local f = s%1
    	return (s-f) + f*mod32
    end
    local function brshift(int, by)
    	local s = int / (2^by)
    	return s - s%1
    end

    local H = { -- First 32 bits of the fractional parts of the square roots of the first 8 primes 2..19
    	0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    	0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    }

    local K = { -- First 32 bits of the fractional parts of the cube roots of the first 64 primes 2..311
    	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }

    local function counter(incr)
    	local t1, t2 = 0, 0
    	if 0xFFFFFFFF - t1 < incr then
    		t2 = t2 + 1
    		t1 = incr - (0xFFFFFFFF - t1) - 1
    	else t1 = t1 + incr
    	end
    	return t2, t1
    end

    local function BE_toInt(bs, i)
    	return blshift((bs[i] or 0), 24) + blshift((bs[i+1] or 0), 16) + blshift((bs[i+2] or 0), 8) + (bs[i+3] or 0)
    end

    local function preprocess(data)
    	local len = #data
    	local proc = {}
    	data[#data+1] = 0x80
    	while #data%64~=56 do data[#data+1] = 0 end
    	local blocks = math.ceil(#data/64)
    	for i = 1, blocks do
    		proc[i] = {}
    		for j = 1, 16 do
    			proc[i][j] = BE_toInt(data, 1+((i-1)*64)+((j-1)*4))
    		end
    	end
    	proc[blocks][15], proc[blocks][16] = counter(len*8)
    	return proc
    end

    local function digestblock(w, C)
    	for j = 17, 64 do
    		local v = w[j-15]
    		local s0 = bxor(rrotate(w[j-15], 7), rrotate(w[j-15], 18), brshift(w[j-15], 3))
    		local s1 = bxor(rrotate(w[j-2], 17), rrotate(w[j-2], 19),brshift(w[j-2], 10))
    		w[j] = (w[j-16] + s0 + w[j-7] + s1)%mod32
    	end
    	local a, b, c, d, e, f, g, h = upack(C)
    	for j = 1, 64 do
    		local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
    		local ch = bxor(band(e, f), band(bnot(e), g))
    		local temp1 = (h + S1 + ch + K[j] + w[j])%mod32
    		local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
    		local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
    		local temp2 = (S0 + maj)%mod32
    		h, g, f, e, d, c, b, a = g, f, e, (d+temp1)%mod32, c, b, a, (temp1+temp2)%mod32
    	end
    	C[1] = (C[1] + a)%mod32
    	C[2] = (C[2] + b)%mod32
    	C[3] = (C[3] + c)%mod32
    	C[4] = (C[4] + d)%mod32
    	C[5] = (C[5] + e)%mod32
    	C[6] = (C[6] + f)%mod32
    	C[7] = (C[7] + g)%mod32
    	C[8] = (C[8] + h)%mod32
    	return C
    end

    local mt = {
    	__tostring = function(a) return string.char(unpack(a)) end,
    	__index = {
    		toHex = function(self, s) return ("%02x"):rep(#self):format(unpack(self)) end,
    		isEqual = function(self, t)
    			if type(t) ~= "table" then return false end
    			if #self ~= #t then return false end
    			local ret = 0
    			for i = 1, #self do
    				ret = bit32.bor(ret, bxor(self[i], t[i]))
    			end
    			return ret == 0
    		end,
            sub = function(self, a, b)
                local len = #self+1
                local start = a%len
                local stop = (b or len-1)%len
                local ret = {}
                local i = 1
                for j = start, stop, start<stop and 1 or -1 do
                    ret[i] = self[j]
                    i = i+1
                end
                return setmetatable(ret, byteArray_mt)
            end,
    	}
    }

    local function toBytes(t, n)
    	local b = {}
    	for i = 1, n do
    		b[(i-1)*4+1] = band(brshift(t[i], 24), 0xFF)
    		b[(i-1)*4+2] = band(brshift(t[i], 16), 0xFF)
    		b[(i-1)*4+3] = band(brshift(t[i], 8), 0xFF)
    		b[(i-1)*4+4] = band(t[i], 0xFF)
    	end
    	return setmetatable(b, mt)
    end

    local function digest(data)
    	local data = data or ""
    	data = type(data) == "table" and {upack(data)} or {tostring(data):byte(1,-1)}

    	data = preprocess(data)
    	local C = {upack(H)}
    	for i = 1, #data do C = digestblock(data[i], C) end
    	return toBytes(C, 8)
    end

    return {
    	digest = digest
    }
end

sha256 = sha256().digest

local function hashFile(name)
    local file = fs.open(name, "r")
    local text = file.readAll()
    file.close()
    return sha256(text):toHex()
end

local function protectFunc(func)
    local accept, call
    local yield, pcall = coroutine.yield, pcall

    function accept(...) return call(yield(...)) end

    function call(...) return accept(pcall(func, ...)) end

    local wrappedFunction = coroutine.wrap(function()
        accept(func, call)
    end)
    wrappedFunction() -- call it once so it can start yielding

    local error = error

    local function processResults(success, ...)
        if success then return ... else error(..., 2) end
    end

    return function(...) --  propagates errors
        return processResults(wrappedFunction(...))
    end
end

local function upvalueIndex(func, name)
    local i = 0
    local currentName
    repeat
        i = i + 1
        currentName = debug.getupvalue(func, i)
    until not currentName or currentName == name
    return i, select(2, debug.getupvalue(func, i))
end

local upper = string.upper
local type, next, rawget, rawset = type, next, rawget, rawset
local headerName = "CcRomDrm"

local function fixHeaders(headersTable, intendedValue)
    local found
    repeat
        found = false
        for header, _ in next, headersTable do
            if type(header) == "string" and upper(header) == upper(headerName) then
                found = true
                rawset(headersTable, header, nil)
                break
            end
        end
    until not found
    rawset(headersTable, headerName, intendedValue)
end

local DRMValue
local DRMEnabled = false

if settings.get("ccromdrm.enabled")
        and settings.get("shell.allow_startup")
        and (not settings.get("shell.allow_disk_startup"))
        and fs.exists("startup")
        and (not fs.isDir("startup")) then
    DRMEnabled = true
    DRMValue = ("DRM-%d-%s"):format(
        os.getComputerID(),
        hashFile("startup")
    )
end

os.isDRMEnabled = protectFunc(function()
    return DRMEnabled
end)

os.disableDRM = protectFunc(function()
    DRMEnabled = false
    DRMValue = nil
end)

local nativeRequestIdx, nativeHTTPRequest = upvalueIndex(http.request, 'nativeHTTPRequest')
local nativeWebsocketIdx, nativeWebsocket = upvalueIndex(http.websocket, 'nativeWebsocket')

debug.setupvalue(http.request, nativeRequestIdx, protectFunc(
    function(_url, _post, _headers, _binary)
        if type(_url) == "table" then
            local headers = rawget(_url, "headers") or {}
            rawset(_url, "headers", headers)
            fixHeaders(headers, DRMValue)
        else
            _headers = _headers or {}
            fixHeaders(_headers, DRMValue)
        end
        return nativeHTTPRequest(_url, _post, _headers, _binary)
    end
))

debug.setupvalue(http.websocket, nativeWebsocketIdx, protectFunc(
    function(_url, _headers)
        if type(_url) == "table" then
            local headers = rawget(_url, "headers") or {}
            rawset(_url, "headers", headers)
            fixHeaders(headers, DRMValue)
        else
            _headers = _headers or {}
            fixHeaders(_headers, DRMValue)
        end
        return nativeWebsocket(_url, _headers)
    end
))
