local Client = require("obsidian").get_client()
local Path = require("obsidian.path")
local Obsidianutil = require("obsidian.util")
local Workspace = require("obsidian.workspace")
local Util = require("obsidian-extensions.util")

local M = {}
-- M.Modules = {
-- 	worklog = require("obsidian-extensions.modules.worklog"),
-- }
local default = {
	worklog = {
		enabled = true,
		heading = "Worklog",
	},
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", default, opts or {})
	if M.config.worklog.enabled then
		local group = vim.api.nvim_create_augroup("obsidian_worklog", { clear = true })
		vim.api.nvim_create_autocmd({ "BufWritePost" }, {
			group = group,
			pattern = "*.md",
			callback = M.on_save,
		})
	end
end

function M.on_save(event)
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

	local b = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(b, false, {
		relative = "editor",
		width = 100,
		height = 100,
		row = 1,
		col = 1,
		hide = false,
	})

	local bufnr = vim.api.nvim_win_call(win, function()
		vim.notify(event.file)
		local ok, bufnr = pcall(M.open_today)

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
			link = Obsidianutil.wiki_link_id_prefix({ id = note.id, label = note.title })
		else
			vim.notify(file_path)
			link = Obsidianutil.markdown_link({
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
		Util.execute_query(
			string.format(worklog_title_tmpl, M.config.worklog.heading),
			function(query, id, node, metadata)
				worklog_title_line = Util.get_node_range(node).row_start
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
			Util.execute_query(string.format(workspace_title_tmpl, workspace_title), function(query, id, node, metadata)
				local text = Util.get_node_text(node)
				workspace_title_line = Util.get_node_range(node).row_start
			end, bufnr)
		end

		vim.notify("workspace_title: " .. workspace_title)
		if workspace_title ~= nil then
			local file_in_worklog = false
			-- Escape special characters in file name for search
			local escaped_path = link:gsub("([^%w])", "%%%1")
			Util.execute_query("((list_marker_minus) (paragraph) @p)", function(query, id, node, metadata)
				local text = Util.get_node_text(node)
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
			table.insert(lines, 1, "## " .. M.config.worklog.heading)
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
		return bufnr
	end)
	vim.api.nvim_win_close(win, false)
	vim.api.nvim_buf_delete(bufnr, {})
	vim.api.nvim_buf_delete(b, {})
end

function M.open_today()
	local note = Client:daily(0)
	local path = Path.new(note.path):resolve()
	-- vim.api.nvim_buf_set_name(bufnr, tostring(path))
	local bufnr = vim.fn.bufadd(tostring(path))
	vim.fn.bufload(bufnr)
	vim.notify("setting " .. tostring(path) .. "in buffer " .. bufnr)
	-- Client:open_note(note, { sync = true, open_strategy = "current" })
	-- vim.api.nvim_buf_call(bufnr, function()
	-- vim.cmd("edit " .. tostring(path))
	-- end)
	return bufnr
end

-- return M
