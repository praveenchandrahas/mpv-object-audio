-- theater_status.lua: status panel and control menu for the home theatre rig, as an overlay on mpv.
--
--   F9   toggle the status panel (read-only: source, route, profile, engine, CamillaDSP load/clipping/underruns)
--   F10  open the control menu (EQ on/off, profile mode, upmix flavours, adaptive engine)
--
-- It runs the `eq` command (the router stays the only thing that changes audio) and, for live DSP numbers, asks theater-ctld on
-- 127.0.0.1 if that is running. If theater-ctld is not running the panel still works from `eq status --json`.
-- Changes that cause about a second of silence (profile mode, flavour, engine) or make the sound louder (EQ off) ask for a second
-- confirmation, because mpv is playing whenever this menu is open. With uosc installed the menu is uosc's (mouse and keys);
-- otherwise a built-in menu is drawn (arrow keys, Enter, Esc, mouse wheel and left click).
--
-- Install: scripts/install-theater-status.sh (copies this file into the mpv config folders and prints the two input.conf lines).
-- Options (script-opts/theater_status.conf):  eq=/path/to/eq   ctl_url=http://127.0.0.1:8765   menu=auto|uosc|builtin   refresh=1.5

local mp = require "mp"
local utils = require "mp.utils"
local msg = require "mp.msg"
local options = require "mp.options"

local opts = { eq = "", ctl_url = "http://127.0.0.1:8765", menu = "auto", refresh = 1.5, font_size = 26 }
options.read_options(opts, "theater_status")

local state = { status = nil, panel = false, menu = false, sel = 1, items = {}, pending = nil, busy = false, note = "" }
local ov = mp.create_osd_overlay("ass-events")
local timer

-- ---------------------------------------------------------------- helpers
local function eq_path()
    if opts.eq ~= "" then return opts.eq end
    local home = os.getenv("HOME") or ""
    local p = home .. "/.local/bin/eq"
    if utils.file_info(p) then return p end
    return "eq"
end

local function esc(s)                       -- ASS-safe text (same idiom as uosc)
    s = tostring(s == nil and "" or s)
    return (s:gsub("\\", "\\\239\187\191"):gsub("{", "\\{"):gsub("\n", "\\N"))
end

local function run(args, cb)
    mp.command_native_async({ name = "subprocess", args = args, capture_stdout = true, capture_stderr = true, playback_only = false },
        function(ok, res, err)
            cb(ok and res and res.status == 0, res, err)
        end)
end

local function have(t, ...)                 -- safe nested lookup
    for _, k in ipairs({ ... }) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end

-- ---------------------------------------------------------------- status
local function set_status(js)
    local d = js and utils.parse_json(js)
    if type(d) == "table" and (d.eq or d.error) then state.status = d else state.status = nil end
end

local function fetch(cb)
    run({ "curl", "-s", "--max-time", "1", opts.ctl_url .. "/v1/status" }, function(ok, res)
        if ok and res.stdout and res.stdout ~= "" then
            set_status(res.stdout)
            if state.status and state.status.eq then return cb() end
        end
        run({ eq_path(), "status", "--json" }, function(ok2, res2)
            if ok2 then set_status(res2.stdout) else state.status = nil end
            cb()
        end)
    end)
end

