-- luacheck: read globals UnitClass UnitLevel GetNumGuildMembers GameTooltip
local _, ns = ...

-- "My ad" tab: the player ad of this character or, with invite rights,
-- the guild's ad, as four numbered steps. On the right a live preview of
-- how others see the ad and the publish controls.
local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local UI = ns.UI
local Ads = ns.Ads
local Search = ns.Search
local MyAds = ns.MyAds
local Filters = ns.Filters

local SIDE_WIDTH = 282
local GAP = 8
local STEP_X = 48
local VERY_GOOD = 75

local MODE_PLAYER, MODE_GUILD = "player", "guild"

local function SameDraft(draft, ad)
	return ad ~= nil and draft.roles == (ad.r or 0) and draft.goals == ad.g and draft.times == ad.t
		and draft.lang == ad.l and Ads.CleanText(draft.text) == ad.x
end

-- Gold pill with role icon and label.
local function RolePill(parent, role, onToggle)
	local pill = W.Chip(parent, function(self)
		self:SetActive(not self.active)
		onToggle(self.active)
	end)
	pill:SetHeight(26)
	local icon = W.RoleIcon(pill, 18, role.bit)
	icon:SetPoint("LEFT", 5, 0)
	pill.text:ClearAllPoints()
	pill.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	pill.text:SetText(role.label)
	pill:SetWidth(5 + 18 + 6 + pill.text:GetStringWidth() + 12)
	pill.bit = role.bit
	function pill:SetAllowed(allowed)
		self:SetEnabled(allowed)
		self:SetAlpha(allowed and 1 or 0.4)
	end
	return pill
end

