-- =====================================================================
-- models.lua  --  Flight Bag (EdgeTX UI) page lib.t("pages", "models")
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/LVGL/models.lua
-- Native view of models_model.lua: model list, model page, battery page
-- (cells, parallel packs), battery assignment, sensor mapping, Wingman's
-- module switches and the model's SD logs, each as its own EdgeTX page.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local lib = ctx.lib
  local function t(id, values) return lib.t("ui", id, values) end
  local function tx(id, values) return lib.t("uix", id, values) end
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

  -- A help text, wrapping at the page width.
  local function help(pg, text)
    pg:label({ text = text, w = WIDE, font = SMLSIZE, color = C })
  end

  -- Centred note in place of an empty list.
  local function note(pg, text)
    pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW }):label({ text = text, color = C })
  end

  -- Writes Lipo Nanny's and/or Wingman's file, then onDone; a failed write asks to retry.
  local function save(onDone, lipo, wing)
    local function step(write, nxt)
      if write() then nxt()
      else lvgl.confirm({ title = t("save"), message = tx("saveFailedRetry"),
                          confirm = function() step(write, nxt) end }) end
    end
    local function saveWing() if wing then step(M.writeWing, onDone) else onDone() end end
    if lipo then step(M.writeLipo, saveWing) else saveWing() end
  end

  local function ask(message, yes) lvgl.confirm({ title = lib.t("pages", "models"), message = message, confirm = yes }) end
  local function tell(message) lvgl.message({ title = lib.t("pages", "models"), message = message }) end

  -- ---------------------------------------------------------------------------
  -- List
  -- ---------------------------------------------------------------------------

  function Show.list()
    local pg = page(ctx.title, ctx.close)
    if M.broken then
      pg:label({ text = t("lipoBroken"), color = COLOR_THEME_WARNING })
      pg:label({ text = t("lipoBrokenFix"), color = C })
      buttons(pg, { { t("back"), ctx.close } })
      return
    end
    local keys, active, addCurrent = M.list()
    if #keys == 0 and not active then note(pg, t("noModels")) end
    for _, k in ipairs(keys) do
      listButton(pg, M.name(k) .. (k == active and ("   " .. t("active")) or ""), function() M.open(k); Show.model() end)
    end
    local list = { { t("back"), ctx.close } }
    if addCurrent then list[2] = { t("addCurrent"), function() M.open(nil); Show.model() end } end
    buttons(pg, list)
  end

  -- ---------------------------------------------------------------------------
  -- Model page
  -- ---------------------------------------------------------------------------

  local function finishSave()
    local lipo, wing = M.commit()
    save(Show.list, lipo, wing)
  end

  local function checkParallel()
    if M.parallelInvalid() then return tell(lib.t("rules", "parallelNeedsTwo")) end
    finishSave()
  end

  -- Parallel mode only allows profiles with 2+ packs: unassign the others after
  -- confirmation, before the check.
  local function proceedSave()
    local dropped = M.smallProfiles()
    if dropped == 0 then return checkParallel() end
    ask(t("parallelDrop", { batteries = M.batteries(dropped) }),
        function() M.dropSmallProfiles(); checkParallel() end)
  end

  local function saveModel()
    local invalid = M.otherCells()
    if invalid == 0 then return proceedSave() end
    ask(t("cellsDrop", { batteries = M.batteries(invalid) }),
        function() M.dropOtherCells(); proceedSave() end)
  end

  local function deleteModel()
    ask(t("deleteModel", { name = M.name(M.model.filename) }), function()
      local lipo, wing = M.delete()
      save(Show.list, lipo, wing)
    end)
  end

  local function cancelModel()
    if M.dirty() then ask(t("discard"), Show.list) else Show.list() end
  end

  function Show.model()
    local m = M.model
    local pg = page(tx(M.isNew and "addModel" or "editModel", { name = M.name(m.filename) }), cancelModel)
    for _, id in ipairs(M.rows()) do
      if id == "battery" then
        setting(pg, t("battery")):button({ text = M.batteryText(), press = Show.battery })
      elseif id == "modules" then
        setting(pg, t("showInWingman")):button({ text = M.modsText(), press = Show.modules })
      else
        setting(pg, t("sdLogs")):button({ text = M.logsText(), active = function() return M.isActive end,
                                        press = function() M.openLogs(); Show.logs() end })
      end
    end
    local list = { { t("back"), cancelModel }, { t("save"), saveModel } }
    if not M.isNew then list[3] = { t("delete"), deleteModel } end
    buttons(pg, list)
  end

  -- ---------------------------------------------------------------------------
  -- Battery page, stored with the model's Save
  -- ---------------------------------------------------------------------------

  function Show.battery()
    local m = M.model
    local pg = page(tx("batteryOf", { name = M.name(m.filename) }), Show.model)
    local L = M.LIMITS.cells
    setting(pg, t("cells")):numberEdit({ min = L.min, max = L.max, get = function() return m.cells end,
      set = function(v) m.cells = v end, display = function(v) return v .. "S" end })
    setting(pg, t("parallelPacks")):toggle({ get = function() return m.parallel end,
      set = function(v) m.parallel = v == 1 end })
    setting(pg, t("batteries")):button({ text = t("selected", { n = #m.batteryIds }), press = Show.assign })
    setting(pg, t("sensors")):button({ text = t(M.sensorsAreCustom(m.sensors) and "custom" or "default"),
                                    press = function() M.openSensors(); Show.sensors() end })
    buttons(pg, { { t("back"), Show.model } })
  end

  -- ---------------------------------------------------------------------------
  -- Battery assignment
  -- ---------------------------------------------------------------------------

  function Show.assign()
    local m = M.model
    local items = M.assignItems()
    local function back() M.applyAssign(items); Show.battery() end
    local pg = page(tx(m.parallel and "selectParallel" or "select", { cells = m.cells }), back)
    if #items == 0 then note(pg, t("noMatching")) end
    for _, it in ipairs(items) do
      setting(pg, it.name):toggle({ get = function() return it.checked end,
        set = function(v) it.checked = v == 1 end, active = function() return it.selectable end })
    end
    buttons(pg, { { t("back"), back } })
  end

  -- ---------------------------------------------------------------------------
  -- Sensor mapping
  -- ---------------------------------------------------------------------------

  function Show.sensors()
    local pg = page(tx("sensorsOf", { name = M.name(M.model.filename) }), Show.battery)
    for _, f in ipairs(M.SENSOR_FIELDS) do
      local labels = M.sensorChoices(f)
      setting(pg, f.label):choice({ title = f.unit and f.label or t("sensorPicker", { label = f.label }), values = labels,
        get = function() local _, i = M.sensorChoices(f); return i end,
        set = function(i) M.setSensor(f, i) end,
        active = function() return M.isActive end })
      if M.isActive then help(pg, f.hint) end
    end
    if not M.isActive then note(pg, t("activateToEdit")) end
    buttons(pg, { { t("back"), Show.battery },
                  { t("resetSensors"), M.resetSensors, M.sensorsResetShown } })
  end

  -- ---------------------------------------------------------------------------
  -- Show in Wingman (module switches), stored with the model's Save
  -- ---------------------------------------------------------------------------

  function Show.modules()
    local mods = M.model.mods
    local pg = page(tx("showInWingmanOf", { name = M.name(M.model.filename) }), Show.model)
    for _, k in ipairs(M.moduleKeys()) do
      setting(pg, M.MODULES[k].label):toggle({ get = function() return mods[k] end,
        set = function(v) mods[k] = v == 1 end })
      help(pg, M.MODULES[k].hint)
    end
    buttons(pg, { { t("back"), Show.model } })
  end

  -- ---------------------------------------------------------------------------
  -- SD logs: the model's "SD Logs" special function, changed at once
  -- ---------------------------------------------------------------------------

  local function cancelLogs()
    if M.logsDirty() then ask(t("discard"), Show.model) else Show.model() end
  end

  local function applyLogs()
    local ok, err = M.applyLogs()
    if ok then Show.model()
    elseif err == "switch" then tell(t("chooseArmFirst"))
    else tell(t("noFreeSlot")) end
  end

  function Show.logs()
    local d = M.logs
    local pg = page(tx("logsOf", { name = M.name(M.model.filename) }), cancelLogs)
    setting(pg, t("log")):choice({ title = t("log"), values = M.LOG_MODES,
      get = M.logsMode, set = M.setLogsMode })
    help(pg, t("logHint"))
    -- Without an arm switch yet the list starts with a placeholder (a choice needs a value).
    local labels, _, ids = M.logsArmChoices()
    local off = d.switch and 0 or 1
    if off == 1 then table.insert(labels, 1, M.logsArm()) end
    setting(pg, t("armSwitch"), function() return not d.always end):choice({ title = t("armSwitch"), values = labels,
      get = function()
        if not d.switch then return 1 end
        local _, i = M.logsArmChoices()
        return i + off
      end,
      set = function(i) if i > off then M.setLogsArm(ids[i - off]) end end })
    pg:label({ text = t("armSwitchHint"), w = WIDE, font = SMLSIZE, color = C, visible = function() return not d.always end })
    local L = M.LOG_INTERVAL
    setting(pg, t("interval")):numberEdit({ min = L.min, max = L.max, get = function() return d.interval end,
      set = function(v) d.interval = v end, display = M.intervalText })
    help(pg, t("intervalHint"))
    if d.exists then
      local found, total = M.logSensors()
      if total > 0 and found < total then
        pg:label({ text = t("logSensorsSome", { found = found, total = total }), w = WIDE,
                   color = COLOR_THEME_WARNING })
        help(pg, t("discoverHelp"))
      elseif total > 0 then
        pg:label({ text = t("logSensorsAll", { total = total }), w = WIDE, color = C })
      end
    end
    local list = { { t("back"), cancelLogs }, { t(d.exists and "apply" or "setUp"), applyLogs } }
    if d.exists then
      list[3] = { t("remove"), function()
        ask(t("removeLogs"), function() M.removeLogs(); Show.model() end)
      end }
    end
    buttons(pg, list)
  end

  Show.list()
end
