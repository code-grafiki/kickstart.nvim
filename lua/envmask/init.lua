-- envmask.nvim: hide secrets in .env files as *****
-- A lightweight Neovim plugin inspired by camouflage.nvim's extmark overlay approach.

local M = {}

M.config = {
  mask_char = '*',
  highlight = 'Conceal',
}

M.ns = vim.api.nvim_create_namespace('envmask')

---Check whether a buffer holds an env-like file.
---@param bufnr integer
---@return boolean
function M.is_env_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return false
  end
  local base = vim.fn.fnamemodify(name, ':t')
  -- Skip example/template files: they usually hold placeholders, not secrets.
  if base:match('example') or base:match('sample') or base:match('template') then
    return false
  end
  return base == '.env'
    or base == '.envrc'
    or base:match('^%.env[%.%w]') ~= nil
    or base:match('%.env$') ~= nil
end

---Parse a single line and return the byte ranges (0-based columns) of secret
---values that should be masked.
---@param line string
---@return {start_col: integer, end_col: integer, width: integer}[]
local function parse_regions(line)
  local regions = {}

  -- Skip blank lines and comments.
  if line:match('^%s*$') or line:match('^%s*#') then
    return regions
  end

  local eq = line:find('=', 1, true)
  if not eq then
    return regions
  end

  local after = line:sub(eq + 1)
  local leading = after:match('^%s*') or ''
  local L = #leading
  local rest = after:sub(L + 1)
  if #rest == 0 then
    return regions
  end

  local start_col = eq + L -- 0-based column of first char of `rest`

  local first = rest:sub(1, 1)
  if first == '"' or first == "'" or first == '`' then
    local quote = first
    local pos = 2
    while pos <= #rest do
      local c = rest:sub(pos, pos)
      if c == '\\' then
        pos = pos + 2
      elseif c == quote then
        break
      else
        pos = pos + 1
      end
    end
    if pos <= #rest then
      local inner = rest:sub(2, pos - 1)
      if #inner > 0 then
        table.insert(regions, {
          start_col = start_col + 1,
          end_col = start_col + pos - 1,
          width = vim.fn.strdisplaywidth(inner),
        })
      end
    end
  else
    -- Cut trailing inline comments (unquoted values).
    local comment_idx = rest:find('%s+#')
    local token_source = rest
    if comment_idx then
      token_source = rest:sub(1, comment_idx - 1)
    end
    local token = token_source:match('^(.-)%s*$') or ''
    if #token > 0 then
      table.insert(regions, {
        start_col = start_col,
        end_col = start_col + #token,
        width = vim.fn.strdisplaywidth(token),
      })
    end
  end

  return regions
end

---Apply (or re-apply) masks to a buffer.
---@param bufnr integer|nil
function M.mask_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M.is_env_file(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  if vim.b[bufnr].envmask_enabled == false then
    return
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok or type(lines) ~= 'table' then
    return
  end

  for i, line in ipairs(lines) do
    local regions = parse_regions(line)
    for _, r in ipairs(regions) do
      local mask = string.rep(M.config.mask_char, math.max(1, r.width))
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, i - 1, r.start_col, {
        end_row = i - 1,
        end_col = r.end_col,
        virt_text = { { mask, M.config.highlight } },
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        priority = 100,
      })
    end
  end
end

---Toggle masking for the current (or given) buffer.
---@param bufnr integer|nil
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].envmask_enabled == false then
    vim.b[bufnr].envmask_enabled = true
  else
    vim.b[bufnr].envmask_enabled = false
  end
  M.mask_buf(bufnr)
end

---Enable masking for the current (or given) buffer.
---@param bufnr integer|nil
function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.b[bufnr].envmask_enabled = true
  M.mask_buf(bufnr)
end

---Disable masking for the current (or given) buffer.
---@param bufnr integer|nil
function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.b[bufnr].envmask_enabled = false
  M.mask_buf(bufnr)
end

---Setup the plugin.
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})

  vim.api.nvim_create_user_command('EnvMaskToggle', function()
    M.toggle()
  end, { desc = 'Toggle env secret masking' })
  vim.api.nvim_create_user_command('EnvMaskEnable', function()
    M.enable()
  end, { desc = 'Enable env secret masking' })
  vim.api.nvim_create_user_command('EnvMaskDisable', function()
    M.disable()
  end, { desc = 'Disable env secret masking' })

  local group = vim.api.nvim_create_augroup('envmask', { clear = true })

  local function apply(args)
    M.mask_buf(args.buf)
  end

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile', 'BufEnter' }, {
    group = group,
    callback = apply,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    callback = apply,
  })

  -- Apply to already-open buffers.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.mask_buf(bufnr)
    end
  end
end

return M
