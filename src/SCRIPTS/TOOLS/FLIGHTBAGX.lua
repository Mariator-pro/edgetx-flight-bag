-- TNS|Flight Bag (EdgeTX UI)|TNE
-- =====================================================================
-- FLIGHTBAGX.lua  --  Flight Bag with the native EdgeTX controls
-- =====================================================================
-- SD card path: /SCRIPTS/TOOLS/FLIGHTBAGX.lua (pages in /SCRIPTS/FLIGHTBAG/)
-- Same settings as Flight Bag, built from EdgeTX's own page, setting rows,
-- choices, number fields and dialogs. Start page: topic buttons on top, the
-- installed apps below; tapping an app opens its About data and resets.
-- Needs EdgeTX 2.12.5 or later on a colour radio.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License version 2 as
-- published by the Free Software Foundation.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along
-- with this program; if not, write to the Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
-- =====================================================================

local BASE  = "/SCRIPTS/FLIGHTBAG/"
local TITLE = "Flight Bag"

-- Page file per topic page (the native views live in /SCRIPTS/FLIGHTBAG/LVGL/).
local FILES = { warnings = "LVGL/settings.lua", alerts = "LVGL/settings.lua", batteries = "LVGL/batteries.lua",
                models = "LVGL/models.lua", flights = "LVGL/flights.lua", display = "LVGL/settings.lua" }

local A, apps, menu
local exitTool = false
local notice          -- lines shown instead of the tool (old firmware, missing files)

-- EdgeTX 2.12.5+ or any later minor or major version.
local function versionOk()
  local _, _, maj, minor, rev = getVersion()
  if not (maj and minor and rev) then return false end
  if maj ~= 2 then return maj > 2 end
  if minor == 12 then return rev >= 5 end
  return minor > 12
end

local function loadModule(file)
  local chunk = loadScript(BASE .. file)
  local ok, mod = false, nil
  if chunk then ok, mod = pcall(chunk) end
  return ok and mod or nil
end

local WIDE = lvgl and lvgl.PERCENT_SIZE + 100
local ICON = lvgl and lvgl.UI_ELEMENT_HEIGHT   -- app icon size, as tall as the button beside it

-- ---------------------------------------------------------------------------
-- Notice page (old firmware, missing files)
-- ---------------------------------------------------------------------------

local function showNotice()
  lvgl.clear()
  local pg = lvgl.page({ title = TITLE, subtitle = "EdgeTX UI", back = function() exitTool = true end,
                         flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_SMALL })
  for _, t in ipairs(notice) do pg:label({ text = t, color = COLOR_THEME_PRIMARY1 }) end
  pg:button({ text = "Exit", press = function() exitTool = true end })
end

-- ---------------------------------------------------------------------------
-- App popup: About data, file list and resets
-- ---------------------------------------------------------------------------

local openPopup

-- Dialog height for its text lines and button rows: EdgeTX gives a dialog a
-- fixed height, not one that fits its content.
local function dialogH(lines, rows)
  local U, P = lvgl.UI_ELEMENT_HEIGHT, lvgl.PAD_SMALL
  return U + 2 * lvgl.PAD_MEDIUM + lines * (math.floor(U * 0.65) + P) + rows * (U + 2 * lvgl.PAD_TINY + P)
end

-- Two-column dialog for label/value rows (the app's files).
local function openRows(title, rows)
  -- Each row is a box with its own outline padding.
  local dg = lvgl.dialog({ title = title, h = dialogH(#rows, 1) + #rows * 2 * lvgl.PAD_TINY, flexFlow = lvgl.FLOW_COLUMN,
                           flexPad = lvgl.PAD_SMALL })
  for _, r in ipairs(rows) do
    dg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, align = LEFT, children = {
      { type = "label", text = r[1], w = lvgl.PERCENT_SIZE + 20, color = COLOR_THEME_PRIMARY1 },
      { type = "label", text = tostring(r[2]), color = COLOR_THEME_PRIMARY1 },
    } })
  end
  dg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW }):button({ text = "OK", w = lvgl.PERCENT_SIZE + 96,
                                                        press = function() dg:close() end })
end

openPopup = function(app)
  if app.ok then A.load(app) end
  local lines = A.popupLines(app)
  local dg, closed
  local function done()   -- once per popup, however it closes
    if closed then return end
    closed = true
    A.unload(apps)
    A.refreshWarnings(apps)
  end
  local actions = A.popupActions(app)
  -- Rows of two buttons, three on wide screens.
  local cols = LCD_W < 600 and 2 or 3
  dg = lvgl.dialog({ title = lines[1][1], h = dialogH(#lines - 1, math.ceil((#actions + 1) / cols)),
                     flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_SMALL, close = done })
  for i = 2, #lines do
    dg:label({ text = lines[i][1], color = lines[i][2] and COLOR_THEME_WARNING or COLOR_THEME_PRIMARY1 })
  end
  local function write(act)
    local ok = A.runAction(apps, app, act)
    dg:close(); done()
    openPopup(app)
    lvgl.message({ title = act.label, message = ok and "Done." or "Save failed. Check SD card." })
  end
  local buttons = {}
  for _, act in ipairs(actions) do
    buttons[#buttons + 1] = { act.label, function()
      if act.rows then openRows(act.label, act.rows)
      elseif act.ask then lvgl.confirm({ title = act.label, message = act.ask, confirm = function() write(act) end })
      else write(act) end
    end }
  end
  buttons[#buttons + 1] = { "Close", function() dg:close(); done() end }
  local row
  for i, b in ipairs(buttons) do
    if (i - 1) % cols == 0 then row = dg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_SMALL }) end
    row:button({ text = b[1], w = lvgl.PERCENT_SIZE + math.floor(96 / cols), press = b[2] })
  end
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local showStart

