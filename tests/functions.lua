local tests = ...

-- pushd, pusha, pushm, pushconst, pushvar
function tests.call1(test)
  test:source [[
    :Return_Five
    ~function, 0
    ~pushconst, 5
    ~return

    :Init
    ~stack/init, $1000
    ~call, :Return_Five, 0
  ]]

  test:check_ram(
    '&SP', 0x1001,
    0x1001, { 5 }
  )
end

function tests.add(test)
  test:source [[
    :Add
    ~function, 2
    ~popd
    @ &SP
    A = M-1
    D = D+M
    ~drop
    ~pushd
    ~return

    :Init
    ~stack/init, $1000
    ~pushconst, $0055
    ~pushconst, $3300
    ~call, :Add, 2
  ]]

  test:check_ram(
    '&SP', 0x1001,
    0x1001, { 0x3355 }
  )
end

function tests.recurse(test)
  test:source [[
    :Recur
    ~function
    ~popd
    @ :Recur_Zero
    D = D-1 <=
    ~pushd
    ~call, :Recur
    ~jmp, :Recur_End
    :Recur_Zero
    ~pushconst, 99
    :Recur_End
    ~return

    :Init
    ~stack/init, $1000,$100
    ~pushconst, 5
    ~call, :Recur
  ]]

  test:check_ram(
    '&SP', 0x1001,
    0x1001, { 99 }
  )
end
