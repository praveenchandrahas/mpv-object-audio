-- Sends the overlay toggle once per file load so the Omniphony trajectory overlay starts off.
-- It is a toggle, not an explicit "off": if the engine's default ever changes, this would turn it on.
mp.register_event("file-loaded", function()
    mp.commandv("script-message", "omniphony-overlay", "toggle")
end)
