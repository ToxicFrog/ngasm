-- Public API for the VM.
-- Internal helpers are defined in vmutil.lua

local bit = require 'bit'
local vmutil = require 'vmutil'

local vm = {}
vm.__index = vm

-- Create a new VM. Initially it has no program loaded, calls to run() will halt
-- immediately and calls to step() will raise an error. Use :flash() to load a
-- program before starting it.
function vm.new()
  local new_vm = {
    -- registers
    A = 0; D = 0; IR = 0; PC = 0; CLK = 0;
    -- memory. These are tables mapping memory address (which may be 0!) to
    -- contents.
    ram = {};
    rom = {};
    -- stream IO connections
    infile = nil; outfile = nil; -- names of files on disk
    stdin = nil; stdout = nil; -- actual file handles
  }

  setmetatable(new_vm, vm)
  new_vm:reset()
  return new_vm
end

-- Reset the VM: set all registers and RAM to 0, and reopen any IO channels.
function vm:reset()
  self.A, self.D, self.IR, self.PC, self.CLK = 0,0,0,0,0
  self.ram = vmutil.fill(0, 0, 2^15)
  self.stdin = vmutil.reopen(self.stdin, self.infile, 'rb')
  self.stdout = vmutil.reopen(self.stdout, self.outfile, 'wb')
  return self
end

-- Flash the VM with a new program.
-- If rom is a table, the VM will hold a reference to it (not a copy).
-- If rom is a string, it will be parsed as a stream of 16-bit words.
function vm:flash(rom)
  if type(rom) == 'table' then
    self.rom = rom
  else
    self.rom = vmutil.string_to_words(rom)
  end
  return self
end

-- Run n steps of the VM. If n is omitted, run until program completion.
function vm:run(n)
  n = n or math.huge
  for i=1,n do
    self:step()
    if not self.rom[self.PC] then
      -- no more program code!
      break
    end
  end
  return self
end

-- Execute a single instruction. Due to the structure of the processor there is
-- a strict 1 instruction = 1 clock cycle relationship.
function vm:step()
  -- fetch the next instruction
  self.IR = self.rom[self.PC]
  -- increment PC - do this now rather than after instruction dispatch so we
  -- don't JMP to the wrong address
  self.PC = self.PC+1

  -- decode instruction. If load immediate, we just handle it here.
  local op = vmutil.decode(self.IR)
  if not op.ci then
    self.A = op.opcode
  else
    -- If a compute instruction, hand off to the more complicated instruction
    -- dispatch function.
    self:dispatch(op)
  end

  -- increment system clock
  self.CLK = self.CLK+1
end

-- Execute a decoded opcode. Note that this is not a full step -- it's used
-- internally by vm:step() and does not advance the clock or anything.
-- End users probably should not call this but I think it is more at home in
-- this file.
function vm:dispatch(op)
  local A = self.A -- save A in case we need to jump
  local X, Y = self.D, self.A
  -- It's important to handle these in order -- memory read first, then swap,
  -- then zero X.
  if op.mr then Y = self:ram_read(cpu.A) end
  if op.sw then X,Y = Y,X end
  if op.zx then X = 0 end
  -- compute result
  local R = bit.band(op.alu_fn(X, Y), 0xFFFF)
  -- if write bits are set, write result
  if op.a then self.A = R end
  if op.d then self.D = R end
  if op.m then self:ram_write(A, R) end
  -- if jump bits are set, jmp
  if (R < 0 and op.lt) or (R == 0 and op.eq) or (R > 0 and op.gt) then
    self.PC = A
  end
end

-- Output the VM state as a human-readable string, for debugging. Will be called
-- automatically by print(), tostring(), etc.
function vm:__tostring()
  -- we use self.ram here rather than ram_read() because if A is pointing to
  -- an MMIO device we don't want to actuate it while printing the VM state!
  return string.format("VM (CLK:%04X D:%04X A:%04X MEM:%04X PC:%04X IR:%s NEXT:%s)",
    self.CLK, self.D, self.A, self.ram[self.A], self.PC,
    vmutil.decode(self.IR),
    self.rom[self.PC] and vmutil.decode(self.rom[self.PC]) or '----')
end

-- Read RAM at the given address. This might return actual memory contents
-- or it might return some sort of memory mapped IO.
function vm:ram_read(address)
  return self.ram[address]
end

-- Write to RAM at the given address. As with ram_read this might store something
-- in ram or it might do memory mapped IO.
function vm:ram_write(address, word)
  self.ram[address] = word
end

-- end of library
return vm