local function lines_for_panel()
    local s, L = state.status, {}
    if not s or not s.eq then return { "Theatre: status not available (is `eq` installed?)" } end
    local dsp, m = s.dsp or {}, s.mpv or {}
    local en = dsp.engine or {}
    L[#L + 1] = "THEATRE"
    local src = m.source
    L[#L + 1] = "Source:  " .. (src and (src.codec .. " " .. tostring(src.channels) .. "ch -> " .. src.kind .. "  (" .. src.why .. ")") or (m.playing and "not identified" or "-"))
    local path = ({ cam = "through CamillaDSP (EQ active)", direct = "direct, no EQ", mixed = "routing unfinished",
                    ["usb-missing"] = "USB interface not connected" })[m.verdict or ""]
    if path then L[#L + 1] = "Path:    " .. path end
    L[#L + 1] = "Profile: " .. tostring(dsp.profile) .. "  (mode " .. tostring(dsp.pmode) .. ((dsp.pmode and dsp.pmode ~= "auto") and ", pinned" or "") .. ")"
    L[#L + 1] = "EQ:      " .. string.upper(tostring(s.eq.switch)) .. "     Engine: " .. tostring(en.state) ..
        (en.linked and " (linked)" or (en.ports_up and " (ports up)" or ""))
    local live = s.live
    if live and live.ok then
        L[#L + 1] = string.format("DSP:     %s  load %s%%  clipped %s  underruns/min %s", tostring(live.state),
            live.load_percent and string.format("%.0f", live.load_percent) or "?", tostring(live.clipped_samples), tostring(s.underruns_60s))
    elseif s.underruns_60s ~= nil then
        L[#L + 1] = "Underruns (last minute): " .. tostring(s.underruns_60s)
    end
    return L
end

-- ---------------------------------------------------------------- the action table (also what the menu offers)
local function build_items()
    local s = state.status or {}
    local dsp, eqs = s.dsp or {}, s.eq or {}
    local items = {}
    local function add(title, args, cur, risky, note)
        items[#items + 1] = { title = title, args = args, active = cur, risky = risky, note = note }
    end
    local sil = "about 1 second of silence"
    add("EQ on", { "on" }, eqs.switch == "on", false)
    add("EQ off (louder)", { "off" }, eqs.switch == "off", true, "EQ off is louder than EQ on")
    for _, md in ipairs({ "auto", "film", "stereo", "bed" }) do
        add("Mode: " .. md, { "mode", md }, dsp.pmode == md, true, sil)
    end
    for _, f in ipairs({ "voice", "balanced", "wide" }) do
        add("Stereo flavour: " .. f, { "flavour", "stereo", f }, have(dsp, "flavours", "stereo") == f, true, sil)
    end
    for _, f in ipairs({ "subtle", "balanced", "wide" }) do
        add("5.1 flavour: " .. f, { "flavour", "bed", f }, have(dsp, "flavours", "bed") == f, true, sil)
    end
    add("Adaptive engine on", { "engine", "on" }, have(dsp, "engine", "state") == "on", true, sil)
    add("Adaptive engine off", { "engine", "off" }, have(dsp, "engine", "state") == "off", true, sil)
    return items
end

local render, close_menu

local function perform(item)
    if state.busy then return end
    if item.active then mp.osd_message("Theatre: already set", 1.5); return end
    state.busy = true
    local args = { eq_path() }
    for _, a in ipairs(item.args) do args[#args + 1] = a end
    run(args, function(ok, res)
        state.busy = false
        mp.osd_message(ok and ("Theatre: " .. table.concat(item.args, " ") .. " done") or ("Theatre: failed (" .. table.concat(item.args, " ") .. ")"), 2.0)
        fetch(function() render() end)
    end)
end

-- ---------------------------------------------------------------- rendering
local function draw(lines, sel)
    local w, h = mp.get_osd_size()
    if not w or w == 0 then w, h = 1280, 720 end
    ov.res_x, ov.res_y = w, h
    local fs = opts.font_size
    local out = {}
    for i, l in ipairs(lines) do
        local style = "{\\an7\\pos(" .. 40 .. "," .. (40 + (i - 1) * math.floor(fs * 1.35)) .. ")\\fs" .. fs .. "\\bord2\\shad0\\1c&HFFFFFF&\\3c&H202020&"
        if i == 1 then style = style .. "\\b1\\1c&HF0C040&" end
        if sel and i - 1 == sel then style = style .. "\\1c&H40E0FF&\\b1" end
        out[#out + 1] = style .. "}" .. esc(l)
    end
    ov.data = table.concat(out, "\n")
    ov:update()
end

function render()
    if state.menu and state.items and not state.uosc then
        local lines = { "THEATRE CONTROLS   (up/down, Enter, Esc; mouse wheel and click work too)" }
        if state.pending then
            lines[#lines + 1] = state.pending.item.title .. ": " .. state.pending.item.note .. "."
            lines[#lines + 1] = "Enter = continue     Esc = cancel"
            draw(lines, nil)
            return
        end
        for i, it in ipairs(state.items) do
            lines[#lines + 1] = (it.active and "* " or "  ") .. it.title .. (it.risky and "" or "")
        end
        draw(lines, state.sel)
    elseif state.panel then
        draw(lines_for_panel(), nil)
    else
        ov:remove()
    end
end

-- ---------------------------------------------------------------- built-in menu (keys and mouse)
local KEYS = { "UP", "DOWN", "ENTER", "KP_ENTER", "ESC", "WHEEL_UP", "WHEEL_DOWN", "MBTN_LEFT" }

local function choose()
    if state.pending then
        local it = state.pending.item
        state.pending = nil
        perform(it)
        close_menu()
        return
    end
    local it = state.items[state.sel]
    if not it then return end
    if it.risky and not it.active then
        state.pending = { item = it }
        render()
    else
        perform(it)
        close_menu()
    end
end

local function key_handler(name)
    return function()
        if name == "UP" or name == "WHEEL_UP" then
            if not state.pending then state.sel = (state.sel - 2) % #state.items + 1 end
        elseif name == "DOWN" or name == "WHEEL_DOWN" then
            if not state.pending then state.sel = state.sel % #state.items + 1 end
        elseif name == "ENTER" or name == "KP_ENTER" then choose()
        elseif name == "ESC" then
            if state.pending then state.pending = nil else close_menu() end
        elseif name == "MBTN_LEFT" then
            local pos = mp.get_mouse_pos()
            local _, h = mp.get_osd_size()
            local fs = opts.font_size
            local row = math.floor((pos.y * ((ov.res_y or h) / math.max(h or 1, 1)) - 40) / math.floor(fs * 1.35))   -- row 0 is the title
            if not state.pending and row >= 1 and row <= #state.items then state.sel = row; choose() end
        end
        render()
    end
end

function close_menu()
    state.menu, state.pending, state.uosc = false, nil, false
    for _, k in ipairs(KEYS) do mp.remove_key_binding("theater-menu-" .. k) end
    render()
end

local function uosc_present()
    if opts.menu == "uosc" then return true end
    if opts.menu == "builtin" then return false end
    local dir = mp.find_config_file("scripts")
    if not dir then return false end
    return (utils.file_info(dir .. "/uosc") or utils.file_info(dir .. "/uosc.lua")) ~= nil
end

local function open_uosc(items)
    local me = mp.get_script_name()
    local list = {}
    for i, it in ipairs(items) do
        local entry = { title = it.title, hint = it.risky and "asks first" or nil, active = it.active }
        if it.risky and not it.active then
            entry.items = {
                { title = "Continue: " .. it.note, value = { "script-message-to", me, "do", tostring(i) } },
                { title = "Cancel", value = { "ignore" } },
            }
        else
            entry.value = { "script-message-to", me, "do", tostring(i) }
        end
        list[#list + 1] = entry
    end
    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json({ type = "theater_menu", title = "Theatre", items = list }))
end

local function open_menu()
    fetch(function()
        state.items, state.sel, state.pending = build_items(), 1, nil
        for i, it in ipairs(state.items) do if it.active then state.sel = i; break end end
        if uosc_present() then
            state.uosc = true
            open_uosc(state.items)
            return
        end
        state.menu, state.uosc = true, false
        for _, k in ipairs(KEYS) do mp.add_forced_key_binding(k, "theater-menu-" .. k, key_handler(k), { repeatable = (k == "UP" or k == "DOWN") }) end
        render()
    end)
end

mp.register_script_message("do", function(i)
    local it = state.items[tonumber(i)]
    if it then perform(it) end
end)

-- ---------------------------------------------------------------- panel and refresh
local function tick()
    if state.panel or state.menu then fetch(function() render() end) end
end

local function toggle_panel()
    state.panel = not state.panel
    if state.panel then fetch(function() render() end) else render() end
end

timer = mp.add_periodic_timer(opts.refresh, tick)
mp.add_key_binding(nil, "toggle", toggle_panel)
mp.add_key_binding(nil, "menu", function() if state.menu then close_menu() else open_menu() end end)
mp.register_event("shutdown", function() ov:remove() end)
msg.info("theater_status loaded: bind `script-binding " .. mp.get_script_name() .. "/toggle` and `.../menu`")

-- for tests
return { state = state, build_items = build_items, lines_for_panel = lines_for_panel, perform = perform, open_menu = open_menu,
         key_handler = key_handler, set_status = set_status, esc = esc }
