local M = {}

M.open = function(opts)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local action_state = require("telescope.actions.state")
	local actions = require("telescope.actions")

	local rfc = require("rfc")
	local index_path = rfc.config.rfc_dir .. "/rfc-ref.txt"

	local file = io.open(index_path, "r")
	if not file then
		vim.notify("rfc.nvim: index not found — run :RfcUpdateIndex", vim.log.levels.ERROR)
		return
	end

	local entries = {}
	for line in file:lines() do
		if line ~= "" then
			table.insert(entries, line)
		end
	end
	file:close()

	opts = vim.tbl_extend("force", {
		layout_strategy = "vertical",
		layout_config = { width = 0.8, height = 0.6 },
	}, opts or {})

	pickers
		.new(opts, {
			prompt_title = "RFCs",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					local num, title = entry:match("^RFC(%d+):(.*)")
					if not num then
						return nil
					end
					return {
						value = entry,
						-- Pad RFC number to 5 digits for consistent column alignment
						display = ("RFC %-5s  %s"):format(num, title),
						-- ordinal includes both number and title for fuzzy matching
						ordinal = ("RFC%s %s"):format(num, title),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr, map)
				local function open_selection()
					actions.close(prompt_bufnr)
					local sel = action_state.get_selected_entry()
					if sel then
						local num = sel.value:match("^RFC(%d+):")
						if num then
							rfc.open(num)
						end
					end
				end

				map("i", "<CR>", open_selection)
				map("n", "<CR>", open_selection)
				return true
			end,
		})
		:find()
end

return M
