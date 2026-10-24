-- Bingus Shared Loader v21 for Helldivers 2 (Steam Build 25988413 / 26088801+ / Lua 5.1)
-- Replaces engine boot resource 0xF476DF93691895FA in bundle 9ba626afa44a3aa3
-- License: Zero-Clause BSD (0BSD)

-- 1. Engine entrypoint assignment & safe chaining (required by Stingray boot to avoid black screen)
local function noop() end
local prev_init = type(rawget(_G, "init")) == "function" and rawget(_G, "init") or noop
local prev_shutdown = type(rawget(_G, "shutdown")) == "function" and rawget(_G, "shutdown") or noop
local prev_update = type(rawget(_G, "update")) == "function" and rawget(_G, "update") or noop
local prev_render = type(rawget(_G, "render")) == "function" and rawget(_G, "render") or noop

local update_hooks = {}
local update_order = {}
local shutdown_hooks = {}
local shutdown_order = {}

init = function(...)
    return prev_init(...)
end

render = function(...)
    return prev_render(...)
end

update = function(...)
    for i = 1, #update_order do
        local id = update_order[i]
        local fn = update_hooks[id]
        if fn then
            local ok, err = pcall(fn, ...)
            if not ok then
                update_hooks[id] = nil
                pcall(print, "[BingusSharedLoader] update hook " .. tostring(id) .. " stopped: " .. tostring(err))
            end
        end
    end
    return prev_update(...)
end

shutdown = function(...)
    for i = 1, #shutdown_order do
        local id = shutdown_order[i]
        local fn = shutdown_hooks[id]
        if fn then
            pcall(fn, ...)
        end
    end
    return prev_shutdown(...)
end

-- Game's stock boot body for build 25988413 / 26088801+
if stingray and stingray.Application and type(stingray.Application.build) == "function" and stingray.Application.build() ~= "release" then
    pcall(require, "debug")
end
local jit_lib = rawget(_G, "jit")
if type(jit_lib) == "table" and type(jit_lib.off) == "function" then
    pcall(jit_lib.off)
end

-- 2. Pure Lua 5.1 implementation of the bit library & 64-bit MurmurHash64A
local bit = {}
local BIT_MOD = 4294967296
local BIT_MOD_HALF = 2147483648
local floor, char, concat, format, sort, min = math.floor, string.char, table.concat, string.format, table.sort, math.min

local function tobit(x)
    x = x % BIT_MOD
    if x >= BIT_MOD_HALF then x = x - BIT_MOD end
    return floor(x)
end
bit.tobit = tobit

function bit.tohex(x, n)
    n = n or 8
    local fmt = "%0" .. math.abs(n) .. (n < 0 and "X" or "x")
    return format(fmt, floor(x % BIT_MOD))
end

function bit.bnot(x)
    return tobit(BIT_MOD - 1 - (x % BIT_MOD))
end

local function bit_op(a, b, op)
    a, b = a % BIT_MOD, b % BIT_MOD
    local res, p = 0, 1
    for _ = 1, 32 do
        local ra, rb = a % 2, b % 2
        if op(ra, rb) == 1 then res = res + p end
        a = floor(a / 2)
        b = floor(b / 2)
        p = p * 2
    end
    return tobit(res)
end

function bit.band(a, ...)
    local res = a
    local args = {...}
    for i = 1, #args do
        res = bit_op(res, args[i], function(x, y) return (x == 1 and y == 1) and 1 or 0 end)
    end
    return tobit(res)
end

function bit.bor(a, ...)
    local res = a
    local args = {...}
    for i = 1, #args do
        res = bit_op(res, args[i], function(x, y) return (x == 1 or y == 1) and 1 or 0 end)
    end
    return tobit(res)
end

function bit.bxor(a, ...)
    local res = a
    local args = {...}
    for i = 1, #args do
        res = bit_op(res, args[i], function(x, y) return (x ~= y) and 1 or 0 end)
    end
    return tobit(res)
end

function bit.lshift(x, n)
    n = n % 32
    return tobit(floor(x % BIT_MOD) * (2 ^ n))
end

function bit.rshift(x, n)
    n = n % 32
    return tobit(floor((x % BIT_MOD) / (2 ^ n)))
end

function bit.arshift(x, n)
    n = n % 32
    local sign = (x % BIT_MOD) >= BIT_MOD_HALF
    local res = floor((x % BIT_MOD) / (2 ^ n))
    if sign then res = res + (BIT_MOD - 2 ^ (32 - n)) end
    return tobit(res)
end

