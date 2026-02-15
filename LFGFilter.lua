----------------------------------------------------------------------
-- LFG Filter v1.0 - TBC Anniversary Looking For Group Browser Filter
-- Two filter modes:
--   "Find Players" - Shows solo players matching class/role filters
--   "Find Groups"  - Shows groups with available role slots
-- Filters auto-apply on toggle. Preferences saved between sessions.
----------------------------------------------------------------------

local addonName, ns = ...

LFGFilterDB = LFGFilterDB or {}

local pairs, ipairs = pairs, ipairs
local strlower = string.lower
local format = string.format

----------------------------------------------------------------------
-- CLASS INFO
----------------------------------------------------------------------
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local CLASS_INFO = {
    { name = "Warrior",  id = 1,  color = "C79C6E", file = "WARRIOR",  tcoords = { 0,       0.25,     0,    0.25   } },
    { name = "Paladin",  id = 2,  color = "F58CBA", file = "PALADIN",  tcoords = { 0,       0.25,     0.5,  0.75   } },
    { name = "Hunter",   id = 3,  color = "ABD473", file = "HUNTER",   tcoords = { 0,       0.25,     0.25, 0.5    } },
    { name = "Rogue",    id = 4,  color = "FFF569", file = "ROGUE",    tcoords = { 0.49609, 0.74219,  0,    0.25   } },
    { name = "Priest",   id = 5,  color = "FFFFFF", file = "PRIEST",   tcoords = { 0.49609, 0.74219,  0.25, 0.5    } },
    { name = "Shaman",   id = 7,  color = "0070DE", file = "SHAMAN",   tcoords = { 0.25,    0.49609,  0.25, 0.5    } },
    { name = "Mage",     id = 8,  color = "69CCF0", file = "MAGE",     tcoords = { 0.25,    0.49609,  0,    0.25   } },
    { name = "Warlock",  id = 9,  color = "9482C9", file = "WARLOCK",  tcoords = { 0.74219, 0.98828,  0.25, 0.5    } },
    { name = "Druid",    id = 11, color = "FF7D0A", file = "DRUID",    tcoords = { 0.74219, 0.98828,  0,    0.25   } },
}

local ROLE_ICON_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"

local ROLE_ICON_TCOORDS = {
    tank   = { 0,       0.296875, 0.34375, 0.640625 },
    healer = { 0.296875, 0.59375,  0,       0.296875 },
    dps    = { 0.296875, 0.59375,  0.34375, 0.640625 },
}

