require "value_sensors.play_time"
require "settingsGUI"

if not speedrun then speedrun = {} end

function speedrun.mod_init()
    if not global.settings then global.settings = {} end
    if not global.settings.update_delay then global.settings.update_delay = 60 end

    for _, player in pairs(game.players) do
        speedrun.create_player_globals(player)
        speedrun.create_sensor_display(player)
    end
end


local function mod_update_0_4_205()
    -- 0.4.204 to 0.4.205: Factorio 0.15.22 introduced a bug wherein a
    -- GUI element with more than 4 characters in its name, which was
    -- shorter than the_mod_name + 4 characters, would get deleted on
    -- load. At this time, the speedrun root element switched from
    -- gui.top.speedrun to gui.top.speedrun_root.
    --
    -- We need to clean up the leftovers for people updating speedrun
    -- from any other version of Factorio now.
    for _, player in pairs(game.players) do
        if player.gui.top.speedrun then
            player.gui.top.speedrun.destroy()
        end
    end
end


function speedrun.mod_update(data)
    if data.mod_changes then
        if data.mod_changes["speedrun"] then
            -- TODO: If a more major migration ever needs doing, do that here.
            -- Otherwise, just falling back to mod_init should work fine.
            speedrun.mod_init()

            mod_update_0_4_205()
        end

        speedrun.validate_sensors(data.mod_changes)
    end
end

function speedrun.on_gui_click(event)
    if string.starts_with(event.element.name, "speedrun_settings_gui_") then
        speedrun.on_settings_click(event)
    elseif event.element.name == "speedrun_toggle_popup" then
        speedrun.speedrun_toggle_popup(event)
    elseif string.starts_with(event.element.name, "speedrun_sensor_") then
        for _, sensor in pairs(speedrun.value_sensors) do
            -- if the gui element name matches 'speedrun_sensor_' + sensor_name, send it the on_click event.
            if string.starts_with(event.element.name, "speedrun_sensor_" .. sensor.name) then
                sensor:on_click(event)
                break
            end
        end
    end
end

-- Iterate through all value_sensors, if any are associated with a mod_name that
-- has been removed, remove the sensor from the list of value_sensors.
function speedrun.validate_sensors(mod_changes)
    for i = #speedrun.value_sensors, 1, -1 do
        local sensor = speedrun.value_sensors[i]
        if sensor.mod_name and mod_changes[sensor.mod_name] then
            -- mod removed, remove sensor from ui
            if mod_changes[sensor.mod_name].new_version == nil then
                speedrun.hide_sensor(sensor)
                table.remove(speedrun.value_sensors, i)
            end
        end
    end
end

function speedrun.hide_sensor(sensor)
    for player_name, data in pairs(global.speedrun) do
        if data.always_visible then
            data.always_visible[sensor["name"]] = false
        end
    end
    for _, player in pairs(game.players) do
        local player_settings = global.speedrun[player.name]

        local sensor_flow = player.gui.top.speedrun_root.sensor_flow
        speedrun.update_av(player, sensor_flow.always_visible)
    end
end


function speedrun.new_player(event)
    local player = game.players[event.player_index]

    speedrun.create_player_globals(player)
    speedrun.create_sensor_display(player)
end


function speedrun.update_gui(event)
    if (event.tick % global.settings.update_delay) ~= 0 then return end

    for player_index, player in pairs(game.players) do
        local player_settings = global.speedrun[player.name]
        -- saves converted from SP with no username to MP won't raise speedrun.new_player
        -- so we have to check here, as well.
        if not player_settings then
            speedrun.new_player({player_index = player_index})
            player_settings = global.speedrun[player.name]
        elseif not player.gui.top.speedrun_root then
            speedrun.create_sensor_display(player)
        end

        local sensor_flow = player.gui.top.speedrun_root.sensor_flow
        speedrun.update_av(player, sensor_flow.always_visible)
        if player_settings.popup_open then
            speedrun.update_ip(player, sensor_flow.in_popup)
        end
    end
