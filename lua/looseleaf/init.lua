local M = {}

-- default settings
local config = {
	configs = vim.fn.expand("~/.local/share/nvim/looseleaf.nvim/"), -- not to be overwritten
	dir = vim.fn.expand("~/.local/share/nvim/looseleaf.nvim/scratchpads/"),
	special = {},
}

local function read_config(filename)
  local path = config.configs .. filename
  if vim.fn.filereadable(path) == 0 then
    vim.notify("Looseleaf: Config file not found: " .. path, vim.log.levels.WARN)
    return nil
  end

  local lines = vim.fn.readfile(path)
  return table.concat(lines, "\n")
end

-- return: bool - successfully written
local function write_config(filename, content)
  local path = config.configs .. filename

  -- Ensure content is a string
  if type(content) ~= "string" then
    vim.notify("Looseleaf: Cannot write non-string content to config file: " .. path, vim.log.levels.ERROR)
    return false
  end

  -- Attempt to write
  local ok = pcall(function()
    local lines = vim.split(content, "\n", { plain = true })
    vim.fn.writefile(lines, path)
  end)

  if not ok then
    vim.notify("Looseleaf: Failed to write config file: " .. path, vim.log.levels.ERROR)
    return false
  end

  return true
end

local function ensure_dir()
  if vim.fn.isdirectory(config.dir) == 0 then
    vim.fn.mkdir(config.dir, "p")
  end

  if vim.fn.isdirectory(config.configs) == 0 then
    vim.fn.mkdir(config.configs, "p")
  end
end

local function generate_filename()
  local newname = config.dir .. "/LL" .. os.date("_%Y_%m_%d__%H_%M") .. ".txt"

	-- TODO update last.txt in other fns too
	write_config("last.txt", newname)
	
	return newname
end

function M.full(opts)
	local arg = opts.args

	local filename = handle_any_argument(arg)
	if filename == nil then return end

	if type(filename) == "string" then
		vim.cmd("edit " .. filename)
	else
		-- callback fn
		filename()
	end
end

local function try_get_special_name(arg)
  local prefix = ":"

  if type(arg) ~= "string" then return nil end
  if arg:sub(1, #prefix) ~= prefix then return nil end

  local name = arg:sub(#prefix + 1)
  if name == "" then return nil end

  return name
end

-- no input
-- returns 
--	nil if failed + reports
--	string (filename) if ok
local function handle_last_file() 
	local last_path = config.configs .. "last.txt"
	local saved_path = vim.fn.filereadable(last_path) == 1 and vim.fn.readfile(last_path)[1] or nil

	if not saved_path or saved_path == "" then
		vim.notify("Looseleaf: No recent file found in last.txt. Use ':LooseleafFloat' to create a new one.", vim.log.levels.INFO, {
			title = "Looseleaf",
		})
		return nil
	end

	return vim.fn.expand(saved_path)
end


-- takes in an arg which may not be a valid special name
-- returns 
--	nil if failed + reports before returning
--	string to resolved filepath if ok 
local function handle_special_name(arg)
	local special_name_cut = try_get_special_name(arg)
	if special_name_cut then -- valid special name
		-- TODO look it up in the config.special
		-- TODO error reporting
		local value = config.special[special_name_cut]
		if value ~= nil then
			-- found
			filename = vim.fn.expand(config.dir .. value)
		else 
			-- not found
			vim.notify("Looseleaf: Special scratchpad name '" .. arg .. "' parsed but not configured.", vim.log.levels.INFO, {
				title = "Looseleaf",
			})
			return nil
		end
	else -- invalid special name
		vim.notify("Looseleaf: Could not parse resolve name for the special scratchpad.", vim.log.levels.ERROR, {
			title = "Looseleaf",
		})
		return nil
	end
end

-- input: arg
-- output:
--	nil if failed + reporting
--	string (filepath) if ok | function if ok + `pick` used
function handle_any_argument(arg)
	-- [empty] (new file)
	-- pick
	-- last
	-- :<special_name>	if arg ~= nil then
	
	-- validate argument
	
	if arg and arg ~= "" then
		if type(arg) ~= "string" or (arg:lower() ~= "last" and arg:lower() ~= "pick" and arg:sub(1, 1) ~= ":") then
			vim.notify("Looseleaf: Invalid argument '" .. arg .. "'. Only 'last', 'pick', ':<special_name>' or nothing is allowed.", vim.log.levels.ERROR, {
				title = "Looseleaf",
			})
			return nil
		end
	end

	ensure_dir()

	local filename
	local picked = false

	-- match against the type of argument
	
	-- last
	if arg == "last" then
		local last_path = config.configs .. "last.txt"
		local saved_path = vim.fn.filereadable(last_path) == 1 and vim.fn.readfile(last_path)[1] or nil

		if not saved_path or saved_path == "" then
			vim.notify("Looseleaf: No recent file found in last.txt. Use ':LooseleafFloat' to create a new one.", vim.log.levels.INFO, {
				title = "Looseleaf",
			})
			return nil
		end

		filename = vim.fn.expand(saved_path)

	-- pick (use oil)
	elseif arg == "pick" then
		picked = true
	
	-- :<special_name>
	elseif arg:sub(1, 1) == ":" then

		local special_name_cut = try_get_special_name(arg)
		if special_name_cut then -- not nil
			local value = config.special[special_name_cut]
			if value ~= nil then
				-- found
				filename = vim.fn.expand(config.dir .. value)
			else 
				-- not found
				vim.notify("Looseleaf: Special scratchpad name '" .. arg .. "' parsed but not configured.", vim.log.levels.INFO, {
					title = "Looseleaf",
				})
				return nil
			end
		end

	-- new file
	elseif arg == nil or arg == "" then
		filename = generate_filename()	
	end
	
	-- returning
	-- case 1) pick -> function
	if picked then
		return function()
			require("oil").open(config.dir)
		end
	end
	-- case 2) -> string (filepath)
	return filename
