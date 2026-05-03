IncognitoExtinguished = LibStub("AceAddon-3.0"):NewAddon("IncognitoExtinguished",
                                                         "AceConsole-3.0",
                                                         "AceEvent-3.0",
                                                         "AceHook-3.0")

local Addon = IncognitoExtinguished
local L = LibStub("AceLocale-3.0"):GetLocale("IncognitoExtinguished", true)
local characterName

local function Trim(value)
    return string.gsub(string.gsub(value or "", "^%s+", ""), "%s+$", "")
end

local function NormalizeChannelName(value)
    value = string.lower(Trim(tostring(value or "")))
    value = string.gsub(value, "^%d+%.%s*", "")
    value = string.gsub(value, "[%s%-%_]", "")
    return value
end

local EXCLUDED_CUSTOM_CHANNELS = {
    general = true,
    world = true,
    localdefense = true,
    trade = true,
    xtensionxtooltip2 = true,
}

local function IsExcludedCustomChannel(channelName)
    local normalized = NormalizeChannelName(channelName)
    if EXCLUDED_CUSTOM_CHANNELS[normalized] then return true end
    if string.find(normalized, "^general") then return true end
    if string.find(normalized, "^trade") then return true end
    if string.find(normalized, "^localdefense") then return true end
    return false
end

local function StartsWithCommandSymbol(msg)
    if type(msg) ~= "string" then return false end
    local firstChar = string.match(msg, "^%s*(.)")
    return firstChar and string.find("/!#@?*", firstChar, 1, true)
end

local function ContainsRPEmoteMarker(msg)
    if type(msg) ~= "string" then return false end
    return string.find(msg, "%*.-%*") ~= nil
end

local function GetInstanceKind()
    if type(GetInstanceInfo) ~= "function" then return nil end
    local _, instanceType = GetInstanceInfo()
    return instanceType
end

local function IsChannelNamed(target, configuredNames)
    if not configuredNames or configuredNames == "" or not target then return false end
    if type(GetChannelName) ~= "function" then return false end

    local _, channelName = GetChannelName(target)
    channelName = channelName or target
    channelName = NormalizeChannelName(channelName)

    for name in string.gmatch(configuredNames, "([^,]+)") do
        if NormalizeChannelName(name) == channelName then return true end
    end

    return false
end

local function GetChannelNameForTarget(target)
    if not target or type(GetChannelName) ~= "function" then return nil end
    local _, channelName = GetChannelName(target)
    return channelName or target
end

local function GetCustomChannelValues()
    local values = {}
    local count = 0

    if type(GetChannelList) == "function" then
        local channels = {GetChannelList()}
        for i = 1, #channels do
            local value = channels[i]
            if type(value) == "string" then
                local display = Trim(value)
                local normalized = NormalizeChannelName(display)
                if display ~= "" and normalized ~= "" and not IsExcludedCustomChannel(display) then
                    values[normalized] = display
                    count = count + 1
                end
            end
        end
    end

    if count == 0 then
        values[""] = L["customChannelNone"]
    end

    return values
end

local function IsEnabledCustomChannel(profile, target)
    local channelName = GetChannelNameForTarget(target)
    local normalized = NormalizeChannelName(channelName)
    if normalized == "" or IsExcludedCustomChannel(channelName) then return false end
    return profile.enabledCustomChannels and profile.enabledCustomChannels[normalized]
end

local function IsFixedChannelEnabled(profile, target)
    local channelName = NormalizeChannelName(GetChannelNameForTarget(target))
    if channelName == "" then return false end

    if profile.general and string.find(channelName, "^general") then return true end
    if profile.trade and string.find(channelName, "^trade") then return true end
    if profile.world and (channelName == "world" or channelName == "worldchat") then return true end

    return false
end