end


function speedrun.create_player_globals(player)
    if not global.speedrun then global.speedrun = {} end
    if not global.speedrun[player.name] then global.speedrun[player.name] = {} end
    local player_settings = global.speedrun[player.name]

    if not player_settings.version then player_settings.version = "" end

    if not player_settings.always_visible then
        player_settings.always_visible = {
            ["evolution_factor"] = true,
            ["play_time"] = true,
        }
    end

    if not player_settings.in_popup then
        player_settings.in_popup = {
            ["day_time"] = true,
        }
    end

    if not player_settings.popup_open then player_settings.popup_open = false end

    if not player_settings.sensor_settings then
        player_settings.sensor_settings = {}
    end

    if not player_settings.sensor_settings['play_time'] then
        player_settings.sensor_settings['play_time'] = {
            ['show_days'] = true,
            ['show_seconds'] = true,
        }
    end
end


function speedrun.create_sensor_display(player)
    local root = player.gui.top.speedrun_root
    local destroyed = false
    if root then
        player.gui.top.speedrun_root.destroy()
        destroyed = true
    end

    if not root or destroyed then
        local root = player.gui.top.add{type="frame",
                                        name="speedrun_root",
                                        direction="horizontal",
                                        style="outer_frame"}

        local action_buttons = root.add{type="flow",
                                        name="action_buttons",
                                        direction="vertical",
                                        style="speedrun_cramped_flow_v"}
        action_buttons.add{type="button",
                           name="speedrun_toggle_popup",
                           style="speedrun_expando_closed"}
        if global.speedrun[player.name].popup_open then
            action_buttons.speedrun_toggle_popup.style = "speedrun_expando_open"
        end
        action_buttons.add{type="button",
                           name="speedrun_settings_gui_settings_open",
                           style="speedrun_settings"}

        local sensor_flow = root.add{type="flow",
                                     name="sensor_flow",
                                     direction="vertical",
                                     style="speedrun_cramped_flow_v"}
        sensor_flow.add{type="flow",
                        name="always_visible",
                        direction="vertical",
                        style="speedrun_cramped_flow_v"}
        sensor_flow.add{type="flow",
                        name="in_popup",
                        direction="vertical",
                        style="speedrun_cramped_flow_v"}
    end
end


local function update_sensors(element, sensor_list, active_sensors)
    for _, sensor in ipairs(sensor_list) do
        if active_sensors[sensor.name] then
            local status, err = pcall(sensor.create_ui, sensor, element)
            if err then error({"err_specific", sensor.name, "create_ui", err}) end
            status, err = pcall(sensor.update_ui, sensor, element)
            if err then error({"err_specific", sensor.name, "update_ui", err}) end
        else
            local status, err = pcall(sensor.delete_ui, sensor, element)
            if err then error({"err_specific", sensor.name, "delete_ui", err}) end
        end
    end
end


function speedrun.update_av(player, element)
    local always_visible = global.speedrun[player.name].always_visible

    update_sensors(element, speedrun.value_sensors, always_visible)
end


function speedrun.update_ip(player, element)
    if not global.speedrun[player.name].popup_open then return end

    local in_popup = global.speedrun[player.name].in_popup

    update_sensors(element, speedrun.value_sensors, in_popup)
end


function speedrun.speedrun_toggle_popup(event)
    local player = game.players[event.player_index]
    local player_settings = global.speedrun[player.name]

    local root = player.gui.top.speedrun_root

    if player_settings.popup_open then
        -- close it
        player_settings.popup_open = false

        for _, childname in ipairs(root.sensor_flow.in_popup.children_names) do
            root.sensor_flow.in_popup[childname].destroy()
        end

        root.action_buttons.speedrun_toggle_popup.style = "speedrun_expando_closed"
    else
        -- open it
        player_settings.popup_open = true

        speedrun.update_ip(player, root.sensor_flow.in_popup)
        root.action_buttons.speedrun_toggle_popup.style = "speedrun_expando_open"
    end
end
