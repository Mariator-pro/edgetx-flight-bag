-- =====================================================================
-- flights.lua  --  Flight Bag (EdgeTX UI) page "Last flights"
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/LVGL/flights.lua
-- Native view of flights_model.lua: one flight with date, model and
-- coordinates, its map link as EdgeTX's QR code, Newer / Older to step.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local M = loadScript("/SCRIPTS/FLIGHTBAG/flights_model.lua")()(ctx)
  local flights, idx = M.flights, 1
  local C, DIM = COLOR_THEME_PRIMARY1, COLOR_THEME_DISABLED
  local PAD = lvgl.PAD_LARGE

  lvgl.clear()
  local pg = lvgl.page({ title = "Flight Bag", subtitle = ctx.title, back = ctx.close,
                         flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_SMALL })
  if #flights == 0 then
    pg:label({ text = "No flight logged yet.", color = C })
    pg:label({ text = "A position is stored when the telemetry ends after a flight.", color = DIM })
    pg:button({ text = "Back", w = lvgl.PERCENT_SIZE + 48, press = ctx.close })
    return
  end

  local function cur() return flights[idx] end
  -- The QR code beside the text, as tall as the page allows; a white margin
  -- of about four modules around it for the scanner.
  local side  = math.min(lvgl.PAGE_BODY_HEIGHT - 2 * PAD, math.floor(LCD_W * 0.46))
  local quiet = math.floor(side / 10)

  local row  = pg:box({ w = lvgl.PERCENT_SIZE + 100, flexFlow = lvgl.FLOW_ROW, flexPad = PAD })
  local left = row:box({ w = LCD_W - side - 4 * PAD, flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_SMALL })
  left:label({ text = function() return idx .. " / " .. #flights end, font = BOLD, color = C })
  left:label({ text = function() return M.stamp(cur()) end, color = C })
  left:label({ text = function() return cur().model end, color = C,
               visible = function() return cur().model ~= "" end })
  for _, c in ipairs({ { "LAT", "lat" }, { "LON", "lon" } }) do
    left:box({ flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_MEDIUM, children = {
      { type = "label", text = c[1], color = DIM },
      { type = "label", text = function() return M.coord(cur()[c[2]]) end, color = C },
    } })
  end

  local qbox = row:box({ w = side, h = side, scrollBar = false })
  qbox:rectangle({ w = side, h = side, filled = true, color = WHITE })
  local qr = qbox:qrcode({ x = quiet, y = quiet, w = side - 2 * quiet, h = side - 2 * quiet,
                           data = M.url(cur()), color = BLACK, bgColor = WHITE })

  local function go(d)
    idx = idx + d
    qr:set({ data = M.url(cur()) })
  end
  local half = lvgl.PERCENT_SIZE + 48
  left:box({ w = lvgl.PERCENT_SIZE + 100, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_SMALL, children = {
    { type = "button", text = "Newer", w = half, press = function() go(-1) end,
      active = function() return idx > 1 end },
    { type = "button", text = "Older", w = half, press = function() go(1) end,
      active = function() return idx < #flights end },
  } })
  left:button({ text = "Back", w = lvgl.PERCENT_SIZE + 98, press = ctx.close })
end