end

function M.float(opts)
	local arg = opts.args

	local filename = handle_any_argument(arg)
	if filename == nil then
		return
	end

  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
	local x = math.floor((vim.o.columns - width)/2)
	local y = math.floor((vim.o.lines - height)/2)
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = y,
    col = x,
    -- style = "minimal",
    border = "single",
  }
  local win = vim.api.nvim_open_win(buf, true, opts)

	if type(filename) == "string" then
		vim.cmd("edit " .. filename)
	else
		-- it's a callback fn
		filename()
	end

  -- Optional: map 'q' to close
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', { noremap = true, silent = true })
end

function M.split(opts)
	local arg = opts.args

  local filename = handle_any_argument(arg) -- Err(nil) Ok(string / function)
	
	if filename == nil then return end

  -- Calculate 20% of screen height
  local total_lines = vim.o.lines
  local target_height = math.floor(total_lines * 0.2)

  -- Open the file in a horizontal split
  vim.cmd("split")
  vim.api.nvim_win_set_height(0, target_height)
	if picked then
		-- ...
	else
		if type(filename) == "string" then
			vim.cmd("edit " .. filename)
		else 
			-- otherwise it's a callback fn
			filename()
		end
	end
end

function M.load_file(filepath)
  -- Replace this with your plugin's file loading logic
  vim.cmd("edit " .. filepath)
end

function M.list()
  ensure_dir()
  local files = vim.fn.globpath(config.dir, "*", false, true)

  print("Scratchpads in " .. config.dir)
	if #files == 0 then
		print("[EMPTY]")
	end
  for i, file in ipairs(files) do
		local name = vim.fn.fnamemodify(file, ":t")
    print(i .. "  " .. name)
  end
end


local function is_string_map(tbl)
  if type(tbl) ~= "table" then return false end

  for k, v in pairs(tbl) do
    if type(k) ~= "string" or type(v) ~= "string" then
      return false
    end
  end

  return true
end

function M.list_special()
  print("Special scratchpad config")

  local is_empty = true
  for key, val in pairs(config.special) do
    print(":" .. key .. " " .. val)
    is_empty = false
  end

  if is_empty then
    print("[EMPTY]")
  end
end

-- set up user commands
function M.setup(opts)
	opts = opts or {}
  config.dir = opts.dir and vim.fn.expand(opts.dir) or config.dir

	opts.special = opts.special or {}

	if is_string_map(opts.special) then
		for key, path in pairs(opts.special) do
			config.special[key] = path
		end
	else
		vim.notify("Looseleaf: 'special' must be a table of string keys and string values", vim.log.levels.ERROR)
	end

	config.special = opts.special or {}

  vim.api.nvim_create_user_command("LooseleafFull", function(opts)
		M.full(opts)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("LooseleafSplit", function(opts)
		M.split(opts)
	end, { nargs = "?" })
  vim.api.nvim_create_user_command("LooseleafList", M.list, {})
  vim.api.nvim_create_user_command("LooseleafSpecial", M.list_special, {})
  vim.api.nvim_create_user_command("LooseleafFloat", function(opts)
		M.float(opts)
	end, { nargs = "?" })
end

return M


