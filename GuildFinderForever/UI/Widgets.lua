-- luacheck: read globals C_ClassColor C_Texture RAID_CLASS_COLORS CLASS_ICON_TCOORDS GameTooltip
local _, ns = ...

-- Small widget kit for the window, built on the game's standard templates
-- plus a few own pieces (chips, role and class icons, emblems).
local W = {}
ns.Widgets = W

local C = ns.Constants
local Serializer = ns.Serializer

W.GOLD = { 1, 0.82, 0 }
W.TEXT = { 0.9, 0.9, 0.9 }
W.WHITE = { 1, 1, 1 }
W.MUTED = { 0.62, 0.62, 0.62 }
W.GREEN = { 0.12, 1, 0 }
W.SOFT_GREEN = { 0.56, 0.94, 0.54 }
W.TAG = { 0.84, 0.75, 0.54 }

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local BACKDROP = { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 }

local function Color(region, color, alpha)
	region:SetTextColor(color[1], color[2], color[3], alpha or 1)
end
W.Color = Color

-- Dark inset panel with a thin border.
function W.Panel(parent, bg, border)
	local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	panel:SetBackdrop(BACKDROP)
	bg = bg or { 0.05, 0.05, 0.05, 0.95 }
	border = border or { 0.17, 0.17, 0.17, 1 }
	panel:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	panel:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
	return panel
end

function W.Text(parent, font, color)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	if color then
		Color(text, color)
	end
	text:SetJustifyH("LEFT")
	return text
end

-- Section heading in the game's yellow.
function W.Header(parent, label, font)
	local text = W.Text(parent, font or "GameFontNormal", W.GOLD)
	text:SetText(label)
	return text
end

function W.Button(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(label)
	button:SetSize(width or (button:GetFontString():GetStringWidth() + 30), 24)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
end

-- Small link-style text button.
function W.LinkButton(parent, label, onClick)
	local button = CreateFrame("Button", nil, parent)
	local text = W.Text(button, "GameFontDisableSmall")
	text:SetPoint("LEFT")
	button:SetFontString(text)
	button:SetNormalFontObject("GameFontDisableSmall")
	button:SetHighlightFontObject("GameFontHighlightSmall")
	button:SetText(label)
	button:SetSize(text:GetStringWidth() + 2, 16)
	button:SetScript("OnClick", onClick)
	return button
end

-- Single-line input. onChange(text) runs on user input.
function W.EditBox(parent, width, onChange)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput and onChange then
			onChange(self:GetText())
		end
	end)
	return box
end

-- Rounded-look search field with a magnifier and placeholder text.
function W.SearchBox(parent, width, placeholder, onChange)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	if box.Instructions then
		box.Instructions:SetText(placeholder)
	end
	box:HookScript("OnTextChanged", function(self, userInput)
		if userInput and onChange then
			onChange(self:GetText())
		end
	end)
	-- The clear button changes the text without userInput.
	if box.clearButton then
		box.clearButton:HookScript("OnClick", function()
			if onChange then
				onChange("")
			end
		end)
	end
	return box
end

-- Multi-line text field with a character counter below it.
function W.TextArea(parent, width, height, maxLetters, onChange)
	local frame = W.Panel(parent, { 0, 0, 0, 1 }, { 0.3, 0.3, 0.3, 1 })
	frame:SetSize(width, height)

	local box = CreateFrame("EditBox", nil, frame)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetMaxLetters(maxLetters)
	box:SetPoint("TOPLEFT", 7, -6)
	box:SetPoint("BOTTOMRIGHT", -7, 6)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	frame:EnableMouse(true)
	frame:SetScript("OnMouseDown", function()
		box:SetFocus()
	end)

	local counter = W.Text(frame, "GameFontDisableSmall")
	counter:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
	local function UpdateCounter()
		counter:SetFormattedText("%d / %d", box:GetNumLetters(), maxLetters)
	end
	box:SetScript("OnTextChanged", function(self, userInput)
		UpdateCounter()
		if userInput and onChange then
			onChange(self:GetText())
		end
	end)

	frame.editBox = box
	frame.counter = counter
	function frame:SetText(text)
		box:SetText(text or "")
		UpdateCounter()
	end
	function frame:GetText()
		return box:GetText()
	end
	UpdateCounter()
	return frame
