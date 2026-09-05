-- ==================================================
--  KoolDots (2026)
--  Project URL: https://github.com/LinuxBeginnings
--  License: GNU GPLv3
--  SPDX-License-Identifier: GPL-3.0-or-later
-- ==================================================

-- User monitor overrides for Lua workflow.
-- MonitorProfiles.sh writes selected Lua monitor profiles into this file.
-- Keep custom hl.monitor(...) entries here so upgrades preserve them.

-- ---------------------------------------------------------------------------
-- nwg-displays bridge
-- ---------------------------------------------------------------------------
-- nwg-displays only knows the hyprlang workflow: it writes its layout to
-- ~/.config/hypr/monitors.conf, which the Lua config provider never reads
-- (hyprland.conf and everything it sources is inert when configProvider=lua).
--
-- This reads that file and replays each entry through hl.monitor(), so the
-- GUI keeps working as-is. Runs on every config reload, so "Apply" in
-- nwg-displays takes effect after a `hyprctl reload`.
--
-- Parsed forms:
--   monitor = NAME, MODE, POSITION, SCALE [, KEY, VALUE]...
--   monitor = NAME, transform, N          (and mirror/bitdepth/vrr/cm/sdr*)
--   monitor = NAME, disable
-- Multiple lines for the same output are merged into one spec.
--
-- To go back to hand-written rules, delete this block and add plain
-- hl.monitor({...}) calls instead.

local function apply_nwg_displays_conf()
    if not (hl and hl.monitor) then
        return
    end

    local configHome = os.getenv("XDG_CONFIG_HOME")
    if not configHome or configHome == "" then
        configHome = (os.getenv("HOME") or "") .. "/.config"
    end
    local path = configHome .. "/hypr/monitors.conf"

    local fh = io.open(path, "r")
    if not fh then
        return
    end

    local function trim(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function split_csv(s)
        local out = {}
        for field in (s .. ","):gmatch("([^,]*),") do
            out[#out + 1] = trim(field)
        end
        return out
    end

    -- Keywords that replace the MODE slot, i.e. "NAME, transform, 1".
    local keyword_slot = {
        disable = true,
        transform = true,
        mirror = true,
        bitdepth = true,
        vrr = true,
        cm = true,
        sdrbrightness = true,
        sdrsaturation = true,
        addreserved = true,
    }

    -- hyprlang key -> (HL.MonitorSpec field, coercion)
    local as_number = function(v) return tonumber(v) end
    local as_string = function(v) return v end
    local extra_map = {
        transform = { "transform", as_number },
        mirror = { "mirror", as_string },
        bitdepth = { "bitdepth", as_number },
        vrr = { "vrr", as_number },
        cm = { "cm", as_string },
        sdrbrightness = { "sdrbrightness", as_number },
        sdrsaturation = { "sdrsaturation", as_number },
    }

    local order, specs = {}, {}
    local function spec_for(name)
        local s = specs[name]
        if not s then
            s = { output = name }
            specs[name] = s
            order[#order + 1] = name
        end
        return s
    end

    local function set_extra(spec, key, value)
        local m = extra_map[string.lower(key or "")]
        if not m or value == nil then
            return
        end
        local coerced = m[2](value)
        if coerced ~= nil then
            spec[m[1]] = coerced
        end
    end

    for line in fh:lines() do
        line = trim((line:gsub("#.*$", "")))
        local body = line:match("^monitor%s*=%s*(.+)$")
        if body then
            local f = split_csv(body)
            local name = f[1]
            if name then
                local second = string.lower(f[2] or "")
                if second == "disable" or second == "disabled" then
                    spec_for(name).disabled = true
                elseif keyword_slot[second] then
                    -- keyword-only line: NAME, KEY, VALUE
                    set_extra(spec_for(name), second, f[3])
                elseif f[2] and f[2] ~= "" then
                    -- full line: NAME, MODE, POSITION, SCALE, [KEY, VALUE]...
                    local spec = spec_for(name)
                    spec.mode = f[2]
                    if f[3] and f[3] ~= "" then
                        spec.position = f[3]
                    end
                    if f[4] and f[4] ~= "" then
                        spec.scale = f[4]
                    end
                    for i = 5, #f, 2 do
                        set_extra(spec, f[i], f[i + 1])
                    end
                end
            end
        end
    end
    fh:close()

    local applied = {}
    for _, name in ipairs(order) do
        local ok, err = pcall(hl.monitor, specs[name])
        if ok then
            applied[#applied + 1] = (name ~= "" and name or "<catch-all>")
        else
            print("[KooLDots] monitors.conf: failed to apply '" .. tostring(name) .. "': " .. tostring(err))
        end
    end

    if #applied > 0 then
        print("[KooLDots] monitors.conf -> applied " .. #applied .. " monitor rule(s): " .. table.concat(applied, ", "))
    end
end

-- Never let a malformed monitors.conf take down the whole config: on error we
-- simply fall through to the catch-all rules in lua/monitors.lua.
do
    local ok, err = pcall(apply_nwg_displays_conf)
    if not ok then
        print("[KooLDots] monitors.conf bridge failed: " .. tostring(err))
    end
end
