local M = {}

M.config = {
	rfc_dir = nil,
}

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

M.download_index = function()
	local Job = require("plenary.job")
	local index_path = M.config.rfc_dir .. "/rfc-ref.txt"

	Job:new({
		command = "curl",
		args = { "-fsSL", "https://www.rfc-editor.org/rfc/rfc-ref.txt" },
		on_exit = function(j, code)
			if code ~= 0 then
				vim.schedule(function()
					vim.notify("rfc.nvim: failed to download index", vim.log.levels.ERROR)
				end)
				return
			end

			local entries = {}
			for _, line in ipairs(j:result()) do
				local num, title = line:match('RFC(%d+)%s*|[^|]+|.*"([^"]+)"')
				if num then
					table.insert(entries, "RFC" .. tonumber(num) .. ":" .. title)
				end
			end

			local file = io.open(index_path, "w")
			if file then
				file:write(table.concat(entries, "\n") .. "\n")
				file:close()
				vim.schedule(function()
					vim.notify(("rfc.nvim: index updated (%d RFCs)"):format(#entries), vim.log.levels.INFO)
				end)
			end
		end,
	}):start()
end

M.download_rfc = function(rfc)
	local Job = require("plenary.job")
	local path = M.config.rfc_dir .. "/rfc" .. rfc .. ".html"

	Job:new({
		command = "curl",
		args = { "-fsSL", "-o", path, "https://www.rfc-editor.org/rfc/rfc" .. rfc .. ".html" },
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					vim.notify("rfc.nvim: failed to download RFC " .. rfc, vim.log.levels.ERROR)
				end)
			end
		end,
	}):sync()
end

M.open = function(rfc)
	local path = M.config.rfc_dir .. "/rfc" .. rfc .. ".html"

	if not file_exists(path) then
		vim.notify("rfc.nvim: downloading RFC " .. rfc .. "...", vim.log.levels.INFO)
		M.download_rfc(rfc)
	end

	if not file_exists(path) then
		vim.notify("rfc.nvim: RFC " .. rfc .. " not available", vim.log.levels.ERROR)
		return
	end

	require("rfc.viewer").open(path, rfc)
end

M.list = function(opts)
	require("rfc.search").open(opts)
end

M.setup = function(opts)
	opts = opts or {}
	M.config.rfc_dir = opts.rfc_dir or (vim.fn.stdpath("data") .. "/rfc.nvim/rfc")

	if vim.fn.isdirectory(M.config.rfc_dir) == 0 then
		vim.fn.mkdir(M.config.rfc_dir, "p")
	end

	if vim.fn.executable("curl") ~= 1 then
		error("rfc.nvim: curl is required")
	end

	if vim.fn.executable("python3") ~= 1 then
		error("rfc.nvim: python3 is required")
	end

	if not pcall(require, "plenary") then
		error("rfc.nvim: nvim-lua/plenary.nvim is required")
	end

	if not pcall(require, "telescope") then
		error("rfc.nvim: nvim-telescope/telescope.nvim is required")
	end

	if not file_exists(M.config.rfc_dir .. "/rfc-ref.txt") then
		M.download_index()
	end

	vim.api.nvim_create_user_command("RfcSearch", function()
		M.list()
	end, { desc = "Search and open RFCs" })

	vim.api.nvim_create_user_command("RfcOpen", function(cmd)
		M.open(cmd.args)
	end, { nargs = 1, desc = "Open RFC by number" })

	vim.api.nvim_create_user_command("RfcUpdateIndex", function()
		M.download_index()
	end, { desc = "Re-download RFC index" })
end

return M
