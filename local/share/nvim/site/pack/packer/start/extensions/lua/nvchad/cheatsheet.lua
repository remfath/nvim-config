local add_highlight = vim.api.nvim_buf_add_highlight

local function display_cheatsheet(mappings)
   if vim.g.nvchad_cheatsheet_displayed then
      return
   end

   vim.g.nvchad_cheatsheet_displayed = true
   vim.cmd [[autocmd BufWinLeave * ++once lua vim.g.nvchad_cheatsheet_displayed = false]]

   local function spaces(amount)
      return string.rep(" ", amount)
   end

   local ns = vim.api.nvim_create_namespace "nvchad_cheatsheet"

   local lines = {}

   local win, buf
   local heading_lines = {}
   local section_lines = {}
   local section_titles = {}
   local border_lines = {}

   local width = vim.o.columns
   local height = vim.o.lines

   local function parse_mapping(mapping)
      mapping = string.gsub(mapping, "C%-", "ctrl+")
      mapping = string.gsub(mapping, "c%-", "ctrl+")
      mapping = string.gsub(mapping, "%<leader%>", "leader+")
      mapping = string.gsub(mapping, "%<(.+)%>", "%1")
      return mapping
   end

   local spacing = math.floor((width * 0.6 - 38) / 2)

   if spacing < 4 then
      spacing = 0
   end

   local line_nr = 0

   for main_sec, section_contents in pairs(mappings) do
      table.insert(lines, " ")
      table.insert(lines, spaces(spacing - 4) .. main_sec)

      line_nr = line_nr + 2
      table.insert(section_titles, line_nr)

      for Title, values in pairs(section_contents) do
         if type(values) == "table" then
            lines[#lines + 1] = " "
            line_nr = line_nr + 1
            lines[#lines + 1] = spaces(spacing) .. Title

            table.insert(heading_lines, line_nr)

            line_nr = line_nr + 1
            lines[#lines + 1] = " "
            line_nr = line_nr + 1

            table.insert(lines, spaces(spacing) .. "▛" .. string.rep("▀", 36) .. "▜")
            table.insert(border_lines, line_nr)

            line_nr = line_nr + 1

            for mapping, key in pairs(values) do
               if type(key) == "boolean" and not key then
                  goto continue -- the continue tag is at the end of the for loop
               end

               if type(key) == "string" then
                  key = parse_mapping(key)
                  table.insert(
                     lines,
                     spaces(spacing) .. "▌" .. mapping .. string.rep(" ", 35 - #mapping - #key) .. key .. " ▐"
                  )

                  table.insert(section_lines, line_nr)
                  line_nr = line_nr + 1
               else
                  if type(key[1]) == "string" then
                     key[1] = parse_mapping(key[1])
                     table.insert(
                        lines,
                        spaces(spacing)
                           .. "▌"
                           .. mapping
                           .. string.rep(" ", 35 - #mapping - #key[1])
                           .. key[1]
                           .. " ▐"
                     )

                     table.insert(section_lines, line_nr)
                     line_nr = line_nr + 1
                  elseif type(key) == "table" then
                     table.insert(
                        lines,
                        spaces(spacing) .. "▌" .. mapping .. ":" .. string.rep(" ", 35 - #mapping) .. "▐"
                     )
                     table.insert(section_lines, line_nr)
                     line_nr = line_nr + 1

                     for mapping_name, keystroke in pairs(key) do
                        keystroke = parse_mapping(keystroke)
                        table.insert(
                           lines,
                           spaces(spacing)
                              .. "▌  "
                              .. mapping_name
                              .. string.rep(" ", 35 - #mapping_name - 2 - #keystroke)
                              .. keystroke
                              .. " ▐"
                        )

                        table.insert(section_lines, line_nr)
                        line_nr = line_nr + 1
                     end
                  end
               end
               ::continue::
            end

            table.insert(lines, spaces(spacing) .. "▙" .. string.rep("▄", 36) .. "▟")
            table.insert(border_lines, line_nr)

            line_nr = line_nr + 1
            table.insert(lines, " ")
            line_nr = line_nr + 1
         else
            lines[#lines + 1] = " "
            line_nr = line_nr + 1
            table.insert(
               lines,
               spaces(spacing) .. "▌" .. Title .. string.rep(" ", 35 - #Title - #values) .. values .. " "
            )

            table.insert(section_lines, line_nr)
            line_nr = line_nr + 1

            table.insert(lines, spaces(spacing) .. "▙" .. string.rep("▄", 36) .. "▟")
            table.insert(section_lines, line_nr)
            line_nr = line_nr + 1
         end
      end
   end
   buf = vim.api.nvim_create_buf(false, true)

   vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
   vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>q<CR>", { noremap = true, silent = true, nowait = true })
   vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

   win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = math.floor(width * 0.6),
      height = math.floor(height * 0.9),
      col = math.floor(width * 0.2),
      row = math.floor(height * 0.1),
      border = "none",
      style = "minimal",
   })

   vim.api.nvim_buf_set_option(buf, "filetype", "nvchad_cheatsheet")
   vim.api.nvim_win_set_option(win, "wrap", false)

   local highlight_nr = 1

   for _, line in ipairs(heading_lines) do
      if true then
         highlight_nr = highlight_nr + 1
         add_highlight(buf, ns, "CheatsheetTitle" .. highlight_nr, line, spacing >= 4 and spacing or 0, -1)

         if highlight_nr == 6 then
            highlight_nr = 1
         end
      end
   end

   for _, line in ipairs(section_lines) do
      add_highlight(buf, ns, "CheatsheetSectionContent", line, spacing, -1)
   end

   for _, line in ipairs(border_lines) do
      add_highlight(buf, ns, "CheatsheetBorder", line, spacing, -1)
   end

   for _, line in ipairs(section_lines) do
      add_highlight(buf, ns, "CheatsheetBorder", line, spacing + 2, spacing + 3)
      vim.api.nvim_buf_add_highlight(buf, ns, "CheatsheetBorder", line, spacing + 41, spacing + 42)
   end

   for _, line in ipairs(section_titles) do
      add_highlight(buf, ns, "CheatsheetHeading", line - 1, 1, -1)
   end

   vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

local cheatsheet = {}

cheatsheet.show = function()
   -- Lua is copy by reference so make a deep copy of the table
   local mappings = vim.deepcopy(require("core.utils").load_config().mappings)
   local pluginMappings = mappings.plugins
   mappings.plugins = nil

   display_cheatsheet {
      ["Plugin Mappings"] = pluginMappings,
      ["Normal mappings"] = mappings,
   }
end

return cheatsheet
