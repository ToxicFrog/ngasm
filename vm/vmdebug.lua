local vmutil = require 'vmutil'

local vmdebug = {}
vmdebug.__index = vmdebug

function vmdebug.new(CPU)
  local dbg = {
    cpu = CPU;
    watches = {};
    symbols = {};
    breakpoints = {};
  }
  return setmetatable(dbg, vmdebug)
end

function vmdebug:reset()
  self.symbols = {}
  self.watches = {}
  self.breakpoints = {}
  return self
end

local function nameid(str)
  local hash = 0
  for char in str:gmatch('.') do
    hash = (hash*2 + char:byte()) % 0x10000
  end
  return hash
end

local symbol_types = {
  [':'] = 'rom';
  ['&'] = 'ram';
  ['#'] = 'constant';
  ['['] = 'macro';
}

local symbol_type_order = { rom = 1, ram = 2, constant = 3, macro = 4 }
local function sort_syms(x, y)
  if x.type == y.type then return x.value < y.value end
  return (symbol_type_order[x.type] or 0) < (symbol_type_order[y.type] or 0)
end

local function bind(self, id, name, line)
  for _,sym in ipairs(self.symbols) do
    if sym.id == id then
      if sym.name then
        print(string.format("WARNING: id %d used for both %s (at line %d) and %s (at line %d)",
          id, sym.name, sym.line or -1, name, line or -1))
      end
      sym.name = name
      sym.line = line
      sym.type = symbol_types[name:sub(1,1)] or '???'
      self.symbols[name] = sym -- fast name-to-symbol lookup
    end
  end
end

-- Load the given file as the source code for the loaded ROM, and attempt to
-- match up entries in the symbol table with declarations in the source.
-- This will be used to display labels for commands like list, trace, and symbols.
function vmdebug:source(source)
  self:load_symbols()
  local n = 0
  for line in io.lines(source) do
    n = n+1
    if line:match('^%s*[:%[&#].*') then
      local label = line:gsub('%s', ''):gsub('[;=].*', '')
      bind(self, nameid(label), label, n)
    end
  end
  -- Re-sort the symbol table using the new name and type information.
  table.sort(self.symbols, sort_syms)
end

function vmdebug:load_symbols()
  -- print(self, self.cpu)
  -- for k,v in pairs(self.cpu) do print('', k, v) end
  local rom = self.cpu.rom
  self.symbols = {}
  local symsize = rom[#rom]
  -- rough heuristic for whether there is actually a symbol table at the end
  -- of the ROM.
  if symsize % 2 == 0 and symsize > 0 and symsize < #rom/4 then
    for addr = #rom - symsize,#rom-2,2 do
      table.insert(self.symbols,
        { id = rom[addr], value = rom[addr+1] })
    end
  end
  table.sort(self.symbols, sort_syms)
  rom.size = rom.size - symsize
  return self
end

function vmdebug:toggle_watch(address)
  if self.watches[address] then
    self.watches[address] = nil
    return false
  else
    self.watches[address] = self.cpu.ram[address]
    return true
  end
end

-- Returns true if the breakpoint was set, false if unset.
function vmdebug:toggle_breakpoint(address)
  local set = self.breakpoints[address]
  self.breakpoints[address] = not set
  return not set
end

function vmdebug:check_watches()
  for addr,val in pairs(self.watches) do
    if self.cpu.ram[addr] ~= val then
      print(self)
      self.watches[addr] = self.cpu.ram[addr]
    end
  end
end

function vmdebug:disassemble(base, size)
  base = base or 0
  size = size or math.huge
  local eof = math.min(self.cpu.rom.size - 1, base + size - 1)

  return coroutine.wrap(function()
    for addr=base,eof do
      local word = self.cpu.rom[addr]
      local src = self.cpu:pc_to_source(addr)
      if not src:match('%+%d+$') then
        coroutine.yield(addr, 'label', src)
      end
      local op = vmutil.decode(word)
      coroutine.yield(addr, 'op', op)
    end
    return nil
  end)
end

-- Resolve a symbol. A + or - suffix offsets the symbol by that much.
-- Returns the resolved value (or nil).
-- As a second return value, returns the type of symbol:
-- - 'rom' for code labels
-- - 'ram' for variable names
-- - 'constant' for compile-time constants
-- - 'macro' for compile-time macros
-- The desired type may be specified as a second argument, in which case it
-- will refuse to resolve if the type doesn't match.
function vmdebug:resolve(symbol, type)
  local offset = 0
  if symbol:match('[+-][0-9]+$') then
    symbol,offset = symbol:match('(.*)([+-][0-9]+)$')
    offset = tonumber(offset)
  end
  local info = self.symbols[symbol]
  if not info then
    return nil,string.format("no entry for '%s' in symbol table", symbol)
  end
  if type and info.type ~= type then
    return nil,string.format(
      "symbol '%s' with value %04X has type '%s', but a value of type '%s' is required",
      symbol, info.value, info.type, type)
  end
  return info.value, info.type
end

-- TODO: implement to_symbol()
local registers = { A = true; D = true; IR = true; PC = true; }
function vmdebug:to_address(str, type)
  if registers[str:upper()] then return self.cpu[str:upper()] end
  str = str:gsub('^%$', '0x')
  if tonumber(str) then return tonumber(str) end
  return assert(self:resolve(str, type))
end

return vmdebug
