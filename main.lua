-- Lua Script for ArduPilot: Log coordinates and play them back in reverse on Acro mode
local storage = {} -- Table to store coordinates
local prev_coord = nil -- Previous coordinate
local log_interval = 1000 -- Logging interval in milliseconds
local timer = 0 -- Timer to track time
local playback_timer = 0 -- Timer for playback
local acro_active = false -- Flag to detect Acro mode
local home_distance_threshold = 10 -- Minimum distance in meters to record coordinates
local playback_index = nil -- Index for coordinate playback
local playback_in_progress = false -- Flag to track if playback is in progress

-- Function to calculate the distance between two coordinates
local function haversine(lat1, lon1, lat2, lon2)
    local R = 6371000 -- Earth radius in meters
    local dLat = math.rad(lat2 - lat1)
    local dLon = math.rad(lon2 - lon1)
    local a = math.sin(dLat / 2) ^ 2 + math.cos(math.rad(lat1)) * math.cos(math.rad(lat2)) * math.sin(dLon / 2) ^ 2
    local c = 2 * math.atan(math.sqrt(a) / math.sqrt(1 - a)) -- Corrected formula to use math.atan
    return R * c
end

-- Function to log coordinates if they meet the criteria
local function log_coordinates()
    local location = ahrs:get_location()
    if not location then
        return -- No valid GPS fix
    end

    local lat = location:lat()
    local lon = location:lng()

    if prev_coord then
        local distance = haversine(prev_coord.lat, prev_coord.lon, lat, lon)
        if distance <= home_distance_threshold then
            return -- Skip if the distance is too small
        end
    end

    -- Record the coordinate
    table.insert(storage, {lat = lat, lon = lon})
    prev_coord = {lat = lat, lon = lon}

    -- Send the coordinate to GCS
    gcs:send_text(6, string.format("Logged: Lat=%.6f, Lon=%.6f", lat, lon))
end

-- Function to play back coordinates in reverse
local function playback_coordinates()
    if #storage == 0 then
        gcs:send_text(6, "No recorded coordinates to play back.")
        return
    end

    -- Start playback from the last recorded coordinate
    if not playback_index then
        playback_index = #storage
    end

    -- Check if enough time has passed to show the next coordinate
    if millis() - playback_timer >= 1000 then
        local coord = storage[playback_index]
        gcs:send_text(6, string.format("Coord %d: Lat=%.6f, Lon=%.6f", playback_index, coord.lat, coord.lon))

        -- Decrease index for the next coordinate
        playback_index = playback_index - 1
        playback_timer = millis()

        -- If all coordinates are played, reset the playback
        if playback_index <= 0 then
            playback_index = nil
            playback_in_progress = false
            gcs:send_text(6, "Playback finished.")
        end
    end
end

-- Main loop
function update()
    -- Check if Acro mode is active (1 corresponds to Acro mode)
    local current_mode = vehicle:get_mode()
    gcs:send_text(6, string.format("Current mode: %d", current_mode))

    -- Start playback if Acro mode is detected and playback is not already in progress
    if current_mode == 1 and not acro_active then -- 1 corresponds to Acro mode
        acro_active = true
        playback_in_progress = true
        gcs:send_text(6, "Acro mode detected. Playing back coordinates...")
    end

    -- Stop playback if not in Acro mode
    if current_mode ~= 1 then
        acro_active = false
    end

    -- Log coordinates every second
    if millis() - timer >= log_interval then
        log_coordinates()
        timer = millis()
    end

    -- Playback coordinates if Acro mode is active and playback has started
    if acro_active and playback_in_progress then
        playback_coordinates()
    end

    -- Return the update function and next interval
    return update, 100 -- Run the update function every 100ms
end

return update() -- Return the initial update function
