local M = {}

-- Find the line number (1-based) of a section header at column 0.
-- section is a string like "1." or "A.1." extracted from a TOC entry.
local function find_section_line(lines, section)
	local pat = "^" .. vim.pesc(section) .. "%s"
	for i, line in ipairs(lines) do
		if line:match(pat) then
			return i
		end
	end
end

-- Return the [label] the cursor sits inside on the given line, or nil.
local function label_under_cursor(line, col)
	local pos = 1
	while true do
		local s, e, lbl = line:find("%[([^%]%[]+)%]", pos)
		if not s then break end
		if col >= s and col <= e then return lbl end
		pos = e + 1
	end
end

-- Find the line number of a reference entry "   [label]  ..." for the given label.
local function find_ref_entry(lines, label)
	local pat = "^%s+%[" .. vim.pesc(label) .. "%]"
	for i, l in ipairs(lines) do
		if l:match(pat) then return i end
	end
end

-- Starting at a reference entry line, scan forward for the first RFC number.
-- RFC-label entries like [RFC2104] have the number in the label itself.
local function rfc_num_from_ref(lines, start)
	local label = lines[start] and lines[start]:match("^%s+%[([^%]]+)%]")
	if label then
		local n = label:match("[Rr][Ff][Cc](%d+)")
		if n then return n end
	end
	for i = start, math.min(start + 6, #lines) do
		local n = lines[i]:match("RFC[%s%-]?(%d+)")
		if n then return n end
		if i > start and (lines[i] == "" or lines[i]:match("^%s+%[")) then break end
	end
end

-- Find the line number of a named header (e.g. "Authors' Addresses") at column 0.
local function find_named_line(lines, title)
	local escaped = vim.pesc(title)
	for i, line in ipairs(lines) do
		if line == title or line:match("^" .. escaped .. "%s") then
			return i
		end
	end
end

local function collect_sections(lines)
	local sections = {}
	for i, line in ipairs(lines) do
		if line:match("^%d[%d%.]*%.%s+%S")          -- 1.  Title
			or line:match("^[A-Z]%.[%d%.]*%.?%s+%S") -- A.1.  Title (appendix sub)
			or line:match("^Appendix%s+[A-Z]")        -- Appendix A.  Title
		then
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
	local previewers = require("telescope.previewers")
	local conf = require("telescope.config").values
	local action_state = require("telescope.actions.state")
	local actions = require("telescope.actions")

	local caller_win = vim.api.nvim_get_current_win()

	local previewer = previewers.new_buffer_previewer({
		title = "RFC Content",
		define_preview = function(self, entry)
			local start = entry.value.lnum - 1
			local preview_lines = vim.api.nvim_buf_get_lines(bufnr, start, start + 80, false)
			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
			vim.bo[self.state.bufnr].filetype = "rfc"
		end,
	})

	pickers
		.new({}, {
			prompt_title = "RFC Sections",
			previewer = previewer,
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

	vim.keymap.set("n", "gd", function()
		local line = vim.api.nvim_get_current_line()
		local col = vim.fn.col(".")
		local cur_lnum = vim.fn.line(".")
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		-- ── TOC navigation ───────────────────────────────────────────────────
		if line:match("^%s+.+%.%.%..*%d+%s*$") then
			-- Numeric: "   1.2.  Title .......  N"
			local section = line:match("^%s+(%d[%d%.]*%.?)%s+")
			-- Letter-based appendix: "     A.1.  Title .......  N"
			if not section then
				section = line:match("^%s+([A-Z]%.[%d%.]*%.?)%s+")
			end
			if section then
				local target = find_section_line(lines, section)
				if target then
					vim.api.nvim_win_set_cursor(0, { target, 0 })
					vim.cmd("normal! zz")
				else
					vim.notify("rfc.nvim: section " .. section .. " not found", vim.log.levels.WARN)
				end
				return
			end
			-- Named: "   Authors' Addresses .....  N", "   Appendix A.  Title ....  N"
			local title = line:match("^%s+(.-)%s*%.%.%.+.*%d+%s*$")
			if title and #title > 0 then
				local target = find_named_line(lines, title)
				if target then
					vim.api.nvim_win_set_cursor(0, { target, 0 })
					vim.cmd("normal! zz")
				else
					vim.notify("rfc.nvim: '" .. title .. "' not found", vim.log.levels.WARN)
				end
				return
			end
		end

		-- ── Reference entry line: "   [label]   Author ..., RFC NNNN, ..." ──
		-- Cursor anywhere on the line → open the RFC it describes.
		if line:match("^%s+%[[^%]]+%]%s+%S") then
			local rfc_num = rfc_num_from_ref(lines, cur_lnum)
			if rfc_num then
				vim.cmd("vsplit")
				require("rfc").open(rfc_num)
			end
			return
		end

		-- ── [label] under cursor in body text → jump to its reference entry ──
		local lbl = label_under_cursor(line, col)
		if lbl then
			local target = find_ref_entry(lines, lbl)
			if target then
				vim.api.nvim_win_set_cursor(0, { target, 0 })
				vim.cmd("normal! zz")
			else
				vim.notify("rfc.nvim: no reference entry for [" .. lbl .. "]", vim.log.levels.WARN)
			end
			return
		end

		-- ── Fallback: RFC NNNN anywhere (continuation lines, body text) ──────
		local rfc_num = line:match("RFC[%s%-]?(%d+)")
		if rfc_num then
			vim.cmd("vsplit")
			require("rfc").open(rfc_num)
		end
	end, opts)

	vim.keymap.set("n", "gO", function()
		show_outline(bufnr)
	end, opts)
end

local function clean(content)
	content = content:gsub("\xef\xbb\xbf", "") -- UTF-8 BOM
	content = content:gsub("\r\n", "\n") -- CRLF → LF
	content = content:gsub("\r", "\n") -- bare CR → LF
	content = content:gsub("\f", "") -- form-feed page breaks
	content = content:gsub("^\n+", "") -- leading blank lines
	content = content:gsub("\n+$", "") -- trailing blank lines
	return content
end

M.open = function(file_path, rfc)
	local bufname = "RFC" .. rfc

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
