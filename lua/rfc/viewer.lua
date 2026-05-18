local M = {}

-- Find the line number (1-based) of a section header at column 0.
-- section is a string like "1." or "1.2." extracted from a TOC entry.
local function find_section_line(lines, section)
	local pat = "^" .. vim.pesc(section) .. "%s"
	for i, line in ipairs(lines) do
		if line:match(pat) then
			return i
		end
	end
end

-- Collect all section headers (lines at col 0 starting with N.)
local function collect_sections(lines)
	local sections = {}
	for i, line in ipairs(lines) do
		if line:match("^%d[%d%.]*%.%s+%S") then
			table.insert(sections, { lnum = i, text = vim.trim(line) })
		end
	end
	return sections
end

local function show_outline(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local sections = collect_sections(lines)

	if #sections == 0 then
		vim.notify("rfc.nvim: no sections found", vim.log.levels.WARN)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local action_state = require("telescope.actions.state")
	local actions = require("telescope.actions")

	local caller_win = vim.api.nvim_get_current_win()

	pickers
		.new({
			layout_strategy = "vertical",
			layout_config = { width = 0.65, height = 0.5 },
		}, {
			prompt_title = "RFC Sections",
			finder = finders.new_table({
				results = sections,
				entry_maker = function(entry)
					return {
						value = entry,
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
		})
		:find()
end

local function setup_keymaps(bufnr)
	local opts = { buffer = bufnr, silent = true, noremap = true }

	-- gd on a TOC line: jump to the corresponding section in the document.
	-- TOC lines are indented and end with dots + page number:
	--   "   1.2.  Background .......  5"
	vim.keymap.set("n", "gd", function()
		local line = vim.api.nvim_get_current_line()
		local section = line:match("^%s+(%d[%d%.]*%.?)%s+[^.]+%.+%s*%d+%s*$")
		if not section then
			return
		end

		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local target = find_section_line(lines, section)
		if target then
			vim.api.nvim_win_set_cursor(0, { target, 0 })
			vim.cmd("normal! zz")
		else
			vim.notify("rfc.nvim: section " .. section .. " not found", vim.log.levels.WARN)
		end
	end, opts)

	-- gO: open a telescope picker of all section headers in this RFC.
	vim.keymap.set("n", "gO", function()
		show_outline(bufnr)
	end, opts)
end

local function clean(content)
	content = content:gsub("\xef\xbb\xbf", "") -- UTF-8 BOM
	content = content:gsub("\r\n", "\n") -- CRLF → LF
	content = content:gsub("\r", "\n") -- bare CR → LF
	content = content:gsub("\f", "") -- form-feed page breaks
	return content
end

M.open = function(file_path, rfc)
	local bufname = "RFC" .. rfc

	-- Reuse an existing buffer for this RFC.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.fn.bufname(buf) == bufname then
			vim.api.nvim_set_current_buf(buf)
			return
		end
	end

	local file = io.open(file_path, "r")
	if not file then
		vim.notify("rfc.nvim: cannot open " .. file_path, vim.log.levels.ERROR)
		return
	end

	local content = clean(file:read("*a"))
	file:close()

	local bufnr = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(bufnr, bufname)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))

	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].readonly = true
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].filetype = "rfc"

	vim.api.nvim_set_current_buf(bufnr)
	setup_keymaps(bufnr)
end

return M
