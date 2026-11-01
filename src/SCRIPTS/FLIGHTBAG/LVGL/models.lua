-- =====================================================================
-- models.lua  --  Flight Bag (EdgeTX UI) page "Models"
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/LVGL/models.lua
-- Native view of models_model.lua: model list, editor (cells, parallel
-- packs), battery assignment, sensor mapping, Wingman's module switches and
-- the model's SD logs, each as its own EdgeTX page.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local M = loadScript("/SCRIPTS/FLIGHTBAG/models_model.lua")()(ctx)
  local WIDE  = lvgl.PERCENT_SIZE + 100
  local VALUE = lvgl.PERCENT_SIZE + (LCD_W < 400 and 42 or 50)   -- x of the value column
  local C = COLOR_THEME_PRIMARY1

  local Show = {}

  local function page(subtitle, back)
    lvgl.clear()
    return lvgl.page({ title = "Flight Bag", subtitle = subtitle, back = back,
                       flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_SMALL })
  end

  -- A row of buttons sharing 96 % of the width, as wide as a list entry:
  -- { { label, press, visible? }, ... }. The share follows the shown buttons.
  local function buttons(pg, list)
    local row = pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_SMALL })
    local function size()
      local n = 0
      for _, b in ipairs(list) do if not b[3] or b[3]() then n = n + 1 end end
      return lvgl.PERCENT_SIZE + math.floor(96 / math.max(n, 1)), lvgl.UI_ELEMENT_HEIGHT
    end
    for _, b in ipairs(list) do
      row:button({ text = b[1], w = (size()), press = b[2], visible = b[3], size = size })
    end
  end

  -- List entry as wide as a button row, so both inset alike.
  local function listButton(pg, text, press)
    pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW }):button({ text = text, w = lvgl.PERCENT_SIZE + 96, press = press })
  end

  -- Setting row titled `title`, shown while visible() is true (always without);
  -- returns the box of its value column.
  -- CENTER: in a row EdgeTX takes the vertical placement from the horizontal flag.
  local function setting(pg, title, visible)
    local s = pg:setting({ w = WIDE, title = title, visible = visible })
    return s:box({ x = VALUE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_MEDIUM, align = CENTER })
  end

  -- The description lines as one text wrapping at the page width.
  local function help(pg, desc)
    pg:label({ text = table.concat(desc, " "), w = WIDE, font = SMLSIZE, color = C })
  end

  -- Centred note in place of an empty list.
  local function note(pg, text)
    pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW }):label({ text = text, color = C })
  end

  -- Writes Lipo Nanny's and/or Wingman's file, then onDone; a failed write asks to retry.
  local function save(onDone, lipo, wing)
    local function step(write, nxt)
      if write() then nxt()
      else lvgl.confirm({ title = "Save", message = "Save failed. Check SD card. Retry?",
                          confirm = function() step(write, nxt) end }) end
    end
    local function saveWing() if wing then step(M.writeWing, onDone) else onDone() end end
    if lipo then step(M.writeLipo, saveWing) else saveWing() end
  end

  local function ask(message, yes) lvgl.confirm({ title = "Models", message = message, confirm = yes }) end
  local function tell(message) lvgl.message({ title = "Models", message = message }) end

  -- ---------------------------------------------------------------------------
  -- List
  -- ---------------------------------------------------------------------------

  function Show.list()
    local pg = page(ctx.title, ctx.close)
    if M.broken then
      pg:label({ text = "Lipo Nanny has no usable settings file.", color = COLOR_THEME_WARNING })
      pg:label({ text = "Fix it in the Lipo Nanny app (start page).", color = C })
      buttons(pg, { { "Back", ctx.close } })
      return
    end
    local keys, active, addCurrent = M.list()
    if #keys == 0 and not active then note(pg, "No models configured.") end
    for _, k in ipairs(keys) do
      listButton(pg, M.name(k) .. (k == active and "   [active]" or ""), function() M.open(k); Show.model() end)
    end
    local list = { { "Back", ctx.close } }
    if addCurrent then list[2] = { "[+] Add current model", function() M.open(nil); Show.model() end } end
    buttons(pg, list)
  end

  -- ---------------------------------------------------------------------------
  -- Model editor
  -- ---------------------------------------------------------------------------

  local function finishSave()
    local lipo, wing = M.commit()
    save(Show.list, lipo, wing)
  end

  local function checkParallel()
    if M.parallelInvalid() then return tell("Parallel mode needs a profile with 2+ packs") end
    finishSave()
  end

  -- Parallel mode only allows profiles with 2+ packs: unassign the others after
  -- confirmation, before the check.
  local function proceedSave()
    local dropped = M.smallProfiles()
    if dropped == 0 then return checkParallel() end
    ask("Parallel mode unassigns " .. M.batteries(dropped) .. " with < 2 packs. Continue?",
        function() M.dropSmallProfiles(); checkParallel() end)
  end

  local function saveModel()
    local invalid = M.otherCells()
    if invalid == 0 then return proceedSave() end
    ask("Changing cells unassigns " .. M.batteries(invalid) .. ". Continue?",
        function() M.dropOtherCells(); proceedSave() end)
  end

  local function deleteModel()
    ask("Delete model config for " .. M.name(M.model.filename) .. "?", function()
      local lipo, wing = M.delete()
      save(Show.list, lipo, wing)
    end)
  end

  local function cancelModel()
    if M.dirty() then ask("Discard changes?", Show.list) else Show.list() end
  end

  function Show.model()
    local m = M.model
    local pg = page((M.isNew and "Add model  " or "Edit model  ") .. M.name(m.filename), cancelModel)
    for _, id in ipairs(M.rows()) do
      if id == "cells" then
        local L = M.LIMITS.cells
        setting(pg, "Cells"):numberEdit({ min = L.min, max = L.max, get = function() return m.cells end,
          set = function(v) m.cells = v end, display = function(v) return v .. "S" end })
      elseif id == "parallel" then
        setting(pg, "Parallel packs"):toggle({ get = function() return m.parallel end,
          set = function(v) m.parallel = v == 1 end })
      elseif id == "batteries" then
        setting(pg, "Batteries"):button({ text = #m.batteryIds .. " selected", press = Show.assign })
      elseif id == "sensors" then
        setting(pg, "Sensors"):button({ text = M.sensorsAreCustom(m.sensors) and "custom" or "default",
                                        press = function() M.openSensors(); Show.sensors() end })
      elseif id == "modules" then
        setting(pg, "Show in Wingman"):button({ text = M.modsText(), press = Show.modules })
      else
        setting(pg, "SD logs"):button({ text = M.logsText(), active = function() return M.isActive end,
                                        press = function() M.openLogs(); Show.logs() end })
      end
    end
    local list = { { "Back", cancelModel }, { "Save", saveModel } }
    if not M.isNew then list[3] = { "Delete", deleteModel } end
    buttons(pg, list)
  end

  -- ---------------------------------------------------------------------------
  -- Battery assignment
  -- ---------------------------------------------------------------------------

  function Show.assign()
    local m = M.model
    local items = M.assignItems()
    local function back() M.applyAssign(items); Show.model() end
    local pg = page(m.parallel and ("Select " .. m.cells .. "S parallel profiles")
                    or ("Select " .. m.cells .. "S batteries"), back)
    if #items == 0 then note(pg, "No matching profiles.") end
    for _, it in ipairs(items) do
      setting(pg, it.name):toggle({ get = function() return it.checked end,
        set = function(v) it.checked = v == 1 end, active = function() return it.selectable end })
    end
    buttons(pg, { { "Back", back } })
  end

  -- ---------------------------------------------------------------------------
  -- Sensor mapping
  -- ---------------------------------------------------------------------------

  function Show.sensors()
    local pg = page("Sensors  " .. M.name(M.model.filename), Show.model)
    for _, f in ipairs(M.SENSOR_FIELDS) do
      local labels = M.sensorChoices(f)
      setting(pg, f.label):choice({ title = f.unit and f.label or (f.label .. " sensor"), values = labels,
        get = function() local _, i = M.sensorChoices(f); return i end,
        set = function(i) M.setSensor(f, i) end,
        active = function() return M.isActive end })
      if M.isActive then help(pg, f.desc) end
    end
    if not M.isActive then note(pg, "Activate this model to edit sensors.") end
    buttons(pg, { { "Back", Show.model },
                  { "Reset to CRSF defaults", M.resetSensors, M.sensorsResetShown } })
  end

  -- ---------------------------------------------------------------------------
  -- Show in Wingman (module switches), stored with the model's Save
  -- ---------------------------------------------------------------------------

  function Show.modules()
    local mods = M.model.mods
    local pg = page("Show in Wingman  " .. M.name(M.model.filename), Show.model)
    for _, k in ipairs(M.moduleKeys()) do
      setting(pg, M.MODULES[k].label):toggle({ get = function() return mods[k] end,
        set = function(v) mods[k] = v == 1 end })
      help(pg, M.MODULES[k].desc)
    end
    buttons(pg, { { "Back", Show.model } })
  end

  -- ---------------------------------------------------------------------------
  -- SD logs: the model's "SD Logs" special function, changed at once
  -- ---------------------------------------------------------------------------

  local function cancelLogs()
    if M.logsDirty() then ask("Discard changes?", Show.model) else Show.model() end
  end

  local function applyLogs()
    local ok, err = M.applyLogs()
    if ok then Show.model()
    elseif err == "switch" then tell("Choose the arm switch first.")
    else tell("No free special function. Remove one in the model.") end
  end

  function Show.logs()
    local d = M.logs
    local pg = page("SD logs  " .. M.name(M.model.filename), cancelLogs)
    setting(pg, "Log"):choice({ title = "Log", values = M.LOG_MODES,
      get = M.logsMode, set = M.setLogsMode })
    -- Without an arm switch yet the list starts with a placeholder (a choice needs a value).
    local labels, _, ids = M.logsArmChoices()
    local off = d.switch and 0 or 1
    if off == 1 then table.insert(labels, 1, M.logsArm()) end
    setting(pg, "Arm switch", function() return not d.always end):choice({ title = "Arm switch", values = labels,
      get = function()
        if not d.switch then return 1 end
        local _, i = M.logsArmChoices()
        return i + off
      end,
      set = function(i) if i > off then M.setLogsArm(ids[i - off]) end end })
    local L = M.LOG_INTERVAL
    setting(pg, "Interval"):numberEdit({ min = L.min, max = L.max, get = function() return d.interval end,
      set = function(v) d.interval = v end, display = M.intervalText })
    if d.exists then
      local found, total = M.logSensors()
      if total > 0 and found < total then
        pg:label({ text = "Log sensors: " .. found .. " of " .. total .. " found", w = WIDE,
                   color = COLOR_THEME_WARNING })
        help(pg, { "Open Model > Telemetry and select", "Discover new sensors while the apps run." })
      elseif total > 0 then
        pg:label({ text = "Log sensors: all " .. total .. " found", w = WIDE, color = C })
      end
    else
      help(pg, { "Armed: one log file per flight.", "Always on: from power-on to power-off." })
    end
    local list = { { "Back", cancelLogs }, { d.exists and "Apply" or "Set up", applyLogs } }
    if d.exists then
      list[3] = { "Remove", function()
        ask("Remove SD logs from this model?", function() M.removeLogs(); Show.model() end)
      end }
    end
    buttons(pg, list)
  end

  Show.list()
end
