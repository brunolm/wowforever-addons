local ADDON, ns = ...

local ROW_HEIGHT = 30
local rows = {}
local categoryID

local CreateRow, CreateSizeSlider, OpenPicker, RefreshRows

function ns.CreateOptions()
  local panel = CreateFrame("Frame")
  panel.name = ADDON

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(ADDON)

  local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  help:SetWidth(620)
  help:SetJustifyH("LEFT")
  help:SetText("Ticked types get their nameplate health bar recolored and resized; everything else keeps the game's look. "
    .. "A unit that fits several types takes the color and size of the highest one in the list. Click a swatch to pick a color. "
    .. "Friendly nameplates must be turned on (Shift-V) to see party colors.")

  for i, cat in ipairs(ns.CATEGORIES) do
    rows[i] = CreateRow(panel, cat)
    rows[i]:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -16 - (i - 1) * ROW_HEIGHT)
  end

  local resetAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetAll:SetSize(120, 24)
  resetAll:SetPoint("TOPLEFT", rows[#rows], "BOTTOMLEFT", 0, -16)
  resetAll:SetText("Reset all")
  resetAll:SetScript("OnClick", function()
    ns.ResetAll()
    RefreshRows()
    ns.RefreshAll()
  end)

  panel:SetScript("OnShow", RefreshRows)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON)
    Settings.RegisterAddOnCategory(category)
    categoryID = category:GetID()
  else
    InterfaceOptions_AddCategory(panel)
  end

  SLASH_PLATECOLORS1 = "/platecolors"
  SLASH_PLATECOLORS2 = "/pcolors"
  SlashCmdList.PLATECOLORS = function(msg)
    if msg == "debug" then
      ns.Debug()
      return
    end
    if categoryID then Settings.OpenToCategory(categoryID) else InterfaceOptionsFrame_OpenToCategory(panel) end
  end
end

function CreateRow(panel, cat)
  local row = CreateFrame("Frame", nil, panel)
  row:SetSize(620, ROW_HEIGHT)

  local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  check:SetPoint("LEFT")
  check:SetScript("OnClick", function(self)
    ns.db.enabled[cat.key] = self:GetChecked()
    ns.RefreshAll()
  end)

  local swatch = CreateFrame("Button", nil, row)
  swatch:SetSize(22, 22)
  swatch:SetPoint("LEFT", check, "RIGHT", 6, 0)
  local border = swatch:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints()
  border:SetColorTexture(0.85, 0.85, 0.85)
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  swatch:SetScript("OnClick", function() OpenPicker(cat.key) end)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
  label:SetText(cat.label)

  local reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  reset:SetSize(80, 22)
  reset:SetPoint("LEFT", 300, 0)
  reset:SetText("Default")
  reset:SetScript("OnClick", function()
    ns.ResetCategory(cat.key)
    row:Refresh()
    ns.RefreshAll()
  end)

  local slider, sizeText = CreateSizeSlider(row)
  slider:SetPoint("LEFT", 400, 0)
  local function ShowSize(value) sizeText:SetFormattedText("%d%%", value * 100 + 0.5) end
  -- Moving the slider also ticks the type, so the change shows right away.
  slider:SetScript("OnValueChanged", function(_, value)
    ShowSize(value)
    if math.abs(value - ns.db.sizes[cat.key]) < 0.001 then return end
    ns.db.sizes[cat.key] = value
    ns.db.enabled[cat.key] = true
    check:SetChecked(true)
    ns.RefreshAll()
  end)

  function row:Refresh()
    check:SetChecked(ns.db.enabled[cat.key])
    fill:SetColorTexture(unpack(ns.db.colors[cat.key]))
    slider:SetValue(ns.db.sizes[cat.key])
    ShowSize(ns.db.sizes[cat.key])
  end

  return row
end

function CreateSizeSlider(row)
  local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(140, 15)
  slider:SetHitRectInsets(0, 0, -10, -10)
  slider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
  })
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetMinMaxValues(ns.SIZE_MIN, ns.SIZE_MAX)
  slider:SetValueStep(ns.SIZE_STEP)
  slider:SetObeyStepOnDrag(true)

  local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  text:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  return slider, text
end

-- Picking a color also ticks the type, so the change shows right away; Cancel undoes both.
function OpenPicker(key)
  local previousColor = ns.db.colors[key]
  local previousEnabled = ns.db.enabled[key]

  local function Apply(color, enabled)
    ns.db.colors[key] = color
    ns.db.enabled[key] = enabled
    RefreshRows()
    ns.RefreshAll()
  end

  ColorPickerFrame:SetupColorPickerAndShow({
    r = previousColor[1], g = previousColor[2], b = previousColor[3],
    swatchFunc = function() Apply({ ColorPickerFrame:GetColorRGB() }, true) end,
    cancelFunc = function() Apply(previousColor, previousEnabled) end,
  })
end

function RefreshRows()
  for _, row in ipairs(rows) do row:Refresh() end
end
