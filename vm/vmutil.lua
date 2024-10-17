-- vmutil -- utility functions for the VM that are not directly related to
-- emulating the CPU.

local bit = require 'bit'

local vmutil = {}

-- Return a table where every entry in the range [from,to) is set to val.
-- This is generally used to set RAM, which means that from is typically 0, not
-- 1 as is normal for arrays in lua.
function vmutil.fill(val, from, to)
  local t = {}
  for i=from,to-1 do
    t[i] = val
  end
  return t
end

-- Reopen an IO channel. If fd is set, close it. If filename is set, open it
-- with the given mode and return the new fd, else return nil.
function vmutil.reopen(fd, filename, mode)
  if fd then fd:close() end
  if filename then return assert(io.open(filename, mode)) end
end

-- Turn a string into a table of 16-bit words, STARTING AT 0, suitable for
-- initializing RAM or ROM from.
function vmutil.string_to_words(str)
  local words = {}
  local ptr = 0
  for i=1,#str,2 do
    local high,low = str:byte(i, i+1)
    words[ptr] = high*0x100 + low
    ptr = ptr+1
  end
  return words
end

-- return true if the given bit is set in the given number.
local function isset(n, bit_index)
  return bit.band(n, 2^bit_index) ~= 0
end

-- Turn an opcode into a human-readable string. Returns nil if it's a no-op.
local function op_to_str(op)
  if op.is_nop then
    return string.format('%04X [nop]', op.opcode)
  end

  if not op.ci then
    return string.format('%04X [A = %d]', op.opcode, op.opcode)
  end

  local s = {}

  -- for _,field in ipairs { 'mr', 'zx', 'sw', 'a', 'd', 'm' } do
  --   if op[field] == true then table.insert(s, field) end
  -- end

  local dst = ''
  if op.a then dst = dst..'A' end
  if op.d then dst = dst..'D' end
  if op.m then dst = dst..'M' end
  if #dst > 0 then
    table.insert(s, dst)
    table.insert(s, '=')
  end

  local alu = {[0] = '&', '|', '^', '!', '+', '+1', '-', '-1'}
  alu = alu[op.alu]

  local X = 'D'
  local Y = 'A'
  if op.mr then Y = 'M' end
  if op.sw then X,Y = Y,X end
  if op.zx then X = '0' end
  table.insert(s, X)
  table.insert(s, alu)
  table.insert(s, Y)


  local jmp = {'JGT', 'JEQ', 'JGE', 'JLT', 'JNE', 'JLE', 'JMP'}
  jmp = jmp[(op.lt and 4 or 0) + (op.eq and 2 or 0) + (op.gt and 1 or 0)]
  if #table > 0 and jmp then
    table.insert(s, ';')
  end
  table.insert(s, jmp)

  return string.format("%04X [%s]", op.opcode, table.concat(s, " "))
end

local alu_ops = {
  [0] = bit.band;
  [1] = bit.bor;
  [2] = bit.bxor;
  [3] = bit.bnot;
  [4] = function(x,y) return x+y end;
  [5] = function(x,_) return x+1 end;
  [6] = function(x,y) return x-y end;
  [7] = function(x,y) return x-1 end;
}

-- turn a 16-bit opcode stored as a number into a bunch of named bits
-- 'alu' field is a number 0-7 indexing the above table; 'alu_fn' is the
-- actual function to be called.
function vmutil.decode(opcode)
  local alu = bit.rshift(bit.band(opcode, 0x0700), 8);
  local op = {
    opcode = opcode;
    ci = isset(opcode, 0xF); -- compute instruction (if unset, load immediate)
    -- bits E and D unused
    mr = isset(opcode, 0xC); -- memory read
    -- bit B unused
    -- bits u, op1, and op0 we condense into a single number in the range 0-7
    -- to select the ALU operation
    alu = alu;
    alu_fn = alu_ops[alu];
    --u = isset(opcode, 0xA);
    --op1 = isset(opcode, 0x9);
    --op0 = isset(opcode, 0x8);
    zx = isset(opcode, 0x7); -- zero first operand to ALU
    sw = isset(opcode, 0x6); -- swap ALU operands before zeroing
    a  = isset(opcode, 0x5); -- write A
    d  = isset(opcode, 0x4); -- write D
    m  = isset(opcode, 0x3); -- write memory
    lt = isset(opcode, 0x2); -- jump if less than
    eq = isset(opcode, 0x1); -- jump if equal
    gt = isset(opcode, 0x0); -- jump if greater than
  }
  -- no-ops are computation instructions that have no jump bits and no
  -- write bits set
  op.is_nop = op.ci
    and not (op.lt or op.gt or op.eq)
    and not (op.a or op.d or op.m)
  return setmetatable(op, {__tostring = op_to_str})
end

function vmutil.find_mmio(devs, address)
  for base,dev in pairs(devs) do
    if address >= base and address < (base + dev:size()) then
      return dev, address-base
    end
  end
end

-- Convert a simple hex dump, consisting of hexadecimal digits and whitespace,
-- into a flashable ROM array.
function vmutil.hex2bin(data)
  local rom = {}
  local ptr = 0
  data = data:gsub("%s+", "") -- remove all whitespace
  assert(#data % 4 == 0, "ROM image has an odd number of bytes")
  for word in data:gmatch("%x%x%x%x") do
    rom[ptr] = tonumber(word, 16)
    ptr = ptr + 1
  end
  return rom
end

-- Convert an xxd hexdump into a ROM image.
-- xxd has the following format:
-- AAAAAAAA: XXXX XXXX XXXX XXXX XXXX XXXX XXXX XXXX  ................
-- where A is the address, X is the actual data, and . is the text dump.
-- We make the simplifying assumption that the dump is contiguous.
function vmutil.xxd2bin(data)
  data = data
    :gsub('%x+: +', '')
    :gsub('  .-\n', '')
  return vmutil.hex2bin(data)
end

return vmutil