-- Remaining slot keys from GetSearchResultMemberCounts
local ROLE_REMAINING_MAP = {
    tank   = "TANK_REMAINING",
    healer = "HEALER_REMAINING",
    dps    = "DAMAGER_REMAINING",
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local filterPanel
local resultCountText
local totalResultCount = 0

local lfgParent
local lfgBrowseFrame
local lfgScrollBox

-- Find Players state
local playerRoleButtons = {}
local classButtons = {}
local activePlayerRoles = {}
local activeClasses = {}

-- Find Groups state
local groupRoleButtons = {}
local activeGroupRoles = {}

----------------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------------
local function AnyPlayerFilterActive()
    for _, v in pairs(activePlayerRoles) do if v then return true end end
    for _, v in pairs(activeClasses) do if v then return true end end
    return false
end

local function AnyGroupFilterActive()
    for _, v in pairs(activeGroupRoles) do if v then return true end end
    return false
end

local function AnyFilterActive()
    return AnyPlayerFilterActive() or AnyGroupFilterActive()
end

local function HexColor(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
           tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
end

----------------------------------------------------------------------
-- SAVED VARIABLES: Save/restore filter state
----------------------------------------------------------------------
local function SaveFilterState()
    LFGFilterDB.playerRoles = {}
    for k, v in pairs(activePlayerRoles) do
        if v then LFGFilterDB.playerRoles[k] = true end
    end

    LFGFilterDB.classes = {}
    for k, v in pairs(activeClasses) do
        if v then LFGFilterDB.classes[k] = true end
    end

    LFGFilterDB.groupRoles = {}
    for k, v in pairs(activeGroupRoles) do
        if v then LFGFilterDB.groupRoles[k] = true end
    end
end

local function RestoreFilterState()
    if not LFGFilterDB then return end

    if LFGFilterDB.playerRoles then
        for k, v in pairs(LFGFilterDB.playerRoles) do
            activePlayerRoles[k] = v
            if playerRoleButtons[k] then
                playerRoleButtons[k].isActive = v
                playerRoleButtons[k]:UpdateVisual()
            end
        end
    end

    if LFGFilterDB.classes then
        for k, v in pairs(LFGFilterDB.classes) do
            activeClasses[k] = v
            if classButtons[k] then
                classButtons[k].isActive = v
                classButtons[k]:UpdateVisual()
            end
        end
    end

    if LFGFilterDB.groupRoles then
        for k, v in pairs(LFGFilterDB.groupRoles) do
            activeGroupRoles[k] = v
            if groupRoleButtons[k] then
                groupRoleButtons[k].isActive = v
                groupRoleButtons[k]:UpdateVisual()
            end
        end
    end
end

----------------------------------------------------------------------
-- Clear one mode's filters (used when switching modes)
----------------------------------------------------------------------
local function ClearPlayerFilters()
    for role, btn in pairs(playerRoleButtons) do
        btn.isActive = false
        activePlayerRoles[role] = false
        btn:UpdateVisual()
    end
    for classId, btn in pairs(classButtons) do
        btn.isActive = false
        activeClasses[classId] = false
        btn:UpdateVisual()
    end
end

local function ClearGroupFilters()
    for role, btn in pairs(groupRoleButtons) do
        btn.isActive = false
        activeGroupRoles[role] = false
        btn:UpdateVisual()
    end
end

----------------------------------------------------------------------
-- CORE: Check if entry passes "Find Players" filters.
----------------------------------------------------------------------
local function EntryPassesFindPlayers(entry, counts, info)
    if not counts then return false end

    local numMembers = info and info.numMembers or 0
    if numMembers ~= 1 then return false end

    -- Check role filter using lfgRoles from LeaderInfo
    local hasRole = false
    for _, v in pairs(activePlayerRoles) do if v then hasRole = true; break end end

    if hasRole then
        local rolePass = false
        local rid = entry.resultID
        if rid and C_LFGList and C_LFGList.GetSearchResultLeaderInfo then
            local ok, leaderInfo = pcall(C_LFGList.GetSearchResultLeaderInfo, rid)
            if ok and type(leaderInfo) == "table" and leaderInfo.lfgRoles then
                local lfgRoles = leaderInfo.lfgRoles
                for roleKey, isActive in pairs(activePlayerRoles) do
                    if isActive and lfgRoles[roleKey] then
                        rolePass = true
                        break
                    end
                end
            end
        end
        if not rolePass then return false end
    end

    -- Check class filter
    local hasClass = false
    for _, v in pairs(activeClasses) do if v then hasClass = true; break end end

    if hasClass then
        local classPass = false
        for classId, isActive in pairs(activeClasses) do
            if isActive then
                for _, cinfo in ipairs(CLASS_INFO) do
                    if cinfo.id == classId then
                        if counts[cinfo.file] and counts[cinfo.file] > 0 then
                            classPass = true
                            break
                        end
                    end
                end
                if classPass then break end
            end
        end
        if not classPass then return false end
    end

    return true
end

----------------------------------------------------------------------
-- CORE: Check if entry passes "Find Groups" filters.
----------------------------------------------------------------------
local function EntryPassesFindGroups(entry, counts, info)
    if not counts then return false end

    local numMembers = info and info.numMembers or 0
    if numMembers < 2 then return false end

    local rolePass = false
    for roleKey, isActive in pairs(activeGroupRoles) do
        if isActive then
            local remainKey = ROLE_REMAINING_MAP[roleKey]
            if remainKey and counts[remainKey] and counts[remainKey] > 0 then
                rolePass = true
                break
            end
        end
    end

    return rolePass
end

----------------------------------------------------------------------
-- CORE: Apply filters
----------------------------------------------------------------------
local function ApplyAndRefresh()
    if not lfgBrowseFrame then return end
    if not lfgScrollBox then
        lfgScrollBox = _G["LFGBrowseFrameScrollBox"]
    end
    if not lfgScrollBox then return end

    -- Refresh to get full unfiltered data
    if lfgBrowseFrame.UpdateResultList then
        lfgBrowseFrame:UpdateResultList()
    elseif lfgBrowseFrame.UpdateResults then
        lfgBrowseFrame:UpdateResults()
    end

    SaveFilterState()

    if not AnyFilterActive() then
        if resultCountText then resultCountText:SetText("") end
        return
    end

    local dp = lfgScrollBox.GetDataProvider and lfgScrollBox:GetDataProvider()
    if not dp or not dp.Enumerate then return end

    local findPlayers = AnyPlayerFilterActive()
    local findGroups = AnyGroupFilterActive()

    local allEntries = {}
    local passingEntries = {}

    for idx, entry in dp:Enumerate() do
        table.insert(allEntries, entry)

        if type(entry) == "table" and entry.resultID then
            local rid = entry.resultID

            local counts = nil
            if C_LFGList and C_LFGList.GetSearchResultMemberCounts then
                local ok, result = pcall(C_LFGList.GetSearchResultMemberCounts, rid)
                if ok and type(result) == "table" then counts = result end
            end

            local info = nil
            if C_LFGList and C_LFGList.GetSearchResultInfo then
                local ok, result = pcall(C_LFGList.GetSearchResultInfo, rid)
                if ok and type(result) == "table" then info = result end
            end

            local passes = false
            if findPlayers then
                passes = EntryPassesFindPlayers(entry, counts, info)
            elseif findGroups then
                passes = EntryPassesFindGroups(entry, counts, info)
            end

            if passes then
                table.insert(passingEntries, entry)
            end
        end
    end

    totalResultCount = #allEntries

    local newDP = CreateDataProvider()
    if newDP then
        newDP:InsertTable(passingEntries)
        lfgScrollBox:SetDataProvider(newDP)
    end

    if resultCountText then
        if findPlayers then
            resultCountText:SetText(format("Showing %d players of %d listings", #passingEntries, totalResultCount))
        elseif findGroups then
            resultCountText:SetText(format("Showing %d groups of %d listings", #passingEntries, totalResultCount))
        end
    end
end

----------------------------------------------------------------------
-- UI HELPERS
----------------------------------------------------------------------
local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 16, yOffset)
    header:SetText(text)
    header:SetTextColor(1, 0.82, 0)
    return header
end

local function CreateSeparator(parent, yOffset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, yOffset)
    line:SetPoint("TOPRIGHT", -12, yOffset)
    line:SetColorTexture(0.6, 0.6, 0.6, 0.3)
    return line
end

local function CreateToggleButton(parent, text, width, height, colorHex, iconInfo)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)

    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    local r, g, b = 1, 1, 1
    if colorHex then r, g, b = HexColor(colorHex) end

    local icon
    local iconSize = height - 4
    if iconInfo then
        icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexture(iconInfo.texture)
        if iconInfo.tcoords then
            icon:SetTexCoord(unpack(iconInfo.tcoords))
        end
    end

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if icon then
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    else
        label:SetPoint("CENTER", 0, 0)
    end
    label:SetText(text)
    btn.label = label
    btn.icon = icon
    btn.isActive = false

    local function UpdateVisual()
        if btn.isActive then
            btn:SetBackdropColor(r, g, b, 0.3)
            btn:SetBackdropBorderColor(r, g, b, 0.8)
            label:SetTextColor(r, g, b)
            if icon then icon:SetDesaturated(false); icon:SetAlpha(1.0) end
        else
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
            label:SetTextColor(0.5, 0.5, 0.5)
            if icon then icon:SetDesaturated(true); icon:SetAlpha(0.5) end
        end
    end
    btn.UpdateVisual = UpdateVisual

    btn:SetScript("OnClick", function(self)
        self.isActive = not self.isActive
        UpdateVisual()
        if self.onToggle then self.onToggle(self.isActive) end
    end)
    btn:EnableMouse(true)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 0.6)
        if icon then icon:SetDesaturated(false); icon:SetAlpha(1.0) end
    end)
    btn:SetScript("OnLeave", function(self) UpdateVisual() end)

    UpdateVisual()
    return btn
end

----------------------------------------------------------------------
-- CLEAR ALL FILTERS
----------------------------------------------------------------------
local function ClearAllFilters()
    ClearPlayerFilters()
    ClearGroupFilters()
    totalResultCount = 0
    if resultCountText then resultCountText:SetText("") end

    SaveFilterState()

    if lfgBrowseFrame then
        if lfgBrowseFrame.UpdateResultList then
            lfgBrowseFrame:UpdateResultList()
        elseif lfgBrowseFrame.UpdateResults then
            lfgBrowseFrame:UpdateResults()
        end
    end
end

----------------------------------------------------------------------
-- UI: Build the side panel
----------------------------------------------------------------------
local function CreateFilterPanel()
    if not lfgParent then return false end

    local PANEL_WIDTH = 260
    local PANEL_HEIGHT = lfgParent:GetHeight()
    local PADDING = 14
    local INNER_WIDTH = PANEL_WIDTH - PADDING * 2

    filterPanel = CreateFrame("Frame", "LFGFilterPanel", lfgParent, "BackdropTemplate")
    filterPanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    filterPanel:SetPoint("TOPLEFT", lfgParent, "TOPRIGHT", -2, 0)
    filterPanel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    filterPanel:SetBackdropColor(0, 0, 0, 0.9)
    filterPanel:SetFrameStrata("DIALOG")

    lfgParent:HookScript("OnShow", function() filterPanel:Show() end)
    lfgParent:HookScript("OnHide", function() filterPanel:Hide() end)
    if not lfgParent:IsShown() then filterPanel:Hide() end

    local yPos = -12

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, filterPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() filterPanel:Hide() end)

    -- Title
    local title = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, yPos)
    title:SetText("LFG Filter")
    title:SetTextColor(1, 0.82, 0)
    yPos = yPos - 22

    -- Result count
    resultCountText = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultCountText:SetPoint("TOP", 0, yPos)
    resultCountText:SetTextColor(0.7, 0.7, 0.7)
    yPos = yPos - 20

    CreateSeparator(filterPanel, yPos)
    yPos = yPos - 10

    ----------------------------------------------------------------
    -- SECTION 1: FIND PLAYERS (for group leaders)
    ----------------------------------------------------------------
    CreateSectionHeader(filterPanel, "Find Players", yPos)
    yPos = yPos - 16
    local fpDesc = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fpDesc:SetPoint("TOPLEFT", 16, yPos)
    fpDesc:SetText("Show solo players matching class/role")
    fpDesc:SetTextColor(0.6, 0.6, 0.6)
    yPos = yPos - 16

    -- Role filters
    local roleLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleLabel:SetPoint("TOPLEFT", 16, yPos)
    roleLabel:SetText("Role:")
    roleLabel:SetTextColor(0.8, 0.8, 0.8)
    yPos = yPos - 18

    local roleData = {
        { key = "tank",   text = "Tank",   color = "5588DD" },
        { key = "healer", text = "Healer", color = "55DD55" },
        { key = "dps",    text = "DPS",    color = "DD5555" },
    }

    local ROLE_BTN_W = (INNER_WIDTH - 8) / 3
    local ROLE_BTN_H = 28
    for i, rd in ipairs(roleData) do
        local iconData = nil
        if ROLE_ICON_TCOORDS[rd.key] then
            iconData = { texture = ROLE_ICON_TEXTURE, tcoords = ROLE_ICON_TCOORDS[rd.key] }
        end
        local btn = CreateToggleButton(filterPanel, rd.text, ROLE_BTN_W, ROLE_BTN_H, rd.color, iconData)
        btn:SetPoint("TOPLEFT", PADDING + (i - 1) * (ROLE_BTN_W + 4), yPos)
        btn.onToggle = function(isActive)
            activePlayerRoles[rd.key] = isActive
            if isActive then ClearGroupFilters() end
            ApplyAndRefresh()
        end
        playerRoleButtons[rd.key] = btn
    end

    yPos = yPos - ROLE_BTN_H - 8

    -- Class filters
    local classLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classLabel:SetPoint("TOPLEFT", 16, yPos)
    classLabel:SetText("Class:")
    classLabel:SetTextColor(0.8, 0.8, 0.8)
    yPos = yPos - 18

    local COLS = 2
    local COL_GAP = 6
    local CLASS_BTN_W = (INNER_WIDTH - COL_GAP) / COLS
    local CLASS_BTN_H = 24
    local CLASS_ROW_H = CLASS_BTN_H + 4

    for idx, cinfo in ipairs(CLASS_INFO) do
        local row = math.floor((idx - 1) / COLS)
        local col = (idx - 1) % COLS
        local xOff = PADDING + col * (CLASS_BTN_W + COL_GAP)
        local rowY = yPos - row * CLASS_ROW_H

        local iconData = { texture = CLASS_ICON_TEXTURE, tcoords = cinfo.tcoords }
        local btn = CreateToggleButton(filterPanel, cinfo.name, CLASS_BTN_W, CLASS_BTN_H, cinfo.color, iconData)
        btn:SetPoint("TOPLEFT", xOff, rowY)
        btn.onToggle = function(isActive)
            activeClasses[cinfo.id] = isActive
            if isActive then ClearGroupFilters() end
            ApplyAndRefresh()
        end
        classButtons[cinfo.id] = btn
    end

    local classRows = math.ceil(#CLASS_INFO / COLS)
    yPos = yPos - classRows * CLASS_ROW_H - 4

    CreateSeparator(filterPanel, yPos)
    yPos = yPos - 10

    ----------------------------------------------------------------
    -- SECTION 2: FIND GROUPS (for solo players)
    ----------------------------------------------------------------
    CreateSectionHeader(filterPanel, "Find Groups", yPos)
    yPos = yPos - 16
    local fgDesc = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fgDesc:SetPoint("TOPLEFT", 16, yPos)
    fgDesc:SetText("Show groups with open role slots")
    fgDesc:SetTextColor(0.6, 0.6, 0.6)
    yPos = yPos - 16

    local groupRoleData = {
        { key = "tank",   text = "Tank Needed",   color = "5588DD" },
        { key = "healer", text = "Healer Needed",  color = "55DD55" },
        { key = "dps",    text = "DPS Needed",     color = "DD5555" },
    }

    local GROUP_BTN_W = INNER_WIDTH
    local GROUP_BTN_H = 26
    for i, rd in ipairs(groupRoleData) do
        local iconData = nil
        if ROLE_ICON_TCOORDS[rd.key] then
            iconData = { texture = ROLE_ICON_TEXTURE, tcoords = ROLE_ICON_TCOORDS[rd.key] }
        end
        local btn = CreateToggleButton(filterPanel, rd.text, GROUP_BTN_W, GROUP_BTN_H, rd.color, iconData)
        btn:SetPoint("TOPLEFT", PADDING, yPos)
        btn.onToggle = function(isActive)
            activeGroupRoles[rd.key] = isActive
            if isActive then ClearPlayerFilters() end
            ApplyAndRefresh()
        end
        groupRoleButtons[rd.key] = btn
        yPos = yPos - GROUP_BTN_H - 4
    end

    yPos = yPos - 4
    CreateSeparator(filterPanel, yPos)
    yPos = yPos - 14

    ----------------------------------------------------------------
    -- CLEAR BUTTON
    ----------------------------------------------------------------
    local clearBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
    clearBtn:SetSize(INNER_WIDTH, 28)
    clearBtn:SetPoint("TOPLEFT", PADDING, yPos)
    clearBtn:SetText("Clear Filters")
    clearBtn:SetScript("OnClick", ClearAllFilters)

    return true
end

----------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------
local function DumpFrameInfo()
    print("|cff00ff00[LFG Filter]|r === Debug ===")

    lfgScrollBox = lfgScrollBox or _G["LFGBrowseFrameScrollBox"]
    if not lfgScrollBox then
        print("  ScrollBox: NOT FOUND")
        return
    end

    local dp = lfgScrollBox.GetDataProvider and lfgScrollBox:GetDataProvider()
    if not dp then
        print("  DataProvider: NOT FOUND")
        return
    end

    local size = dp.GetSize and dp:GetSize() or 0
    print(format("  DataProvider size: %d (total tracked: %d)", size, totalResultCount))

    if dp.Enumerate and size > 0 then
        local soloCount, groupCount = 0, 0
        local count = 0
        for idx, entry in dp:Enumerate() do
            if type(entry) == "table" and entry.resultID then
                local ok, info = pcall(C_LFGList.GetSearchResultInfo, entry.resultID)
                if ok and type(info) == "table" then
                    if info.numMembers == 1 then
                        soloCount = soloCount + 1
                    else
                        groupCount = groupCount + 1
                    end
                end

                count = count + 1
                if count <= 3 then
                    local ok2, counts = pcall(C_LFGList.GetSearchResultMemberCounts, entry.resultID)
                    if ok2 and type(counts) == "table" then
                        local parts = {}
                        for _, cinfo in ipairs(CLASS_INFO) do
                            local n = counts[cinfo.file] or 0
                            if n > 0 then table.insert(parts, format("%s=%d", cinfo.name, n)) end
                        end
                        local roleParts = {}
                        if (counts["TANK"] or 0) > 0 then table.insert(roleParts, "T=" .. counts["TANK"]) end
                        if (counts["HEALER"] or 0) > 0 then table.insert(roleParts, "H=" .. counts["HEALER"]) end
                        if (counts["DAMAGER"] or 0) > 0 then table.insert(roleParts, "D=" .. counts["DAMAGER"]) end

                        local nm = ok and type(info) == "table" and info.numMembers or "?"
                        print(format("  Entry %d (rid=%d, members=%s): %s | %s",
                            count, entry.resultID, tostring(nm),
                            table.concat(parts, ", "),
                            table.concat(roleParts, ", ")))
                    end
                end
            end
        end
        print(format("  Solo players: %d | Groups: %d", soloCount, groupCount))
    end

    -- Active filters
    print("  --- Active filters ---")
    local any = false
    for role, active in pairs(activePlayerRoles) do
        if active then print("    Find Players Role: " .. role); any = true end
    end
    for classId, active in pairs(activeClasses) do
        if active then
            for _, ci in ipairs(CLASS_INFO) do
                if ci.id == classId then print("    Find Players Class: " .. ci.name); any = true end
            end
        end
    end
    for role, active in pairs(activeGroupRoles) do
        if active then print("    Find Groups: " .. role .. " needed"); any = true end
    end
    if not any then print("    (none)") end
end

----------------------------------------------------------------------
-- SLASH COMMANDS
----------------------------------------------------------------------
SLASH_LFGFILTER1 = "/lfgf"
SLASH_LFGFILTER2 = "/lfgfilter"
SlashCmdList["LFGFILTER"] = function(msg)
    msg = strlower(msg or "")
    if msg == "reset" then
        ClearAllFilters()
    elseif msg == "hide" then
        if filterPanel then filterPanel:Hide() end
    elseif msg == "show" then
        if filterPanel then filterPanel:Show() end
    elseif msg == "debug" then
        DumpFrameInfo()
    else
        print("|cff00ff00[LFG Filter]|r Commands:")
        print("  /lfgf show  - Show filter panel")
        print("  /lfgf hide  - Hide filter panel")
        print("  /lfgf reset - Reset all filters")
        print("  /lfgf debug - Dump debug info")
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("LFG_UPDATE")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local initialized = false

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        LFGFilterDB = LFGFilterDB or {}
        print("|cff00ff00[LFG Filter]|r loaded. Type /lfgf for commands.")
    end

    if not initialized then
        lfgParent = _G["LFGParentFrame"]
        lfgBrowseFrame = _G["LFGBrowseFrame"]

        if lfgParent and lfgBrowseFrame then
            if CreateFilterPanel() then
                initialized = true
                RestoreFilterState()
            end
        end
    end
end)