local function ShouldHideForCharacterName(profile)
    if not profile.hideOnMatchingCharName or not characterName then return false end
    local configured = string.lower(profile.name or "")
    local current = string.lower(characterName or "")
    if configured == "" then return false end
    if configured == current then return true end

    local mode = profile.partialMatchMode or "disabled"
    if mode == "start" then
        return string.sub(current, 1, #configured) == configured
    elseif mode == "anywhere" then
        return string.find(current, configured, 1, true) ~= nil
    elseif mode == "end" then
        return string.sub(current, -#configured) == configured
    end

    return false
end

local function ExtractPlayerGUID(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and string.match(value, "^Player%-") then
            return value
        end
    end
end

local function GetMinimapButtonPosition(angle)
    local radians = math.rad(angle or 225)
    return math.cos(radians) * 80, math.sin(radians) * 80
end

local function GetCursorMinimapAngle()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    local dx, dy = px - mx, py - my

    if math.atan2 then
        return math.deg(math.atan2(dy, dx))
    elseif atan2 then
        return math.deg(atan2(dy, dx))
    end

    if dx == 0 then
        return dy >= 0 and 90 or -90
    end

    local angle = math.deg(math.atan(dy / dx))
    if dx < 0 then angle = angle + 180 end
    return angle
end

local Options = {
    name = "Incognito Extinguished",
    type = "group",
    args = {
        generalSettings = {
            name = L["generalSettings"],
            type = "group",
            inline = true,
            order = 1,
            get = function(item) return Addon.db.profile[item[#item]] end,
            set = function(item, value) Addon.db.profile[item[#item]] = value end,
            args = {
                name = {
                    order = 1,
                    type = "input",
                    name = L["name"],
                    desc = L["name_desc"],
                    width = "normal",
                },
                enable = {
                    order = 2,
                    type = "toggle",
                    name = L["enable"],
                    desc = L["enable_desc"],
                    width = "normal",
                },
                bracketStyle = {
                    order = 3,
                    type = "select",
                    name = L["bracketStyle"],
                    desc = L["bracketStyle_desc"],
                    values = {
                        paren = "(round)",
                        square = "[square]",
                        curly = "{curly}",
                        angle = "<angle>",
                    },
                    sorting = {"paren", "square", "curly", "angle"},
                    width = "normal",
                },
                hideOnMatchingCharName = {
                    order = 4,
                    type = "toggle",
                    name = L["hideOnMatchingCharName"],
                    desc = L["hideOnMatchingCharName_desc"],
                    width = "normal",
                },
                partialMatchMode = {
                    order = 5,
                    type = "select",
                    name = L["partialMatchMode"],
                    desc = L["partialMatchMode_desc"],
                    values = {
                        disabled = L["partialMatchMode_disabled"],
                        start = L["partialMatchMode_start"],
                        anywhere = L["partialMatchMode_anywhere"],
                        ["end"] = L["partialMatchMode_end"],
                    },
                    sorting = {"disabled", "start", "anywhere", "end"},
                    disabled = function() return not Addon.db.profile.hideOnMatchingCharName end,
                    width = "normal",
                },
                ignoreLeadingSymbols = {
                    order = 6,
                    type = "toggle",
                    name = L["ignoreLeadingSymbols"],
                    desc = L["ignoreLeadingSymbols_desc"],
                    width = "normal",
                },
                colorizePrefix = {
                    order = 7,
                    type = "toggle",
                    name = L["colorizePrefix"],
                    desc = L["colorizePrefix_desc"],
                    width = "normal",
                },
                hideMinimap = {
                    order = 8,
                    type = "toggle",
                    name = L["hideMinimap"],
                    desc = L["hideMinimap_desc"],
                    width = "normal",
                    set = function(item, value)
                        Addon.db.profile[item[#item]] = value
                        Addon:RefreshMinimapButton()
                    end,
                },
                debug = {
                    order = 9,
                    type = "toggle",
                    name = L["debug"],
                    desc = L["debug_desc"],
                    width = "normal",
                },
            },
        },
        chatTargets = {
            name = L["chatTargets"],
            type = "group",
            inline = true,
            order = 2,
            get = function(item) return Addon.db.profile[item[#item]] end,
            set = function(item, value) Addon.db.profile[item[#item]] = value end,
            args = {
                guild = {
                    order = 1,
                    type = "toggle",
                    name = L["guild"],
                    desc = L["guild_desc"],
                    width = "normal",
                },
                party = {
                    order = 2,
                    type = "toggle",
                    name = L["party"],
                    desc = L["party_desc"],
                    width = "normal",
                },
                dungeon = {
                    order = 3,
                    type = "toggle",
                    name = L["dungeon"],
                    desc = L["dungeon_desc"],
                    width = "normal",
                },
                raid = {
                    order = 4,
                    type = "toggle",
                    name = L["raid"],
                    desc = L["raid_desc"],
                    width = "normal",
                },
                battleground = {
                    order = 5,
                    type = "toggle",
                    name = L["battleground"],
                    desc = L["battleground_desc"],
                    width = "normal",
                },
                arena = {
                    order = 6,
                    type = "toggle",
                    name = L["arena"],
                    desc = L["arena_desc"],
                    width = "normal",
                },
                general = {
                    order = 7,
                    type = "toggle",
                    name = L["general"],
                    desc = L["general_desc"],
                    width = "normal",
                },
                trade = {
                    order = 8,
                    type = "toggle",
                    name = L["trade"],
                    desc = L["trade_desc"],
                    width = "normal",
                },
                world = {
                    order = 9,
                    type = "toggle",
                    name = L["world"],
                    desc = L["world_desc"],
                    width = "normal",
                },
                customChannelSelect = {
                    order = 10,
                    type = "select",
                    name = L["customChannelSelect"],
                    desc = L["customChannelSelect_desc"],
                    values = GetCustomChannelValues,
                    get = function() return Addon.db.profile.selectedCustomChannel or "" end,
                    set = function(_, value) Addon.db.profile.selectedCustomChannel = value end,
                    width = "normal",
                },
                customChannelToggle = {
                    order = 11,
                    type = "execute",
                    name = function()
                        local selected = Addon.db.profile.selectedCustomChannel or ""
                        if selected == "" then return L["customChannelToggle"] end
                        if Addon.db.profile.enabledCustomChannels and Addon.db.profile.enabledCustomChannels[selected] then
                            return L["customChannelDisable"]
                        end
                        return L["customChannelEnable"]
                    end,
                    desc = L["customChannelToggle_desc"],
                    disabled = function()
                        local selected = Addon.db.profile.selectedCustomChannel or ""
                        return selected == ""
                    end,
                    func = function()
                        local selected = Addon.db.profile.selectedCustomChannel or ""
                        if selected == "" then return end
                        Addon.db.profile.enabledCustomChannels = Addon.db.profile.enabledCustomChannels or {}
                        Addon.db.profile.enabledCustomChannels[selected] = not Addon.db.profile.enabledCustomChannels[selected] or nil
                        LibStub("AceConfigRegistry-3.0"):NotifyChange("IncognitoExtinguished Options")
                    end,
                    width = "normal",
                },
            },
        },
    },
}

local Defaults = {
    profile = {
        enable = true,
        name = "",
        guild = true,
        party = false,
        dungeon = false,
        raid = false,
        battleground = false,
        arena = false,
        world_chat = false,
        general = false,
        trade = false,
        world = false,
        selectedCustomChannel = "",
        enabledCustomChannels = {},
        debug = false,
        hideOnMatchingCharName = true,
        partialMatchMode = "disabled",
        bracketStyle = "paren",
        ignoreLeadingSymbols = true,
        colorizePrefix = true,
        hideMinimap = false,
        minimapAngle = 225,
    },
}

function Addon:MigrateChannelSettings()
    local profile = self.db.profile
    profile.enabledCustomChannels = profile.enabledCustomChannels or {}

    if profile.world_chat then
        profile.general = true
        profile.trade = true
        profile.world = true
        profile.world_chat = false
    end

    if profile.globalChannelEnabled then
        local preset = profile.globalChannelPreset
        if preset == "general" then profile.general = true end
        if preset == "trade" then profile.trade = true end
        if preset == "world" or preset == "global" then profile.world = true end

        if preset == "custom" and profile.channel and profile.channel ~= "" then
            for name in string.gmatch(profile.channel, "([^,]+)") do
                local normalized = NormalizeChannelName(name)
                if normalized ~= "" and not IsExcludedCustomChannel(name) then
                    profile.enabledCustomChannels[normalized] = true
                    if profile.selectedCustomChannel == "" then
                        profile.selectedCustomChannel = normalized
                    end
                end
            end
        end

        profile.globalChannelEnabled = false
    end
end

local SlashOptions = {
    type = "group",
    handler = Addon,
    get = function(item) return Addon.db.profile[item[#item]] end,
    set = function(item, value) Addon.db.profile[item[#item]] = value end,
    args = {
        name = {
            type = "input",
            name = L["name"],
            desc = L["name_desc"],
            set = function(_, value)
                Addon.db.profile.name = value
                Addon:Print("Incognito name set to: |cFF00FF00" .. value .. "|r")
            end,
        },
        config = {
            type = "execute",
            name = L["config"],
            desc = L["config_desc"],
            func = function() Addon:OpenConfig() end,
        },
        help = {
            type = "execute",
            name = "Help",
            desc = "Show slash command help.",
            func = function() Addon:PrintHelp() end,
        },
    },
}

function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("IncognitoExtinguishedDB", Defaults, "Default")

    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("IncognitoExtinguished Slash", SlashOptions)
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("IncognitoExtinguished Options", Options)
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("IncognitoExtinguished Profiles", profiles)

    local dialog = LibStub("AceConfigDialog-3.0")
    self.optionFrames = {
        main = dialog:AddToBlizOptions("IncognitoExtinguished Options", "IncognitoExtinguished"),
        profiles = dialog:AddToBlizOptions("IncognitoExtinguished Profiles", "Profiles", "IncognitoExtinguished"),
    }

    characterName = UnitName("player")
    self:MigrateChannelSettings()
    self:RegisterChatFilters()
    self:RegisterChatCommand("inc", "SlashCommand")
    self:RegisterChatCommand("incognito", "SlashCommand")
    self:RegisterChatCommand("incex", "SlashCommand")
    self:RegisterRawSlashCommands()
    self:CreateMinimapButton()
    self:RawHook("SendChatMessage", true)
    self:Print("Loaded. Use /incex or click the minimap icon for options.")
    self:Safe_Print(L["Loaded"])
end

function Addon:OnDisable()
    if self:IsHooked("SendChatMessage") then
        self:Unhook("SendChatMessage")
    end
    self:UnregisterChatFilters()
end

function Addon:OpenConfig()
    local dialog = LibStub("AceConfigDialog-3.0", true)
    if dialog and dialog.Open then
        dialog:Open("IncognitoExtinguished Options")
        return
    end

    if self.optionFrames and self.optionFrames.main and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.optionFrames.main)
        InterfaceOptionsFrame_OpenToCategory(self.optionFrames.main)
    else
        self:PrintHelp()
    end
end

function Addon:RegisterRawSlashCommands()
    SLASH_INCOGNITOEXTINGUISHED1 = "/incex"
    SLASH_INCOGNITOEXTINGUISHED2 = "/incognitoextinguished"
    SLASH_INCOGNITOEXTINGUISHED3 = "/inc"
    SLASH_INCOGNITOEXTINGUISHED4 = "/incognito"
    SlashCmdList["INCOGNITOEXTINGUISHED"] = function(input)
        Addon:SlashCommand(input)
    end

    if hash_SlashCmdList then
        hash_SlashCmdList["/incex"] = "INCOGNITOEXTINGUISHED"
        hash_SlashCmdList["/incognitoextinguished"] = "INCOGNITOEXTINGUISHED"
        hash_SlashCmdList["/inc"] = "INCOGNITOEXTINGUISHED"
        hash_SlashCmdList["/incognito"] = "INCOGNITOEXTINGUISHED"
    end
end

function Addon:CreateMinimapButton()
    if self.minimapButton then
        self:RefreshMinimapButton()
        return
    end

    local button = CreateFrame("Button", "IncognitoExtinguishedMinimapButton", Minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetPoint("TOPLEFT", 7, -5)
    button.icon = icon

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Incognito Extinguished")
        GameTooltip:AddLine(L["minimapLeftClick"], 1, 1, 1)
        GameTooltip:AddLine(L["minimapRightClick"], 1, 1, 1)
        GameTooltip:AddLine(L["minimapDrag"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(_, clickedButton)
        if clickedButton == "RightButton" then
            Addon.db.profile.enable = not Addon.db.profile.enable
            Addon:Print("Incognito Extinguished " .. (Addon.db.profile.enable and "|cFF00FF00enabled|r" or "|cFFFF0000disabled|r"))
        else
            Addon:OpenConfig()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            Addon.db.profile.minimapAngle = GetCursorMinimapAngle()
            Addon:RefreshMinimapButton()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)

    self.minimapButton = button
    self:RefreshMinimapButton()
end

function Addon:RefreshMinimapButton()
    local button = self.minimapButton
    if not button then return end

    if self.db.profile.hideMinimap then
        button:Hide()
        return
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", GetMinimapButtonPosition(self.db.profile.minimapAngle))
    button:Show()
end

function Addon:GetNamePrefix()
    local pairs = {
        paren = {"(", ")"},
        square = {"[", "]"},
        curly = {"{", "}"},
        angle = {"<", ">"},
    }
    local pair = pairs[self.db.profile.bracketStyle or "paren"] or pairs.paren
    return pair[1] .. (self.db.profile.name or "") .. pair[2] .. ": "
end

function Addon:ShouldPrefix(chatType, target)
    local profile = self.db.profile
    if not profile.enable or not profile.name or profile.name == "" then return false end
    if profile.ignoreLeadingSymbols and StartsWithCommandSymbol(self._activeMessage) then return false end
    if profile.ignoreLeadingSymbols and ContainsRPEmoteMarker(self._activeMessage) then return false end
    if ShouldHideForCharacterName(profile) then return false end

    local instanceType = GetInstanceKind()

    if profile.guild and (chatType == "GUILD" or chatType == "OFFICER") then return true end
    if profile.raid and (chatType == "RAID" or chatType == "RAID_LEADER" or chatType == "RAID_WARNING") then return true end

    if chatType == "PARTY" then
        if instanceType == "party" then return profile.dungeon end
        return profile.party
    end

    if chatType == "INSTANCE_CHAT" then
        if instanceType == "pvp" then return profile.battleground end
        if instanceType == "arena" then return profile.arena end
        if instanceType == "party" then return profile.dungeon end
        if instanceType == "raid" then return profile.raid end
    end

    if chatType == "CHANNEL" then
        self:Safe_Print("Channel send target=" .. tostring(target) .. " name=" .. tostring(GetChannelNameForTarget(target)))
        return IsFixedChannelEnabled(profile, target) or IsEnabledCustomChannel(profile, target)
    end

    return false
end

function Addon:SendChatMessage(msg, chatType, language, target)
    self._activeMessage = msg
    if self:ShouldPrefix(chatType, target) then
        msg = self:GetNamePrefix() .. msg
    end
    self._activeMessage = nil

    self.hooks.SendChatMessage(msg, chatType, language, target)
end

function Addon:ChatPrefixColorFilter(frame, event, msg, author, ...)
    if not (self.db and self.db.profile and self.db.profile.enable and self.db.profile.colorizePrefix) then
        return false
    end
    if type(msg) ~= "string" then return false end

    local pre, open, name, close, afterClose, colonSpaces, rest =
        string.match(msg, "^(%s*)([%(%[%{%<])([^%(%[%{%<%]%}%>]+)([%)%]%}%>])(%s*):(%s*)(.*)$")
    if not open then return false end

    local expectedClose = {["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">"}
    if expectedClose[open] ~= close then return false end

    local classFile
    local guid = ExtractPlayerGUID(...)
    if guid and GetPlayerInfoByGUID then
        local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
        if ok then classFile = class end
    end

    local colors = (type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS) or RAID_CLASS_COLORS
    local color = colors and classFile and colors[classFile]
    if not color then return false end

    local hex = string.format("|cff%02x%02x%02x",
                              math.floor((color.r or 1) * 255 + 0.5),
                              math.floor((color.g or 1) * 255 + 0.5),
                              math.floor((color.b or 1) * 255 + 0.5))
    local newMsg = string.format("%s%s%s%s|r%s%s:%s%s", pre or "", open, hex, name or "",
                                 close, afterClose or "", colonSpaces or "", rest or "")
    return false, newMsg, author, ...
end

function Addon:RegisterChatFilters()
    if self._filtersRegistered or type(ChatFrame_AddMessageEventFilter) ~= "function" then return end

    self._filterFunc = function(frame, event, msg, author, ...)
        return Addon:ChatPrefixColorFilter(frame, event, msg, author, ...)
    end

    self._filterEvents = {
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_CHANNEL",
    }

    for _, event in ipairs(self._filterEvents) do
        ChatFrame_AddMessageEventFilter(event, self._filterFunc)
    end

    self._filtersRegistered = true
end

function Addon:UnregisterChatFilters()
    if not self._filtersRegistered or type(ChatFrame_RemoveMessageEventFilter) ~= "function" then return end

    for _, event in ipairs(self._filterEvents) do
        ChatFrame_RemoveMessageEventFilter(event, self._filterFunc)
    end

    self._filtersRegistered = false
end

function Addon:Safe_Print(msg)
    if self.db and self.db.profile and self.db.profile.debug then
        self:Print(msg)
    end
end

function Addon:PrintHelp()
    self:Print(L["slashHelpHeader"])
    self:Print("/inc - Open the config window")
    self:Print("/inc name <name> - Set your incognito name prefix")
    self:Print("/inc debug - Toggle debug mode")
    self:Print("/incex - Open the config window")
end

function Addon:SlashCommand(input)
    input = Trim(input or "")
    local command, rest = string.match(input, "^(%S+)%s*(.*)$")
    command = command and string.lower(command) or ""

    if command == "help" then
        self:PrintHelp()
    elseif command == "name" then
        local newName = string.match(rest, '^"(.-)"$') or rest
        if newName and newName ~= "" then
            self.db.profile.name = newName
            self:Print("Incognito name set to: |cFF00FF00" .. newName .. "|r")
        else
            self:Print("Usage: /inc name <name>")
        end
    elseif command == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        self:Print("Debug mode " .. (self.db.profile.debug and "|cFF00FF00enabled|r" or "|cFFFF0000disabled|r"))
    else
        self:OpenConfig()
    end
end
