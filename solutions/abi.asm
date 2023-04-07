# DEFMACRO CALL functionName argumentCount
# ( args... -- retval )
# Call a function.
# Use by pushing all arguments to the function onto the stack, then invoking
# CALL with the function name and the number of arguments.

# Save ARGS & LOCALS stack region pointers
PUSH_STATIC ARGS
PUSH_STATIC LOCALS
# Push return value -- macro expander will make sure the "return" label gets
# properly adjusted for every use of CALL in the program. ✨magic✨
PUSH_VALUE return
# Point ARGS at the start of the argument region. This is SP minus 3 for the
# three values we just pushed, minus argumentCount so it points to the first
# argument.
A = argumentCount
D = A
A = 3
D = D + A
# D is now (3 + argumentCount), so subtract it from SP and stuff the result in ARGS
A = SP
D = *A - D
A = ARGS
*A = D
# Jump to the function we're calling.
D = *A
A = functionName
JMP

    LABEL return
# postscript -- runs after we return from the called function. Our saved LOCALS
# is now on top of the stack, with the return value in RETVAL.
# Restore stack region pointers.
POP_STATIC LOCALS
POP_STATIC ARGS
# Pop all arguments by directly adjusting SP.
A = argumentCount
D = A
A = SP
*A = *A - D
# Push the return value we're done.
PUSH_STATIC RETVAL


# DEFMACRO FUNCTION functionName localsCount
# ( -- locals... )
# Used to declare a function.
# Defines a label with the given name.
# When the function is called, ARGS will point to the first argument passed to
# the function, and LOCALS will point to the first of the locals you asked for.
# The locals are uninitialized!

  LABEL functionName
# Set up the LOCALS stack region pointer
A = SP
D = *A
A = LOCALS
*A = D
# Allocate locals
A = localsCount
D = A
A = SP
*A = D + *A


# DEFMACRO RETURN
# ( retval -- )
# Returns from the enclosing function, returning the value on top of the stack.
# Note that you must return SOMETHING; if you haven't pushed anything since
# entering the function it returns the last local, and if you have no locals
# it crashes the program.
# Move the return value into our temporary
POP_STATIC RETVAL
# Release locals
A = SP
D = *A
A = LOCALS
*A = D
# pop address and return
POP_A
JMP
