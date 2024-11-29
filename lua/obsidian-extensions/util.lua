-- local lib = require("lua-utils")
local ts = vim.treesitter

local Util = {}

function Util.get_node_text(node, source)
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

function Util.get_node_range(node)
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

function Util.execute_query(query_string, callback, source, start, finish)
	local query = Util.ts_parse_query("markdown", query_string)
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

function Util.ts_parse_query(language, query_string)
	if vim.treesitter.query.parse then
		return vim.treesitter.query.parse(language, query_string)
	else
		---@diagnostic disable-next-line
		return vim.treesitter.parse_query(language, query_string)
	end
end

--- Wrapped around `match()` that performs an action based on a condition.
--- @param comparison boolean The comparison to perform.
--- @param when_true function|any The value to return when `comparison` is true.
--- @param when_false function|any The value to return when `comparison` is false.
--- @return any # The value that either `when_true` or `when_false` returned.
--- @see neorg.core.lib.match
function Util.when(comparison, when_true, when_false)
	if type(comparison) ~= "boolean" then
		comparison = (comparison ~= nil)
	end

	return lib.match(type(comparison) == "table" and unpack(comparison) or comparison)({
		["true"] = when_true,
		["false"] = when_false,
	})
end

return Util
