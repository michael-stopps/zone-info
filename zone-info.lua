-- GLOBAL VARIABLES
local frame = CreateFrame("Frame", "ZoneInfoFrame", UIParent)
local bg = frame:CreateTexture(nil, "BACKGROUND")
local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

local ZoneInfoSettings = {}

-- SETTINGS REGISTRATION
local function RegisterZoneInfoSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("ZoneInfo")

    -- Lock Position
    ZoneInfoSettings.lock = Settings.RegisterAddOnSetting(category, "ZONEINFO_LOCK", "isLocked", ZoneInfoDB, Settings.VarType.Boolean, "Lock Position", true)
    Settings.CreateCheckbox(category, ZoneInfoSettings.lock, "Prevents the frame from being moved.")

    -- Show Background
    ZoneInfoSettings.bg = Settings.RegisterAddOnSetting(category, "ZONEINFO_BG", "showBG", ZoneInfoDB, Settings.VarType.Boolean, "Show Background", false)
    Settings.CreateCheckbox(category, ZoneInfoSettings.bg, "Toggles the dark background box.")

    -- Scale Slider
    ZoneInfoSettings.scale = Settings.RegisterAddOnSetting(category, "ZONEINFO_SCALE", "textScale", ZoneInfoDB, Settings.VarType.Number, "Text Scale", 1.0)
    Settings.CreateSlider(category, ZoneInfoSettings.scale, Settings.CreateSliderOptions(0.5, 3.0, 0.1), "Adjust the size of the text and coordinates.")

    Settings.RegisterAddOnCategory(category)
    return category
end

local categoryObj

-- INIT
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "zone-info" then
        -- Initialize Database
        ZoneInfoDB = ZoneInfoDB or {}
        local defaults = {
            pos = { point = "TOP", x = 0, y = -40 },
            color = { r = 1, g = 0.82, b = 0 },
            isLocked = false,
            textScale = 1.0,
            showBG = true,
        }
        for k, v in pairs(defaults) do
            if ZoneInfoDB[k] == nil then ZoneInfoDB[k] = v end
        end

        -- Setup UI Elements
        self:SetSize(200, 50)
        self:SetMovable(true)
        self:EnableMouse(true)
        self:RegisterForDrag("LeftButton")
        
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        
        text:SetPoint("CENTER")
        
        local p = ZoneInfoDB.pos
        self:ClearAllPoints()
        self:SetPoint(p.point, p.x, p.y)

        -- Register the Settings menu
        categoryObj = RegisterZoneInfoSettings()
        
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- ==========================================
-- COPY POPUP FRAME
-- ==========================================
local copyFrame = CreateFrame("Frame", "ZoneInfoCopyFrame", UIParent, "BackdropTemplate")
copyFrame:SetSize(280, 70)
copyFrame:SetPoint("TOP", frame, "BOTTOM", 0, -10)
copyFrame:SetFrameStrata("DIALOG")
copyFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})
copyFrame:Hide()

local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
copyTitle:SetPoint("TOP", 0, -15)
copyTitle:SetText("Press Ctrl+C to Copy")

local copyBox = CreateFrame("EditBox", nil, copyFrame, "InputBoxTemplate")
copyBox:SetSize(220, 20)
copyBox:SetPoint("BOTTOM", 0, 15)
copyBox:SetAutoFocus(true)
copyBox:SetScript("OnEscapePressed", function(self) copyFrame:Hide() end)
copyBox:SetScript("OnEditFocusLost", function(self) copyFrame:Hide() end)

local function ShowCopyPopup(wayCommand)
    copyBox:SetText(wayCommand)
    copyFrame:Show()
    copyBox:HighlightText()
    copyBox:SetFocus()
end

-- ==========================================
-- INTERACTION & COPY LOGIC
-- ==========================================
frame.isDragging = false

frame:SetScript("OnDragStart", function(self) 
    if not ZoneInfoDB.isLocked then 
        self.isDragging = true
        self:StartMoving() 
    end 
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    ZoneInfoDB.pos = { point = point, x = x, y = y }
    
    -- Delay clearing the drag flag slightly so OnMouseUp doesn't trigger an accidental copy
    C_Timer.After(0.05, function() self.isDragging = false end)
end)

