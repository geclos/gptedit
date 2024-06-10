-- Required libraries
local uv = vim.loop
local api = vim.api
local curl = require("plenary.curl")

-- Function to get current buffer content and cursor position
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

-- Function to make OpenAI API request
local function call_openai_api(prompt, filetype, buffer, row, column)
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
        .. "\n\n Cursor is at line " .. row .. "and column " .. column .. "."
        .. "\n\n " .. prompt
        .. "\n\nRespond exclusively with the snippet that should be prepended before the selection above.",
      }
    },
    n = 1,
    temperature = 0.7,
    stream = false,
  })

  vim.notify(vim.inspect(payload), "info", { title = "GPTedit" })

  local response = curl.post('https://api.openai.com/v1/chat/completions', {
    body = body,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key
    }
  })

  return vim.fn.json_decode(response.body)
end

-- Main function connecting all parts
local function handle_openai_completion(append, start_line, end_line, range)
  local buffer, row, col, filetype = get_current_buffer_and_position()
  local user_input = prompt_user_input("Prompt: ")
  local response = call_openai_api(user_input, filetype, buffer, row, col)

  -- Get the text response from OpenAI API
  local text_output = response.choices[1].message.content
  local text_output_lines = vim.split(text_output, "\n", false)

  if range == 2 and start_line and end_line then
    api.nvim_buf_set_lines(0, start_line - 1, end_line, false, text_output_lines)
  else
    if append then
      api.nvim_buf_set_lines(0, row, row, false, text_output_lines)
    else
      api.nvim_buf_set_lines(0, row - 1, row - 1, false, text_output_lines)
    end
  end
end

-- Defining command in Neovim
vim.api.nvim_create_user_command(
  "GPTappend",
  function(params) handle_openai_completion(true, params.line1, params.line2, params.range) end,
  { nargs = 0, range = true}
)

vim.api.nvim_create_user_command(
  "GPTprepend",
  function(params) handle_openai_completion(false, params.line1, params.line2, params.range) end,
  { nargs = 0, range = true}
)
