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
  return setmetatable(op, {__tostring = error})
end

function vmutil.find_mmio(devs, address)
  for base,dev in pairs(devs) do
    if address >= base and address < (base + dev:size()) then
      return dev, address-base
    end
  end
end

function vmutil.hex2bin(data)
  local buf = {}
  data = data:gsub("%s+", "") -- remove all whitespace
  for i=1,#data,2 do
    table.insert(buf, string.char(tonumber(data:sub(i,i+1), 16)))
  end
  return table.concat(buf, '')
end

-- Convert a simple hex dump, consisting of hexadecimal digits and whitespace,
-- into a flashable ROM array.
function vmutil.hex2rom(data)
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
function vmutil.xxd2rom(data)
  data = data
    :gsub('%x+: +', '')
    :gsub('  .-\n', '')
  return vmutil.hex2rom(data)
end

return vmutil