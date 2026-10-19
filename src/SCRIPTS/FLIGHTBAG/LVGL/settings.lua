-- =====================================================================
-- settings.lua  --  Flight Bag (EdgeTX UI) topic page
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/LVGL/settings.lua
-- Native view of settings_model.lua: a setting row per field (toggle,
-- choice, number), the hint below it, a block per app, Back and Save.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local M = loadScript("/SCRIPTS/FLIGHTBAG/settings_model.lua")()(ctx)
  local WIDE  = lvgl.PERCENT_SIZE + 100
  local VALUE = lvgl.PERCENT_SIZE + (LCD_W < 400 and 42 or 50)   -- x of the value column
  local SOUND_W = math.floor(lvgl.UI_ELEMENT_HEIGHT * 25 / 8)     -- sound choice, as wide as a number field

  local function leave()
    if M.touched then
      lvgl.confirm({ title = ctx.title, message = "Discard changes?", confirm = ctx.close })
    else
      ctx.close()
    end
  end

  local function save()
    local problems = M.save()
    if #problems > 0 then
      lvgl.message({ title = "Save", message = table.concat(problems, "\n") })
    else
      ctx.close()
    end
  end

  local function titleColor(r)
    return function() return r.off and COLOR_THEME_DISABLED or COLOR_THEME_PRIMARY1 end
  end
  local function active(r) return function() return not r.off end end

  -- "Mixed" beside a control while a shared value differs per app.
  local function mixedLabel(box, r)
    box:label({ text = "Mixed", color = COLOR_THEME_WARNING,
                visible = function() local _, mixed = M.rowValue(r); return mixed and not r.off end })
  end

  local function fieldControl(box, r)
    local f = r.field
    if f.type == "bool" then
      box:toggle({ get = function() return M.getValue(r) == true end,
                   set = function(v) M.setValue(r, v == 1) end, active = active(r) })
    elseif f.type == "choice" then
      box:choice({ title = f.label, values = M.choiceLabels(f), active = active(r),
                   get = function() return M.choiceIndex(r) end,
                   set = function(i) M.setValue(r, f.choices[i]) end })
    else
      -- The number field counts steps from min: it has no step of its own.
      local step = f.step or 1
      local function valueAt(i) return f.min + i * step end
      box:numberEdit({ min = 0, max = math.floor((f.max - f.min) / step + 0.5), active = active(r),
                       get = function()
                         local v = M.getValue(r)
                         if v == nil then v = f.default or f.min end
                         return math.floor((v - f.min) / step + 0.5)
                       end,
                       set = function(i) M.setValue(r, valueAt(i)) end,
                       display = function(i) return M.format(r, valueAt(i)) end })
    end
    mixedLabel(box, r)
  end

  local build

  local function fix(r)
    local function write()
      if M.fixWrite(r) then M.reload(r); build()
      else lvgl.message({ title = r.button, message = "Save failed. Check SD card." }) end
    end
    if r.button == "Create" then write()
    else
      lvgl.confirm({ title = r.button, message = "Replace the damaged settings file with factory settings?",
                     confirm = write })
    end
  end

  local function addRow(pg, r)
    if r.kind == "head" then
      pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW }):label({ text = r.text, font = BOLD, color = COLOR_THEME_PRIMARY1 })
      return
    end
    if r.kind == "fix" then
      pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, align = LEFT + VCENTER, children = {
        { type = "label", text = r.text, color = COLOR_THEME_WARNING },
        { type = "button", text = r.button, press = function() fix(r) end },
      } })
      return
    end
    local s = pg:setting({ w = WIDE, title = r.label or r.field.label, color = titleColor(r) })
    -- CENTER: in a row EdgeTX takes the vertical placement from the horizontal flag.
    local box = s:box({ x = VALUE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_MEDIUM, align = CENTER })
    if r.kind == "sound" then
      box:choice({ title = r.label .. " sound", values = M.soundLabels(r.block), active = active(r), w = SOUND_W,
                   get = function() return M.soundIndex(r) end,
                   set = function(i) M.setSound(r, i) end })
      box:button({ text = "Play", press = function() M.playTest(r) end,
                   active = function() return not r.off and not M.isMuted(r) end })
    else
      fieldControl(box, r)
    end
    pg:label({ text = function() return M.hintOf(r) or "" end, font = SMLSIZE, color = titleColor(r),
               visible = function() return M.hintOf(r) ~= nil end })
  end

  build = function()
    lvgl.clear()
    local pg = lvgl.page({ title = "Flight Bag", subtitle = ctx.title, back = leave,
                           flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_SMALL })
    if #M.rows == 0 then pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW }):label({ text = "Nothing to set here.", color = COLOR_THEME_PRIMARY1 }) end
    for _, r in ipairs(M.rows) do addRow(pg, r) end
    pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
      { type = "button", text = "Back", w = lvgl.PERCENT_SIZE + 48, press = leave },
      { type = "button", text = "Save", w = lvgl.PERCENT_SIZE + 48, press = save },
    } })
  end

  build()
end