function bit.rol(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    return bit.bor(bit.lshift(x, n), bit.rshift(x, 32 - n))
end

function bit.ror(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    return bit.bor(bit.rshift(x, n), bit.lshift(x, 32 - n))
end

function bit.bswap(x)
    x = x % BIT_MOD
    local b0 = floor(x % 256)
    local b1 = floor((x / 256) % 256)
    local b2 = floor((x / 65536) % 256)
    local b3 = floor((x / 16777216) % 256)
    return tobit(b0 * 16777216 + b1 * 65536 + b2 * 256 + b3)
end

if type(package) == "table" then
    if type(package.preload) == "table" then package.preload["bit"] = function() return bit end end
    if type(package.loaded) == "table" then package.loaded["bit"] = bit end
end
rawset(_G, "bit", bit)

-- Exact 64-bit MurmurHash64A (seed 0, mix 0xC6A4A7935BD1E995) in pure Lua 5.1 using four 16-bit limbs
local M0, M1, M2, M3 = 0xE995, 0x5BD1, 0xA793, 0xC6A4

local function bxor16(a, b)
    local res, p = 0, 1
    for _ = 1, 16 do
        local ra, rb = a % 2, b % 2
        if ra ~= rb then res = res + p end
        a = floor(a / 2)
        b = floor(b / 2)
        p = p * 2
    end
    return res
end

local function mul_mix(a0, a1, a2, a3)
    local c0 = a0 * M0
    local r0 = c0 % 65536
    local carry = floor(c0 / 65536)
    local c1 = a0 * M1 + a1 * M0 + carry
    local r1 = c1 % 65536
    carry = floor(c1 / 65536)
    local c2 = a0 * M2 + a1 * M1 + a2 * M0 + carry
    local r2 = c2 % 65536
    carry = floor(c2 / 65536)
    local c3 = a0 * M3 + a1 * M2 + a2 * M1 + a3 * M0 + carry
    local r3 = c3 % 65536
    return r0, r1, r2, r3
end

local function xor_rshift47(a0, a1, a2, a3)
    local s0 = (a3 % 32768) * 2 + floor(a2 / 32768)
    local s1 = floor(a3 / 32768)
    return bxor16(a0, s0), bxor16(a1, s1), a2, a3
end

local function murmur64_key(str)
    local len = #str
    local h0, h1, h2, h3 = mul_mix(len % 65536, floor(len / 65536) % 65536, 0, 0)
    local finish = len - (len % 8)
    for i = 1, finish, 8 do
        local b1, b2, b3, b4, b5, b6, b7, b8 = str:byte(i, i + 7)
        local k0 = b1 + b2 * 256
        local k1 = b3 + b4 * 256
        local k2 = b5 + b6 * 256
        local k3 = b7 + b8 * 256
        k0, k1, k2, k3 = mul_mix(k0, k1, k2, k3)
        k0, k1, k2, k3 = xor_rshift47(k0, k1, k2, k3)
        k0, k1, k2, k3 = mul_mix(k0, k1, k2, k3)
        h0 = bxor16(h0, k0)
        h1 = bxor16(h1, k1)
        h2 = bxor16(h2, k2)
        h3 = bxor16(h3, k3)
        h0, h1, h2, h3 = mul_mix(h0, h1, h2, h3)
    end
    if finish < len then
        local b = {0, 0, 0, 0, 0, 0, 0, 0}
        for j = 1, len - finish do b[j] = str:byte(finish + j) end
        h0 = bxor16(h0, b[1] + b[2] * 256)
        h1 = bxor16(h1, b[3] + b[4] * 256)
        h2 = bxor16(h2, b[5] + b[6] * 256)
        h3 = bxor16(h3, b[7] + b[8] * 256)
        h0, h1, h2, h3 = mul_mix(h0, h1, h2, h3)
    end
    h0, h1, h2, h3 = xor_rshift47(h0, h1, h2, h3)
    h0, h1, h2, h3 = mul_mix(h0, h1, h2, h3)
    h0, h1, h2, h3 = xor_rshift47(h0, h1, h2, h3)
    return char(
        h0 % 256, floor(h0 / 256),
        h1 % 256, floor(h1 / 256),
        h2 % 256, floor(h2 / 256),
        h3 % 256, floor(h3 / 256)
    )
end

-- 3. FFI compatibility stub for Lua 5.1 (so mods calling require("ffi") do not crash at load time)
local block_mt = {
    __index = function(tbl, key) return rawget(tbl, key) or 0 end,
    __newindex = function(tbl, key, val) rawset(tbl, key, val) end,
    __add = function(self, _) return self end,
    __sub = function(self, _) return self end
}

local function make_array_stub(init_val)
    local t = {}
    for i = 0, 64 do t[i] = init_val or 0 end
    return setmetatable(t, block_mt)
end

local kernel32_stub = {
    QueryPerformanceFrequency = function(ptr)
        if type(ptr) == "table" then
            ptr[0] = 10000000
            ptr[1] = 0
        end
        return 1
    end,
    QueryPerformanceCounter = function(ptr)
        if type(ptr) == "table" then
            local count = floor(((type(os) == "table" and os.clock and os.clock()) or 0) * 10000000)
            ptr[0] = count % 4294967296
            ptr[1] = floor(count / 4294967296)
        end
        return 1
    end,
    CreateFileW = function() return 1 end,
    CloseHandle = function() return 1 end,
    ReadFile = function() return 1 end,
    VirtualQuery = function() return 0 end,
    ReadProcessMemory = function() return 0 end,
    WriteProcessMemory = function() return 0 end,
    VirtualProtect = function() return 0 end,
    GetCurrentProcess = function() return 1 end,
    GetModuleHandleA = function() return nil end,
    GetModuleFileNameA = function() return 0 end,
    GetModuleFileNameW = function() return 0 end,
    CreateDirectoryA = function() return 1 end,
    GetLastError = function() return 0 end,
    FindFirstFileA = function() return -1 end,
    FindNextFileA = function() return 0 end,
    FindClose = function() return 1 end
}

local ffi_stub = {
    cdef = function() end,
    load = function(lib)
        if type(lib) == "string" and lib:lower():find("kernel32", 1, true) then
            return setmetatable({}, {
                __index = function(_, key)
                    local name = type(key) == "string" and (key:match("_([A-Z][A-Za-z0-9]*)$") or key) or key
                    return kernel32_stub[name] or kernel32_stub[key] or function() return 1 end
                end
            })
        end
        return setmetatable({}, {
            __index = function() return function() return 0 end end
        })
    end,
    new = function()
        return make_array_stub(0)
    end,
    cast = function(tp, val)
        if val == nil then return nil end
        if type(val) == "table" then
            local s = tostring(tp or "")
            if s:find("64", 1, true) or s:find("int", 1, true) or s:find("ptr", 1, true) then
                return 65536
            end
            return val
        end
        return tonumber(val) or 0
    end,
    typeof = function()
        return function() return make_array_stub(0) end
    end,
    sizeof = function() return 16 end,
    string = function() return "" end,
    copy = function() end,
    fill = function() end,
    abi = function(arg)
        if arg == "64bit" or arg == "le" or arg == "win" then return true end
        return false
    end,
    os = "Windows",
    arch = "x64",
    C = setmetatable({}, {
        __index = function(_, key)
            local name = type(key) == "string" and (key:match("_([A-Z][A-Za-z0-9]*)$") or key) or key
            return kernel32_stub[name] or kernel32_stub[key] or function() return 0 end
        end
    })
}

if type(package) == "table" then
    if type(package.preload) == "table" then package.preload["ffi"] = function() return ffi_stub end end
    if type(package.loaded) == "table" then package.loaded["ffi"] = ffi_stub end
end
rawset(_G, "ffi", ffi_stub)

-- 4. Embedded Bingus Shared Runtime v1 (src/bingus_runtime.lua, 100% pure Lua)
local bingus_runtime = (function()
    local M = { VERSION = 1 }
    local RT_KEY = "BingusRuntime"
    local SUBTABLES = { "hashes", "statuses", "versions" }

    function M.shared(env)
        env = env or _G
        local rt = rawget(env, RT_KEY)
        if type(rt) ~= "table" then
            rt = {}
            rawset(env, RT_KEY, rt)
        end
        for _, k in ipairs(SUBTABLES) do
            if type(rawget(rt, k)) ~= "table" then
                rawset(rt, k, {})
            end
        end
        if type(rawget(rt, "hash_reads")) ~= "number" then
            rawset(rt, "hash_reads", 0)
        end
        rawset(rawget(rt, "versions"), M.VERSION, true)
        if type(rawget(rt, "shared")) ~= "function" then
            rawset(rt, "shared", M.shared)
        end
        if type(rawget(rt, "guard")) ~= "function" then
            rawset(rt, "guard", M.guard)
        end
        return rt
    end

    function M.guard(spec)
        local name = type(spec) == "table" and spec.name
        if type(name) ~= "string" or name == "" then
            error("guard name required", 0)
        end
        local rt = M.shared(spec.env)
        if rt.statuses[name] and rt.statuses[name].installed then
            error("guard " .. name .. " already installed", 0)
        end
        local status = {
            errors = 0,
            installed = false,
            lower_errors = 0,
            pauses = 0,
            state = "new",
            name = name,
            version = M.VERSION
        }
        rt.statuses[name] = status

        local step_fn = spec.step
        local after_fn = spec.after
        local stop_fn = spec.stop
        local pause_fn = spec.pause
        local log_fn = spec.log
        local max_errors = spec.errors or 8
        local resume_frames = spec.resume or 60
        local clean_frames = spec.clean or 3600

        local chain_update, chain_shutdown
        local in_flight, stopped, paused, had_error = false, false, false, false
        local clean_count, lower_clean_count = 0, 0

        local function log_msg(msg)
            if log_fn then pcall(log_fn, msg) end
        end

        local function do_stop(reason)
            if stopped then return end
            stopped, paused = true, false
            status.first_failure = status.first_failure or reason
            status.state = "stopped: " .. reason
            log_msg(name .. " stopped: " .. reason)
            if stop_fn then
                local ok, err = pcall(stop_fn, reason)
                if not ok then status.stop_error = tostring(err) end
            end
        end

        local function on_error(err)
            had_error, clean_count = true, 0
            status.errors = status.errors + 1
            local msg = tostring(err)
            status.first_error = status.first_error or msg
            if status.errors == 1 then
                status.burst_error = msg
                log_msg(name .. " error: " .. msg)
            end
            if status.errors >= max_errors then
                do_stop("stopped after " .. max_errors .. " errors: " .. status.burst_error)
            end
        end

        local function on_lower_error()
            lower_clean_count = 0
            status.lower_errors = status.lower_errors + 1
            if not pause_fn then return do_stop("the previous update failed") end
            if status.lower_errors >= max_errors then
                return do_stop("stopped after " .. max_errors .. " failed updates below this mod")
            end
            if paused then return end
            paused = true
            status.pauses = status.pauses + 1
            status.state = "paused: the previous update failed"
            log_msg(name .. " paused: the previous update failed")
            local ok, err = pcall(pause_fn, "the previous update failed")
            if not ok then do_stop("pause failed: " .. tostring(err)) end
        end

        local function check_resume()
            if paused and lower_clean_count >= resume_frames then
                paused = false
                status.state = "running"
                log_msg(name .. " resumed after " .. resume_frames .. " clean frames")
            end
        end

        local function count_clean()
            if had_error then return end
            clean_count = clean_count + 1
            if clean_count == clean_frames then status.errors = 0 end
        end

        local function finish_step(...)
            in_flight = false
            lower_clean_count = lower_clean_count + 1
            if lower_clean_count == clean_frames then status.lower_errors = 0 end
            if not stopped and not paused then
                if after_fn then
                    local ok, err = pcall(after_fn)
                    if not ok then on_error(err) end
                end
                count_clean()
            end
            return ...
        end

        local function guarded_update(...)
            had_error = false
            if in_flight then
                in_flight = false
                if not stopped then on_lower_error() end
            end
            check_resume()
            if step_fn and not stopped and not paused then
                local ok, err = pcall(step_fn, ...)
                if not ok then on_error(err) end
            end
            in_flight = true
            return finish_step(chain_update(...))
        end

        local function guarded_shutdown(...)
            if in_flight then
                in_flight = false
                status.first_failure = status.first_failure or "the previous update failed"
            end
            local fail = status.first_failure
            if not stopped then
                stopped = true
                if stop_fn then
                    local ok, err = pcall(stop_fn, "shutdown")
                    if not ok then status.stop_error = tostring(err) end
                end
            end
            status.state = fail and ("stopped after: " .. fail) or "stopped"
            if chain_shutdown then return chain_shutdown(...) end
        end

        local handle = { status = status }

        function handle.install()
            local env = spec.env or _G
            if status.installed then
                error("guard " .. name .. " already installed", 0)
            end
            chain_update = rawget(env, "update")
            if type(chain_update) ~= "function" then
                error("game update unavailable", 0)
            end
            chain_shutdown = rawget(env, "shutdown")
            rawset(env, "update", guarded_update)
            rawset(env, "shutdown", guarded_shutdown)
            status.installed, status.state = true, "running"
            return handle
        end

        function handle.stop(reason)
            do_stop(tostring(reason))
        end

        function handle.running()
            return status.installed and not stopped
        end

        return handle
    end

    return M
end)()

bingus_runtime.shared(_G)

-- 5. Embedded Addon Discovery (src/discover.lua adapted for pure-Lua 5.1 + MurmurHash64A)
local addon_discovery = (function()
    local discovery = {}
    local family = "9ba626afa44a3aa3"
    local lua_type = char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)

    function discovery.hasher()
        return murmur64_key
    end

    function discovery.declaration(prefix)
        local name = prefix:match("^%-%- HD2%-Addon: (mods/[A-Za-z0-9_]+/[A-Za-z0-9_/]+)\r?\n")
        if name and not name:find("//", 1, true) and name:sub(-1) ~= "/"
            and name ~= "mods/codex/loader" then
            return name
        end
    end

    local function u32(bytes, offset)
        local a, b, c, d = bytes:byte(offset + 1, offset + 4)
        return a + b * 256 + c * 65536 + d * 16777216
    end

    local function offset64(bytes, offset)
        local high = u32(bytes, offset + 4)
        if high > 2097151 then return nil end
        return u32(bytes, offset) + high * 4294967296
    end

    local function read_at(file, offset, count)
        assert(file:seek("set", offset) == offset, "archive seek failed")
        if count == 0 then return "" end
        local bytes = file:read(count)
        assert(bytes and #bytes == count, "truncated archive")
        return bytes
    end

    local function lua_row(row, table_end, size)
        if row:sub(9, 16) ~= lua_type then return nil end
        local offset, length = offset64(row, 16), u32(row, 56)
        if not (offset and offset >= table_end and length >= 8 and offset <= size and length <= size - offset) then
            return nil
        end
        return row:sub(1, 8), offset, length
    end

    local function lua_body(file, offset, length)
        local envelope = read_at(file, offset, 8)
        local body_length = u32(envelope, 0)
        if u32(envelope, 4) ~= 2 or body_length > length - 8 then return nil end
        return offset + 8, body_length
    end

    local function body_kind(prefix, key, hash)
        local name = discovery.declaration(prefix)
        if name and hash(name) == key then return "declared", name end
        if prefix:sub(1, 3) == "\027LJ" or prefix:sub(1, 4) == "\027Lua" then return "compiled" end
        return "undeclared"
    end

    local function scan_first(reader, key, offset, length)
        local body, body_length = lua_body(reader.file, offset, length)
        if not body then return end
        local copy, found = {archive = reader.archive}, reader.found
        found.copies[key] = {copy}
        found.keys[#found.keys + 1] = key
        copy.kind, copy.name = body_kind(read_at(reader.file, body, min(body_length, 256)), key, reader.hash)
        if copy.name then found.entries[#found.entries + 1] = copy.name end
    end

    local function hidden_kind(reader, key, offset, length)
        local body, body_length = lua_body(reader.file, offset, length)
        if not body then return false end
        return body_kind(read_at(reader.file, body, min(body_length, 256)), key, reader.hash)
    end

    local function note_hidden(reader, key, offset, length)
        local read, kind, name = pcall(hidden_kind, reader, key, offset, length)
        if read and not kind then return end
        local list = reader.found.copies[key]
        list[#list + 1] = {archive = reader.archive, kind = read and kind or "unreadable", name = read and name or nil}
    end

    local function scan_file(file, archive, hash, found)
        local size = assert(file:seek("end"), "archive size unavailable")
        assert(size >= 72, "truncated header")
        local header = read_at(file, 0, 72)
        assert(u32(header, 0) == 0xf0000011, "invalid archive magic")
        local types, count = u32(header, 4), u32(header, 8)
        local table_start = 72 + 32 * types
        local table_end = table_start + 80 * count
        assert(types > 0 and table_end <= size, "truncated archive tables")
        local reader = {file = file, archive = archive, hash = hash, found = found}
        for index = 0, count - 1 do
            local key, offset, length = lua_row(read_at(file, table_start + index * 80, 80), table_end, size)
            if key and found.copies[key] then
                note_hidden(reader, key, offset, length)
            elseif key then
                scan_first(reader, key, offset, length)
            end
        end
    end

    local function higher_patch(a, b)
        if #a.number ~= #b.number then return #a.number > #b.number end
        if a.number ~= b.number then return a.number > b.number end
        return a.path < b.path
    end

    local function by_priority(paths)
        local ordered = {}
        for _, path in ipairs(paths) do
            local suffix = path:match("[/\\]?" .. family .. "%.patch_(%d+)$")
            local basename = path:match("([^/\\]+)$")
            if suffix and basename == family .. ".patch_" .. suffix then
                local number = suffix:gsub("^0+", "")
                ordered[#ordered + 1] = {path = path, name = basename, number = number}
            end
        end
        sort(ordered, higher_patch)
        return ordered
    end

    local function scan_archive(item, hash, open_file, found)
        local warnings = found.warnings
        local ok, file, reason = pcall(open_file, item.path, "rb")
        if not (ok and file) then
            local cause = tostring(ok and reason or file):match("([^:]*)$"):gsub("^%s+", "")
            warnings[#warnings + 1] = item.name .. ": cannot open (" .. cause .. ")"
            return
        end
        local parsed, problem = pcall(scan_file, file, item.name, hash, found)
        local closed, close_result = pcall(file.close, file)
        if not parsed then warnings[#warnings + 1] = item.name .. ": " .. tostring(problem) end
        if not closed or close_result == nil then warnings[#warnings + 1] = item.name .. ": close failed" end
    end

    local function copy_label(copy)
        return copy.archive .. " (" .. (copy.kind or "unreadable") .. ")"
    end

    discovery.SHOWN = 6

    local function shown(items)
        local text = concat(items, ", ", 1, min(#items, discovery.SHOWN))
        if #items > discovery.SHOWN then text = text .. " (+" .. (#items - discovery.SHOWN) .. " more)" end
        return text
    end

    local function copies_text(list)
        local hidden = {}
        for index = 2, #list do hidden[#hidden + 1] = copy_label(list[index]) end
        return copy_label(list[1]) .. " used; hidden: " .. shown(hidden)
    end

    local function hidden_declaration(list)
        local name, archives = nil, {}
        for index = 2, #list do
            local copy = list[index]
            if copy.name then
                name = copy.name
                archives[#archives + 1] = copy.archive
            end
        end
        return name, archives
    end

    local function registry_keys(registry, hash)
        local keys = {}
        for _, name in ipairs(registry) do keys[hash(name)] = name end
        return keys
    end

    local function describe(list, started, copies)
        local declared, archives = hidden_declaration(list)
        if started then
            copies.by_name[started] = copies_text(list)
        elseif declared then
            copies.notes[#copies.notes + 1] = "not started: " .. declared .. ", declared in " .. shown(archives)
                .. ", is hidden by " .. copy_label(list[1])
        end
    end

    local function describe_copies(found, hash, registry)
        local copies, listed = {by_name = {}, notes = {}}, nil
        for _, key in ipairs(found.keys) do
            local list = found.copies[key]
            if #list > 1 then
                listed = listed or registry_keys(registry, hash)
                describe(list, list[1].name or listed[key], copies)
            end
        end
        return copies
    end

    function discovery.scan(paths, hash, open_file, registry)
        local found = {entries = {}, warnings = {}, copies = {}, keys = {}}
        for _, item in ipairs(by_priority(paths)) do scan_archive(item, hash, open_file, found) end
        local described, copies = pcall(describe_copies, found, hash, registry or {})
        if not described then copies = {by_name = {}, notes = {"copies unavailable (" .. tostring(copies) .. ")"}} end
        return found.entries, found.warnings, copies
    end

    function discovery.enumerate_pure_lua(open_file)
        local prefixes = {
            "data/" .. family,
            "../data/" .. family
        }
        -- Also check package.path for any <game_root>/bin/?.lua entry
        if type(package) == "table" and type(package.path) == "string" then
            for entry in package.path:gmatch("[^;]+") do
                local root = entry:gsub("\\", "/"):match("^([A-Za-z]:/[^?]+)/bin/")
                if root then
                    prefixes[#prefixes + 1] = root .. "/data/" .. family
                end
            end
        end
        local active_prefix = nil
        for _, pref in ipairs(prefixes) do
            local ok, f = pcall(open_file, pref .. ".patch_0", "rb")
            if not (ok and f) then
                ok, f = pcall(open_file, pref, "rb")
            end
            if ok and f then
                pcall(f.close, f)
                active_prefix = pref
                break
            end
        end
        if not active_prefix then return {} end
        local paths = {}
        for n = 0, 255 do
            local p = active_prefix .. ".patch_" .. n
            local ok, f = pcall(open_file, p, "rb")
            if ok and f then
                pcall(f.close, f)
                paths[#paths + 1] = p
            end
        end
        return paths
    end

    function discovery.discover(open_file, registry)
        if type(open_file) ~= "function" then error("io.open unavailable", 0) end
        local paths = discovery.enumerate_pure_lua(open_file)
        return discovery.scan(paths, discovery.hasher(), open_file, registry)
    end

    return discovery
end)()

-- 6. Embedded Loader Health Report (src/health.lua, 100% pure Lua)
local loader_health = (function()
    local health = {}
    local next, type, rawget, rawequal, pcall, ipairs, tostring = next, type, rawget, rawequal, pcall, ipairs, tostring
    local getmetatable, collectgarbage = getmetatable, collectgarbage

    health.LIBRARIES = {"string", "table", "math", "os", "io", "coroutine", "debug", "package", "bit", "jit"}
    health.SHOWN = 6
    health.KEPT = 64
    health.LOG_BYTES = 65536

    local function name_of(prefix, key)
        if type(key) == "string" then return prefix .. key end
        return prefix .. "[" .. type(key) .. "]"
    end

    local function note(list, name)
        list.total = list.total + 1
        if #list < health.KEPT then list[#list + 1] = name end
    end

    local function copy(source)
        local seen, key, value = {}, next(source)
        while not rawequal(key, nil) do
            seen[key] = value
            key, value = next(source, key)
        end
        return seen
    end

    local function same(a, b)
        if rawequal(a, b) then return true end
        return type(a) == "number" and type(b) == "number" and a ~= a and b ~= b
    end

    local function compare(current, seen, prefix, report_added, found)
        local key, value = next(current)
        while not rawequal(key, nil) do
            local before = seen[key]
            if rawequal(before, nil) then
                if report_added then note(found.added, name_of(prefix, key)) end
                seen[key] = value
            elseif not same(before, value) then
                note(found.replaced, name_of(prefix, key))
                seen[key] = value
            end
            key, value = next(current, key)
        end
        key = next(seen)
        while not rawequal(key, nil) do
            local following = next(seen, key)
            if rawequal(rawget(current, key), nil) then
                note(found.removed, name_of(prefix, key))
                seen[key] = nil
            end
            key = following
        end
    end

    local function gc_setting(collect, option)
        local ok, value = pcall(collect, option, 200)
        if not ok or type(value) ~= "number" then return nil end
        pcall(collect, option, value)
        return value
    end

    local function setting_change(settings, label, before, after)
        if before ~= nil and after ~= nil and before ~= after then
            settings[#settings + 1] = label .. " " .. tostring(before) .. " -> " .. tostring(after)
        end
    end

    local function settings_changes(settings, before, now)
        setting_change(settings, "GC pause", before.pause, now.pause)
        setting_change(settings, "GC step multiplier", before.stepmul, now.stepmul)
    end

    local function swap_kind(found, before, current)
        if rawequal(before, nil) then return found.added end
        if rawequal(current, nil) then return found.removed end
        return found.replaced
    end

    local function scope_changes(item, found)
        local current = item.resolve()
        if rawequal(current, item.value) then
            if item.seen then compare(current, item.seen, item.prefix, item.report_added, found) end
            return
        end
        if item.identity then note(swap_kind(found, item.value, current), item.identity) end
        item.value, item.seen = current, type(current) == "table" and copy(current) or nil
    end

    function health.observer(globals, hooks)
        hooks = hooks or {}
        local collect = hooks.collect or collectgarbage
        local scopes = {}
        local function scope(prefix, resolve, identity, report_added)
            local value = resolve()
            scopes[#scopes + 1] = {prefix = prefix, resolve = resolve, identity = identity,
                report_added = report_added, value = value, seen = type(value) == "table" and copy(value) or nil}
        end
        scope("", function() return globals end, nil, true)
        for _, name in ipairs(health.LIBRARIES) do
            scope(name .. ".", function() return rawget(globals, name) end, nil, true)
        end
        scope("package.loaded.", function()
            local pkg = rawget(globals, "package")
            if type(pkg) == "table" then return rawget(pkg, "loaded") end
        end, "package.loaded", false)
        scope("string metatable.", function() return getmetatable("") end, "string metatable", true)
        scope("_G metatable.", function() return getmetatable(globals) end, "_G metatable", true)

        local function settings()
            return {pause = gc_setting(collect, "setpause"), stepmul = gc_setting(collect, "setstepmul")}
        end
        local baseline = settings()
        local obs = {initial = {heap_kb = floor(collect("count") + 0.5), pause = baseline.pause,
            stepmul = baseline.stepmul}}

        function obs.mark()
            local mark = {heap = collect("count")}
            if hooks.clock then mark.clock = hooks.clock() end
            return mark
        end

        function obs.changes(mark)
            local heap = collect("count")
            local stop = hooks.clock and hooks.clock()
            local found = {heap_kb = floor(heap - mark.heap + 0.5), settings = {},
                added = {total = 0}, replaced = {total = 0}, removed = {total = 0}}
            if stop and mark.clock then found.ms = floor((stop - mark.clock) * 1000 + 0.5) end
            for _, item in ipairs(scopes) do scope_changes(item, found) end
            local now = settings()
            settings_changes(found.settings, baseline, now)
            baseline = now
            return found
        end
        return obs
    end

    function health.describe_start(initial)
        local parts = {"heap " .. initial.heap_kb .. " KB"}
        if initial.pause then parts[#parts + 1] = "GC pause " .. initial.pause end
        if initial.stepmul then parts[#parts + 1] = "GC step multiplier " .. initial.stepmul end
        parts[#parts + 1] = tostring(_VERSION or "Lua 5.1")
        return concat(parts, ", ")
    end

    local function listed(label, list)
        if list.total == 0 then return nil end
        sort(list)
        local shown = {}
        for index = 1, min(#list, health.SHOWN) do shown[index] = list[index] end
        local text = label .. " " .. concat(shown, ", ")
        if list.total > #shown then text = text .. " (+" .. (list.total - #shown) .. " more)" end
        return text
    end

    function health.describe(found)
        local first = "heap " .. (found.heap_kb >= 0 and "+" or "") .. found.heap_kb .. " KB"
        if found.ms then first = first .. ", " .. found.ms .. " ms" end
        local parts = {first}
        for _, text in ipairs(found.settings) do parts[#parts + 1] = text end
        for _, kind in ipairs({"added", "replaced", "removed"}) do
            local text = listed(kind, found[kind])
            if text then parts[#parts + 1] = text end
        end
        return concat(parts, "; ")
    end

    function health.previous_session(text)
        if type(text) ~= "string" or text == "" then return "no log" end
        local version = text:match("^Bingus Shared Loader (loader%-v%d+)") or "unknown loader"
        local started = text:match("\nStarted: ([^\r\n]+)")
        if not started then return version .. " log without session details" end
        local result = "started " .. started .. " (" .. version .. ")"
        local finished = text:match("\n(Startup finished[^\r\n]*)")
        if finished then
            result = result .. "; " .. finished:sub(1, 1):lower() .. finished:sub(2)
            if text:find("\nAfter startup: running ", 1, true) then
                return result .. "; its log ended while after_startup callbacks ran"
            end
            return result
        end
        local loading
        for line in text:gmatch("[^\r\n]+") do
            loading = line:match("^(mods/[^:]+): loading$") or loading
        end
        if loading then return result .. "; its log ended while loading " .. loading end
        return result .. "; its log ended during startup"
    end

    return health
end)()

-- 7. Coordinator (src/shared_loader.lua adapted for v21)
local state = rawget(_G, "CowboyBingusModLoader")
if state then return end

state = {version = 17, api = 1, modules = {}, revision = "loader-v21"}
rawset(_G, "CowboyBingusModLoader", state)
rawset(_G, "HD2ModLoader", state)

local pcall, tostring, ipairs, type, assert, rawget = pcall, tostring, ipairs, type, assert, rawget
local error, setmetatable = error, setmetatable
local open = type(io) == "table" and io.open or nil
local getenv = type(os) == "table" and os.getenv or nil

local capabilities = {
    api = 1,
    logs = true,
    discovery = true,
    jit_budget = false,
    health = true,
    after_startup = true,
    build_gate = false,
    on_update = true
}
state.capabilities = setmetatable({}, {
    __index = capabilities,
    __metatable = false,
    __newindex = function() error("CowboyBingusModLoader.capabilities is read-only", 2) end
})

local LOG_NAME = "BingusSharedLoader.log"
local names = {
    "mods/cowboybingus/vanilla_plus_megapack",
    "mods/cowboybingus/better_stratagem_bounce",
    "mods/cowboybingus/hellpod_steering_unlocked",
    "mods/cowboybingus/wide_angle_stratagems",
    "mods/cowboybingus/reinforcement_beacon_fix_data",
    "mods/cowboybingus/consistent_vaulting",
    "mods/cowboybingus/shallow_water_dive",
    "mods/cowboybingus/sentry_aim_retention",
    "mods/cowboybingus/corpse_collision_repair",
    "mods/cowboybingus/vehicle_stability",
    "mods/cowboybingus/hover_pack_cancel",
    "mods/cowboybingus/enemy_intelligence",
    "mods/codex/gun_calibration",
    "mods/cowboybingus/armory_preview_cache",
    "mods/cowboybingus/mod_bindings_menu",
    "mods/cowboybingus/mod_options_menu",
    "mods/chef/seaf_artillery_loadout",
    "mods/mortar/mortar_hud",
    "mods/vehicle_seat_tools/vehicle_seat_switch",
    "mods/engle/eagle_hud_probe",
    "mods/retrox/sentry_hud",
    "mods/warbond_desk/main",
    "mods/arena_local/mech_part_hud",
    "mods/reticle_ammo/hud",
    "mods/patpatpatrick/helmet_headlamp",
    "mods/driverhud/driver_hud",
    "mods/chef/smarter_guard_dogs_and_sentries",
    "mods/chef/smarter_guard_dogs_and_sentries_dogs",
    "mods/chef/smarter_guard_dogs_and_sentries_sentries",
    "mods/chef/smarter_guard_dogs_and_sentries_tesla",
    "mods/chef/smarter_guard_dogs_and_sentries_armor",
    "mods/chef/smarter_guard_dogs_and_sentries_priority",
    "mods/chef/smarter_guard_dogs_and_sentries_ping",
    "mods/chef/smarter_guard_dogs_and_sentries_safety",
    "mods/chef/smarter_guard_dogs_and_sentries_teammates",
    "mods/chef/smarter_guard_dogs_and_sentries_sentry_safety",
    "mods/chef/smarter_guard_dogs_and_sentries_seaf_safety",
    "mods/chef/smarter_guard_dogs_and_sentries_laser",
    "mods/chef/smarter_guard_dogs_and_sentries_glow",
    "mods/chef/smarter_guard_dogs_and_sentries_laser_invert",
    "mods/chef/smarter_guard_dogs_and_sentries_brightness",
    "mods/chef/smarter_guard_dogs_and_sentries_marker",
    "mods/chef/smarter_guard_dogs_and_sentries_marker_opacity",
    "mods/chef/smarter_guard_dogs_and_sentries_marker_size"
}

local logs_initialized = false
local function log_directory()
    if not logs_initialized then
        logs_initialized = true
        local base = getenv and getenv("LOCALAPPDATA")
        if base and base ~= "" then
            state.log_directory = base .. "/CowboyBingus/Helldivers2/Logs"
        end
    end
    return state.log_directory
end

local function open_file(name)
    local directory = log_directory()
    if not directory or not open then return nil end
    local ok, file = pcall(open, directory .. "/" .. name, "w")
    if ok and file then return file end
    -- Fallback to current working directory if %LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs does not exist yet
    local ok_cwd, file_cwd = pcall(open, name, "w")
    if ok_cwd and file_cwd then
        state.log_directory = "."
        return file_cwd
    end
    return nil
end

function state.open_log(name)
    if type(name) ~= "string" or not name:match("^[%w_%-]+%.log$") then return nil end
    return open_file(name)
end

function state.on_update(id, fn)
    if type(id) ~= "string" or id == "" then return false, "on_update needs a string id" end
    if fn ~= nil and type(fn) ~= "function" then return false, "on_update needs a function or nil" end
    if update_hooks[id] == nil and fn ~= nil then
        update_order[#update_order + 1] = id
    end
    update_hooks[id] = fn
    return true
end

function state.on_shutdown(id, fn)
    if type(id) ~= "string" or id == "" then return false, "on_shutdown needs a string id" end
    if fn ~= nil and type(fn) ~= "function" then return false, "on_shutdown needs a function or nil" end
    if shutdown_hooks[id] == nil and fn ~= nil then
        shutdown_order[#shutdown_order + 1] = id
    end
    shutdown_hooks[id] = fn
    return true
end

local header, changes, finished = {}, {}, nil
state.health = {header = header, changes = changes}
local date = type(os) == "table" and os.date or nil
local function date_text(seconds)
    return date("%Y-%m-%d %H:%M:%S", seconds)
end

local previous_log
if loader_health then
    pcall(function()
        local directory = log_directory()
        local file = directory and open and open(directory .. "/" .. LOG_NAME, "rb")
        if not file and open then file = open(LOG_NAME, "rb") end
        if not file then return end
        local ok, text = pcall(file.read, file, loader_health.LOG_BYTES)
        file:close()
        if ok then previous_log = text end
    end)
    local ok, text = pcall(date_text)
    header[#header + 1] = "Started: " .. (ok and tostring(text) or "unknown")
end

local copies = {by_name = {}, notes = {}}
local CALLBACK_LIMIT = 256
local callbacks = {queue = {}, owners = {}, next = 1, accepted = 0, running = false, ready = false, lines = {}}

local function add_callback_lines(lines)
    if callbacks.summary then lines[#lines + 1] = callbacks.summary end
    for _, line in ipairs(callbacks.lines) do lines[#lines + 1] = line end
end

local function add_module_lines(lines)
    for _, name in ipairs(names) do
        local status = state.modules[name]
        if status then
            lines[#lines + 1] = name .. ": " .. status
            if copies.by_name[name] then lines[#lines + 1] = "  copies: " .. copies.by_name[name] end
            if changes[name] then lines[#lines + 1] = "  changes: " .. changes[name] end
        end
    end
end

local function write_log()
    pcall(function()
        local file = open_file(LOG_NAME)
        if not file then return end
        local lines = {"Bingus Shared Loader loader-v21; API 1"}
        for _, line in ipairs(header) do lines[#lines + 1] = line end
        if state.discovery then lines[#lines + 1] = "Discovery: " .. state.discovery end
        for _, note in ipairs(copies.notes) do lines[#lines + 1] = "  " .. note end
        add_module_lines(lines)
        if finished then lines[#lines + 1] = finished end
        add_callback_lines(lines)
        lines[#lines + 1] = ""
        pcall(file.write, file, concat(lines, "\n"))
        file:close()
    end)
end

local function report(name, status)
    state.modules[name] = status
    pcall(print, "[BingusSharedLoader] " .. name .. ": " .. status)
end

local function error_text(value)
    local printable, text = pcall(tostring, value)
    if not printable or type(text) ~= "string" then return "an error value without text" end
    return (text:gsub("[\r\n]+", " "))
end

local function callback_failed(owner, message)
    local who = owner and ("callback of " .. owner) or "callback registered after startup"
    local line = "After startup: " .. who .. " failed: " .. error_text(message)
    callbacks.lines[#callbacks.lines + 1] = line
    pcall(print, "[BingusSharedLoader] " .. line)
end

local function run_callbacks()
    local ran, failed = 0, 0
    local queue, owners = callbacks.queue, callbacks.owners
    while callbacks.next <= #queue do
        local index = callbacks.next
        local fn, owner = queue[index], owners[index]
        callbacks.next, queue[index], owners[index] = index + 1, false, false
        callbacks.owner = owner
        local ok, message = pcall(fn)
        ran = ran + 1
        if not ok then
            failed = failed + 1
            callback_failed(owner, message)
        end
    end
    return ran, failed
end

local function drain()
    if callbacks.running then return 0, 0 end
    callbacks.running = true
    local ok, ran, failed = pcall(run_callbacks)
    callbacks.running, callbacks.owner = false, nil
    callbacks.queue, callbacks.owners, callbacks.next = {}, {}, 1
    if not ok then
        callbacks.lines[#callbacks.lines + 1] = "After startup: callbacks stopped: " .. error_text(ran)
        return 0, 0
    end
    return ran, failed
end

local function run_now()
    local before = #callbacks.lines
    drain()
    if #callbacks.lines > before then write_log() end
end

local function refuse()
    if not callbacks.refused then
        callbacks.refused = true
        local line = "After startup: " .. CALLBACK_LIMIT .. " callbacks registered; later registrations refused"
        callbacks.lines[#callbacks.lines + 1] = line
        pcall(print, "[BingusSharedLoader] " .. line)
        if callbacks.ready and not callbacks.running then write_log() end
    end
    return false, "after_startup: " .. CALLBACK_LIMIT .. " callbacks already registered"
end

function state.after_startup(fn)
    if type(fn) ~= "function" then return false, "after_startup needs a function" end
    if callbacks.accepted >= CALLBACK_LIMIT then return refuse() end
    callbacks.accepted = callbacks.accepted + 1
    local index = #callbacks.queue + 1
    callbacks.queue[index] = fn
    callbacks.owners[index] = callbacks.owner or callbacks.starting or false
    if callbacks.ready then run_now() end
    return true
end

local function note_callbacks()
    local count = #callbacks.queue
    if count > 0 then
        callbacks.summary = "After startup: running " .. count .. (count == 1 and " callback" or " callbacks")
    end
end

local function run_startup_callbacks()
    callbacks.ready = true
    if not callbacks.summary then return end
    local ran, failed = drain()
    callbacks.summary = "After startup: " .. ran .. (ran == 1 and " callback" or " callbacks") .. " run, "
        .. failed .. " failed"
    write_log()
end

state.build = {
    supported = true,
    exe_sha256 = "0ACC07DEBE04714AE04281E1A66BD2EB9D3D85232953E32A93C8A3DD0874EABE",
    game_sha256 = "6D1D4D3BC6FC84801D9F8F1B310E13A603D07409F3D9495D74B42E1D0BB1C08F"
}
state.jit = {
    managed = false,
    reason = "Lua 5.1 standard interpreter (no JIT)"
}

local observer
if loader_health then
    local function line(label, step)
        local ok, text = pcall(step)
        if not ok then text = "unavailable (" .. tostring(text) .. ")" end
        if text then header[#header + 1] = label .. ": " .. text end
    end
    line("Lua at start", function()
        local clock = type(os) == "table" and os.clock or nil
        if type(clock) ~= "function" then clock = nil end
        observer = loader_health.observer(_G, {collect = collectgarbage, clock = clock})
        return loader_health.describe_start(observer.initial)
    end)
    line("Previous session", function() return loader_health.previous_session(previous_log) end)
    previous_log = nil
end

local application = stingray and stingray.Application

if addon_discovery then
    local ok, entries, warnings, disc_report = pcall(addon_discovery.discover, open, names)
    if ok then
        state.discovery = tostring(#entries) .. " declared entries"
        local listed = {}
        for _, name in ipairs(names) do listed[name] = true end
        for _, name in ipairs(entries) do
            if not listed[name] then names[#names + 1] = name; listed[name] = true end
        end
        if warnings and #warnings > 0 then
            state.discovery = state.discovery .. "; " .. concat(warnings, "; ")
        end
        if type(disc_report) == "table" and type(disc_report.by_name) == "table" and type(disc_report.notes) == "table" then
            copies = disc_report
        end
    else
        state.discovery = "failed: " .. tostring(entries)
    end
    pcall(print, "[BingusSharedLoader] Discovery: " .. state.discovery)
end

local function observed_require(name)
    local ok, mark = pcall(function() return observer and observer.mark() end)
    local loaded, reason = pcall(require, name)
    if ok and mark then
        local measured, found = pcall(observer.changes, mark)
        if measured then measured, found = pcall(loader_health.describe, found) end
        if measured then
            changes[name] = found
        else
            changes[name] = "unavailable (" .. tostring(found) .. ")"
            observer = nil
        end
    end
    return loaded, reason
end

for _, name in ipairs(names) do
    local other = rawget(_G, "HD2ModLoader")
    local other_status = other and other ~= state and other.modules and other.modules[name]
    if state.modules[name] then
        -- Never retry a previous initialization attempt
    elseif other_status == "loaded" or other_status == "loading" then
        report(name, other_status)
    else
        local ok, available = pcall(function()
            assert(application and type(application.can_get) == "function", "resource lookup unavailable")
            return application.can_get("lua", name)
        end)
        if not ok then
            report(name, "lookup failed: " .. tostring(available))
        elseif not available then
            report(name, "not installed")
        else
            state.modules[name] = "loading"
            write_log()
            callbacks.starting = name
            local loaded, reason = observed_require(name)
            callbacks.starting = nil
            report(name, loaded and "loaded" or "load failed: " .. error_text(reason))
        end
    end
end

local loaded_count, failed_count = 0, 0
for _, name in ipairs(names) do
    local status = state.modules[name]
    if status == "loaded" then
        loaded_count = loaded_count + 1
    elseif status and status ~= "not installed" and status ~= "loading" then
        failed_count = failed_count + 1
    end
end
finished = "Startup finished: " .. loaded_count .. " loaded, " .. failed_count .. " failed"
note_callbacks()
write_log()
run_startup_callbacks()
