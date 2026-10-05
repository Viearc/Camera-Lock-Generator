--[[
	Widget

	Builds the Camera Lock Generator settings panel inside a DockWidgetPluginGui and
	wires it to Config (parsing/validation) and Installer (writing the place).

	The panel edits a draft. If CameraLock is installed, the draft starts from
	the installed script's attributes and follows edits made elsewhere (e.g.
	the Properties window) until you change a field yourself.
--]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(script.Parent.Config)
local Installer = require(script.Parent.Installer)

local C = Enum.StudioStyleGuideColor
local DRAFT_SETTING = "CameraLockDraft" -- no "." : periods in keys can corrupt the settings file
local LEGACY_DRAFT_SETTING = "CameraLock.Draft"
local SHIFT_KEYS = { [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.RightShift] = true }
local CONFIRM_WINDOW = 5 -- seconds to click a destructive button again
local OPTION_HEIGHT = 22

local Widget = {}

function Widget.mount(plugin, gui)
	local studio = settings().Studio
	local themed = {} -- [instance] = { [property] = StudioStyleGuideColor }
	local connections = {}
	local stateConnections = {}

	-- Colors an instance from the Studio theme and keeps it in sync when the
	-- theme changes. Calling it again with a new color re-themes it.
	local function theme(inst, property, color)
		themed[inst] = themed[inst] or {}
		themed[inst][property] = color
		inst[property] = studio.Theme:GetColor(color)
		return inst
	end

	----------------------------------------------------------------------
	-- Building blocks
	----------------------------------------------------------------------
	local function new(className, props, children)
		local inst = Instance.new(className)
		for key, value in props do
			inst[key] = value
		end
		for _, child in children or {} do
			child.Parent = inst
		end
		return inst
	end

	local function text(parent, value, opts)
		opts = opts or {}
		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = opts.size or UDim2.new(1, 0, 0, 0),
			Position = opts.position or UDim2.new(),
			AutomaticSize = opts.size and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
			Font = opts.bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans,
			TextSize = opts.textSize or 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Text = value,
			LayoutOrder = opts.order or 0,
			Parent = parent,
		})
		theme(label, "TextColor3", opts.color or C.MainText)
		return label
	end

	local function paintButton(btn, primary)
		theme(btn, "BackgroundColor3", primary and C.DialogMainButton or C.Button)
		theme(btn, "TextColor3", primary and C.DialogMainButtonText or C.ButtonText)
		theme(btn:FindFirstChildOfClass("UIStroke"), "Color", primary and C.DialogMainButton or C.ButtonBorder)
	end

	local function button(parent, label, primary)
		local btn = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			Font = Enum.Font.SourceSansSemibold,
			TextSize = 14,
			Text = label,
			AutoButtonColor = true,
			Parent = parent,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 3) }),
			new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		paintButton(btn, primary)
		return btn
	end

	local function setEnabled(btn, enabled)
		btn.Active = enabled
		btn.AutoButtonColor = enabled
		btn.TextTransparency = enabled and 0 or 0.6
	end

	local function vertical(parent, padding)
		new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, padding or 6),
			Parent = parent,
		})
	end

	local function section(parent, order)
		local frame = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = parent,
		})
		vertical(frame)
		return frame
	end

	local function grid(parent, columns, order)
		return new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = parent,
		}, {
			new("UIGridLayout", {
				CellSize = UDim2.new(1 / columns, -6 * (columns - 1) / columns, 0, 26),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	----------------------------------------------------------------------
	-- Layout
	----------------------------------------------------------------------
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = gui })
	theme(root, "BackgroundColor3", C.MainBackground)

	local scroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Parent = root,
	}, {
		new("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 14),
		}),
	})
	theme(scroll, "ScrollBarImageColor3", C.ScrollBar)
	vertical(scroll, 12)

	-- Dropdown popup, drawn over everything else in the widget
	local overlay = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	local catcher = new("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 10,
		Parent = overlay,
	})
	local popup = new("ScrollingFrame", {
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ZIndex = 11,
		Parent = overlay,
	}, {
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	theme(popup, "BackgroundColor3", C.Dropdown)
	theme(new("UIStroke", { Parent = popup }), "Color", C.Border)

	local function closeDropdown()
		overlay.Visible = false
		for _, child in popup:GetChildren() do
			if child:IsA("TextButton") then
				themed[child] = nil
				child:Destroy()
			end
		end
	end
	table.insert(connections, catcher.Activated:Connect(closeDropdown))

	local function openDropdown(anchor, options, current, onPick)
		closeDropdown()
		for index, option in options do
			local item = new("TextButton", {
				Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
				BorderSizePixel = 0,
				Font = Enum.Font.SourceSans,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "  " .. option,
				LayoutOrder = index,
				ZIndex = 12,
				Parent = popup,
			})
			theme(item, "BackgroundColor3", option == current and C.CurrentMarker or C.Dropdown)
			theme(item, "TextColor3", option == current and C.BrightText or C.MainText)
			item.Activated:Connect(function()
				closeDropdown()
				onPick(option)
			end)
		end

		local origin = anchor.AbsolutePosition - root.AbsolutePosition
		local height = math.min(#options * OPTION_HEIGHT, 220)
		local y = origin.Y + anchor.AbsoluteSize.Y + 2
		if y + height > root.AbsoluteSize.Y then
			y = math.max(origin.Y - height - 2, 0) -- no room below: open upward
		end
		popup.Position = UDim2.fromOffset(origin.X, y)
		popup.Size = UDim2.fromOffset(anchor.AbsoluteSize.X, height)
		local currentIndex = table.find(options, current) or 1
		popup.CanvasPosition = Vector2.new(0, math.max((currentIndex - 1) * OPTION_HEIGHT - height / 2, 0))
		overlay.Visible = true
	end

	-- Status
	local statusSection = section(scroll, 1)
	text(statusSection, "Camera Lock Generator", { bold = true, textSize = 18, order = 1 })
	local statusLabel = text(statusSection, "", { order = 2 })
	local conflictLabel = text(statusSection, "", { order = 3, color = C.WarningText, textSize = 13 })
	local shiftLockLabel = text(statusSection, "⚠ Lock Key is a Shift key, which is also Roblox's Shift Lock "
		.. "key in this place. Players with Shift Lock turned on will toggle both. Pick another key, or turn "
		.. "off StarterPlayer.EnableMouseLockOption.", { order = 4, color = C.WarningText, textSize = 13 })

	local function heading(parent, value, order)
		return text(parent, value, { bold = true, textSize = 12, color = C.DimmedText, order = order })
	end

	-- Settings
	local basicSection = section(scroll, 2)
	heading(basicSection, "SETTINGS", 0)

	local animationSection = section(scroll, 3)
	heading(animationSection, "ANIMATION", 0)
	local presetGrid = grid(animationSection, #Config.PRESETS, 1)
	local presetButtons = {}
	for index, preset in Config.PRESETS do
		local btn = button(presetGrid, preset.name)
		btn.LayoutOrder = index
		presetButtons[preset.name] = btn
	end

	local advancedWrapper = section(scroll, 4)
	local advancedToggle = new("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Font = Enum.Font.SourceSansBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "▸  ADVANCED",
		LayoutOrder = 0,
		Parent = advancedWrapper,
	})
	theme(advancedToggle, "TextColor3", C.DimmedText)
	local advancedSection = section(advancedWrapper, 1)
	advancedSection.Visible = false

	local sectionFrames = { basic = basicSection, animation = animationSection, advanced = advancedSection }

	local draft -- assigned below; dropdowns read it when opened
	local controls = {}    -- [key] = { set = function(value), stroke = UIStroke }
	local fieldErrors = {} -- [key] = message
	local onFieldChanged   -- (field, value), assigned in Behaviour

	local function paintField(key)
		theme(controls[key].stroke, "Color", fieldErrors[key] and C.ErrorText or C.InputFieldBorder)
	end

	local function inputFrame(className, row, props)
		local inst = new(className, props)
		inst.Position = UDim2.fromScale(0.45, 0)
		inst.Size = UDim2.new(0.55, 0, 0, 24)
		inst.Font = Enum.Font.SourceSans
		inst.TextSize = 14
		inst.TextXAlignment = Enum.TextXAlignment.Left
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = inst })
		new("UICorner", { CornerRadius = UDim.new(0, 3), Parent = inst })
		theme(inst, "BackgroundColor3", C.InputFieldBackground)
		theme(inst, "TextColor3", C.MainText)
		inst.Parent = row
		return inst, new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
	end

	for order, field in Config.FIELDS do
		local row = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 10 + order,
			Parent = sectionFrames[field.section],
		})
		text(row, field.label, { size = UDim2.new(0.45, -6, 0, 24), textSize = 14 })

		local control
		if field.kind == "easing" then
			local select, stroke = inputFrame("TextButton", row, { AutoButtonColor = false, Text = "" })
			local arrow = text(select, "▾", { size = UDim2.fromScale(1, 1), color = C.DimmedText })
			arrow.TextXAlignment = Enum.TextXAlignment.Right
			select.Activated:Connect(function()
				openDropdown(select, Config.EASINGS, draft[field.key], function(option)
					onFieldChanged(field, option)
				end)
			end)
			control = { stroke = stroke, set = function(value) select.Text = value end }
		else
			local box, stroke = inputFrame("TextBox", row, { ClearTextOnFocus = false, Text = "" })
			theme(box, "PlaceholderColor3", C.DimmedText)
			box.PlaceholderText = field.kind == "image" and "(none)" or Config.format(field, Config.DEFAULTS[field.key])
			table.insert(connections, box.FocusLost:Connect(function()
				local value, err = Config.parse(field, box.Text)
				if err then
					fieldErrors[field.key] = err
					paintField(field.key)
					onFieldChanged(field, nil, err)
					return
				end
				box.Text = Config.format(field, value)
				onFieldChanged(field, value)
			end))
			control = { stroke = stroke, set = function(value) box.Text = Config.format(field, value) end }
		end
		controls[field.key] = control
		paintField(field.key)

		text(row, field.hint, { position = UDim2.fromOffset(0, 26), textSize = 12, color = C.DimmedText })
	end

	-- Messages + actions
	local actionsSection = section(scroll, 5)
	local messageLabel = text(actionsSection, "", { order = 1, textSize = 13 })
	messageLabel.Visible = false

	local primaryButton = button(actionsSection, "Install", true)
	primaryButton.LayoutOrder = 2

	local actionGrid = grid(actionsSection, 2, 3)
	local reinstallButton = button(actionGrid, "Reinstall")
	local removeButton = button(actionGrid, "Remove")
	local defaultsButton = button(actionGrid, "Reset to Defaults")
	local selectButton = button(actionGrid, "Select Script")
	reinstallButton.LayoutOrder, removeButton.LayoutOrder = 1, 2
	defaultsButton.LayoutOrder, selectButton.LayoutOrder = 3, 4

	----------------------------------------------------------------------
	-- Behaviour
	----------------------------------------------------------------------
	draft = Config.deserialize(plugin:GetSetting(DRAFT_SETTING) or plugin:GetSetting(LEGACY_DRAFT_SETTING))
	local dirty = false
	local state = Installer.inspect()
	local confirmUntil = 0

	local function setMessage(value, kind)
		messageLabel.Visible = value ~= nil
		messageLabel.Text = value or ""
		theme(messageLabel, "TextColor3", ({ ok = C.MainText, warn = C.WarningText, error = C.ErrorText })[kind] or C.SubText)
	end

	local function renderPresets()
		local active = Config.matchingPreset(draft)
		for name, btn in presetButtons do
			paintButton(btn, name == active)
		end
	end

	local function showDraft()
		for _, field in Config.FIELDS do
			controls[field.key].set(draft[field.key])
			fieldErrors[field.key] = nil
			paintField(field.key)
		end
		renderPresets()
	end

	local function saveDraft()
		plugin:SetSetting(DRAFT_SETTING, Config.serialize(draft))
	end

	local function isOutdated()
		return state.outdated == true
	end

	local function renderState()
		local installed = state.installed
		if not installed then
			statusLabel.Text = "Not installed in this place."
		else
			local version = state.version or "?"
			local notes = {}
			if isOutdated() then
				table.insert(notes, if version ~= Installer.VERSION
					then `plugin has v{Installer.VERSION}; upgrade to use every setting below`
					else "the plugin has a newer build; upgrade to use every setting below")
			end
			if state.modified == true then
				table.insert(notes, "runtime code edited by hand")
			end
			if dirty then
				table.insert(notes, "unsaved changes")
			end
			statusLabel.Text = `Installed: StarterCharacterScripts.{installed.Name} (v{version})`
				.. (#notes > 0 and `\n• {table.concat(notes, "\n• ")}` or "")
		end

		if #state.conflicts > 0 then
			local names = {}
			for _, inst in state.conflicts do
				table.insert(names, inst:GetFullName())
			end
			conflictLabel.Text = "⚠ Other camera lock scripts found. Running more than one makes them fight "
				.. "over the camera, so disable or delete these:\n" .. table.concat(names, "\n")
			conflictLabel.Visible = true
		else
			conflictLabel.Visible = false
		end
		shiftLockLabel.Visible = SHIFT_KEYS[draft.LockKey] == true and StarterPlayer.EnableMouseLockOption

		primaryButton.Text = if not installed then "Install"
			elseif isOutdated() then "Upgrade & Apply"
			else "Apply Settings"
		setEnabled(primaryButton, state.container ~= nil and (not installed or isOutdated() or dirty))
		setEnabled(reinstallButton, installed ~= nil)
		setEnabled(removeButton, installed ~= nil)
		setEnabled(selectButton, installed ~= nil)
	end

	local refreshQueued = false
	local function refresh()
		if refreshQueued then
			return
		end
		refreshQueued = true
		task.defer(function()
			refreshQueued = false
			state = Installer.inspect()

			for _, conn in stateConnections do
				conn:Disconnect()
			end
			table.clear(stateConnections)
			if state.installed then
				table.insert(stateConnections, state.installed.AttributeChanged:Connect(refresh))
				-- Follow the installed values unless the user is mid-edit.
				if not dirty then
					draft = Config.readAttributes(state.installed)
					showDraft()
				end
			end
			renderState()
		end)
	end

	local function markDirty()
		dirty = true
		saveDraft()
		renderPresets()
		renderState()
	end

	onFieldChanged = function(field, value, err)
		if err then
			setMessage(err, "error")
			return
		end
		fieldErrors[field.key] = nil
		paintField(field.key)
		controls[field.key].set(value)
		setMessage(nil)
		if draft[field.key] ~= value then
			draft[field.key] = value
			markDirty()
		end
	end

	local function firstFieldError()
		for _, field in Config.FIELDS do
			if fieldErrors[field.key] then
				return fieldErrors[field.key]
			end
		end
		return Config.validate(draft)
	end

	local function report(ok, message)
		setMessage(message, ok and "ok" or "error")
		if ok then
			dirty = false
		end
		refresh()
	end

	-- Replaces the installed code (and applies the draft). Hand edits need a
	-- second click within CONFIRM_WINDOW seconds.
	local function reinstall(buttonName)
		if state.modified and os.clock() > confirmUntil then
			confirmUntil = os.clock() + CONFIRM_WINDOW
			local why = if state.modified == "unknown"
				then "This copy came from an older plugin, so any hand edits to its code can't be detected."
				else `The installed runtime has hand edits that {buttonName} will replace.`
			setMessage(`{why} Click {buttonName} again to confirm (Ctrl+Z undoes it).`, "warn")
			return
		end
		confirmUntil = 0
		report(Installer.install(draft, { overwriteModified = true }))
	end

	table.insert(connections, primaryButton.Activated:Connect(function()
		if not primaryButton.Active then return end
		local err = firstFieldError()
		if err then
			setMessage(err, "error")
			return
		end
		if not state.installed then
			report(Installer.install(draft))
		elseif isOutdated() then
			reinstall("Upgrade")
		else
			report(Installer.applySettings(draft))
		end
	end))

	table.insert(connections, reinstallButton.Activated:Connect(function()
		if not reinstallButton.Active then return end
		local err = firstFieldError()
		if err then
			setMessage(err, "error")
			return
		end
		reinstall("Reinstall")
	end))

	table.insert(connections, removeButton.Activated:Connect(function()
		if not removeButton.Active then return end
		report(Installer.uninstall())
	end))

	for _, preset in Config.PRESETS do
		table.insert(connections, presetButtons[preset.name].Activated:Connect(function()
			for key, value in preset.values do
				draft[key] = value
			end
			showDraft()
			markDirty()
			setMessage(`{preset.name} animation loaded.`
				.. (state.installed and " Click Apply Settings to save it." or ""))
		end))
	end

	table.insert(connections, defaultsButton.Activated:Connect(function()
		draft = Config.defaults()
		showDraft()
		markDirty()
		setMessage(state.installed and "Defaults loaded. Click Apply Settings to save them." or "Defaults loaded.")
	end))

	table.insert(connections, selectButton.Activated:Connect(function()
		if state.installed then
			Selection:Set({ state.installed })
		end
	end))

	table.insert(connections, advancedToggle.Activated:Connect(function()
		advancedSection.Visible = not advancedSection.Visible
		advancedToggle.Text = (advancedSection.Visible and "▾" or "▸") .. "  ADVANCED"
	end))

	-- Keep the panel in sync with the place.
	local container = Installer.getContainer()
	if container then
		table.insert(connections, container.ChildAdded:Connect(refresh))
		table.insert(connections, container.ChildRemoved:Connect(refresh))
	end
	table.insert(connections, StarterPlayer:GetPropertyChangedSignal("EnableMouseLockOption"):Connect(renderState))
	table.insert(connections, ChangeHistoryService.OnUndo:Connect(refresh))
	table.insert(connections, ChangeHistoryService.OnRedo:Connect(refresh))
	table.insert(connections, gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			refresh()
		else
			closeDropdown()
		end
	end))

	table.insert(connections, studio.ThemeChanged:Connect(function()
		for inst, properties in themed do
			for property, color in properties do
				inst[property] = studio.Theme:GetColor(color)
			end
		end
	end))

	showDraft()
	refresh()

	return function()
		for _, conn in connections do
			conn:Disconnect()
		end
		for _, conn in stateConnections do
			conn:Disconnect()
		end
		root:Destroy()
	end
end

return Widget
