local scan = require("plenary.scandir")
local Job = require("plenary.job")
local lualine = require("lualine")
local Layout = require("nui.layout")
local Popup = require("nui.popup")
local Input = require("nui.input")
local Menu = require("nui.menu")
local Text = require("nui.text")
local event = require("nui.utils.autocmd").event

local arduino_component_name = "arduino_status"
local M = {}

-- Configuration
M.config = {
	active = false,
	current_board = nil,
	current_board_fqbn = nil,
	current_project = nil,
	current_port = nil,
	current_platform = nil,
	lualine_section = "lualine_y", -- Default section, can be changed
	enable_lualine = true,
	persistent = false,
	component_color = { fg = "#ff9900", gui = "bold" },
	window_width_factor = 0.6,
	window_height_factor = 0.6,
	upload_after_compile = false,
}

-- Save persistent configuration
local function save_persistent_config()
	if not M.config.persistent then
		return
	end

	local config_file = vim.fn.getcwd() .. "/.arduino_mode_board_info"
	local lines = {
		"current_board=" .. (M.config.current_board or ""),
		"current_board_fqbn=" .. (M.config.current_board_fqbn or ""),
		"current_port=" .. (M.config.current_port or ""),
		"current_platform=" .. (M.config.current_platform or ""),
	}

	local success, error_msg = pcall(function()
		vim.fn.writefile(lines, config_file)
	end)

	if not success then
		print("Failed to save Arduino configuration: " .. error_msg)
	end
end

local function load_persistent_config()
	local config_file = vim.fn.getcwd() .. "/.arduino_mode_board_info"
	if vim.fn.filereadable(config_file) == 1 then
		local lines = vim.fn.readfile(config_file)
		local config = {}
		for _, line in ipairs(lines) do
			local key, value = line:match("^(.+)=(.+)$")
			if key and value then
				config[key] = value
			end
		end
		return config
	end
	return nil
end

-- Create Arduino component
local function create_arduino_component()
	return {
		function()
			if not M.config.active then
				return ""
			end
			return string.format("Arduino Mode")
		end,
		-- color = M.config.component_color,
		cond = function()
			return M.config.active
		end,
		__arduino_component = true, -- Add this unique tag
	}
end

local function create_project_component()
	return {
		function()
			if not M.config.active then
				return ""
			end
			local project = M.config.current_project and vim.fn.fnamemodify(M.config.current_project, ":t") or "No project"
			return string.format(" %s", project)
		end,
		-- color = M.config.component_color,
		cond = function()
			return M.config.active
		end,
		__arduino_component = true, -- Add this unique tag
	}
end

local function create_board_component()
	return {
		function()
			if not M.config.active then
				return ""
			end
			local board = M.config.current_board or "No board"
			return string.format(" %s", board)
		end,
		-- color = M.config.component_color,
		cond = function()
			return M.config.active
		end,
		__arduino_component = true, -- Add this unique tag
	}
end

local function create_port_component()
	return {
		function()
			if not M.config.active then
				return ""
			end
			local port = M.config.current_port or "No port"
			return string.format("󰙜 %s", port)
		end,
		-- color = M.config.component_color,
		cond = function()
			return M.config.active
		end,
		__arduino_component = true, -- Add this unique tag
	}
end

-- Setup Lualine component
function M.setup_lualine()
	if not M.config.enable_lualine then
		print("Lualine is not enabled")
		return
	end
	print("Setting up Lualine component")

	local ok, current_config = pcall(lualine.get_config)
	if not ok then
		print("Error getting Lualine config")
		return
	end

	-- Add our component to the config
	table.insert(current_config.sections[M.config.lualine_section], 1, create_arduino_component())
	table.insert(current_config.sections[M.config.lualine_section], 1, create_project_component())
	table.insert(current_config.sections[M.config.lualine_section], 1, create_board_component())
	table.insert(current_config.sections[M.config.lualine_section], 1, create_port_component())

	-- Apply the updated config
	ok, _ = pcall(lualine.setup, current_config)
	if not ok then
		print("Error applying Lualine config")
		return
	end

	print("Current Lualine config:", vim.inspect(current_config.sections[M.config.lualine_section]))
	print("Lualine setup complete")
end

