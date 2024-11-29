local Client = require("obsidian").get_client()
local Path = require("obsidian.path")
local Util = require("obsidian.util")
local Workspace = require("obsidian.workspace")
local lib = require("lua-utils")
local ts = vim.treesitter

local Worklog = {}
function Worklog.on_save(event)
	local file_path = vim.api.nvim_buf_get_name(0)
	vim.notify("file: " .. event.file)
	local workspace = Workspace.get_default_workspace(Client.opts.workspaces)
	vim.notify("current_workspace: " .. workspace.name)
	local event_workspace = Workspace.get_workspace_for_dir(event.file, Client.opts.workspaces)
	local workspace_title
	if event_workspace == nil then
		workspace_title = "default"
	else
		workspace_title = event_workspace.name
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = 100,
		height = 100,
		row = 1,
		col = 1,
		hide = false,
	})

	vim.api.nvim_win_call(win, function()
		vim.notify(event.file)
		local bufnr = vim.api.nvim_get_current_buf()
		vim.notify("current bufnr: " .. bufnr)
		local ok = pcall(Worklog.open_today, bufnr)

		if not ok then
			vim.notify("could not open")
			return
		end

		local journal_path = vim.api.nvim_buf_get_name(bufnr)
		vim.notify("journal_path: " .. journal_path)

		-- do not log journal to it's own worklog
		if event.file == journal_path then
			vim.notify("file todays journal. " .. "returning")
			return
		end

		local isnote = Client:path_is_note(event.file, event_workspace) and event_workspace ~= nil
		local link
		if isnote then
			local note = Client:resolve_note(event.file)
			link = Util.wiki_link_id_prefix({ id = note.id, label = note.title })
		else
			vim.notify(file_path)
			link = Util.markdown_link({
				label = vim.fs.basename(event.file),
				path = file_path,
			})
		end
		vim.notify(link)
		local worklog_title_line = nil
		local workspace_title_line = nil
		local worklog_title_tmpl = [[
      ((atx_heading
        (atx_h2_marker) 
          (inline) @title)
      (#eq? @title "%s"))
		    ]]
		local worklog_link_text = [[
    ((list_marker_minus) (paragraph) @p)
    ]]
		Worklog.execute_query(
			string.format(worklog_title_tmpl, config.worklog.heading),
			function(query, id, node, metadata)
				worklog_title_line = Worklog.get_node_range(node).row_start
			end,
			bufnr
		)
		vim.notify("worklog_title_line: " .. (worklog_title_line or "nil"))
		if worklog_title_line ~= nil then
			local workspace_title_tmpl = [[
        ((atx_heading
          (atx_h3_marker) 
            (inline) @title)
        (#eq? @title "%s"))
		      ]]
			Worklog.execute_query(
				string.format(workspace_title_tmpl, workspace_title),
				function(query, id, node, metadata)
					local text = Worklog.get_node_text(node)
					workspace_title_line = Worklog.get_node_range(node).row_start
				end,
				bufnr
			)
		end

		vim.notify("workspace_title: " .. workspace_title)
		if workspace_title ~= nil then
			local file_in_worklog = false
			-- Escape special characters in file name for search
			local escaped_path = link:gsub("([^%w])", "%%%1")
			Worklog.execute_query("((list_marker_minus) (paragraph) @p)", function(query, id, node, metadata)
				local text = Worklog.get_node_text(node)
				if string.match(text, escaped_path) then
					file_in_worklog = true
					return true
				end
			end, bufnr)

			vim.notify("file_in_worklog: " .. tostring(file_in_worklog))
			if file_in_worklog then
				-- Early return, no insert needed
				return
			end
		end

		local lines = {
			"- " .. link,
		}

		vim.notify("workspace_title_line: " .. (workspace_title_line or "nil"))
		if workspace_title_line == nil then
			table.insert(lines, 1, "### " .. workspace_title)
		end

		vim.notify("worklog_title_line: " .. (worklog_title_line or "nil"))
		if worklog_title_line == nil then
			table.insert(lines, 1, "## " .. config.worklog.heading)
		end

		if workspace_title_line ~= nil then
			vim.api.nvim_buf_set_lines(bufnr, workspace_title_line + 1, workspace_title_line + 1, false, lines)
		elseif worklog_title_line ~= nil then
			vim.api.nvim_buf_set_lines(bufnr, worklog_title_line + 1, worklog_title_line + 1, false, lines)
		else
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
		end

		vim.cmd("silent! write")
	end)
	-- vim.api.nvim_win_close(win, false)
	-- vim.api.nvim_buf_delete(buf, {})
end

function Worklog.open_today(bufnr)
	local note = Client:daily(0)
	local path = Path.new(note.path):resolve()
	vim.api.nvim_buf_set_name(bufnr, tostring(path))
	vim.notify("setting " .. tostring(path) .. "in buffer " .. bufnr)
	-- Client:open_note(note, { sync = true, open_strategy = "current" })
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("edit " .. tostring(path))
	end)
end
function Worklog.get_node_text(node, source)
	if not node then
		return ""
	end

	-- when source is the string contents of the file
	if type(source) == "string" then
		local _, _, start_bytes = node:start()
		local _, _, end_bytes = node:end_()
		return string.sub(source, start_bytes + 1, end_bytes)
	end

	source = source or 0

	local start_row, start_col = node:start()
	local end_row, end_col = node:end_()

	local eof_row = vim.api.nvim_buf_line_count(source)

	if end_row >= eof_row then
		end_row = eof_row - 1
		end_col = -1
	end

	if start_row >= eof_row then
		return ""
	end

	local lines = vim.api.nvim_buf_get_text(source, start_row, start_col, end_row, end_col, {})

	return table.concat(lines, "\n")
end
function Worklog.get_node_range(node)
	if not node then
		return {
			row_start = 0,
			column_start = 0,
			row_end = 0,
			column_end = 0,
		}
	end

	local rs, cs, re, ce = lib.when(type(node) == "table", function()
		local brs, bcs, _, _ = node[1]:range()
		local _, _, ere, ece = node[#node]:range()
		return brs, bcs, ere, ece
	end, function()
		local a, b, c, d = node:range() ---@diagnostic disable-line -- TODO: type error workaround <pysan3>
		return a, b, c, d
	end)

	return {
		row_start = rs,
		column_start = cs,
		row_end = re,
		column_end = ce,
	}
end

--- Wrapped around `match()` that performs an action based on a condition.
--- @param comparison boolean The comparison to perform.
--- @param when_true function|any The value to return when `comparison` is true.
--- @param when_false function|any The value to return when `comparison` is false.
--- @return any # The value that either `when_true` or `when_false` returned.
--- @see neorg.core.lib.match
function Worklog.when(comparison, when_true, when_false)
	if type(comparison) ~= "boolean" then
		comparison = (comparison ~= nil)
	end

	return lib.match(type(comparison) == "table" and unpack(comparison) or comparison)({
		["true"] = when_true,
		["false"] = when_false,
	})
end

function Worklog.ts_parse_query(language, query_string)
	if vim.treesitter.query.parse then
		return vim.treesitter.query.parse(language, query_string)
	else
		---@diagnostic disable-next-line
		return vim.treesitter.parse_query(language, query_string)
	end
end
function Worklog.execute_query(query_string, callback, source, start, finish)
	local query = Worklog.ts_parse_query("markdown", query_string)
	local parser = ts.get_parser(source, "markdown")

	if not parser then
		return false
	end

	local root = parser:parse()[1]:root()
	for id, node, metadata in query:iter_captures(root, source, start, finish) do
		if callback(query, id, node, metadata) == true then
			return true
		end
	end

	return true
end
return Worklog
