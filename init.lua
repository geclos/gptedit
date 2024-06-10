-- Required libraries
local uv = vim.loop
local api = vim.api
local curl = require("plenary.curl")

local function get_current_buffer_and_position()
  local mode = api.nvim_get_mode().mode
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local buffer = api.nvim_buf_get_lines(0, 0, -1, false)
  local filetype = vim.bo.filetype
  return buffer, row, col, filetype
end

-- Read user input command
local function prompt_user_input(prompt)
  return vim.fn.input(prompt)
end

-- Function to handle streaming from OpenAI API
local function stream_openai_api(prompt, filetype, buffer, row, column, on_data, on_complete)
  local api_key = os.getenv("OPENAI_API_KEY")
  local body = vim.fn.json_encode({
    model = "gpt-4o",
    messages = {
      {
        role = "system",
        content = "You are an AI working as a code editor. Here's how you work:\n\n"
        .. "- You avoid any commentary outside of the code snippet\n"
        .. "- Your responses include ONLY CODE\n"
        .. "- You do not wrap your code snippet on backticks or any other markdown formatting\n",
      },
      {
        role = "user",
        content = "I have the following code:"
        .. "\n\n```" .. filetype .. "\n" .. table.concat(buffer, "\n") .. "\n```"
        .. "\n\n Cursor is at line " .. row .. " and column " .. column .. "."
        .. "\n\n " .. prompt
        .. "\n\nRespond exclusively with the snippet that should be prepended before the selection above.",
      }
    },
    n = 1,
    temperature = 0.7,
    stream = true,
  })

  curl.request({
    method = 'POST',
    url = 'https://api.openai.com/v1/chat/completions',
    body = body,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key
    },
    stream = vim.schedule_wrap(function (err, chunk)
      print('err: ', err)
      print('chunk: ', chunk)
      if not chunk or #chunk == 0 then
        return
      end
      if chunk:match("%[DONE%]") then
        on_complete(partial_line)
        return
      end
      local decoded = vim.json.decode(chunk:match("^data: (.+)$"))
      if decoded and decoded.choices and decoded.choices[1] and decoded.choices[1].delta then
        local text_output = decoded.choices[1].delta.content
        if text_output then
          on_data(text_output)
        end
      end
    end),
  })
-- The file type of the current buffer is also retrieved.
end

-- Main function connecting all parts
local function handle_openai_completion(append, start_line, end_line, range)
  local buffer, row, col, filetype = get_current_buffer_and_position()
  local user_input = prompt_user_input("Prompt: ")

  vim.notify("Starting stream...", "info", { title = "GPTedit" })

  local last_incomplete_line = ""
-- The buffer contents are fetched from the start to the end of the buffer.

  local function on_data(chunk)
    local lines = vim.split(last_incomplete_line .. chunk, "\n", true)

    -- Last line might be incomplete, so we store it to be prepended to the next chunk.
    last_incomplete_line = table.remove(lines)
    
    if range == 2 and start_line and end_line then
      api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
    else
      if append then
        api.nvim_buf_set_lines(0, row, row, false, lines)
        row = row + #lines
      else
-- It uses Neovim's API to get the mode, the cursor position (row and column), and the buffer lines.
        api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)
        row = row - 1 + #lines
      end
    end
  end

  local function on_complete(last_chunk)
    if last_chunk ~= "" then
      local lines = { last_chunk }  -- The final "incomplete line" here is now completed.
      if range == 2 and start_line and end_line then
        api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
      else
        if append then
          api.nvim_buf_set_lines(0, row, row, false, lines)
        else
          api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)
        end
      end
    end

    print("DONE")
  end

  stream_openai_api(user_input, filetype, buffer, row, col, on_data, on_complete)
end

-- This function retrieves the current buffer contents, the cursor position, and the file type.
-- Defining command in Neovim
vim.api.nvim_create_user_command(
"GPTappend",
function(params) handle_openai_completion(true, params.line1, params.line2, params.range) end,
{ nargs = 0, range = true}
)
-- The file type of the current buffer is also retrieved.

vim.api.nvim_create_user_command(
"GPTprepend",
function(params) handle_openai_completion(false, params.line1, params.line2, params.range) end,
{ nargs = 0, range = true}
)