-- Restore original Lualine config
function M.restore_lualine()
	if not M.config.enable_lualine then
		print("Lualine is not enabled")
		return
	end
	print("Restoring Lualine config")

	local ok, current_config = pcall(lualine.get_config)
	if not ok then
		print("Error getting Lualine config")
		return
	end

	-- Remove our component from the config
	local no_more_components_found = false
	while not no_more_components_found do
		no_more_components_found = true
		for i, component in ipairs(current_config.sections[M.config.lualine_section]) do
			if type(component) == "table" and component.__arduino_component then
				table.remove(current_config.sections[M.config.lualine_section], i)
				no_more_components_found = false
				break
			end
		end
	end

	-- for i, component in ipairs(current_config.sections[M.config.lualine_section]) do
	-- 	-- print("Checking component:", vim.inspect(component))
	-- 	if type(component) == "table" and component.__arduino_component then
	-- 		print("Arduino component found at index:", i)
	-- 		table.remove(current_config.sections[M.config.lualine_section], i)
	-- 		print("Arduino component removed")
	-- 		break
	-- 	end
	-- end

	-- Apply the updated config
	ok, _ = pcall(lualine.setup, current_config)
	if not ok then
		print("Error applying Lualine config")
		return
	end
	print("Current Lualine config:", vim.inspect(current_config.sections[M.config.lualine_section]))
	print("Lualine restoration complete")
end

-- Toggle Arduino Mode
function M.toggle_arduino_mode()
	M.config.active = not M.config.active
	print(" Arduino Mode Toggle...")
	if M.config.active then
		M.scan_project()
		if not M.config.current_project then
			print("No Arduino project found. Arduino mode will not be activated.")
			M.config.active = false
			return
		end

		if M.config.persistent then
			print("Persistent config enabled")
			print("Loading board information from .arduino_mode_board_info...")
			persistent_config = load_persistent_config() or {}

			-- Merge configurations: default < persistent < user_config
			for k, v in pairs(persistent_config) do
				if k == "current_board" or k == "current_board_fqbn" or k == "current_port" or k == "current_platform" then
					M.config[k] = v
				end
			end
		end

		M.setup_lualine()
	else
		M.restore_lualine()
	end
	-- vim.cmd("redrawstatus")
	print("Arduino Mode: " .. (M.config.active and "ON" or "OFF"))
end

-- Scan current directory for .ino files
function M.scan_project()
	local cwd = vim.fn.getcwd()
	local ino_files = scan.scan_dir(cwd, {
		search_pattern = "%.ino$",
		depth = 1, -- Adjust this value to control how deep the search goes
	})

	if #ino_files > 0 then
		M.config.current_project = ino_files[1] -- Use the first .ino file found
		print("Arduino project found: " .. M.config.current_project)
	else
		M.config.current_project = nil
		print("No Arduino project (.ino file) found in the current directory.")
	end
end

-- Board Selection