-- Left Click: Copy Waypoint | Ctrl-Left Click: Link to Chat | Right Click: Color Picker
frame:SetScript("OnMouseUp", function(self, button)
    if self.isDragging then return end

    if button == "RightButton" and not ZoneInfoDB.isLocked then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = ZoneInfoDB.color.r, g = ZoneInfoDB.color.g, b = ZoneInfoDB.color.b,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                ZoneInfoDB.color = { r = r, g = g, b = b }
            end,
            hasOpacity = false,
        })
    elseif button == "LeftButton" then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if pos then
                local x, y = pos:GetXY()
                if x >= 0.001 or y >= 0.001 then
                    if IsControlKeyDown() then
                        -- Ctrl-Click: Generate Native Map Link for Chat
                        
                        -- 1. Backup current waypoint and extended-pins DB state
                        local oldWP = C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint() or nil
                        local oldPinCount = ExtendedPinsDB and #ExtendedPinsDB or 0
                        
                        -- 2. Set temporary waypoint to force client to generate certified link
                        local pt = UiMapPoint.CreateFromCoordinates(mapID, x, y)
                        C_Map.SetUserWaypoint(pt)
                        local link = C_Map.GetUserWaypointHyperlink()
                        
                        -- 3. Restore previous waypoint
                        if oldWP then
                            C_Map.SetUserWaypoint(oldWP)
                        else
                            C_Map.ClearUserWaypoint()
                        end
                        
                        -- 4. Cleanup extended-pins database from hook side-effects
                        if ExtendedPinsDB then
                            while #ExtendedPinsDB > oldPinCount do
                                table.remove(ExtendedPinsDB)
                            end
                        end
                        
                        -- 5. Insert the certified link into the chat box automatically
                        if link then
                            if ChatEdit_GetActiveWindow() then
                                ChatEdit_InsertLink(link)
                            else
                                ChatFrame_OpenChat(link)
                            end
                        end
                    else
                        -- Normal Click: Popup to copy /way command
                        local wayCommand = string.format("/way #%d %.2f %.2f", mapID, x * 100, y * 100)
                        ShowCopyPopup(wayCommand)
                    end
                end
            end
        end
    end
end)

-- SLASH COMMAND
SLASH_ZONEINFO1 = "/zi"
SLASH_ZONEINFO2 = "/zoneinfo"
SlashCmdList["ZONEINFO"] = function(msg)
    if msg:lower() == "reset" then
        ZoneInfoDB = nil
        ReloadUI()
    elseif categoryObj then
        Settings.OpenToCategory(categoryObj:GetID())
    end
end

-- UPDATE LOOP
C_Timer.NewTicker(0.2, function()
    -- Only run if the database is loaded
    if not ZoneInfoDB then return end

    -- Apply reactive settings
    frame:SetScale(ZoneInfoDB.textScale or 1.0)
    bg:SetShown(ZoneInfoDB.showBG)
    
    local c = ZoneInfoDB.color
    text:SetTextColor(c.r, c.g, c.b)

    -- Get Location
    local zone = GetRealZoneText() or ""
    local subzone = GetSubZoneText() or ""
    local loc = zone == "Home Interior" and subzone or ((subzone ~= "" and subzone ~= zone) and (subzone..", "..zone) or zone)

    -- Get Coords
    local mapID = C_Map.GetBestMapForUnit("player")
    local coords = nil
    if mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local x, y = pos:GetXY()
            if x < 0.001 and y < 0.001 then
                coords = nil
            else
                coords = string.format("%.2f, %.2f", x * 100, y * 100)
            end
        end
    end
    if coords then
        text:SetText(string.format("%s\n|cffffffff%s|r", loc, coords))
    else
        text:SetText(loc)
    end
end)

function ZoneInfo_OnCompartmentClick()
    SlashCmdList["ZONEINFO"]("") 
end