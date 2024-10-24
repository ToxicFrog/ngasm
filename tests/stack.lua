local tests = ...

-- pushd, pusha, pushm, pushconst, pushvar
function tests.push(test)
  test:source [[
    :Init
    ~stack/init, $1000, $0F00
    @ $1234
    D = 0|A
    ~pushd
    @ $2345
    ~pusha
    @ &SP
    ~pushm
    ~pushconst, $3456
    ~pushvar, &SP
  ]]

  test:check_ram(
    '&SP', 0x1005,
    0x1000, { 0x1234, 0x2345, 0x1002, 0x3456, 0x1004, 0x0000 }
  )
end

function tests.dupdrop(test)
  test:source [[
    :Init
    ~stack/init, $1000, $0F00
    @ $4444
    D = 0|A
    ~pushd
    D = D+1
    ~pushd
    ~dup
    ~dup
    ~popd
    D = D+1
    ~pushd
    ~dup
    ~pushconst, 66
    ~pushconst, 77
    ~nip
  ]]

  test:check_ram(
    0x1000, { 0x4444, 0x4445, 0x4445, 0x4446, 0x4446, 77, }
  )
end

function tests.pop(test)
  test:source [[
    &first = $100
    &second = $101
    &third = $102
    &fourth = $103

    :Init
    ~stack/init, $1000, $0F00
    ~pushconst, 11
    ~popvar, &first
    ~pushconst, 22
    ~popd
    ~stored, &second
    ~pushconst, 33
    ~popa
    ~storea, &third
    ~pushconst, 44
    @ &fourth
    ~popm
  ]]

  test:check_ram(
    '&SP', 0x1000,
    '&first', 11,
    '&second', 22,
    '&third', 33,
    '&fourth', 44
  )
end

function tests.pop2(test)
  test:source [[
    &first = $100
    &second = $101
    &third = $102

    :Init
    ~stack/init, $1000, $0F00
    ~pushconst, 33
    ~pushconst, 22
    ~pushconst, 11
    ~popvar, &first
    ~popd
    ~stored, &second
    ~popa
    ~storea, &third
  ]]

  test:check_ram(
    '&SP', 0x1000,
    '&first', 11,
    '&second', 22,
    '&third', 33
  )
end

function tests.math(test)
  test:source [[
    :Init
    ~stack/init, $1000, $0F00
    ~pushconst, 451
    ~pushconst, 85
    ~add
    ~pushconst, 451
    ~pushconst, 85
    ~sub
    ~pushconst, 12
    ~inctop
    ~pushconst, 12
    ~dectop
  ]]

  test:check_ram(
    '&SP', 0x1004,
    0x1000, { 451+85, 451-85, 13, 11 }
  )
end

function tests.logic(test)
  test:source [[
    :Init
    ~stack/init, $1000, $0F00
    ~pushconst, 12
    ~pushconst, 12
    ~eq
    ~dup
    ~not
    ~pushconst, 12
    ~pushconst, 12
    ~neq
    ~dup
    ~not
  ]]

  test:check_ram(
    '&SP', 0x1004,
    0x1000, { 1, 0, 0, 1 }
  )
end