local function Build(content)
	local tab = { mode = MODE_PLAYER }
	local controls = {}

	local form = W.Panel(content)
	form:SetPoint("TOPLEFT")
	form:SetPoint("BOTTOMRIGHT", -(SIDE_WIDTH + GAP), 0)

	local function Draft()
		return tab.mode == MODE_GUILD and tab.guildDraft or MyAds.GetPlayerDraft()
	end

	local function Changed()
		tab:UpdateLive()
	end

	-- Mode switch and identity
	controls.playerMode = W.Chip(form, function()
		tab.mode = MODE_PLAYER
		tab:Refresh()
	end)
	controls.playerMode:SetLabel(L.MODE_PLAYER)
	controls.playerMode:SetWidth(124)
	controls.playerMode:SetHeight(26)
	controls.playerMode:SetPoint("TOPLEFT", 14, -12)
	controls.guildMode = W.Chip(form, function()
		tab.mode = MODE_GUILD
		tab.guildDraft = MyAds.GetGuildDraft()
		tab:Refresh()
	end)
	controls.guildMode:SetLabel(L.MODE_GUILD)
	controls.guildMode:SetWidth(124)
	controls.guildMode:SetHeight(26)
	controls.guildMode:SetPoint("LEFT", controls.playerMode, "RIGHT", -1, 0)
	controls.guildMode:SetMotionScriptsWhileDisabled(true)
	controls.guildMode:HookScript("OnEnter", function(self)
		if not self:IsEnabled() then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L.MODE_GUILD, 1, 1, 1)
			GameTooltip:AddLine(Ads.GetGuild() and L.NOTE_OTHER_GUILD_CANNOT or L.NOTE_OTHER_GUILD_NONE, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	controls.guildMode:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	controls.identity = W.Text(form, "GameFontHighlight", W.MUTED)
	controls.identity:SetPoint("LEFT", controls.guildMode, "RIGHT", 14, 0)
	controls.identity:SetPoint("RIGHT", form, "RIGHT", -14, 0)

	-- Numbered steps
	controls.steps = {}
	local function Step(index, y)
		local circle = W.StepCircle(form, index, 24)
		circle:SetPoint("TOPLEFT", 14, y)
		local header = W.Header(form, "", "GameFontNormalLarge")
		header:SetPoint("LEFT", circle, "RIGHT", 10, 0)
		local hint = W.Text(form, "GameFontDisableSmall")
		hint:SetPoint("BOTTOMLEFT", header, "BOTTOMRIGHT", 8, 1)
		controls.steps[index] = { circle = circle, header = header, hint = hint }
		return circle
	end

	-- 1: roles
	local step1 = Step(1, -52)
	controls.roles = {}
	local x = STEP_X
	for i, role in ipairs(C.ROLES) do
		local pill = RolePill(form, role, function(on)
			local draft = Draft()
			draft.roles = C.SetBit(draft.roles, role.bit, on)
			Changed()
		end)
		pill:SetPoint("TOPLEFT", step1, "TOPLEFT", x - 14, -32)
		x = x + pill:GetWidth() + 8
		controls.roles[i] = pill
	end

	-- 2: goals and language
	local step2 = Step(2, -122)
	controls.goals = {}
	x = STEP_X
	for i, goal in ipairs(C.GOALS) do
		local chip = W.Chip(form, function(self)
			self:SetActive(not self.active)
			local draft = Draft()
			draft.goals = C.SetBit(draft.goals, goal.bit, self.active)
			Changed()
		end)
		chip:SetLabel(goal.label)
		chip:SetHeight(26)
		chip:SetWidth(math.max(64, chip:GetWidth()))
		chip:SetPoint("TOPLEFT", step2, "TOPLEFT", x - 14, -32)
		chip.bit = goal.bit
		x = x + chip:GetWidth() + 6
		controls.goals[i] = chip
	end
	local langHeader = W.Header(form, L.FILTER_LANGUAGE, "GameFontNormalLarge")
	langHeader:SetPoint("TOPLEFT", 346, -124)
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
	controls.lang:SetPoint("TOPLEFT", 346, -150)

	-- 3: play times with presets
	local step3 = Step(3, -192)
	controls.grid = W.TimeGrid(form, 34, 18, true, function(mask)
		Draft().times = mask
		Changed()
	end)
	controls.grid:SetPoint("TOPLEFT", step3, "TOPLEFT", STEP_X - 14, -30)
	local weekend, evenings = 0, 0
	for slot = 1, #C.SLOTS do
		weekend = C.SetBit(C.SetBit(weekend, C.TimeBit(6, slot), true), C.TimeBit(7, slot), true)
	end
	for day = 1, #C.DAYS do
		evenings = C.SetBit(evenings, C.TimeBit(day, 2), true)
	end
	local presets = {
		{ L.PRESET_WEEKEND, weekend },
		{ L.PRESET_EVENINGS, evenings },
		{ L.PRESET_NONE, 0 },
	}
	for slot, preset in ipairs(presets) do
		local link = W.LinkButton(form, preset[1], function()
			Draft().times = preset[2]
			controls.grid:SetMask(preset[2])
			Changed()
		end)
		local rowEnd = controls.grid.rowEnds[slot]
		link:SetPoint("TOPLEFT", controls.grid, "TOPLEFT", rowEnd.x + 4, rowEnd.y - 2)
	end

	-- 4: text
	local step4 = Step(4, -310)
	controls.text = W.TextArea(form, 400, 64, C.MAX_TEXT, function(text)
		Draft().text = text
		Changed()
	end)
	controls.text:SetPoint("TOPLEFT", step4, "TOPLEFT", STEP_X - 14, -32)
	controls.text:SetPoint("RIGHT", form, "RIGHT", -14, 0)
	local textHint = W.Text(form, "GameFontDisableSmall")
	textHint:SetPoint("TOPLEFT", controls.text, "BOTTOMLEFT", 0, -4)
	textHint:SetText(L.TEXT_HINT)

	--------------------------------------------------------------------------
	-- Preview
	--------------------------------------------------------------------------

	local preview = W.Panel(content)
	preview:SetPoint("TOPRIGHT")
	preview:SetSize(SIDE_WIDTH, 214)
	controls.previewHeader = W.Header(preview, "", "GameFontNormalLarge")
	controls.previewHeader:SetPoint("TOPLEFT", 14, -14)

	local card = W.Panel(preview, { 0.1, 0.1, 0.1, 1 }, { 0.79, 0.635, 0.29, 1 })
	card:SetPoint("TOPLEFT", 12, -40)
	card:SetPoint("TOPRIGHT", -12, -40)
	card:SetHeight(112)
	controls.cardClass = W.ClassIcon(card, 36)
	controls.cardClass:SetPoint("TOPLEFT", 10, -10)
	controls.cardEmblem = W.GuildEmblem(card, 36)
	controls.cardEmblem:SetPoint("TOPLEFT", 10, -10)
	controls.cardName = W.Text(card, "GameFontNormal")
	controls.cardName:SetPoint("TOPLEFT", 54, -10)
	controls.cardName:SetPoint("RIGHT", -10, 0)
	controls.cardName:SetWordWrap(false)
	controls.cardText = W.Text(card, "GameFontHighlightSmall", W.TEXT)
	controls.cardText:SetPoint("TOPLEFT", controls.cardName, "BOTTOMLEFT", 0, -5)
	controls.cardText:SetPoint("RIGHT", -10, 0)
	controls.cardText:SetJustifyV("TOP")
	controls.cardText:SetMaxLines(3)
	controls.cardText:SetSpacing(2)
	controls.cardTags = W.GoalTags(card)
	controls.cardTags:SetPoint("BOTTOMLEFT", 54, 8)
	controls.cardStrip = W.WeekStrip(card, 8)
	controls.cardStrip:SetPoint("BOTTOMRIGHT", -10, 14)

	controls.matches = W.Text(preview, "GameFontHighlightSmall", W.MUTED)
	controls.matches:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 2, -10)
	controls.matches:SetPoint("RIGHT", preview, "RIGHT", -14, 0)
	controls.matches:SetSpacing(2)

	--------------------------------------------------------------------------
	-- Publish
	--------------------------------------------------------------------------

	local side = W.Panel(content)
	side:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", 0, -GAP)
	side:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 0, -GAP)
	side:SetPoint("BOTTOM", content, "BOTTOM")

	controls.badge = W.Panel(side)
	controls.badge:SetHeight(22)
	controls.badge:SetPoint("TOPLEFT", 14, -14)
	controls.badgeDot = W.Dot(controls.badge, 8, W.GOLD)
	controls.badgeDot:SetPoint("LEFT", 8, 0)
	controls.badgeText = W.Text(controls.badge, "GameFontNormalSmall")
	controls.badgeText:SetPoint("LEFT", controls.badgeDot, "RIGHT", 6, 0)

	controls.info = W.Text(side, "GameFontHighlightSmall", W.MUTED)
	controls.info:SetPoint("TOPLEFT", controls.badge, "BOTTOMLEFT", 0, -8)
	controls.info:SetPoint("RIGHT", side, "RIGHT", -14, 0)
	controls.info:SetSpacing(3)

	local buttonWidth = SIDE_WIDTH - 28
	controls.publish = W.Button(side, L.PUBLISH, buttonWidth, function()
		local draft = Draft()
		draft.text = Ads.CleanText(controls.text:GetText())
		local ad, err
		if tab.mode == MODE_GUILD then
			ad, err = MyAds.PublishGuild(draft)
		else
			ad, err = MyAds.PublishPlayer(draft)
		end
		if ad then
			ns.db.settings.seenIntro = true
			ns:Print(L.PUBLISHED)
		else
			ns:Print(err)
		end
		tab:Refresh()
	end)
	controls.publish:SetPoint("TOPLEFT", controls.info, "BOTTOMLEFT", 0, -12)

	local function PublishedAd()
		if tab.mode == MODE_GUILD then
			return MyAds.GetGuildAd()
		end
		return MyAds.GetPlayerAd()
	end

	controls.discard = W.Button(side, L.DISCARD, (buttonWidth - 8) / 2, function()
		local ad = PublishedAd()
		if ad then
			local draft = Draft()
			draft.roles, draft.goals, draft.times, draft.lang, draft.text = ad.r or 0, ad.g, ad.t, ad.l, ad.x
			tab:Refresh()
		end
	end)
	controls.discard:SetPoint("TOPLEFT", controls.publish, "BOTTOMLEFT", 0, -8)
	controls.withdraw = W.Button(side, L.WITHDRAW, (buttonWidth - 8) / 2, function()
		if tab.mode == MODE_GUILD then
			MyAds.WithdrawGuild()
		else
			MyAds.WithdrawPlayer()
		end
		ns:Print(L.WITHDRAWN)
		tab:Refresh()
	end)
	controls.withdraw:SetPoint("TOPRIGHT", controls.publish, "BOTTOMRIGHT", 0, -8)

	controls.otherNote = W.Text(side, "GameFontDisableSmall")
	controls.otherNote:SetPoint("BOTTOMLEFT", 14, 14)
	controls.otherNote:SetPoint("RIGHT", side, "RIGHT", -14, 0)
	controls.otherNote:SetSpacing(2)

	--------------------------------------------------------------------------
	-- Updates
	--------------------------------------------------------------------------

	local function SetBadge(label, color)
		controls.badgeText:SetText(label)
		W.Color(controls.badgeText, color)
		controls.badgeDot:SetColor(color)
		controls.badge:SetBackdropColor(color[1] * 0.2, color[2] * 0.2, color[3] * 0.2, 1)
		controls.badge:SetBackdropBorderColor(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6, 1)
		controls.badge:SetWidth(controls.badgeText:GetStringWidth() + 30)
	end

	function tab:UpdatePublish()
		local ad = PublishedAd()
		local draft = Draft()
		local canEdit = self.mode == MODE_PLAYER or Ads.CanInvite()
		if ad then
			local dirty = not SameDraft(draft, ad)
			if dirty then
				SetBadge(L.STATUS_CHANGED, W.GOLD)
			else
				SetBadge(L.STATUS_ACTIVE, W.GREEN)
			end
			local lines = {
				L.INFO_ACTIVE:format(W.Duration(GetServerTime() - ad.v), W.Duration(Ads.ExpiresIn(ad))),
			}
			if self.mode == MODE_GUILD then
				lines[#lines + 1] = L.INFO_CHANGED_BY:format(Ads.OwnerName(ad.o))
				lines[#lines + 1] = L.NOTE_GUILD_AD
			else
				lines[#lines + 1] = L.NOTE_RENEW
			end
			controls.info:SetText(table.concat(lines, "\n"))
			controls.publish:SetText(L.PUBLISH_CHANGES)
			controls.publish:SetEnabled(canEdit and dirty)
			controls.discard:SetEnabled(dirty)
			controls.withdraw:SetEnabled(canEdit)
		else
			SetBadge(L.STATUS_NOT_PUBLISHED, W.MUTED)
			controls.info:SetText(L.INFO_NOT_PUBLISHED .. "\n" .. (self.mode == MODE_GUILD and L.NOTE_GUILD_AD or L.NOTE_RENEW))
			controls.publish:SetText(L.PUBLISH)
			controls.publish:SetEnabled(canEdit)
			controls.discard:SetEnabled(false)
			controls.withdraw:SetEnabled(false)
		end
	end

	function tab:UpdatePreview()
		local draft = Draft()
		local text = Ads.CleanText(draft.text or "")
		if self.mode == MODE_GUILD then
			controls.cardClass:Hide()
			controls.cardEmblem:Show()
			local guild = Ads.GetGuild() or "?"
			controls.cardEmblem:SetGuild(guild, Ads.GetFactionCode())
			controls.cardName:SetText("|cffffd100" .. guild .. "|r")
		else
			controls.cardEmblem:Hide()
			controls.cardClass:Show()
			local _, classFile = UnitClass("player")
			controls.cardClass:SetClass(classFile)
			controls.cardName:SetText("|c" .. W.ClassColorHex(classFile) .. Ads.OwnerName(ns:GetPlayerFullName() or "?")
				.. "|r  |cff9d9d9d" .. C.ClassName(classFile) .. " · " .. UnitLevel("player") .. "|r")
		end
		controls.cardText:SetText(text ~= "" and text or ("|cff9d9d9d" .. L.NO_TEXT .. "|r"))
		controls.cardTags:SetGoals(draft.goals)
		controls.cardStrip:SetMask(draft.times)

		-- What the other side has on offer, scored against the draft.
		local otherKind = self.mode == MODE_GUILD and Ads.KIND_PLAYER or Ads.KIND_GUILD
		local faction = Ads.GetFactionCode()
		local filter = { kind = otherKind, factions = { [faction] = true }, sameMode = true }
		local profile = { goals = draft.goals or 0, times = draft.times or 0, roles = draft.roles or 0, lang = draft.lang }
		local results = Search.Run(filter, profile)
		local good = 0
		for _, result in ipairs(results) do
			if (result.score or 0) >= VERY_GOOD then
				good = good + 1
			end
		end
		local format = self.mode == MODE_GUILD and L.PREVIEW_MATCHES_PLAYERS or L.PREVIEW_MATCHES_GUILDS
		controls.matches:SetText(format:format(#results, good))
	end

	function tab:UpdateSteps()
		local draft = Draft()
		local steps = controls.steps
		steps[1].circle:SetDone((draft.roles or 0) > 0)
		steps[2].circle:SetDone((draft.goals or 0) > 0 and draft.lang ~= nil)
		steps[3].circle:SetDone((draft.times or 0) > 0)
		steps[4].circle:SetDone(Ads.CleanText(draft.text or "") ~= "")
	end

	-- Everything that follows the form while typing.
	function tab:UpdateLive()
		self:UpdateSteps()
		self:UpdatePreview()
		self:UpdatePublish()
	end

	function tab:Refresh()
		local guild = Ads.GetGuild()
		local canInvite = Ads.CanInvite()
		local guildAllowed = guild ~= nil and canInvite
		controls.guildMode:SetEnabled(guildAllowed)
		controls.guildMode:SetAlpha(guildAllowed and 1 or 0.5)
		if self.mode == MODE_GUILD and not guildAllowed then
			self.mode = MODE_PLAYER
		end
		if self.mode == MODE_GUILD and not self.guildDraft then
			self.guildDraft = MyAds.GetGuildDraft()
		end
		controls.playerMode:SetActive(self.mode == MODE_PLAYER)
		controls.guildMode:SetActive(self.mode == MODE_GUILD)

		local draft = Draft()
		local faction = Filters.FactionName(Ads.GetFactionCode())
		local steps = controls.steps
		if self.mode == MODE_GUILD then
			local members = GetNumGuildMembers()
			controls.identity:SetText("|cffffd100<" .. guild .. ">|r · " .. faction
				.. ((members or 0) > 0 and (" · " .. L.MEMBERS:format(members)) or "") .. " " .. L.GUILD_LOCKED)
			steps[1].header:SetText(L.STEP_ROLES_GUILD)
			steps[1].hint:SetText(L.STEP_ROLES_GUILD_HINT)
			steps[2].header:SetText(L.STEP_GOALS_GUILD)
			steps[3].header:SetText(L.STEP_TIMES_GUILD)
			steps[4].header:SetText(L.STEP_TEXT_GUILD)
			controls.previewHeader:SetText(L.PREVIEW_GUILD)
			controls.otherNote:SetText(L.NOTE_OTHER_PLAYER)
		else
			local name = ns:GetPlayerFullName() or "?"
			local _, classFile = UnitClass("player")
			controls.identity:SetText("|c" .. W.ClassColorHex(classFile) .. Ads.OwnerName(name) .. "|r · "
				.. C.ClassName(classFile) .. " " .. UnitLevel("player") .. " · " .. faction .. " · "
				.. (guild and ("<" .. guild .. ">") or L.NO_GUILD) .. " " .. L.FROM_CHARACTER)
			steps[1].header:SetText(L.STEP_ROLES)
			steps[1].hint:SetText(L.STEP_ROLES_HINT)
			steps[2].header:SetText(L.STEP_GOALS)
			steps[3].header:SetText(L.STEP_TIMES)
			steps[4].header:SetText(L.STEP_TEXT)
			controls.previewHeader:SetText(L.PREVIEW_PLAYER)
			controls.otherNote:SetText(guild and (canInvite and L.NOTE_OTHER_GUILD_CAN or L.NOTE_OTHER_GUILD_CANNOT)
				or L.NOTE_OTHER_GUILD_NONE)
		end
		steps[3].hint:SetText(L.STEP_TIMES_HINT)

		local classRoles = self.mode == MODE_PLAYER and C.ClassRoles(select(2, UnitClass("player"))) or 7
		for _, pill in ipairs(controls.roles) do
			local possible = C.HasBit(classRoles, pill.bit)
			if not possible and C.HasBit(draft.roles, pill.bit) then
				draft.roles = C.SetBit(draft.roles, pill.bit, false)
			end
			pill:SetActive(C.HasBit(draft.roles, pill.bit))
			pill:SetAllowed(possible)
		end
		for _, chip in ipairs(controls.goals) do
			chip:SetActive(C.HasBit(draft.goals, chip.bit))
		end
		controls.lang:Refresh()
		controls.grid:SetMask(draft.times)
		controls.text:SetText(draft.text)
		self:UpdateLive()
	end

	-- Keeps the form as typed; only status and preview follow new versions.
	function tab:OnAdsChanged()
		self:UpdatePreview()
		self:UpdatePublish()
	end

	return tab
end

UI.RegisterTab(3, L.TAB_MY_AD, Build)
