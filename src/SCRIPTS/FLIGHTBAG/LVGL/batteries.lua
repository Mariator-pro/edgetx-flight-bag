-- =====================================================================
-- batteries.lua  --  Flight Bag (EdgeTX UI) page "Batteries"
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/LVGL/batteries.lua
-- Native view of batteries_model.lua: profile list, profile editor (name and
-- manufacturer in EdgeTX text fields), packs and statistics, each as its own
-- EdgeTX page.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local M = loadScript("/SCRIPTS/FLIGHTBAG/batteries_model.lua")()(ctx)
  local WIDE  = lvgl.PERCENT_SIZE + 100
  local VALUE = lvgl.PERCENT_SIZE + (LCD_W < 400 and 42 or 50)   -- x of the value column
  local C = COLOR_THEME_PRIMARY1
  local Buy = M.Buy
  local CAP_STEP = 10   -- capacity field counts in 10 mAh
  local TEXT_W = math.floor(LCD_W * (LCD_W < 400 and 0.54 or 0.46))   -- name fields: value column to the right edge

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

  -- Setting row titled `title` (text or function); returns the box of its value column.
  -- CENTER: in a row EdgeTX takes the vertical placement from the horizontal flag.
  local function setting(pg, title)
    local s = pg:setting({ w = WIDE, title = title })
    return s:box({ x = VALUE, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_MEDIUM, align = CENTER })
  end

  local function ask(message, yes) lvgl.confirm({ title = "Batteries", message = message, confirm = yes }) end
  local function tell(message) lvgl.message({ title = "Batteries", message = message }) end

  -- Writes Lipo Nanny's file, then onDone; a failed write asks to retry.
  local function save(onDone)
    if M.write() then onDone()
    else ask("Save failed. Check SD card. Retry?", function() save(onDone) end) end
  end

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
    local items = M.sorted()
    if #items == 0 then pg:box({ w = WIDE, flexFlow = lvgl.FLOW_ROW }):label({ text = "No batteries yet - add your first.", color = C }) end
    for _, b in ipairs(items) do
      listButton(pg, b.name, function() M.open(b); Show.profile() end)
    end
    buttons(pg, { { "Back", ctx.close }, { "[+] Add new", function() M.open(nil); Show.profile() end } })
  end

  -- ---------------------------------------------------------------------------
  -- Profile editor
  -- ---------------------------------------------------------------------------

  local function saveProfile()
    local msg = M.invalid()
    if msg then return tell(msg) end
    M.commit()
    save(Show.list)
  end

  local function deleteProfile()
    local msg = M.deleteBlocked()
    if msg then return tell(msg) end
    ask(M.deleteQuestion(), function()
      M.delete()
      save(Show.list)
    end)
  end

  local function cancelProfile()
    if M.dirty() then ask("Discard changes?", Show.list) else Show.list() end
  end

  local function pctRow(pg, title, key)
    local L = M.LIMITS[key]
    local box = setting(pg, title)
    box:numberEdit({ min = L.min, max = L.max, get = function() return M.pct(key) end,
      set = function(v) M.setPct(key, v) end, display = function(v) return v .. " %" end })
    box:label({ text = "(default)", color = COLOR_THEME_DISABLED, visible = function() return M.prof[key] == nil end })
  end

  function Show.profile()
    local p = M.prof
    local pg = page(M.isNew and "Add battery" or "Edit battery", cancelProfile)
    -- The value as a function shows a new auto name (:set would shrink the
    -- field to zero height).
    local nameBox = setting(pg, function() return p.nameAuto and "Name (auto)" or "Name" end)
    nameBox:textEdit({ value = function() return p.name end, length = M.TEXT_MAX.name, w = TEXT_W,
                       set = function(s) M.setText(1, s) end })
    setting(pg, "Manufacturer"):textEdit({ value = p.manufacturer, length = M.TEXT_MAX.mfr,
      w = TEXT_W, set = function(s) M.setText(2, s) end })
    setting(pg, "Chemistry"):choice({ title = "Chemistry", values = M.CHEM_NAMES,
      get = M.chemIndex, set = M.setChemistry })
    local L = M.LIMITS.capacityMah
    setting(pg, "Capacity"):numberEdit({ min = math.ceil(L.min / CAP_STEP), max = math.floor(L.max / CAP_STEP),
      get = function() return math.floor(p.capacityMah / CAP_STEP + 0.5) end,
      set = function(v) M.setCapacity(v * CAP_STEP) end,
      display = function(v) return (v * CAP_STEP) .. " mAh" end })
    L = M.LIMITS.cells
    setting(pg, "Cells"):numberEdit({ min = L.min, max = L.max, get = function() return p.cells end,
      set = M.setCells, display = function(v) return v .. "S" end })
    setting(pg, "Packs"):button({ text = tostring(#p.instances), press = Show.packs })
    setting(pg, "Statistics"):button({ text = "Show", press = Show.stats })
    pctRow(pg, "Battery low", "warnPct")
    pctRow(pg, "Battery critical", "critPct")
    local list = { { "Back", cancelProfile }, { "Save", saveProfile } }
    if not M.isNew then list[#list + 1] = { "Delete", deleteProfile } end
    list[#list + 1] = { "Reset name", M.resetName, function() return not p.nameAuto end }
    buttons(pg, list)
  end

  -- ---------------------------------------------------------------------------
  -- Packs: one row per pack at fixed columns
  -- ---------------------------------------------------------------------------

  local function at(f) return math.floor(LCD_W * f) end
  local PK = { cyc = at(0.12), wear = at(0.33), buy = at(0.54), del = at(0.82) }
  local H = lvgl.UI_ELEMENT_HEIGHT + 2 * lvgl.PAD_SMALL

  function Show.packs()
    local p = M.prof
    local pg = page("Packs - " .. p.name, Show.profile)
    pg:box({ w = WIDE, h = H, children = {
      { type = "label", x = 0, y = lvgl.PAD_SMALL, text = "ID", font = BOLD, color = C },
      { type = "label", x = PK.cyc, y = lvgl.PAD_SMALL, text = "Cycles", font = BOLD, color = C },
      { type = "label", x = PK.wear, y = lvgl.PAD_SMALL, text = "Wear", font = BOLD, color = C },
      { type = "label", x = PK.buy, y = lvgl.PAD_SMALL, text = "Bought", font = BOLD, color = C },
    } })
    for i, pack in ipairs(p.instances) do
      local row = pg:box({ w = WIDE, h = H })
      row:label({ x = 0, y = lvgl.PAD_MEDIUM, text = "#" .. pack.label, color = C })
      row:numberEdit({ x = PK.cyc, w = PK.wear - PK.cyc - lvgl.PAD_LARGE, min = 0, max = 9999,
        get = function() return pack.cycles or 0 end, set = function(v) M.setCycles(pack, v) end })
      local W = M.LIMITS.wear
      row:numberEdit({ x = PK.wear, w = PK.buy - PK.wear - lvgl.PAD_LARGE, min = W.min, max = W.max,
        get = function() return pack.wear end, set = function(v) M.setWear(pack, v) end,
        display = function(v) return v .. " %" end })
      -- Unset date shows "-"; the first step starts from this month.
      row:numberEdit({ x = PK.buy, w = PK.del - PK.buy - lvgl.PAD_LARGE, min = Buy.MIN, max = Buy.MAX,
        get = function() return Buy.toMonths(pack.buyDate or Buy.today()) end,
        set = function(v) M.setBuy(pack, v) end,
        display = function(v) return pack.buyDate and Buy.fromMonths(v) or "-" end })
      row:button({ x = PK.del, text = "X", press = function()
        local reason = M.archiveLocked()
        if reason then return tell(reason) end
        M.removePack(i)   -- archived for real on profile save
        Show.packs()
      end })
    end
    buttons(pg, { { "Back", Show.profile }, { "[+] Add pack", function()
      local msg = M.addPack()
      if msg then tell(msg) else Show.packs() end
    end } })
  end

  -- ---------------------------------------------------------------------------
  -- Statistics (read-only)
  -- ---------------------------------------------------------------------------

  function Show.stats()
    local p = M.prof
    local pg = page("Statistics - " .. p.name, Show.profile)
    local SX = { at(0.12), at(0.30), at(0.52), at(0.70) }
    local function row(cells, font)
      local r = pg:box({ w = WIDE, h = lvgl.UI_ELEMENT_HEIGHT })
      r:label({ x = 0, text = cells[1], font = font, color = C })
      for j = 2, 5 do r:label({ x = SX[j - 1], text = cells[j], font = font, color = C }) end
    end
    row({ "ID", "Cycles", "Life mAh", "Vmin", "Last used" }, BOLD)
    for _, pack in ipairs(p.instances) do
      row({ "#" .. pack.label, tostring(pack.cycles or 0), tostring(pack.totalMah or 0),
            pack.minVCell and string.format("%.2f", pack.minVCell) or "-", pack.lastUsed or "-" })
    end
    buttons(pg, { { "Back", Show.profile } })
  end

  Show.list()
end
