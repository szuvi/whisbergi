--[[
  WhisBergi.lua
  A Cataclysm Classic addon that whispers quest progress updates to selected friends.
  Usage:
  - Select a quest in your quest log and click "Track in WhisBergi"
  - Add friends in the options panel (comma-separated)
  - Friends will receive whispers when quest objectives update

  Commands:
  - /whisbergi or /wbergi - opens the options panel
]]

------------------------------
-- 1) Variables
------------------------------
-- Saved variables defaults
local defaults = {
    questId = nil,
    questTitle = "None",
    friends = {} -- List of friends to whisper
}

-- Local variables
local previousObjectives = {} -- For detecting quest objective changes
local settingdCategory = nil -- For the settings panel registration
local isInitialized = false

-- Forward declare UI elements that need to be accessed by functions
local trackedQuestText
local trackButton
local friendsEditBox

------------------------------
-- 4) UI Elements
------------------------------
-- Quest Log Button
trackButton = CreateFrame("Button", "WhisBergiTrackButton", QuestLogFrame, "UIPanelButtonTemplate")
trackButton:SetSize(140, 21)
trackButton:SetText("Track in WhisBergi")
trackButton:SetPoint("TOPRIGHT", QuestLogFrame, "TOPRIGHT", -40, -12)

-- Options Panel
local WhisBergiOptionsPanel = CreateFrame("Frame", "WhisBergiOptionsPanel", UIParent)
WhisBergiOptionsPanel.name = "WhisBergi"

local title = WhisBergiOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("WhisBergi Settings")

local trackedQuestLabel = WhisBergiOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
trackedQuestLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -30)
trackedQuestLabel:SetText("Currently tracked quest:")

trackedQuestText = WhisBergiOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
trackedQuestText:SetPoint("TOPLEFT", trackedQuestLabel, "BOTTOMLEFT", 0, -5)
trackedQuestText:SetText("None")

local friendsLabel = WhisBergiOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
friendsLabel:SetPoint("TOPLEFT", trackedQuestText, "BOTTOMLEFT", 0, -20)
friendsLabel:SetText("Friends to whisper (comma-separated):")

friendsEditBox = CreateFrame("EditBox", "WhisBergiFriendsEditBox", WhisBergiOptionsPanel, "InputBoxTemplate")
friendsEditBox:SetSize(300, 25)
friendsEditBox:SetPoint("TOPLEFT", friendsLabel, "BOTTOMLEFT", 0, -8)
friendsEditBox:SetAutoFocus(false)

------------------------------
-- 2) Helper Functions
------------------------------
-- Merges default values with saved variables
local function MergeDefaults(saved, defaults)
    if type(saved) ~= "table" then saved = {} end
    if type(defaults) ~= "table" then return saved end
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = v
        end
    end
    return saved
end

-- Finds quest log index for a given quest ID
local function GetQuestLogIndexByID(questID)
    if not questID then return nil end
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader, _, _, _, thisQuestID = GetQuestLogTitle(i)
        if (not isHeader) and thisQuestID == questID then
            return i
        end
    end
    return nil
end

-- Updates the tracked quest display in options
local function UpdateTrackedQuestDisplay()
    if WhisBergiDB.questTitle then
        trackedQuestText:SetText(WhisBergiDB.questTitle)
    else
        trackedQuestText:SetText("None")
    end
end

-- Updates track button state based on quest selection
local function UpdateTrackButton()
    local selectedQuest = GetQuestLogSelection()
    if selectedQuest then
        local _, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(selectedQuest)
        if not isHeader then
            if questId == WhisBergiDB.questId then
                trackButton:SetEnabled(true)
                trackButton:SetText("|cff00ff00Untrack in WhisBergi|r")
            else
                trackButton:SetEnabled(true)
                trackButton:SetText("Track in WhisBergi")
            end
        else
            trackButton:SetEnabled(false)
            trackButton:SetText("Track in WhisBergi")
        end
    else
        trackButton:SetEnabled(false)
        trackButton:SetText("Track in WhisBergi")
    end
end

-- Parses and saves the friends list from the edit box
local function SaveFriendsFromEditBox()
    local friendsText = friendsEditBox:GetText() or ""
    local friendsTable = {}
    for friend in string.gmatch(friendsText, "([^,]+)") do
        friend = strtrim(friend)
        if friend ~= "" then
            table.insert(friendsTable, friend)
        end
    end
    WhisBergiDB.friends = friendsTable
end