end

-- Dropdown button. setup(root) fills the menu (MenuUtil descriptions).
function W.Menu(parent, width, setup)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width)
	dropdown:SetupMenu(function(_, root)
		setup(root)
	end)
	function dropdown:Refresh()
		self:GenerateMenu()
	end
	return dropdown
end

-- Dropdown with radio entries: options = list or function returning
-- { value, label }; get() returns the selected value, set(value) stores it.
function W.Dropdown(parent, width, options, get, set)
	return W.Menu(parent, width, function(root)
		local list = type(options) == "function" and options() or options
		for _, option in ipairs(list) do
			root:CreateRadio(option.label, function()
				return get() == option.value
			end, function()
				set(option.value)
			end)
		end
	end)
end

function W.Tooltip(frame, title, text)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if text then
			GameTooltip:AddLine(text, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

--------------------------------------------------------------------------------
-- Chips
--------------------------------------------------------------------------------

-- Pill-shaped toggle. :SetActive(bool) switches between the gold (active)
-- and the grey look; removable chips show a "×".
function W.Chip(parent, onClick)
	local chip = CreateFrame("Button", nil, parent, "BackdropTemplate")
	chip:SetBackdrop(BACKDROP)
	chip:SetHeight(22)
	local text = W.Text(chip, "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	chip.text = text
	chip:SetHighlightTexture(WHITE8)
	chip:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.08)
	chip:SetScript("OnClick", function(self)
		if onClick then
			onClick(self)
		end
	end)
	function chip:SetLabel(label, removable)
		text:SetText(removable and (label .. "  |cff9d9d9d×|r") or label)
		self:SetWidth(text:GetStringWidth() + 20)
	end
	function chip:SetActive(active)
		self.active = active
		if active then
			self:SetBackdropColor(0.24, 0.19, 0.09, 1)
			self:SetBackdropBorderColor(0.79, 0.635, 0.29, 1)
			Color(text, W.GOLD)
		else
			self:SetBackdropColor(0.13, 0.13, 0.13, 1)
			self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
			Color(text, W.WHITE)
		end
	end
	chip:SetActive(false)
	return chip
end

-- Lays chips out left to right from anchor; returns the right edge offset.
function W.FlowChips(chips, parent, x, y, gap)
	for _, chip in ipairs(chips) do
		if chip:IsShown() then
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
			x = x + chip:GetWidth() + (gap or 6)
		end
	end
	return x
end

-- Small read-only label pill for goals.
function W.Tag(parent)
	local tag = W.Panel(parent, { 0.16, 0.16, 0.16, 1 }, { 0.3, 0.3, 0.3, 1 })
	tag:SetHeight(18)
	local text = W.Text(tag, "GameFontHighlightSmall", W.TAG)
	text:SetPoint("CENTER")
	function tag:SetLabel(label)
		text:SetText(label)
		self:SetWidth(text:GetStringWidth() + 14)
	end
	return tag
end

-- Pool of tags for a goal mask; :SetGoals(mask) returns the right edge.
function W.GoalTags(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(1, 18)
	holder.tags = {}
	for i = 1, #C.GOALS do
		holder.tags[i] = W.Tag(holder)
	end
	function holder:SetGoals(mask)
		local shown = {}
		for i, goal in ipairs(C.GOALS) do
			local tag = self.tags[i]
			if C.HasBit(mask or 0, goal.bit) then
				tag:SetLabel(goal.label)
				tag:Show()
				shown[#shown + 1] = tag
			else
				tag:Hide()
			end
		end
		local width = W.FlowChips(shown, self, 0, 0, 4) - 4
		self:SetWidth(math.max(1, width))
		return width
	end
	return holder
end

-- Horizontal 1 px line.
function W.Divider(parent)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetColorTexture(0.3, 0.25, 0.15, 0.8)
	return line
end

local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- Round texture of the given colour (rgb).
local function Circle(frame, layer, inset, color)
	local tex = frame:CreateTexture(nil, layer)
	tex:SetPoint("TOPLEFT", inset, -inset)
	tex:SetPoint("BOTTOMRIGHT", -inset, inset)
	tex:SetColorTexture(color[1], color[2], color[3], 1)
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	return tex
end

-- Numbered step circle; :SetDone(bool) turns it green.
function W.StepCircle(parent, number, size)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size or 24, size or 24)
	local ring = Circle(frame, "BACKGROUND", 0, { 0.79, 0.635, 0.29 })
	local fill = Circle(frame, "BORDER", 2, { 0.13, 0.1, 0.05 })
	local text = W.Text(frame, "GameFontNormal", W.GOLD)
	text:SetPoint("CENTER", 0, 0)
	text:SetJustifyH("CENTER")
	text:SetText(number)
	function frame:SetDone(done)
		if done then
			ring:SetColorTexture(0.25, 0.6, 0.2, 1)
			fill:SetColorTexture(0.1, 0.3, 0.08, 1)
			Color(text, W.WHITE)
		else
			ring:SetColorTexture(0.79, 0.635, 0.29, 1)
			fill:SetColorTexture(0.13, 0.1, 0.05, 1)
			Color(text, W.GOLD)
		end
	end
	return frame
end

-- Small coloured dot.
function W.Dot(parent, size, color)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	frame.tex = Circle(frame, "ARTWORK", 0, color)
	function frame:SetColor(c)
		self.tex:SetColorTexture(c[1], c[2], c[3], 1)
	end
	return frame
end

--------------------------------------------------------------------------------
-- Icons
--------------------------------------------------------------------------------

local ROLE_ATLAS = {
	[C.ROLE.TANK] = "groupfinder-icon-role-large-tank",
	[C.ROLE.HEALER] = "groupfinder-icon-role-large-heal",
	[C.ROLE.DAMAGE] = "groupfinder-icon-role-large-dps",
}

local function HasAtlas(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function RoleInfo(bit)
	for _, role in ipairs(C.ROLES) do
		if role.bit == bit then
			return role
		end
	end
end

-- Role icon texture (game atlas, coloured square with letter as fallback).
function W.RoleIcon(parent, size, bit)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	local letter = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	letter:SetPoint("CENTER")
	frame.tex = tex
	function frame:SetRole(roleBit)
		local role = RoleInfo(roleBit)
		if HasAtlas(ROLE_ATLAS[roleBit]) then
			tex:SetAtlas(ROLE_ATLAS[roleBit])
			letter:SetText("")
		elseif role then
			tex:SetColorTexture(role.color[1], role.color[2], role.color[3], 1)
			letter:SetText(role.short)
		end
	end
	if bit then
		frame:SetRole(bit)
	end
	return frame
end

-- Row of role icons; :SetRoles(mask).
function W.RoleIcons(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size * 3 + 6, size)
	holder.icons = {}
	for i, role in ipairs(C.ROLES) do
		holder.icons[i] = W.RoleIcon(holder, size, role.bit)
	end
	function holder:SetRoles(mask)
		local x = 0
		for i, role in ipairs(C.ROLES) do
			local icon = self.icons[i]
			if C.HasBit(mask or 0, role.bit) then
				icon:ClearAllPoints()
				icon:SetPoint("LEFT", x, 0)
				icon:Show()
				x = x + size + 2
			else
				icon:Hide()
			end
		end
	end
	return holder
end

-- Round role toggle for filters and the ad form. onToggle(on).
function W.RoleToggle(parent, size, bit, onToggle)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	local icon = W.RoleIcon(button, size, bit)
	icon:SetAllPoints()
	button.icon = icon
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnClick", function(self)
		self:SetOn(not self.on)
		if onToggle then
			onToggle(self.on)
		end
	end)
	function button:SetOn(on)
		self.on = on
		icon.tex:SetDesaturated(not on)
		icon:SetAlpha(on and 1 or 0.4)
	end
	function button:SetAllowed(allowed)
		self:SetEnabled(allowed)
		if not allowed then
			icon:SetAlpha(0.15)
		else
			self:SetOn(self.on)
		end
	end
	local role = RoleInfo(bit)
	if role then
		W.Tooltip(button, role.label)
	end
	button:SetOn(false)
	return button
end

-- Class icon from the character creation sheet.
function W.ClassIcon(parent, size)
	local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	frame:SetSize(size, size)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 1)
	frame:SetBackdropBorderColor(0.33, 0.33, 0.33, 1)
	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", -1, 1)
	function frame:SetClass(classFile)
		local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
		if coords then
			tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
			tex:SetTexCoord(coords[1] + 0.01, coords[2] - 0.01, coords[3] + 0.01, coords[4] - 0.01)
		else
			tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		local hex = W.ClassColorHex(classFile)
		local r, g, b = tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
		self:SetBackdropBorderColor(r, g, b, 1)
	end
	return frame
end

-- Guild emblem: guilds share no tabard data, so the name picks one of a
-- few shield icons and a border colour.
local EMBLEM_ICONS = {
	"Interface\\Icons\\INV_Shield_01", "Interface\\Icons\\INV_Shield_02", "Interface\\Icons\\INV_Shield_03",
	"Interface\\Icons\\INV_Shield_04", "Interface\\Icons\\INV_Shield_05", "Interface\\Icons\\INV_Shield_06",
	"Interface\\Icons\\INV_Shield_07", "Interface\\Icons\\INV_Shield_08", "Interface\\Icons\\INV_Shield_09",
}
local EMBLEM_COLORS = {
	{ 0.11, 0.25, 0.48 }, { 0.23, 0.11, 0.36 }, { 0.36, 0.11, 0.11 }, { 0.18, 0.23, 0.18 },
	{ 0.36, 0.29, 0.11 }, { 0.1, 0.32, 0.32 },
}

function W.GuildEmblem(parent, size)
	local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	frame:SetSize(size, size)
	frame:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 2 })
	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 3, -3)
	tex:SetPoint("BOTTOMRIGHT", -3, 3)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	function frame:SetGuild(name)
		local hash = Serializer.Hash(name or "")
		tex:SetTexture(EMBLEM_ICONS[hash % #EMBLEM_ICONS + 1])
		local color = EMBLEM_COLORS[math.floor(hash / 16) % #EMBLEM_COLORS + 1]
		self:SetBackdropColor(color[1], color[2], color[3], 1)
		self:SetBackdropBorderColor(0.79, 0.635, 0.29, 1)
	end
	return frame
end

--------------------------------------------------------------------------------
-- Play times
--------------------------------------------------------------------------------

-- Seven small cells: the evening slot Mo–Su (the most telling one).
function W.WeekStrip(parent, cellWidth)
	cellWidth = cellWidth or 10
	local strip = CreateFrame("Frame", nil, parent)
	strip:SetSize(7 * (cellWidth + 2), 6)
	strip.cells = {}
	for day = 1, 7 do
		local cell = strip:CreateTexture(nil, "ARTWORK")
		cell:SetSize(cellWidth, 6)
		cell:SetPoint("LEFT", (day - 1) * (cellWidth + 2), 0)
		strip.cells[day] = cell
	end
	function strip:SetMask(mask)
		for day = 1, 7 do
			local on = C.HasBit(mask or 0, C.TimeBit(day, 2))
			if on then
				self.cells[day]:SetColorTexture(0.79, 0.635, 0.29, 1)
			else
				self.cells[day]:SetColorTexture(0.16, 0.16, 0.16, 1)
			end
		end
	end
	W.Tooltip(strip, ns.L.STRIP_TIP)
	strip:EnableMouse(true)
	return strip
end

-- Match bar plus "94 %" text.
function W.MatchBar(parent, width)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width + 44, 14)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(width, 6)
	bg:SetPoint("LEFT")
	bg:SetColorTexture(0.16, 0.16, 0.16, 1)
	local fill = frame:CreateTexture(nil, "ARTWORK")
	fill:SetHeight(6)
	fill:SetPoint("LEFT")
	local text = W.Text(frame, "GameFontNormalSmall")
	text:SetPoint("LEFT", bg, "RIGHT", 6, 0)
	function frame:SetScore(score)
		if not score then
			fill:Hide()
			text:SetText("–")
			Color(text, W.MUTED)
			return
		end
		local color = W.ScoreColor(score)
		fill:Show()
		fill:SetWidth(math.max(1, width * score / 100))
		fill:SetColorTexture(color[1], color[2], color[3], 1)
		text:SetText(score .. " %")
		Color(text, color)
	end
	return frame
end

function W.ScoreColor(score)
	if score >= 75 then
		return W.GREEN
	elseif score >= 60 then
		return W.GOLD
	end
	return W.MUTED
end

-- 7 × 3 grid of play time slots. interactive: cells toggle on click and
-- onChange(mask) runs. :SetMask(mask, highlight) shows a mask; cells also
-- in highlight get a green frame.
function W.TimeGrid(parent, cellWidth, cellHeight, interactive, onChange)
	local labelWidth = 56
	local gap = 3
	local grid = CreateFrame("Frame", nil, parent)
	grid:SetSize(labelWidth + #C.DAYS * (cellWidth + gap), 16 + #C.SLOTS * (cellHeight + gap))
	grid.mask = 0
	grid.highlight = 0
	grid.cells = {}
	grid.rowEnds = {}

	for day, name in ipairs(C.DAYS) do
		local text = W.Text(grid, "GameFontDisableSmall")
		text:SetPoint("TOPLEFT", labelWidth + (day - 1) * (cellWidth + gap), 0)
		text:SetWidth(cellWidth)
		text:SetJustifyH("CENTER")
		text:SetText(name)
	end

	local function Paint(cell)
		local on = C.HasBit(grid.mask, cell.bit)
		if on then
			cell.fill:SetColorTexture(0.79, 0.635, 0.29, 1)
			cell.border:SetColorTexture(1, 0.82, 0, 1)
		else
			cell.fill:SetColorTexture(0.14, 0.14, 0.14, 1)
			cell.border:SetColorTexture(0.2, 0.2, 0.2, 1)
		end
		if on and C.HasBit(grid.highlight, cell.bit) then
			cell.border:SetColorTexture(W.GREEN[1], W.GREEN[2], W.GREEN[3], 1)
		end
	end

	for slot, name in ipairs(C.SLOTS) do
		local y = -16 - (slot - 1) * (cellHeight + gap)
		local text = W.Text(grid, "GameFontDisableSmall")
		text:SetPoint("TOPLEFT", 0, y - 3)
		text:SetWidth(labelWidth - 4)
		text:SetText(name)
		for day = 1, #C.DAYS do
			local cell = CreateFrame(interactive and "Button" or "Frame", nil, grid)
			cell:SetSize(cellWidth, cellHeight)
			cell:SetPoint("TOPLEFT", labelWidth + (day - 1) * (cellWidth + gap), y)
			cell.border = cell:CreateTexture(nil, "BACKGROUND")
			cell.border:SetAllPoints()
			cell.fill = cell:CreateTexture(nil, "ARTWORK")
			cell.fill:SetPoint("TOPLEFT", 2, -2)
			cell.fill:SetPoint("BOTTOMRIGHT", -2, 2)
			cell.bit = C.TimeBit(day, slot)
			if interactive then
				cell:SetHighlightTexture(WHITE8)
				cell:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.2)
				cell:SetScript("OnClick", function(self)
					grid.mask = C.SetBit(grid.mask, self.bit, not C.HasBit(grid.mask, self.bit))
					Paint(self)
					if onChange then
						onChange(grid.mask)
					end
				end)
			end
			grid.cells[#grid.cells + 1] = cell
			Paint(cell)
		end
		grid.rowEnds[slot] = { x = labelWidth + #C.DAYS * (cellWidth + gap) + 4, y = y }
	end

	function grid:SetMask(mask, highlight)
		self.mask = mask or 0
		self.highlight = highlight or 0
		for _, cell in ipairs(self.cells) do
			Paint(cell)
		end
	end
	return grid
end

--------------------------------------------------------------------------------
-- Colors and formatting
--------------------------------------------------------------------------------

function W.ClassColorHex(classFile)
	if C_ClassColor and C_ClassColor.GetClassColor then
		local color = C_ClassColor.GetClassColor(classFile)
		if color then
			return color:GenerateHexColor()
		end
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	return color and color.colorStr or "ffffffff"
end

-- "3 h", "2 d" for seconds.
function W.Duration(seconds)
	local L = ns.L
	seconds = math.max(0, seconds or 0)
	if seconds < 3600 then
		return L.DURATION_MINUTES:format(math.max(1, math.floor(seconds / 60)))
	elseif seconds < 86400 then
		return L.DURATION_HOURS:format(math.floor(seconds / 3600))
	end
	local days = math.floor(seconds / 86400)
	return (days == 1 and L.DURATION_DAY or L.DURATION_DAYS):format(days)
end