local function openPage(p)
  local mk = loadModule(FILES[p.id])
  if type(mk) ~= "function" then
    lvgl.message({ title = p.label, message = p.label .. " could not be started. Copy " .. BASE
                                              .. " to the SD card again." })
    return
  end
  local function close()
    A.unload(apps)
    A.refreshWarnings(apps)
    showStart()
  end
  lvgl.clear()
  local ok, err = pcall(mk, { lib = A, apps = A.pageApps(apps, p), id = p.id, title = p.label, close = close })
  if not ok then
    close()
    lvgl.message({ title = p.label, message = "Error: " .. tostring(err) })
  end
end

-- Warning sign: a triangle in the theme's warning colour with a black "!"
-- (bar and dot), shown while the app needs attention.
local function warnSign(parent, x, y, s, app)
  local function on() return A.needsSign(app) end
  local bw = math.max(2, math.floor(s / 8))
  local cx = x + math.floor((s - bw) / 2)
  parent:triangle({ pts = { { x + math.floor(s / 2), y }, { x, y + s }, { x + s, y + s } },
                    color = COLOR_THEME_WARNING, visible = on })
  parent:rectangle({ x = cx, y = y + math.floor(s * 0.35), w = bw, h = math.floor(s * 0.35),
                     filled = true, color = BLACK, visible = on })
  parent:rectangle({ x = cx, y = y + math.floor(s * 0.78), w = bw, h = bw,
                     filled = true, color = BLACK, visible = on })
end

showStart = function()
  lvgl.clear()
  local pg = lvgl.page({ title = TITLE, subtitle = "Settings", back = function() exitTool = true end,
                         flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_MEDIUM })
  if #apps == 0 then
    for _, t in ipairs({ "No settings found.",
                         "Flight Bag shows the settings of installed scripts.",
                         "Copy a script to the SD card and open Flight Bag again." }) do
      pg:label({ text = t, color = COLOR_THEME_PRIMARY1 })
    end
    return
  end
  -- Topics as buttons, several per row.
  local cols = LCD_W < 400 and 1 or 3
  local bw   = lvgl.PERCENT_SIZE + math.floor(100 / cols) - 2
  local row
  for i, p in ipairs(menu) do
    if (i - 1) % cols == 0 then
      row = pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_SMALL })
    end
    row:button({ text = p.label, w = bw, h = lvgl.UI_ELEMENT_HEIGHT * 2, press = function() openPage(p) end })
  end
  -- Apps: icon, name and version on a button, warning sign beside it.
  for _, app in ipairs(apps) do
    local r = pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_MEDIUM, align = LEFT + VCENTER })
    if app.iconPath then
      r:image({ file = app.iconPath, w = ICON, h = ICON })
    else
      r:box({ w = ICON, h = ICON, children = {
        { type = "rectangle", w = ICON, h = ICON, filled = true, color = COLOR_THEME_SECONDARY1 },
        { type = "label", y = math.floor(ICON / 4), w = ICON, align = CENTER, font = BOLD,
          text = string.sub(app.folder, 1, 1), color = COLOR_THEME_PRIMARY2 },
      } })
    end
    r:button({ text = (app.name or app.folder) .. (app.version and ("   v" .. app.version) or ""),
               w = lvgl.PERCENT_SIZE + 70, h = ICON, press = function() openPopup(app) end })
    warnSign(r:box({ w = ICON, h = ICON, scrollBar = false }), 2, 2, ICON - 4, app)
  end
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

local function init()
  if not lvgl then return end   -- run() shows the notice with lcd
  if not versionOk() then
    notice = { "Flight Bag (EdgeTX UI) needs EdgeTX 2.12.5 or later.",
               "Update EdgeTX or use Flight Bag." }
  else
    A = loadModule("apps.lua")
    if type(A) ~= "table" then
      notice = { "Flight Bag files are missing.", "Copy " .. BASE .. " to the SD card again." }
    end
  end
  if notice then showNotice(); return end
  apps = A.scan()
  A.refreshWarnings(apps)
  menu = A.menu(apps, FILES)
  showStart()
end

local function run(event)
  if not lvgl then
    lcd.clear()
    lcd.drawText(10, 10, "Flight Bag (EdgeTX UI) needs the EdgeTX UI", COLOR_THEME_PRIMARY1)
    lcd.drawText(10, 40, "(EdgeTX 2.12.5, colour radio).", COLOR_THEME_PRIMARY1)
    lcd.drawText(10, 70, "Use Flight Bag instead.", COLOR_THEME_PRIMARY1)
    if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then return 1 end
    return 0
  end
  if exitTool then return 1 end
  return 0
end

return { init = init, run = run, useLvgl = true }
