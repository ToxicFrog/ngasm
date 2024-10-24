local vm = require 'vm'
local vmutil = require 'vmutil'
local memstream = require 'memstream'

local function printf(...)
  io.stdout:write(string.format(...))
  io.stdout:flush()
end

local function rom_str(bin, start, size)
  local buf = {}
  start = start or 1
  size = size or math.min(#bin, 16)
  for i=1,size,2 do
    local h,l = bin:byte(start+i-1, start+i)
    table.insert(buf, string.format('%04X', h*256 + l))
  end
  return table.concat(buf, ' ')
end

local function ram_str(ram, start, size)
  start = start or 1
  size = size or math.min(#ram, 16)
  local buf = {}
  for i=start,start+size-1 do
    table.insert(buf, string.format('%04X', ram[i] or 0))
  end
  return table.concat(buf, ' ')
end

local Test = {}
Test.__index = Test

function Test.new(compiler)
  return setmetatable({
    compiler = compiler;
    errors = {};
    use_headers = true;
  }, Test)
end

function Test:source(src)
  if self.use_headers then
    local prelude = assert(io.open('next/prelude.asm')):read('*a')
    local postscript = assert(io.open('next/postscript.asm')):read('*a')
    src = prelude .. src .. postscript
  end
  local bin = memstream.new('')
  self.compiler:reset()
  self.compiler:attach(0x7FF0, memstream.new(src))
  self.compiler:attach(0x7FF8, bin)
  self.compiler:run(self.time_limit or math.huge)
  self.compiler:detach(0x7FF0)
  self.compiler:detach(0x7FF8)
  self.rom = bin.buf
  self.src = src
  -- print('compilation complete, bytes emitted:', #self.rom)
end

function Test:error(err)
  local lines = {}
  table.insert(lines, string.format(unpack(err)))
  if err.expected then
    table.insert(lines, string.format('%9s: %s', 'Expected', err.expected))
  end
  if err.actual then
    table.insert(lines, string.format('%9s: %s', 'Got', err.actual))
  end
  if err.src then
    table.insert(lines, 'Failing source code:')
    for _,srcline in ipairs(err.src) do
      table.insert(lines, srcline)
    end
  end
  for i=1,#lines do
    lines[i] = '\x1B[1;31m║\x1B[0m '..lines[i]
  end
table.insert(self.errors, table.concat(lines, '\n'))
end

function Test:error_if(condition)
  if not condition then
    return function() end
  else
    return function(...) return self:error(...) end
  end
end

function Test:check_error(line, pass)
end

local function lines_around(src, err)
  local n = 0
  local buf = {}
  for line in src:gmatch('([^\n]*)\n') do
    n = n+1
    if n >= err-2 and n <= err+2 then
      table.insert(buf,
        string.format('%4s%4d ┊ %s',
          n == err and '->> ' or '',
          n, line))
    end
  end
  return buf
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
        'Build failed on pass %d at line %d (%s)',
        self.build_error.pass, self.build_error.line,
        src = lines_around(self.src, self.build_error.line),
        (self.build_error.pass == 0) and "syntax error" or "symbol lookup error";
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
    self:error_if(bin ~= self.rom) {
      'Emitted ROM does not match expected image:';
      expected = rom_str(bin), actual = rom_str(self.rom);
    }
    return self:check_rom(value, ...)
  elseif addr == '*' then
    -- check if value appears anywhere in ROM
    local bin = vmutil.hex2bin(value)
    self:error_if(not self.rom:match(bin, 1, true)) {
      'Emitted ROM does not contain expected code:';
      expected = rom_str(bin), -- actual = self.rom;
    }
    return self:check_rom(...)
  else
    -- check if value appears at specified address
    addr = self.cpu.debug:to_address(addr, 'rom')
    local bin = vmutil.hex2bin(value)
    self:error_if(self.rom:match(bin, addr, true) ~= addr) {
      'Emitted ROM does not contain expected code at address $%04X:', addr;
      expected = rom_str(bin), actual = rom_str(self.rom, addr, #bin);
    }
    return self:check_rom(...)
  end
end

function Test:run_test_rom()
  if not self.cpu then
    local cpu = vm.new()
    cpu:flash(self.rom)
    cpu.debug:source(self.src)
    cpu:reset()
    cpu:run()
    self.cpu = cpu
  end
  return true
end

local function diff_region(ram, addr, expected)
  for i=0,#expected-1 do
    if ram[addr+i] ~= expected[i+1] then
      return true
    end
  end
  return false
end

function Test:check_ram(addr, value, ...)
  if not addr then return nil end
  if not self:check_valid_rom() then return end
  if not self:run_test_rom() then return end

  local true_addr = self.cpu.debug:to_address(addr, 'ram')
  if type(value) == 'number' then
    self:error_if(self.cpu.ram[true_addr] ~= value) {
      'RAM at $%04X%s has wrong value %04X (≠ %04X)',
      true_addr, addr ~= true_addr and ' ('..addr..')' or '',
      self.cpu.ram[true_addr], value
    }
  elseif type(value) == 'table' then
    self:error_if(diff_region(self.cpu.ram, true_addr, value)) {
      'RAM at address $%04X%s does not match expected values',
      true_addr, addr ~= true_addr and ' ('..addr..')' or '';
      expected = ram_str(value);
      actual = ram_str(self.cpu.ram, true_addr, #value);
    }
  else
    -- TODO: automatic string to ram conversion
    error()
  end
  return self:check_ram(...)
end

local function run_test_case_on_cpu(cpu, tests, name, fn)
  local test = Test.new(cpu)

  printf(' [')
  tests.before(test)
  fn(test)
  tests.after(test)
  if #test.errors > 0 then
    printf('\r\x1B[1;31m╓──╼\x1B[0m%-22s [\x1B[1;31m FAIL\x1B[0m %-8s ]\n',
      name, '('..cpu._name..')')
    -- FIXME: this is all spiders with the new dual-cpu code
    for _,err in ipairs(test.errors) do
      print(err)
    end
    -- print('\x1B[1;31m╙   \x1B[0m ')
    return false
  end
  printf('\x1B[1;32m PASS \x1B[0m]')
  return true
end

local function run_test_case(stable, next, tests, name, fn)
  printf('    %-22s', name)

  return run_test_case_on_cpu(stable, tests, name, fn),
    run_test_case_on_cpu(next, tests, name, fn),
    printf('\n')
end

local function run_test_suite(stable, next, file)
  local ignore = { name = true; before = true; after = true; }
  local tests = {
    name = file:gsub('%.lua$','');
    before = function() end;
    after = function() end;
  }
  local spassed,npassed = 0,0

  local names = {}
  assert(loadfile(file))(tests)
  for k in pairs(tests) do
    if not ignore[k] then
      table.insert(names, k)
    end
  end
  table.sort(names)
  for _,name in ipairs(names) do
    local sp,np = run_test_case(stable, next, tests, name, tests[name])
    spassed = spassed + (sp and 1 or 0)
    npassed = npassed + (np and 1 or 0)
  end
  return spassed,npassed,#names
end

local function main(stable_rom, stable_src, next_rom, next_src, ...)
  local stable = vm.new()
  stable:flash(assert(io.open(stable_rom, 'rb')):read('*a'))
  stable.debug:source(stable_src)
  stable._name = 'stable'
  local next = vm.new()
  next:flash(assert(io.open(next_rom, 'rb')):read('*a'))
  next.debug:source(next_src)
  next._name = 'devel'

  for _,file in ipairs {...} do
    printf('  \x1B[4m%s\x1B[0m\n', file)
    local spassed,npassed,total = run_test_suite(stable, next, file)
    printf('  %-24s [ %s%2d/%-2d%s] [ %s%2d/%-2d%s]\n',
      '',
      spassed == total and '\x1B[1;32m' or '\x1B[1;31m',
      spassed, total, '\x1B[0m',
      npassed == total and '\x1B[1;32m' or '\x1B[1;31m',
      npassed, total, '\x1B[0m')
  end
end

return main(...)