-- Public API for the VM.
-- Internal helpers are defined in vmutil.lua

local bit = require 'bit'
local vmutil = require 'vmutil'

local vm = {}
vm.__index = vm

local MAX_RAM = 2^15

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
    -- peripherals
    dev = {};
    -- debugging
    watches = {};
    symbols = {};
  }

  setmetatable(new_vm, vm)
  new_vm:reset()
  return new_vm
end

-- Reset the VM: set all registers and RAM to 0, and reopen any IO channels.
function vm:reset()
  self.A, self.D, self.IR, self.PC, self.CLK = 0,0,0,0,0
  self.ram = vmutil.fill(0, 0, MAX_RAM)
  self.stdin = vmutil.reopen(self.stdin, self.infile, 'rb')
  self.stdout = vmutil.reopen(self.stdout, self.outfile, 'wb')
  for _,dev in pairs(self.dev) do
    dev:reset()
  end
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
  self.symbols = {}
  local symsize = self.rom[#self.rom]
  -- rough heuristic for whether there is actually a symbol table at the end
  -- of the ROM.
  if symsize % 2 == 0 and symsize > 0 and symsize < #self.rom/4 then
    for addr = #self.rom - symsize,#self.rom-2,2 do
      local sym = { hash = self.rom[addr], addr = self.rom[addr+1] }
      table.insert(self.symbols, sym)
    end
  end
  table.sort(self.symbols, function(x,y) return x.addr < y.addr end)
  return self
end

local function nghash(str)
  local hash = 0
  for char in str:gmatch('.') do
    hash = (hash*2 + char:byte()) % 0x10000
  end
  return hash
end

local function bind(self, name, hash)
  for _,sym in ipairs(self.symbols) do
    if sym.hash == hash then
      sym.name = name
      return
    end
  end
  error("Symbol " .. name .. " has no entry in symbol table with hash " .. hash)
end

-- Load the given file as the source code for the loaded ROM.
-- This will be used to display labels in trace mode.
function vm:source(source)
  local label = "(start)"
  local label_addr = 0
  local nlabels = 0
  for line in io.lines(source) do
    -- we only look for labels here; other symbols either point into RAM or
    -- into the source file, not into ROM.
    if line:match('^%s*:.*') then
      label = line:gsub('%s', ''):gsub(';.*', '')
      bind(self, label, nghash(label))
    end
  end
end

-- Run n steps of the VM. If n is omitted, run until program completion.
function vm:run(n)
  return self:trace(n, function() end)
end

function vm:trace(n, fn)
  fn = fn or print
  n = n or math.huge
  for i=1,n do
    if not self.rom[self.PC] then
      -- no more program code!
      break
    end
    self:step()
    self:check_watches()
    fn(self)
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
  if op.mr then Y = self:ram_read(self.A) end
  if op.sw then X,Y = Y,X end
  if op.zx then X = 0 end
  -- compute result
  local R = bit.band(op.alu_fn(X, Y), 0xFFFF)
  -- if write bits are set, write result
  if op.a then self.A = R end
  if op.d then self.D = R end
  if op.m then self:ram_write(A, R) end
  -- if jump bits are set, jmp
  -- note that the & 0xFFFF above means the result will always be positive,
  -- since lua is not 16-bit -- so we check the high bit explicitly here.
  local negative = bit.band(R, 0x8000) ~= 0
  if (negative and op.lt) or (R == 0 and op.eq) or (R ~= 0 and not negative and op.gt) then
    self.PC = A
  end
end

function vm:pc_to_source(pc)
  local label = "(start)"
  if pc > 0 then
    label = label.."+"..pc
  end
  for _,sym in ipairs(self.symbols) do
    if sym.addr < pc and sym.name then
      label = sym.name.."+"..(pc - sym.addr)
    elseif sym.addr == pc and sym.name then
      label = sym.name
    end
  end
  return label
end

-- Output the VM state as a human-readable string, for debugging. Will be called
-- automatically by print(), tostring(), etc.
function vm:__tostring()
  -- we use self.ram here rather than ram_read() because if A is pointing to
  -- an MMIO device we don't want to actuate it while printing the VM state!
  return string.format("VM (IR:%-20s CLK:%04X D:%04X A:%04X MEM:%04X PC:%04X @ %s)",
    vmutil.decode(self.IR),
    self.CLK, self.D, self.A, self.ram[self.A] or 0xFFFF, self.PC,
    self:pc_to_source(self.PC))
end

-- Read RAM at the given address. This might return actual memory contents
-- or it might return some sort of memory mapped IO.
function vm:ram_read(address)
  assert(address >= 0 and address < MAX_RAM,
    string.format("Out of bounds memory read $%04X\n%s", address, tostring(self)))
  local dev,devaddr = vmutil.find_mmio(self.dev, address)
  if dev then
    return dev:read(devaddr)
  end
  return self.ram[address]
end

-- Write to RAM at the given address. As with ram_read this might store something
-- in ram or it might do memory mapped IO.
function vm:ram_write(address, word)
  assert(address >= 0 and address < MAX_RAM,
    string.format("Out of bounds memory write $%04X <- %d\n%s",
      address, word, tostring(self)))
  local dev,devaddr = vmutil.find_mmio(self.dev, address)
  if dev then
    dev:write(devaddr, word)
  end
  self.ram[address] = word
end

-- Attach a peripheral to memory-mapped IO. All memory reads and writes in the
-- range [base, base+dev:size()) will be redirected to it, calling
-- dev:write(addr-base) and dev:read(addr-base).
-- Trying to attach multiple devices to the same address is an error; detach
-- the original device first.
function vm:attach(base, dev)
  local eof = base + dev:size()-1
  -- check attachments
  for old_base,old_dev in pairs(self.dev) do
    local old_eof = old_base + old_dev:size()-1
    assert(base > old_eof or eof < old_base,
      string.format(
        "Attempt to attach overlapping peripherals: %s [%04X-%04X] vs. %s [%04X-%04X]",
        old_dev, old_base, old_eof, dev, base, eof))
  end
  self.dev[base] = dev
  dev:attach()
  return self
end

-- Detach the peripheral at the given address.
function vm:detach(base)
  assert(self.dev[base], string.format("Attempt to detach nonexistent device at address %04X", base))
  self.dev[base]:detach()
  self.dev[base] = nil
  return self
end

function vm:add_watch(address)
  self.watches[address] = 0
end

function vm:check_watches()
  for addr,val in pairs(self.watches) do
    if self.ram[addr] ~= val then
      print(self)
      self.watches[addr] = self.ram[addr]
    end
  end
end

-- end of library
return vm
