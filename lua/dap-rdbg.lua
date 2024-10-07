local M = {}

local dap = require('dap')
local repl = require('dap.repl')

---@class PluginConfiguration
---@field rdbg RDBGConfiguration?
---@field configurations table<Configuration>?
---@field remote {host:string, port:number}? default remote debugger host and port
---@field timeout number

---@class RDBGConfiguration
---@field path string
---@field use_bundler boolean

---@class Configuration
---@field type "rdbg"
---@field request "launch"|"attach"
---@field name string
-- type launch option
---@field command? string
---@field script? string
---@field args? table<string>|fun()
---@field use_bundler? boolean
-- type attach option
---@field sock_file? string|fun() via Unix domain socket
---@field addr? string|fun() via TCP/IP

---@type PluginConfiguration
local internal_global_config = {}

---@type PluginConfiguration
local default_config = {
  rdbg = {
    path = 'rdbg',
    use_bundler = false,
  },
  remote = {
    host = '127.0.0.1',
    port = 12345,
  },
  configurations = {},
  timeout = 3000,
}

-- https://github.com/leoluz/nvim-dap-go/blob/5511788255c92bdd845f8d9690f88e2e0f0ff9f2/lua/dap-go.lua#L34C1-L42C4
---@param prompt string
local function ui_input_list(prompt)
  return coroutine.create(function(dap_run_co)
    local args = {}
    vim.ui.input({ prompt = prompt }, function(input)
      args = vim.split(input or '', ' ')
      coroutine.resume(dap_run_co, args)
    end)
  end)
end

---@param prompt string
local function ui_input_text(prompt)
  return coroutine.create(function(dap_run_co)
    vim.ui.input({ prompt = prompt }, function(input)
      local txt = input or ''
      coroutine.resume(dap_run_co, txt)
    end)
  end)
end

local function get_arguments()
  return ui_input_list('Args: ')
end

local function build_command_args(plugin_opts, config)
  local args = {}
  local use_bundler = config.use_bundler or plugin_opts.rdbg.use_bundler
  local command = ''
  local common_rdbg_args = { '--open', '--command', '--' }
  if use_bundler then
    command = 'bundle'
    vim.list_extend(args, { 'exec', 'rdbg' })
    vim.list_extend(args, common_rdbg_args)
    vim.list_extend(args, { 'bundle', 'exec' })
  else
    command = plugin_opts.rdbg.path
    vim.list_extend(args, common_rdbg_args)
  end

  vim.list_extend(args, { config.command, config.script })
  config.args = config.args or {}
  vim.list_extend(args, config.args)
  return {
    command = command,
    args = args,
  }
end

local function rails_unix_domain_socket(callback, plugin_opts, config)
  local sock_path = os.tmpname() .. '_nvim_dap_rdbg'
  local tb = build_command_args(plugin_opts, config)
  local command = tb.command
  local args = { '--sock-path', sock_path, '--nonstop' }
  vim.list_extend(args, tb.args)

  local commands = { command }
  vim.list_extend(commands, args)

  local rdbg_start = false
  local debugger_log_count = 0
  vim.fn.jobstart(commands, {
    on_stdout = function(job_id, data, event)
      for _, line in ipairs(data) do
        repl.append(line)
      end
    end,
    on_stderr = function(job_id, data, event)
      for _, line in ipairs(data) do
        repl.append(line)
        if line:find('DEBUGGER: Debugger') then
          debugger_log_count = debugger_log_count + 1
          -- 何故か2回 rdbg のログが出る。1回目の出たところでつなぐことができない。
          rdbg_start = debugger_log_count == 2
        end
      end
    end,
  })

  vim.wait(config.timeout or internal_global_config.timeout, function()
    return rdbg_start
  end)

  callback({
    type = 'pipe',
    pipe = sock_path,
    enrich_config = function(cfg, on_config)
      local final_config = vim.deepcopy(cfg)
      final_config.request = 'attach'
      on_config(final_config)
    end,
  })
end

---@param plugin_opts PluginConfiguration
local function setup_adapter(plugin_opts)
  -- Dap.AdapterFactory fun(callback: fun(adapter: Adapter), config: Configuration, parent?: Session)
  -- https://github.com/mfussenegger/nvim-dap/blob/0.8.0/lua/dap.lua#L217
  -- https://github.com/mfussenegger/nvim-dap/blob/0.8.0/lua/dap.lua#L232-L233
  dap.adapters.rdbg = function(callback, config)
    config = vim.deepcopy(config)

    if config.command == 'rails' then
      -- rails_tcp(callback, plugin_opts, config)
      rails_unix_domain_socket(callback, plugin_opts, config)
      -- rails_unix_domain_socket2(callback, plugin_opts, config)
      -- rails_executable(callback, plugin_opts, config)
    elseif config.request == 'launch' then
      local tb = build_command_args(plugin_opts, config)
      local command = tb.command
      local args = { '--sock-path', '${pipe}' }
      vim.list_extend(args, tb.args)

      callback({
        type = 'pipe',
        pipe = '${pipe}',
        executable = {
          command = command,
          args = args,
        },
      })
    elseif config.sock_file ~= nil then
      callback({
        type = 'pipe',
        pipe = config.sock_file,
      })
    else
      local host = plugin_opts.remote.host
      local port = plugin_opts.remote.port
      if config.addr ~= nil and config.addr ~= '' then
        local tmp_addr = vim.split(vim.trim(config.addr), ':')
        assert(#tmp_addr == 2, 'invalid addr form: given ' .. config.addr .. ' expected like host:port')
        host = tmp_addr[1]
        port = tonumber(tmp_addr[2], 10)
      end
      callback({
        type = 'server',
        host = host,
        port = port,
      })
    end
  end
end

---@param plugin_opts PluginConfiguration
local function setup_dap_configurations(plugin_opts)
  dap.configurations.ruby = dap.configurations.ruby or {}

  local common_configurations = {
    {
      type = 'rdbg',
      name = 'Ruby Debugger: Current File',
      request = 'launch',
      command = 'ruby',
      script = '${file}',
    },
    {
      type = 'rdbg',
      name = 'Ruby Debugger: Current File with Arguments',
      request = 'launch',
      command = 'ruby',
      script = '${file}',
      args = get_arguments,
    },
    {
      type = 'rdbg',
      name = 'Ruby Debugger: Rails server',
      request = 'attach',
      command = 'rails',
      args = { 'server' },
      localfs = true,
      timeout = 3000,
    },
    {
      type = 'rdbg',
      name = 'Ruby Debugger: Remote Attach via Unix domain socket',
      request = 'attach',
      sock_file = function()
        return ui_input_text('socket file path: ')
      end,
    },
    {
      type = 'rdbg',
      name = 'Ruby Debugger: Remote Attach via TCP/IP',
      request = 'attach',
      localfs = true,
      addr = function()
        return ui_input_text('addr (default ' .. plugin_opts.remote.host .. ':' .. plugin_opts.remote.port .. '): ')
      end,
    },
  }

  vim.list_extend(dap.configurations.ruby, common_configurations)
  vim.list_extend(dap.configurations.ruby, plugin_opts.configurations)
end

---@param opts PluginConfiguration
function M.setup(opts)
  internal_global_config = vim.tbl_deep_extend('force', default_config, opts or {})
  setup_adapter(internal_global_config)
  setup_dap_configurations(internal_global_config)
end

function M.get_arguments()
  return get_arguments()
end

function M.ui_input_list(prompt)
  return ui_input_list(prompt)
end

function M.ui_input_text(prompt)
  return ui_input_text(prompt)
end

function M.get_config()
  return internal_global_config
end

return M
