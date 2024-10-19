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
      local src = self:pc_to_label(addr)
      if not src:match('%+%d+$') then
        coroutine.yield(addr, 'label', src)
      end
      local op = self.cpu:decode(addr)
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

-- Turn a typed number or label into an address.
-- If it's a register name or a number, returns the contents of the register
-- or the parsed number with no type checking.
-- Otherwise, tries to resolve it in the symbol table, with optional type
-- checking, e.g. a request for a 'rom' address will not resolve if the symbol
-- table entry is of type 'ram'.
local registers = { A = true; D = true; IR = true; PC = true; }
function vmdebug:to_address(str, type)
  if registers[str:upper()] then return self.cpu[str:upper()] end
  str = str:gsub('^%$', '0x')
  if tonumber(str) then return tonumber(str) end
  return assert(self:resolve(str, type))
end

-- Turn an address into the set of symbols with that value.
-- Returns a table mapping symbol names to symbol info, or nil if no symbols
-- with the requested value exist.
function vmdebug:to_symbols(value)
  local syms = {}
  for _,info in ipairs(self.symbols) do
    if info.value == value then
      syms[info.name] = info
    end
  end
  return next(syms) and syms or nil
end

-- Turns a program counter value into a ":Label+offset" label.
-- Returns nil if no symbol table is loaded.
function vmdebug:pc_to_label(pc)
  if #self.symbols == 0 then return nil end

  local symbol = nil
  for _,info in ipairs(self.symbols) do
    if info.type ~= 'rom' or info.value > pc then break end
    symbol = info
  end
  if symbol then
    if symbol.value == pc then return symbol.name end
    return symbol.name..'+'..(pc - symbol.value)
  elseif pc == 0 then
    return '(start)'
  else
    return '(start)+'..pc
  end
end

local function alu_to_str(op)
  local alu = {
    [0] = 'X&Y', 'X|Y', 'X^Y', '!X',
          'X+Y', 'X+1', 'X-Y', 'X-1',
  }
  alu = alu[op.alu]

  local X,Y = 'D','A'
  if op.mr then Y = 'M' end
  if op.sw then X,Y = Y,X end
  if op.zx then X = '0' end

  return (alu:gsub('X', X)
    :gsub('Y', Y)
    :gsub('0[|^+]', '')
    :gsub('1&', ''))
end

local function compute_op_to_str(op)
  local dst = (op.a and 'A' or '') .. (op.d and 'D' or '') .. (op.m and 'M' or '')
  local alu = alu_to_str(op)
  local asm
  if #dst > 0 then
    asm = string.format('%3s = %-3s', dst, alu)
  else
    asm = string.format('      %3s', alu)
  end

  local jmp = {'JGT', 'JEQ', 'JGE', 'JLT', 'JNE', 'JLE', 'JMP'}
  jmp = jmp[(op.lt and 4 or 0) + (op.eq and 2 or 0) + (op.gt and 1 or 0)]

  local sep = jmp and '⯈' or '┊'

  return asm,sep,jmp or ''
end

local function load_op_to_str(opcode)
  local sep,char = '┊',''
  if opcode >= 0x20 and opcode <= 0x7e then
    -- Annotate with printable ASCII character, if any
    sep = '◁'
    char = string.format('\\%c', opcode)
  end
  return '@ '..opcode, sep, char
end

-- Turn an opcode into a human-readable string.
local function op_str(op)
  if op.is_nop then
    return string.format('%04X ┋ %-9s ┊ %3s', op.opcode, 'nop', '')
  elseif not op.ci then
    return string.format('%04X ┋ %-9s %s %-3s', op.opcode, load_op_to_str(op.opcode))
  else
    return string.format('%04X ┋ %-9s %s %-3s', op.opcode, compute_op_to_str(op))
  end
end

local function sym_annotations(self, op)
  if op.ci then return '' end
  local syms = self:to_symbols(op.opcode)
  if not syms then return '' end
  local buf = { ' ⧏' }
  for sym,info in pairs(syms) do
    if info.type ~= 'macro' then
      table.insert(buf, sym)
    end
  end
  if #buf > 1 then
    return table.concat(buf, ' ')
  else
    return ''
  end
end

-- Return a human-readable string describing the given opcode.
-- If labels is false, returns a fixed-width (15 cols, 16 bytes) format
-- containing the disassembly. Load instructions in the ASCII printable range
-- are annotated with the corresponding character.
-- If symbols is true, load instructions are additionally annotated with any
-- symbol names that hold that value.
function vmdebug:op_to_string(op, symbols)
  op.str = op.str or op_str(op)
  if symbols and #self.symbols > 0 then
    op.symbols = op.symbols or sym_annotations(self, op)
    return op.str .. op.symbols
  else
    return op.str
  end
end

return vmdebug
