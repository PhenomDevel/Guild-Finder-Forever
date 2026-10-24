-- luacheck: read globals UnitClass UnitLevel GetNumGuildMembers
local _, ns = ...

-- "My ad" tab: edit and publish the character's player ad or, with invite
-- rights, the guild's ad. A switch at the top picks which one.
local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local UI = ns.UI
local Ads = ns.Ads
local MyAds = ns.MyAds

local SIDE_WIDTH = 270
local GAP = 8

local MODE_PLAYER, MODE_GUILD = "player", "guild"

local function SameDraft(draft, ad)
	return ad ~= nil and draft.roles == (ad.r or 0) and draft.goals == ad.g and draft.times == ad.t
		and draft.lang == ad.l and Ads.CleanText(draft.text) == ad.x
end

local function Build(content)
	local tab = { mode = MODE_PLAYER }
	local controls = {}

	local form = W.Panel(content)
	form:SetPoint("TOPLEFT")
	form:SetPoint("BOTTOMRIGHT", -(SIDE_WIDTH + GAP), 0)
	local side = W.Panel(content)
	side:SetPoint("TOPRIGHT")
	side:SetPoint("BOTTOMRIGHT")
	side:SetWidth(SIDE_WIDTH)

	local function Draft()
		return tab.mode == MODE_GUILD and tab.guildDraft or MyAds.GetPlayerDraft()
	end

	local function Changed()
		tab:UpdateSide()
	end

	-- Mode switch
	controls.playerMode = W.Button(form, L.MODE_PLAYER, 150, function()
		tab.mode = MODE_PLAYER
		tab:Refresh()
	end)
	controls.playerMode:SetPoint("TOPLEFT", 14, -12)
	controls.guildMode = W.Button(form, L.MODE_GUILD, 150, function()
		tab.mode = MODE_GUILD
		tab.guildDraft = MyAds.GetGuildDraft()
		tab:Refresh()
	end)
	controls.guildMode:SetPoint("LEFT", controls.playerMode, "RIGHT", 8, 0)

	-- Identity line
	controls.identityHeader = W.Header(form, L.MY_PLAYER_AD)
	controls.identityHeader:SetPoint("TOPLEFT", 16, -46)
	local identity = W.Panel(form)
	identity:SetPoint("TOPLEFT", 14, -62)
	identity:SetPoint("TOPRIGHT", -14, -62)
	identity:SetHeight(26)
	identity:SetBackdropColor(0.086, 0.07, 0.047, 1)
	controls.identity = W.Text(identity, "GameFontHighlight")
	controls.identity:SetPoint("LEFT", 8, 0)
	controls.identityNote = W.Text(identity, "GameFontDisableSmall")
	controls.identityNote:SetPoint("RIGHT", -8, 0)

	-- Roles
	controls.rolesHeader = W.Header(form, L.ROLES)
	controls.rolesHeader:SetPoint("TOPLEFT", 16, -102)
	controls.roles = {}
	for i, role in ipairs(C.ROLES) do
		local check = W.Checkbox(form, role.label, function(on)
			local draft = Draft()
			draft.roles = C.SetBit(draft.roles, role.bit, on)
			Changed()
		end)
		check:SetPoint("TOPLEFT", 12, -118 - (i - 1) * 22)
		check.bit = role.bit
		controls.roles[i] = check
	end

	-- Goals
	local goalsHeader = W.Header(form, L.FILTER_GOALS)
	goalsHeader:SetPoint("TOPLEFT", 196, -102)
	controls.goals = {}
	for i, goal in ipairs(C.GOALS) do
		local check = W.Checkbox(form, goal.label, function(on)
			local draft = Draft()
			draft.goals = C.SetBit(draft.goals, goal.bit, on)
			Changed()
		end)
		local column = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		check:SetPoint("TOPLEFT", 192 + column * 90, -118 - row * 22)
		check.bit = goal.bit
		controls.goals[i] = check
	end

	-- Language
	local langHeader = W.Header(form, L.FILTER_LANGUAGE)
	langHeader:SetPoint("TOPLEFT", 196, -170)
	controls.lang = W.Dropdown(form, 150, function()
		local list = {}
		for _, lang in ipairs(C.LANGUAGES) do
			list[#list + 1] = { value = lang.key, label = lang.label }
		end
		return list
	end, function()
		return Draft().lang
	end, function(value)
		Draft().lang = value
		Changed()
	end)
	controls.lang:SetPoint("TOPLEFT", 194, -186)

	-- Times
	controls.timesHeader = W.Header(form, L.PLAY_TIMES_EDIT)
	controls.timesHeader:SetPoint("TOPLEFT", 16, -222)
	controls.grid = W.TimeGrid(form, 30, 18, true, function(mask)
		Draft().times = mask
		Changed()
	end)
	controls.grid:SetPoint("TOPLEFT", 16, -240)

	-- Text
	local textHeader = W.Header(form, L.SHORT_TEXT)
	textHeader:SetPoint("TOPLEFT", 16, -330)
	controls.text = W.TextArea(form, 470, 64, C.MAX_TEXT, function(text)
		Draft().text = text
		Changed()
	end)
	controls.text:SetPoint("TOPLEFT", 14, -346)
	controls.text:SetPoint("RIGHT", form, "RIGHT", -14, 0)

	-- Side panel
	local statusHeader = W.Header(side, L.STATUS)
	statusHeader:SetPoint("TOPLEFT", 14, -14)
	controls.status = W.Text(side, "GameFontNormal")
	controls.status:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -6)
	controls.info = W.Text(side, "GameFontHighlightSmall", W.TEXT)
	controls.info:SetPoint("TOPLEFT", controls.status, "BOTTOMLEFT", 0, -10)
	controls.info:SetPoint("RIGHT", side, "RIGHT", -14, 0)
	controls.info:SetSpacing(4)
	controls.note = W.Text(side, "GameFontHighlightSmall", W.MUTED)
	controls.note:SetPoint("TOPLEFT", controls.info, "BOTTOMLEFT", 0, -12)
	controls.note:SetPoint("RIGHT", side, "RIGHT", -14, 0)
	controls.note:SetSpacing(2)

	controls.publish = W.Button(side, L.PUBLISH, SIDE_WIDTH - 28, function()
		local draft = Draft()
		draft.text = Ads.CleanText(controls.text:GetText())
		local ad, err
		if tab.mode == MODE_GUILD then
			ad, err = MyAds.PublishGuild(draft)
		else
			ad, err = MyAds.PublishPlayer(draft)
		end
		if ad then
			ns:Print(L.PUBLISHED)
		else
			ns:Print(err)
		end
		tab:Refresh()
	end)
	controls.publish:SetPoint("TOPLEFT", controls.note, "BOTTOMLEFT", 0, -16)
	controls.withdraw = W.Button(side, L.WITHDRAW, SIDE_WIDTH - 28, function()
		if tab.mode == MODE_GUILD then
			MyAds.WithdrawGuild()
		else
			MyAds.WithdrawPlayer()
		end
		ns:Print(L.WITHDRAWN)
		tab:Refresh()
	end)
	controls.withdraw:SetPoint("TOPLEFT", controls.publish, "BOTTOMLEFT", 0, -8)

	local otherHeader = W.Header(side, "")
	otherHeader:SetPoint("BOTTOMLEFT", 14, 64)
	controls.otherHeader = otherHeader
	controls.otherNote = W.Text(side, "GameFontHighlightSmall", W.MUTED)
	controls.otherNote:SetPoint("TOPLEFT", otherHeader, "BOTTOMLEFT", 0, -6)
	controls.otherNote:SetPoint("RIGHT", side, "RIGHT", -14, 0)
	controls.otherNote:SetSpacing(2)

	local function PublishedAd()
		if tab.mode == MODE_GUILD then
			return MyAds.GetGuildAd()
		end
		return MyAds.GetPlayerAd()
	end

	function tab:UpdateSide()
		local ad = PublishedAd()
		local draft = Draft()
		local canEdit = self.mode == MODE_PLAYER or Ads.CanInvite()
		if ad then
			local dirty = not SameDraft(draft, ad)
			controls.status:SetText(dirty and ("|cffe6b43a" .. L.STATUS_CHANGED .. "|r") or ("|cff4fb34a" .. L.STATUS_ACTIVE .. "|r"))
			local lines = {
				L.INFO_CHANGED:format(W.Duration(GetServerTime() - ad.v)),
				L.INFO_EXPIRES:format(W.Duration(Ads.ExpiresIn(ad))),
			}
			if self.mode == MODE_GUILD then
				table.insert(lines, 1, L.INFO_CHANGED_BY:format(Ads.OwnerName(ad.o)))
			end
			controls.info:SetText(table.concat(lines, "\n"))
			controls.publish:SetText(L.PUBLISH_CHANGES)
			controls.publish:SetEnabled(canEdit and dirty)
			controls.withdraw:SetEnabled(canEdit)
		else
			controls.status:SetText("|cffa8a090" .. L.STATUS_NOT_PUBLISHED .. "|r")
			controls.info:SetText(L.INFO_NOT_PUBLISHED)
			controls.publish:SetText(L.PUBLISH)
			controls.publish:SetEnabled(canEdit)
			controls.withdraw:SetEnabled(false)
		end
	end

	function tab:Refresh()
		local guild = Ads.GetGuild()
		local canInvite = Ads.CanInvite()
		controls.guildMode:SetEnabled(guild ~= nil and canInvite)
		if self.mode == MODE_GUILD and not (guild and canInvite) then
			self.mode = MODE_PLAYER
		end
		if self.mode == MODE_GUILD and not self.guildDraft then
			self.guildDraft = MyAds.GetGuildDraft()
		end
		controls.playerMode:SetButtonState(self.mode == MODE_PLAYER and "PUSHED" or "NORMAL", self.mode == MODE_PLAYER)
		controls.guildMode:SetButtonState(self.mode == MODE_GUILD and "PUSHED" or "NORMAL", self.mode == MODE_GUILD)

		local draft = Draft()
		local faction = Ads.GetFactionCode() == "H" and L.FACTION_HORDE or L.FACTION_ALLIANCE
		if self.mode == MODE_GUILD then
			controls.identityHeader:SetText(L.MY_GUILD_AD:upper())
			local members = GetNumGuildMembers()
			controls.identity:SetText("|cffffd100<" .. guild .. ">|r  |cffa8a090" .. faction
				.. ((members or 0) > 0 and (" · " .. L.MEMBERS:format(members)) or "") .. "|r")
			controls.identityNote:SetText(L.GUILD_LOCKED)
			controls.rolesHeader:SetText(L.WANTED_ROLES:upper())
			controls.timesHeader:SetText(L.RAID_TIMES_EDIT:upper())
			controls.note:SetText(L.NOTE_GUILD_AD)
			controls.otherHeader:SetText(L.MY_PLAYER_AD:upper())
			controls.otherNote:SetText(L.NOTE_OTHER_PLAYER)
		else
			controls.identityHeader:SetText(L.MY_PLAYER_AD:upper())
			local name = ns:GetPlayerFullName() or "?"
			local _, classFile = UnitClass("player")
			controls.identity:SetText("|c" .. W.ClassColorHex(classFile) .. Ads.OwnerName(name) .. "|r  |cffa8a090"
				.. C.ClassName(classFile) .. " · " .. L.LEVEL:format(UnitLevel("player")) .. " · " .. faction .. " · "
				.. (guild and ("<" .. guild .. ">") or L.NO_GUILD) .. "|r")
			controls.identityNote:SetText(L.FROM_CHARACTER)
			controls.rolesHeader:SetText(L.ROLES:upper())
			controls.timesHeader:SetText(L.PLAY_TIMES_EDIT:upper())
			controls.note:SetText(L.NOTE_PLAYER_AD)
			controls.otherHeader:SetText(L.MY_GUILD_AD:upper())
			controls.otherNote:SetText(guild and (canInvite and L.NOTE_OTHER_GUILD_CAN or L.NOTE_OTHER_GUILD_CANNOT) or L.NOTE_OTHER_GUILD_NONE)
		end

		local classRoles = self.mode == MODE_PLAYER and C.ClassRoles(select(2, UnitClass("player"))) or 7
		for _, check in ipairs(controls.roles) do
			local possible = C.HasBit(classRoles, check.bit)
			if not possible and C.HasBit(draft.roles, check.bit) then
				draft.roles = C.SetBit(draft.roles, check.bit, false)
			end
			check:SetChecked(C.HasBit(draft.roles, check.bit))
			check:SetLabelEnabled(possible)
		end
		for _, check in ipairs(controls.goals) do
			check:SetChecked(C.HasBit(draft.goals, check.bit))
		end
		controls.lang:Refresh()
		controls.grid:SetMask(draft.times)
		controls.text:SetText(draft.text)
		self:UpdateSide()
	end

	-- Keeps the form as typed; only the status reflects new versions.
	function tab:OnAdsChanged()
		self:UpdateSide()
	end

	return tab
end

UI.RegisterTab(3, L.TAB_MY_AD, Build)