function M.board_select()
	if not M.config.active then
		print("Arduino mode is not active")
		return
	end

	local detected_board_json = io.popen("arduino-cli board list --format json"):read("*a")
	local full_board_json = io.popen("arduino-cli board listall --format json"):read("*a")
	local detected_boards = vim.json.decode(detected_board_json)
	local full_boards = vim.json.decode(full_board_json)

	local detected_fqbns = {}
	for _, board_info in ipairs(detected_boards) do
		for _, matching_board in ipairs(board_info.matching_boards) do
			detected_fqbns[matching_board.fqbn] = {
				name = matching_board.name,
				port = board_info.port.address,
			}
		end
	end

	local menu_items = {}
	local detected_items = {}
	local undetected_items = {}

	for _, board in ipairs(full_boards.boards) do
		local item = Menu.item(board.name, {
			name = board.name,
			fqbn = board.fqbn,
			platform = board.platform,
		})

		if detected_fqbns[board.fqbn] then
			item.text = "[Detected] " .. item.text
			table.insert(detected_items, item)
		else
			table.insert(undetected_items, item)
		end
	end

	-- Combine detected and undetected items, with detected items first
	for _, item in ipairs(detected_items) do
		table.insert(menu_items, item)
	end
	for _, item in ipairs(undetected_items) do
		table.insert(menu_items, item)
	end

	local function wrap_text(text, max_width)
		local lines = {}
		local line = ""
		for word in text:gmatch("%S+") do
			if #line + #word + 1 > max_width then
				table.insert(lines, line)
				line = word
			else
				line = #line > 0 and (line .. " " .. word) or word
			end
		end
		if #line > 0 then
			table.insert(lines, line)
		end
		return lines
	end

	local function create_tree_lines(item, max_width)
		local lines = {
			" Board",
		}

		local function add_wrapped_line(prefix, value, is_last)
			local wrapped = wrap_text(prefix .. (value or "N/A"), max_width)
			for i, line in ipairs(wrapped) do
				if i == 1 then
					table.insert(lines, line)
				else
					local indent = is_last and "    " or "│   "
					table.insert(lines, indent .. line)
				end
			end
		end
		add_wrapped_line("  ├Name: ", item.name)
		add_wrapped_line("  └FQBN: ", item.fqbn)

		table.insert(lines, "󰕣 Platform")
		add_wrapped_line("  ├ID: ", item.platform.id)
		add_wrapped_line("  ├Installed: ", item.platform.installed)
		add_wrapped_line("  ├Latest: ", item.platform.latest)
		add_wrapped_line("  ├Name: ", item.platform.name)
		add_wrapped_line("  ├Maintainer: ", item.platform.maintainer)
		add_wrapped_line("  ├Website: ", item.platform.website)
		add_wrapped_line("  ├Email: ", item.platform.email)
		add_wrapped_line("  ├Indexed: ", tostring(item.platform.indexed))
		add_wrapped_line("  └Missing Metadata: ", tostring(item.platform.missing_metadata))

		return lines
	end

	local function create_interface()
		local screen_width = vim.o.columns
		local screen_height = vim.o.lines
		local width = math.floor(screen_width * M.config.window_width_factor)
		local height = math.floor(screen_height * M.config.window_height_factor)
		local layout
		local filtered_items = menu_items
		local selected_index = 1
		local update_pending = false
		local menu_height = height - 3

		local function filter_items(search_text)
			if search_text == "" then
				return menu_items
			end
			local filtered = {}
			for _, item in ipairs(menu_items) do
				if item.text:lower():find(search_text:lower(), 1, true) then
					table.insert(filtered, item)
				end
			end
			return #filtered > 0 and filtered or { { text = "No results found" } }
		end

		local menu_popup = Popup({
			enter = false,
			border = {
				style = "rounded",
				text = {
					top = "[Select Board]",
					top_align = "left",
				},
			},
			position = "50%",
			style = "rounded",
			size = {
				width = math.floor(width * 0.4),
				height = menu_height,
			},
		})

		local details_popup = Popup({
			enter = false,
			border = "single",
			position = "50%",
			style = "rounded",
			size = {
				width = math.floor(width * 0.6),
				height = menu_height,
			},
		})

		local function update_details(item)
			local max_width = math.floor(width * 0.6) - 4
			local lines = item.text ~= "No results found" and create_tree_lines(item, max_width) or { "No details available" }
			vim.api.nvim_buf_set_lines(details_popup.bufnr, 0, -1, false, lines)
		end

		local function update_menu()
			if update_pending then
				return
			end
			update_pending = true
			vim.defer_fn(function()
				local lines = {}
				for i, item in ipairs(filtered_items) do
					local prefix = i == selected_index and "> " or "  "
					table.insert(lines, prefix .. item.text)
				end
				vim.api.nvim_buf_set_lines(menu_popup.bufnr, 0, -1, false, lines)

				-- Scroll the view if necessary
				local scroll_offset = 0
				local top_line = math.max(1, selected_index - scroll_offset)
				local bottom_line = math.min(#lines, top_line + menu_height - 1)
				vim.api.nvim_win_set_cursor(menu_popup.winid, { top_line, 0 })

				-- Clear existing highlights
				vim.api.nvim_buf_clear_namespace(menu_popup.bufnr, -1, 0, -1)

				-- Add highlight to the selected item
				vim.api.nvim_buf_add_highlight(menu_popup.bufnr, -1, "PmenuSel", selected_index - 1, 0, -1)

				update_pending = false
			end, 0)
		end

		local popup_options = {
			relative = "editor",
			position = {
				row = math.floor((screen_height - height) / 2) + height - 3,
				col = math.floor((screen_width - width) / 2),
			},
			size = width,
			border = {
				style = "rounded",
				text = {
					top = "[Search]",
					top_align = "left",
				},
			},
			win_options = {
				winhighlight = "Normal:Normal",
			},
		}

		local input = Input(popup_options, {
			prompt = "> ",
			default_value = "",
			on_close = function()
				print("Input closed!")
				layout:unmount()
			end,
			on_submit = function(value)
				if filtered_items[selected_index].text ~= "No results found" then
					print("Selected board:", vim.inspect(filtered_items[selected_index].name))
					print("FQBN:", filtered_items[selected_index].fqbn)
					print("Platform:", filtered_items[selected_index].platform.name)
					print("Version:", filtered_items[selected_index].platform.latest)
					M.config.current_board = filtered_items[selected_index].name
					M.config.current_board_fqbn = filtered_items[selected_index].fqbn
					M.config.current_platform = filtered_items[selected_index].platform.name
					save_persistent_config()
				else
					print("No item selected")
				end
				layout:unmount()
			end,
			on_change = function(value)
				print("Input changed:", value)
				search_text_cus_stuff = value
				filtered_items = filter_items(value)
				selected_index = 1
			end,
		})

		input:map("i", "<Down>", function()
			selected_index = math.min(selected_index + 1, #filtered_items)
			update_menu()
			update_details(filtered_items[selected_index])
		end, { noremap = true })

		input:map("i", "<Up>", function()
			selected_index = math.max(selected_index - 1, 1)
			update_menu()
			update_details(filtered_items[selected_index])
		end, { noremap = true })

		layout = Layout(
			{
				relative = "editor",
				position = "50%",
				size = {
					width = width,
					height = height,
				},
			},
			Layout.Box({
				Layout.Box({
					Layout.Box(menu_popup, { size = "30%" }),
					Layout.Box(details_popup, { size = "70%" }),
				}, { dir = "row", size = height - 3 }),
				Layout.Box(input, { size = 3 }),
			}, { dir = "col" })
		)

		-- Mount the layout
		layout:mount()

		local augroup = vim.api.nvim_create_augroup("InterfaceUpdate", { clear = true })
		vim.api.nvim_create_autocmd("TextChangedI", {
			group = augroup,
			buffer = input.bufnr,
			callback = function()
				update_menu()
				update_details(filtered_items[selected_index])
			end,
		})

		-- Initial update
		update_menu()
		update_details(filtered_items[1])

		-- Clean up the autocommand when the layout is unmounted
		-- layout:unmount(vim.api.nvim_del_augroup_by_name("InterfaceUpdate"))
	end

	create_interface()
end

function M.port_select()
	if not M.config.active then
		print("Arduino mode is not active")
		return
	end

	local detected_board_json = io.popen("arduino-cli board list --format json"):read("*a")
	local detected_boards = vim.json.decode(detected_board_json)

	local menu_items = {}

	for _, board_info in ipairs(detected_boards) do
		for _, matching_board in ipairs(board_info.matching_boards) do
			local item = Menu.item(matching_board.name, {
				name = matching_board.name,
				fqbn = matching_board.fqbn,
				port = board_info.port.address,
				protocol = board_info.port.protocol,
				protocol_label = board_info.port.protocol_label,
				hardware_id = board_info.port.hardware_id,
			})
			item.text = string.format("%s (%s)", board_info.port.address, matching_board.name)
			table.insert(menu_items, item)
		end
	end

	if #menu_items == 0 then
		print("No boards detected")
		return
	end

	local screen_width = vim.o.columns
	local screen_height = vim.o.lines
	local width = math.floor(screen_width * M.config.window_width_factor)
	local height = math.floor(screen_height * M.config.window_height_factor)
	local menu = Menu({
		relative = "editor",
		position = "50%",
		size = {
			width = width,
			height = menu_items and math.min(#menu_items, height) or height,
		},
		border = {
			style = "rounded",
			text = {
				top = "[Select Port] from detected boards",
				top_align = "left",
			},
		},
		win_options = {
			winhighlight = "Normal:Normal,FloatBorder:Normal",
		},
	}, {
		lines = menu_items,
		max_width = width,
		max_height = height,
		keymap = {
			focus_next = { "j", "<Down>", "<Tab>" },
			focus_prev = { "k", "<Up>", "<S-Tab>" },
			close = { "<Esc>", "<C-c>" },
			submit = { "<CR>", "<Space>" },
		},
		on_submit = function(item)
			if item then
				-- Set the selected board and port
				M.config.current_port = item.port
				print(string.format("Selected port %s", item.port))
				save_persistent_config()
			end
		end,
	})
	menu:mount()
end

function M.compile(upload_after)
	if not M.config.active then
		print("Arduino mode is not active")
		return
	end
	if not M.config.current_project then
		print("No Arduino project found")
		return
	end
	if not M.config.current_board_fqbn then
		print("No board selected")
		return
	end

	local screen_width = vim.o.columns
	local screen_height = vim.o.lines
	local width = math.floor(screen_width * M.config.window_width_factor)
	local height = math.floor(screen_height * M.config.window_height_factor)

	-- Create a popup window to display the compilation output
	local popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = "Compilation Information",
				top_align = "center",
				bottom = "<Ctrl> + C - Stop Compilation",
				bottom_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})

	local project_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = " Project",
				top_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})

	local board_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = " Board",
				top_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})
	local platform_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = "󰕣 Platform",
				top_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})

	layout = Layout(
		{
			relative = "editor",
			position = "50%",
			size = {
				width = width,
				height = height,
			},
		},
		Layout.Box({
			Layout.Box({
				Layout.Box(project_popup, { size = "50%" }),
				Layout.Box(board_popup, { size = "25%" }),
				Layout.Box(platform_popup, { size = "25%" }),
			}, { dir = "row", size = 3 }),
			Layout.Box(popup, { size = height - 3 }),
		}, { dir = "col" })
	)

	-- Mount the layout
	layout:mount()
	-- Function to set text in a popup
	local function set_popup_text(popup, text)
		vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", true)
		vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(text, "\n"))
		vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", false)
	end
	local project_info = string.format("%s", M.config.current_project)
	local board_info = string.format("%s", M.config.current_board)
	local platform_info = string.format("%s", M.config.current_platform)
	set_popup_text(project_popup, project_info)
	set_popup_text(board_popup, board_info)
	set_popup_text(platform_popup, platform_info)
	-- Function to append text to the popup buffer
	local function append_to_popup(text)
		vim.schedule(function()
			local lines = vim.split(text, "\n")
			vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", true)
			vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, lines)
			vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", false)
			-- Scroll to the bottom
			vim.api.nvim_win_set_cursor(popup.winid, { vim.api.nvim_buf_line_count(popup.bufnr), 0 })
		end)
	end

	-- Create a job to run the arduino-cli compile command
	local job = Job:new({
		command = "arduino-cli",
		args = { "compile", "--fqbn", M.config.current_board_fqbn, M.config.current_project, "--log", "--no-color" },
		on_stdout = function(_, data)
			append_to_popup(data)
		end,
		on_stderr = function(_, data)
			append_to_popup(data)
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					append_to_popup("\nCompilation completed successfully!")
					append_to_popup("\nPress q to exit this window")
					if upload_after then
						append_to_popup("\nPress <Enter> to upload the compiled sketch")
						-- Add a new keymap to start upload
						popup:map("n", "<CR>", function()
							popup:unmount()
							M.upload()
						end, { noremap = true })
					end
				else
					append_to_popup("\nCompilation failed with exit code: " .. exit_code)
					append_to_popup("\nPress r to retry compilation " .. exit_code)
					-- Add a new keymap to retry compilation
					popup:map("n", "r", function()
						popup:unmount()
						M.compile(upload_after)
					end, { noremap = true })
				end
			end)
		end,
	})

	-- Start the job
	job:start()

	-- Set up keymaps for the popup
	popup:map("n", "q", function()
		popup:unmount()
	end, { noremap = true })

	-- Optionally, you can add more keymaps, e.g., to stop the compilation
	popup:map("n", "<C-c>", function()
		job:shutdown()
		append_to_popup("\nCompilation interrupted by user")
	end, { noremap = true })
