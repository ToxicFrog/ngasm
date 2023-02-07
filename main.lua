local vm = require "vm"

local CPU = vm.new()
CPU:flash {
  [0] =
  0b1000000010010000,
  0b0000000000000010,
  0b1000010100010000,
  0b1000000000000111,
}

for i=1,16 do
  CPU:step()
  print(CPU)
end
