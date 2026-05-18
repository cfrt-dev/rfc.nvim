local M = {}

-- Per-buffer link/anchor data (avoids vim.b serialisation for nested tables).
local buf_data = {}  -- [bufnr] = {links = [...], anchors = {...}}

-- Run parse_html.py on path, return {text, links, anchors} or nil.
local function parse_html(path)
	local script = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "parse_html.py"
	local out    = require("plenary.job"):new({ command = "python3", args = { script, path } }):sync()
	if not out or #out == 0 then
		vim.notify("rfc.nvim: HTML parser returned no output", vim.log.levels.ERROR)
		return nil
	end
	local ok, data = pcall(vim.json.decode, table.concat(out, "\n"))
	if not ok or not data then
		vim.notify("rfc.nvim: failed to decode HTML parser output", vim.log.levels.ERROR)
		return nil
	end
	return data
end

-- Return the link record under (lnum, col) (both 0-based), or nil.
local function link_at(bufnr, lnum, col)
	local d = buf_data[bufnr]
	if not d then return nil end
	for _, lnk in ipairs(d.links) do
		if lnk.line == lnum and col >= lnk.col_start and col < lnk.col_end then
			return lnk
		end
	end
end

-- Jump to anchor id in the current window. Returns true on success.
local function jump_to_anchor(bufnr, id)
	local d = buf_data[bufnr]
	if not d then return false end
	local lnum = d.anchors[id]  -- 0-based
	if lnum == nil then return false end
	vim.api.nvim_win_set_cursor(0, { lnum + 1, 0 })
	vim.cmd("normal! zz")
	return true
end

local function show_outline(bufnr)
	local d = buf_data[bufnr]
	if not d then return end

	local lines    = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local sections = {}

	for id, lnum in pairs(d.anchors) do
		-- Match heading anchors (section-1, section-1.1, section-abstract, appendix-A)
		-- but NOT paragraph anchors (section-1.1-3, section-abstract-1) which have a
		-- trailing hyphen+digits component.
		if id:match("^section%-[%w%.]+$") or id:match("^appendix%-[%w%.]+$") then
			local text = vim.trim(lines[lnum + 1] or "")  -- lnum 0-based, lines 1-based
			table.insert(sections, { lnum = lnum + 1, text = text })
		end
	end

	if #sections == 0 then
		vim.notify("rfc.nvim: no sections found", vim.log.levels.WARN)
		return
	end

	table.sort(sections, function(a, b) return a.lnum < b.lnum end)

	local pickers      = require("telescope.pickers")
	local finders      = require("telescope.finders")
	local previewers   = require("telescope.previewers")
	local conf         = require("telescope.config").values
	local action_state = require("telescope.actions.state")
	local actions      = require("telescope.actions")
	local caller_win   = vim.api.nvim_get_current_win()

	pickers.new({}, {
		prompt_title = "RFC Sections",
		previewer = previewers.new_buffer_previewer({
			title = "RFC Content",
			define_preview = function(self, entry)
				local start   = entry.value.lnum - 1
				local preview = vim.api.nvim_buf_get_lines(bufnr, start, start + 80, false)
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview)
				vim.bo[self.state.bufnr].filetype = "rfc"
			end,
		}),
		finder = finders.new_table({
			results = sections,
			entry_maker = function(entry)
				return {
					value   = entry,
					display = ("%4d  %s"):format(entry.lnum, entry.text),
					ordinal = entry.text,
				}
			end,
		}),
		sorter = conf.generic_sorter({}),
		attach_mappings = function(prompt_bufnr)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local sel = action_state.get_selected_entry()
				if sel then
					vim.api.nvim_set_current_win(caller_win)
					vim.api.nvim_win_set_cursor(caller_win, { sel.value.lnum, 0 })
					vim.cmd("normal! zz")
				end
			end)
			return true
		end,
	}):find()
end

local function setup_keymaps(bufnr)
	local opts = { buffer = bufnr, silent = true, noremap = true }

	vim.keymap.set("n", "gd", function()
		local lnum = vim.fn.line(".") - 1  -- 0-based
		local col  = vim.fn.col(".") - 1   -- 0-based
		local lnk  = link_at(bufnr, lnum, col)
		if not lnk then return end

		local href = lnk.href
		if href:sub(1, 1) == "#" then
			-- Internal anchor → jump in current buffer
			local anchor = href:sub(2)
			if not jump_to_anchor(bufnr, anchor) then
				vim.notify("rfc.nvim: anchor not found: " .. anchor, vim.log.levels.WARN)
			end
		else
			-- External link → open RFC in vsplit
			local rfc_num = href:match("/rfc(%d+)") or href:match("[Rr][Ff][Cc](%d+)%.html?")
			if rfc_num then
				vim.cmd("vsplit")
				require("rfc").open(rfc_num)
			else
				vim.notify("rfc.nvim: unrecognised link: " .. href, vim.log.levels.WARN)
			end
		end
	end, opts)

	vim.keymap.set("n", "gO", function()
		show_outline(bufnr)
	end, opts)
end

M.open = function(file_path, rfc)
	local bufname = "RFC" .. rfc

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.fn.bufname(buf) == bufname then
			vim.api.nvim_set_current_buf(buf)
			return
		end
	end

	local parsed = parse_html(file_path)
	if not parsed then return end

	local bufnr = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(bufnr, bufname)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, parsed.lines)

	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].readonly   = true
	vim.bo[bufnr].bufhidden  = "wipe"
	vim.bo[bufnr].filetype   = "rfc"

	buf_data[bufnr] = { links = parsed.links, anchors = parsed.anchors }

	vim.api.nvim_buf_attach(bufnr, false, {
		on_detach = function() buf_data[bufnr] = nil end,
	})

	vim.api.nvim_set_current_buf(bufnr)
	setup_keymaps(bufnr)
end

return M
