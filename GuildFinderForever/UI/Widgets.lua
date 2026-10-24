-- luacheck: read globals C_ClassColor RAID_CLASS_COLORS GameTooltip
local _, ns = ...

-- Small widget kit for the window, built on the game's standard templates.
local W = {}
ns.Widgets = W

local C = ns.Constants

W.GOLD = { 1, 0.82, 0 }
W.TEXT = { 0.91, 0.89, 0.82 }
W.MUTED = { 0.66, 0.63, 0.56 }
W.GREEN = { 0.56, 0.94, 0.54 }
W.RED = { 1, 0.35, 0.3 }

local PANEL_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

-- Dark panel with a thin bronze border.
function W.Panel(parent)
	local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	panel:SetBackdrop(PANEL_BACKDROP)
	panel:SetBackdropColor(0.047, 0.04, 0.027, 0.92)
	panel:SetBackdropBorderColor(0.29, 0.235, 0.133, 1)
	return panel
end

function W.Text(parent, font, color)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	if color then
		text:SetTextColor(color[1], color[2], color[3])
	end
	text:SetJustifyH("LEFT")
	return text
end

-- Small gold caps heading.
function W.Header(parent, label)
	local text = W.Text(parent, "GameFontNormalSmall", W.GOLD)
	text:SetText(label:upper())
	return text
end

function W.Button(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(label)
	button:SetSize(width or (button:GetFontString():GetStringWidth() + 30), 22)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
end

-- Checkbox with a clickable label. onChange(checked) runs on user clicks.
function W.Checkbox(parent, label, onChange)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	local text = W.Text(check, "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 2, 1)
	text:SetText(label)
	check.label = text
	check:SetHitRectInsets(0, -math.max(text:GetStringWidth(), 20) - 4, 0, 0)
	check:SetScript("OnClick", function(self)
		if onChange then
			onChange(self:GetChecked() and true or false)
		end
	end)
	function check:SetLabelEnabled(enabled)
		self:SetEnabled(enabled)
		local color = enabled and W.TEXT or W.MUTED
		text:SetTextColor(color[1], color[2], color[3])
	end
	return check
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

-- Multi-line text field with a character counter below it.
function W.TextArea(parent, width, height, maxLetters, onChange)
	local frame = W.Panel(parent)
	frame:SetSize(width, height)
	frame:SetBackdropColor(0.106, 0.086, 0.059, 1)
	frame:SetBackdropBorderColor(0.416, 0.337, 0.188, 1)

	local box = CreateFrame("EditBox", nil, frame)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetMaxLetters(maxLetters)
	box:SetPoint("TOPLEFT", 6, -5)
	box:SetPoint("BOTTOMRIGHT", -6, 5)
	box:SetTextInsets(0, 0, 0, 0)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	frame:EnableMouse(true)
	frame:SetScript("OnMouseDown", function()
		box:SetFocus()
	end)

	local counter = W.Text(frame, "GameFontDisableSmall")
	counter:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -3)
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

-- Dropdown with radio entries. options: list or function returning a list
-- of { value, label }; get() returns the selected value, set(value) stores it.
function W.Dropdown(parent, width, options, get, set)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width)
	dropdown:SetupMenu(function(_, root)
		local list = type(options) == "function" and options() or options
		for _, option in ipairs(list) do
			root:CreateRadio(option.label, function()
				return get() == option.value
			end, function()
				set(option.value)
			end)
		end
	end)
	-- Refresh the shown selection after the value changed elsewhere.
	function dropdown:Refresh()
		self:GenerateMenu()
	end
	return dropdown
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

function W.FactionColor(faction)
	if faction == "H" then
		return { 0.7, 0.15, 0.12 }
	end
	return { 0.18, 0.42, 0.84 }
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
	return L.DURATION_DAYS:format(math.floor(seconds / 86400))
end

--------------------------------------------------------------------------------
-- Role badges
--------------------------------------------------------------------------------

-- Row of up to three role badges; :SetRoles(mask) shows them.
function W.RoleBadges(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size * 3 + 6, size)
	holder.badges = {}
	for i = 1, #C.ROLES do
		local badge = CreateFrame("Frame", nil, holder)
		badge:SetSize(size, size)
		local bg = badge:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		local color = C.ROLES[i].color
		bg:SetColorTexture(color[1], color[2], color[3], 1)
		local text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("CENTER", 0, 0)
		text:SetText(C.ROLES[i].short)
		holder.badges[i] = badge
	end
	function holder:SetRoles(mask)
		local x = 0
		for i, role in ipairs(C.ROLES) do
			local badge = self.badges[i]
			if C.HasBit(mask or 0, role.bit) then
				badge:ClearAllPoints()
				badge:SetPoint("LEFT", x, 0)
				badge:Show()
				x = x + size + 3
			else
				badge:Hide()
			end
		end
	end
	return holder
end

--------------------------------------------------------------------------------
-- Play time grid
--------------------------------------------------------------------------------

-- 7 × 3 grid of play time slots. interactive: cells toggle on click and
-- onChange(mask) runs. :SetMask(mask) shows a mask.
function W.TimeGrid(parent, cellWidth, cellHeight, interactive, onChange)
	local labelWidth = 52
	local gap = 3
	local grid = CreateFrame("Frame", nil, parent)
	grid:SetSize(labelWidth + #C.DAYS * (cellWidth + gap), 14 + #C.SLOTS * (cellHeight + gap))
	grid.mask = 0
	grid.cells = {}

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
		else
			cell.fill:SetColorTexture(0.133, 0.11, 0.075, 1)
		end
	end

	for slot, name in ipairs(C.SLOTS) do
		local y = -14 - (slot - 1) * (cellHeight + gap)
		local text = W.Text(grid, "GameFontDisableSmall")
		text:SetPoint("TOPLEFT", 0, y - 2)
		text:SetWidth(labelWidth - 4)
		text:SetText(name)
		for day = 1, #C.DAYS do
			local cell = CreateFrame(interactive and "Button" or "Frame", nil, grid)
			cell:SetSize(cellWidth, cellHeight)
			cell:SetPoint("TOPLEFT", labelWidth + (day - 1) * (cellWidth + gap), y)
			local border = cell:CreateTexture(nil, "BACKGROUND")
			border:SetAllPoints()
			border:SetColorTexture(0.23, 0.18, 0.11, 1)
			cell.fill = cell:CreateTexture(nil, "ARTWORK")
			cell.fill:SetPoint("TOPLEFT", 1, -1)
			cell.fill:SetPoint("BOTTOMRIGHT", -1, 1)
			cell.bit = C.TimeBit(day, slot)
			if interactive then
				cell:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
				cell:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.25)
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
	end

	function grid:SetMask(mask)
		self.mask = mask or 0
		for _, cell in ipairs(self.cells) do
			Paint(cell)
		end
	end
	return grid
end
