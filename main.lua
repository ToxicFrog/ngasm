local vm = require "vm"
local iostream = require "iostream"

local CPU = vm.new()
CPU:flash {
  [0] =
  0b1000000010010000,
  0b0000000000000010,
  0b1000010100010000,
  0b1000000000000111,
}

CPU:trace(16)
CPU:reset()
CPU:attach(0x7FFE, iostream.new('test.out', 'wb'))
--CPU:attach(0x7FFC, iostream.new('test.in', 'r'))
print('----')

CPU:flash {
  [0] =
  0x7FFE, -- A = 0x7FFE
  0b1000000000001000, -- M = D
}
CPU:trace()
