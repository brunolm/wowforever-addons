local ADDON, ns = ...

local ROW_HEIGHT = 30
local SETTINGS = {
  { key = "running", label = "Text (running or at zero)" },
  { key = "paused", label = "Text (paused)" },
  { key = "border", label = "Border" },
  { key = "background", label = "Background" },
}
local rows = {}
local panel, categoryID

local CreateRow, OpenPicker, RefreshRows

function ns.CreateOptions()
  panel = CreateFrame("Frame")
  panel.name = ADDON

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(ADDON)

  local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  help:SetWidth(620)
  help:SetJustifyH("LEFT")
  help:SetText("Click a swatch to pick a color; the opacity slider in the picker sets transparency. "
    .. "The stopwatch changes as you pick, and Cancel restores the previous color. "
    .. "Left-click the stopwatch to start or pause, right-click to reset, drag to move.")

  for i, setting in ipairs(SETTINGS) do
    rows[i] = CreateRow(setting)
    rows[i]:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -16 - (i - 1) * ROW_HEIGHT)
  end

  local resetAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetAll:SetSize(120, 24)
  resetAll:SetPoint("TOPLEFT", rows[#rows], "BOTTOMLEFT", 0, -16)
  resetAll:SetText("Reset all")
  resetAll:SetScript("OnClick", function()
    for _, setting in ipairs(SETTINGS) do
      ns.db.colors[setting.key] = CopyTable(ns.DEFAULT_COLORS[setting.key])
    end
    RefreshRows()
    ns.ApplyColors()
  end)

  panel:SetScript("OnShow", RefreshRows)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON)
    Settings.RegisterAddOnCategory(category)
    categoryID = category:GetID()
  else
    InterfaceOptions_AddCategory(panel)
  end
end

function ns.OpenOptions()
  if categoryID then
    Settings.OpenToCategory(categoryID)
  else
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end

function CreateRow(setting)
  local row = CreateFrame("Frame", nil, panel)
  row:SetSize(620, ROW_HEIGHT)

  local swatch = CreateFrame("Button", nil, row)
  swatch:SetSize(22, 22)
  swatch:SetPoint("LEFT", 4, 0)
  local border = swatch:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints()
  border:SetColorTexture(0.85, 0.85, 0.85)
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  swatch:SetScript("OnClick", function() OpenPicker(setting.key) end)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
  label:SetText(setting.label)

  local reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  reset:SetSize(80, 22)
  reset:SetPoint("LEFT", 260, 0)
  reset:SetText("Default")
  reset:SetScript("OnClick", function()
    ns.db.colors[setting.key] = CopyTable(ns.DEFAULT_COLORS[setting.key])
    row:Refresh()
    ns.ApplyColors()
  end)

  function row:Refresh()
    fill:SetColorTexture(unpack(ns.db.colors[setting.key]))
  end

  return row
end

function OpenPicker(key)
  local previous = CopyTable(ns.db.colors[key])

  local function Apply(color)
    ns.db.colors[key] = color
    RefreshRows()
    ns.ApplyColors()
  end

  local function ApplyPicked()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or previous[4]
    Apply({ r, g, b, a })
  end

  ColorPickerFrame:SetupColorPickerAndShow({
    r = previous[1], g = previous[2], b = previous[3],
    hasOpacity = true,
    opacity = previous[4],
    swatchFunc = ApplyPicked,
    opacityFunc = ApplyPicked,
    cancelFunc = function() Apply(previous) end,
  })
end

function RefreshRows()
  for _, row in ipairs(rows) do
    row:Refresh()
  end
end
