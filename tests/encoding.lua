local tests = ...

function tests.load_immediate(test)
  test:source [[
    @ 0
    @ $1234
    @ 6800
    @ 0777
    @ \%
  ]]

  test:check_rom [[ 0000 1234 1A90 01FF 0025 0000 ]]
end

function tests.jump(test)
  test:source [[
    = 0|D <=>
    = 0|A <=
    = 0|M >=
    = A+1 <>
    = D+1 <
    = M+1 >
    = A-D =
    = D-A
  ]]

  test:check_rom [[ 81C7 8186 9183 8545 8504 9541 8642 8600 0000 ]]
end

function tests.assign(test)
  test:source [[
    = 0+1
    A = 0+1
    D = 0+1
    M = 0+1
    AD = 0+1
    AM = 0+1
    DM = 0+1
    ADM = 0+1
  ]]

  test:check_rom [[ 8580 85A0 8590 8588 85B0 85A8 8598 85B8 0000 ]]
end

function tests.alu(test)
  test:source [[
    = D+A
    = D+1
    = 0+A
    = M-1
    = M-D
    = 0!
    = A!
    = D|A
    = M&D
    = D^1
  ]]

  test:check_rom [[ 8400 8500 8480 9740 9640 8380 8340 8100 9040 8300 0000 ]]
end

