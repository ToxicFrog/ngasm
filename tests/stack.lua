local tests = ...

-- pushd, pusha, pushm, pushconst, pushvar
function tests.push(test)
  test:source [[
    :Init
    ~stack/init, $1000
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
    0x1002, { 0x1234, 0x2345, 0x1002, 0x3456, 0x1004, 0x000 }
  )
end

function tests.dupdrop(test)
  test:source [[
    :Init
    ~stack/init, $1000
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
  ]]

  test:check_ram(
    0x1002, { 0x4444, 0x4445, 0x4445, 0x4446, 0x4446, 0x0000 }
  )
end

function tests.pop(test)
  test:source [[
    &first = $100
    &second = $101
    &third = $102
    &fourth = $103

    :Init
    ~stack/init, $1000
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
    ~stack/init, $1000
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