-- Updates quest titles in the quest log to show tracking indicator
local function UpdateQuestLogDisplay()
    if not WhisBergiDB.questId then return end

    -- First, clean up any existing tracking icons
    for i = 1, GetNumQuestLogEntries() do
        local questLogTitleFrame = _G["QuestLogTitle" .. i]
        if questLogTitleFrame and questLogTitleFrame.whisbergiIcon then
            questLogTitleFrame.whisbergiIcon:Hide()
        end
    end

    -- Add icon to the currently tracked quest
    local questLogIndex = GetQuestLogIndexByID(WhisBergiDB.questId)
    if questLogIndex then
        local questLogTitleFrame = _G["QuestLogTitle" .. questLogIndex]
        if questLogTitleFrame then
            if not questLogTitleFrame.whisbergiIcon then
                local icon = questLogTitleFrame:CreateTexture(nil, "OVERLAY")
                icon:SetSize(16, 16)
                icon:SetPoint("RIGHT", questLogTitleFrame, "RIGHT", -5, 0)
                icon:SetTexture("Interface\\MINIMAP\\TRACKING\\Target")
                questLogTitleFrame.whisbergiIcon = icon
            end
            questLogTitleFrame.whisbergiIcon:Show()
        end
    end
end

------------------------------
-- 3) Quest Tracking Logic
------------------------------
-- Updates the currently tracked quest when selected in quest log
local function UpdateTrackedQuest()
    local selectedQuest = GetQuestLogSelection()
    if selectedQuest then
        local questTitle, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(selectedQuest)
        if not isHeader and questId then
            if questId == WhisBergiDB.questId then
                -- Untrack the quest
                WhisBergiDB.questId = nil
                WhisBergiDB.questTitle = "None"
                print("|cff00ff00[WhisBergi]|r Stopped tracking: " .. questTitle)
            else
                -- Track the quest
                WhisBergiDB.questId = questId
                WhisBergiDB.questTitle = questTitle
                print("|cff00ff00[WhisBergi]|r Now tracking: " .. questTitle)
            end
            UpdateTrackedQuestDisplay()
            UpdateTrackButton()
        end
    end
end

-- Checks for quest objective updates and sends whispers
local function CheckQuestProgressUpdate()
    if not WhisBergiDB.questId then return end

    local questLogIndex = GetQuestLogIndexByID(WhisBergiDB.questId)
    if not questLogIndex then
        -- Quest not found in log, but we'll keep tracking it
        -- in case it becomes available again
        return
    end

    local questTitle, _, _, isHeader = GetQuestLogTitle(questLogIndex)
    if not questTitle or isHeader then return end

    local numLeaderboards = GetNumQuestLeaderBoards(questLogIndex)
    if not numLeaderboards or numLeaderboards == 0 then return end

    -- Get current objective states
    local newObjectives = {}
    for i = 1, numLeaderboards do
        local leaderboardText = GetQuestLogLeaderBoard(i, questLogIndex)
        newObjectives[i] = leaderboardText or ""
    end

    -- Check for changes and send whispers
    for i, newVal in ipairs(newObjectives) do
        if previousObjectives[i] ~= newVal then
            if WhisBergiDB.friends and #WhisBergiDB.friends > 0 then
                for _, friendName in ipairs(WhisBergiDB.friends) do
                    SendChatMessage(newVal, "WHISPER", nil, friendName)
                end
            end
        end
    end

    previousObjectives = newObjectives
end

------------------------------
-- 5) Event Handling and UI Setup
------------------------------
-- Set up button click handler after all functions are defined
trackButton:SetScript("OnClick", UpdateTrackedQuest)

-- Register events
local WhisBergiFrame = CreateFrame("Frame")
WhisBergiFrame:RegisterEvent("ADDON_LOADED")
WhisBergiFrame:RegisterEvent("VARIABLES_LOADED")
WhisBergiFrame:RegisterEvent("QUEST_LOG_UPDATE")

-- Event handler
WhisBergiFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "WhisBergi" then
        -- Initialize saved variables
        WhisBergiDB = MergeDefaults(WhisBergiDB, defaults)

        -- Register options panel
        if Settings and Settings.RegisterCanvasLayoutCategory then
            settingdCategory = Settings.RegisterCanvasLayoutCategory(WhisBergiOptionsPanel, "WhisBergi")
            Settings.RegisterAddOnCategory(settingdCategory)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(WhisBergiOptionsPanel)
        end

        UpdateTrackedQuestDisplay()

    elseif event == "VARIABLES_LOADED" then
        if not IsAddOnLoaded("Blizzard_OptionsUI") then
            LoadAddOn("Blizzard_OptionsUI")
        end

    elseif event == "QUEST_LOG_UPDATE" then
        CheckQuestProgressUpdate()
        UpdateTrackedQuestDisplay()
        if QuestLogFrame and QuestLogFrame:IsVisible() then
            UpdateTrackButton()
        end
    end
end)

-- Hook quest log updates
hooksecurefunc("QuestLog_Update", UpdateTrackButton)

-- Update options panel when shown
WhisBergiOptionsPanel:SetScript("OnShow", function(self)
    UpdateTrackedQuestDisplay()
    friendsEditBox:SetText(table.concat(WhisBergiDB.friends, ", "))
end)

-- Save friends list when edited
friendsEditBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        SaveFriendsFromEditBox()
    end
end)

------------------------------
-- 6) Slash Commands
------------------------------
SLASH_WHISBERGI1 = '/wbergi'
SLASH_WHISBERGI2 = '/whisbergi'
SlashCmdList["WHISBERGI"] = function(msg)
    Settings.OpenToCategory(settingdCategory:GetID())
end
