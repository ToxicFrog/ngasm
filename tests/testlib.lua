local vm = require 'vm'
local vmutil = require 'vmutil'
local memstream = require 'memstream'

local function printf(...)
  io.stdout:write(string.format(...))
  io.stdout:flush()
end

local function rom_str(bin)
  local buf = {}
  for i=1,#bin,2 do
    local h,l = bin:byte(i, i+1)
    table.insert(buf, string.format('%04X', h*256 + l))
  end
  return table.concat(buf, ' ')
end

local Test = {}
Test.__index = Test

function Test.new(compiler)
  return setmetatable({ compiler = compiler, errors = {} }, Test)
end

function Test:source(src)
  local bin = memstream.new('')
  self.compiler:reset()
  self.compiler:attach(0x7FF0, memstream.new(src))
  self.compiler:attach(0x7FF8, bin)
  self.compiler:run(self.time_limit or math.huge)
  self.compiler:detach(0x7FF0)
  self.compiler:detach(0x7FF8)
  self.rom = bin.buf
  -- print('compilation complete, bytes emitted:', #self.rom)
end

function Test:error(err)
  local lines = {}
  table.insert(lines, string.format(unpack(err)))
  if err.expected then
    table.insert(lines, string.format('%9s: %s', 'Expected', rom_str(err.expected)))
    table.insert(lines, string.format('%9s: %s', 'Got', rom_str(err.rom)))
  end
  table.insert(self.errors, table.concat(lines, '\n'))
end

function Test:check_error(line, pass)
end

function Test:check_valid_rom()
  if self.build_error == nil then
    if #self.rom % 2 == 1 then
      local h,l,pass = self.rom:byte(-3, -1)
      self.build_error = {
        pass = pass;
        line = h * 256 + l;
      }
      self:error {
        'Build failed on pass %d at line %d',
        self.build_error.pass, self.build_error.line
      }
    else
      self.build_error = false
    end
  end
  return not self.build_error
end

function Test:check_rom(addr, value, ...)
  if not addr then return end
  if not self:check_valid_rom() then return end

  if not value then
    -- check entire ROM
    local bin = vmutil.hex2bin(addr)
    if bin ~= self.rom then
      self:error {
        'Emitted ROM does not match expected image:';
        expected = bin, rom = self.rom;
      }
    end
    return self:check_rom(value, ...)
  elseif addr == '*' then
    -- check if value appears anywhere in ROM
    local bin = vmutil.hex2bin(value)
    if not self.rom:match(bin, 1, true) then
      self:error {
        'Emitted ROM does not contain expected code:';
        expected = bin, rom = self.rom;
      }
    end
    return self:check_rom(...)
  else
    -- check if value appears at specified address
    addr = tonumber(addr)
    local bin = vmutil.hex2bin(value)
    if self.rom:match(bin, addr, true) ~= addr then
      self:error {
        'Emitted ROM does not contain expected code at address $%04X:', addr;
        expected = bin, rom = self.rom:sub(addr, addr+#bin-1);
      }
    end
    return self:check_rom(...)
  end
end

function Test:check_ram(hex)
end

local function run_test_case(cpu, tests, name, fn)
  local test = Test.new(cpu)

  printf('    %-22s [', name)
  tests.before(test)
  fn(test)
  tests.after(test)
  if #test.errors > 0 then
    for _,err in ipairs(test.errors) do
      -- print(err)
    end
    printf('\x1B[1;31m FAIL \x1B[0m]\n')
    return false
  end
  printf('\x1B[1;32m PASS \x1B[0m]\n')
  return true
end

function run_test_suite(cpu, file)
  local ignore = { name = true; before = true; after = true; }
  local tests = {
    name = file:gsub('%.lua$','');
    before = function() end;
    after = function() end;
  }
  local total,passed = 0,0

  assert(loadfile(file))(tests)
  for k,v in pairs(tests) do
    if not ignore[k] then
      total = total + 1
      passed = passed + (run_test_case(cpu, tests, k, v) and 1 or 0)
    end
  end
  return passed,total
end

local function main(compiler_rom, compiler_src, ...)
  local cpu = vm.new()
  cpu:flash(io.open(compiler_rom, 'rb'):read('*a'))
  cpu.debug:source(compiler_src)

  for _,file in ipairs {...} do
    printf('  %-24s\n', file)
    local passed,total = run_test_suite(cpu, file)
    printf('  %-24s [ %s%2d/%-2d%s]\n',
      file,
      passed == total and '\x1B[1;32m' or '\x1B[1;31m',
      passed, total, '\x1B[0m')
  end
end

return main(...)