end

function M.upload()
	if not M.config.active then
		print("Arduino mode is not active")
		return
	end
	if not M.config.current_project then
		print("No Arduino project found")
		return
	end
	if not M.config.current_board_fqbn then
		print("No board selected")
		return
	end
	if not M.config.current_port then
		print("No port selected")
		return
	end

	local screen_width = vim.o.columns
	local screen_height = vim.o.lines
	local width = math.floor(screen_width * M.config.window_width_factor)
	local height = math.floor(screen_height * M.config.window_height_factor)

	-- Create a popup window to display the compilation output
	local popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = "Upload Information",
				top_align = "center",
				bottom = "<Ctrl> + C - Stop Upload",
				bottom_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})

	local project_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = " Project",
				top_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})

	local board_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = " Board",
				top_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})
	local platform_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = "󰕣 Platform",
				top_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})

	local port_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = "󰙜 Port",
				top_align = "left",
			},
		},
		position = "50%",
		size = "100%",
	})

	layout = Layout(
		{
			relative = "editor",
			position = "50%",
			size = {
				width = width,
				height = height,
			},
		},
		Layout.Box({
			Layout.Box({
				Layout.Box(project_popup, { size = "100%" }),
			}, { dir = "row", size = 3 }),
			Layout.Box({
				Layout.Box(board_popup, { size = "33%" }),
				Layout.Box(platform_popup, { size = "33%" }),
				Layout.Box(port_popup, { size = "33%" }),
			}, { dir = "row", size = 3 }),
			Layout.Box(popup, { size = height - 3 }),
		}, { dir = "col" })
	)

	-- Mount the layout
	layout:mount()
	-- Function to set text in a popup
	local function set_popup_text(popup, text)
		vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", true)
		vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(text, "\n"))
		vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", false)
	end
	local project_info = string.format("%s", M.config.current_project)
	local board_info = string.format("%s", M.config.current_board)
	local platform_info = string.format("%s", M.config.current_platform)
	local port_info = string.format("%s", M.config.current_port)
	set_popup_text(project_popup, project_info)
	set_popup_text(board_popup, board_info)
	set_popup_text(platform_popup, platform_info)
	set_popup_text(port_popup, port_info)
	-- Function to append text to the popup buffer
	local function append_to_popup(text)
		vim.schedule(function()
			local lines = vim.split(text, "\n")
			vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", true)
			vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, lines)
			vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", false)
			-- Scroll to the bottom
			vim.api.nvim_win_set_cursor(popup.winid, { vim.api.nvim_buf_line_count(popup.bufnr), 0 })
		end)
	end

	-- Create a job to run the arduino-cli compile command
	local job = Job:new({
		command = "arduino-cli",
		args = {
			"upload",
			"-p",
			M.config.current_port,
			"--fqbn",
			M.config.current_board_fqbn,
			M.config.current_project,
			"--log",
			"--no-color",
		},
		on_stdout = function(_, data)
			append_to_popup(data)
		end,
		on_stderr = function(_, data)
			append_to_popup(data)
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					append_to_popup("\nCompilation completed successfully!")
				else
					append_to_popup("\nCompilation failed with exit code: " .. exit_code)
				end
				-- Add a message to press 'q' to close the popup
				append_to_popup("\nPress 'q' to close this window")

				-- popup.border.text.bottom = "q - close window"
			end)
		end,
	})

	-- Start the job
	job:start()

	-- Set up keymaps for the popup
	popup:map("n", "q", function()
		popup:unmount()
	end, { noremap = true })

	-- Optionally, you can add more keymaps, e.g., to stop the compilation
	popup:map("n", "<C-c>", function()
		job:shutdown()
		append_to_popup("\nUpload interrupted by user")
	end, { noremap = true })
end

function M.compile_wrapper()
	M.compile(M.config.upload_after_compile)
end

-- Library Management
function M.library_management()
	-- Implementation for Arduino library management
	-- Interface with Arduino CLI for library operations
end

-- Setup function to be called from init.lua
function M.setup(user_config)
	-- Load persistent config if enabled
	local persistent_config = {}

	if user_config then
		for k, v in pairs(user_config) do
			M.config[k] = v
		end
	end

	-- Create and export the Arduino component as a Lualine extension
	local arduino_extension = {}
	arduino_extension[arduino_component_name] = create_arduino_component()

	-- Set up commands
	vim.cmd([[
    command! ArduinoMode lua require('arduino_mode').toggle_arduino_mode()
    command! ArduinoBoardSelect lua require('arduino_mode').board_select()
    command! ArduinoPortSelect lua require('arduino_mode').port_select()
    command! ArduinoCompile lua require('arduino_mode').compile_wrapper()
    command! ArduinoUpload lua require('arduino_mode').upload()
    command! ArduinoCompileUpload lua require('arduino_mode').compile(true)
    command! ArduinoLibrary lua require('arduino_mode').library_management()
    ]])

	-- Export the extension
	return {
		extensions = arduino_extension,
	}
end

return M
