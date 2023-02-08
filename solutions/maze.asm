# Maze-escape program.
# Conceptually, this is a simple wall-follower: put your right hand on the wall
# and follow it to the exit. However, it is (as ever) complicated by the tragic
# realities of hardware.
#
# The first of these is that the robot's only obstacle sensor points forward,
# so we need to turn right after each move to make sure the wall is still there.
# This makes our algorithm:
# - move forward
# - turn right
# - while there is a wall in front: turn left
# - restart
#
# The second complication is that all instructions to the robot take time to
# complete. So after every move or turn instruction, we need to wait for the
# robot to be idle.
#
# We end up with two main branches of the program:
# - find_opening does the "turn left until unblocked" part; it checks if the
#   robot is blocked, and calls turn_left_and_retry if it is and move_forward
#   if it isn't.
#   - turn_left_and_retry turns left and then calls find_opening again
# - move_forward moves the robot forward and then calls turn_right
#   - turn_right turns right and then calls find_opening
# Of course, after each move or turn, we need to wait for the robot. So any move
# or turn operation ends by calling wait. Depending on where we are in the
# program, the wait might need to be followed by turn_right or by find_opening;
# rather than write two different wait routines, we instead use the next_fn
# variable to hold the address of the routine to call after wait finishes.

# Variables.
# Flag indicating if we've found the initial wall.
# Not actually used in this version :)
#DEFINE found_wall   0x0000
# Pointer to the next state to execute after waiting.
DEFINE next_fn      0x0001
# Robot is memory mapped at 0x7FFF.
DEFINE robot        0x7FFF

# Constants.
# Writing bits 2-4 tells it to do stuff.
DEFINE GO_FORWARD   0x0004
DEFINE GO_LEFT      0x0008
DEFINE GO_RIGHT     0x0010
# Reading bits 8-10 returns robot status.
DEFINE IS_BLOCKED   0x0100
DEFINE IS_TURNING   0x0200
DEFINE IS_MOVING    0x0400
# "Is the robot doing something" bitmask is turning|moving
DEFINE IS_ACTIVE    0x0600

  LABEL startup
# Initial setup code. Runs only on program startup.
# Set up the continuation to call follow_wall, then wait->follow_wall.
A = find_opening
D = A
A = next_fn
*A = D
A = wait
A ; JMP

# Wait routine. Block until the robot is done whatever it's doing, then jump
# to whatever is stored in next_fn. The caller should write to next_fn the
# address of whatever routine should be called once the wait is finished.
  LABEL wait
A = IS_ACTIVE
D = A
A = robot
D = D & *A
# D is now nonzero if the robot is doing something, so in that case loop
A = wait
D ; JNE
# D was zero, so call the continuation
A = next_fn
A = *A
A ; JMP
# end wait

# find-opening routine. Initially called immediately after the robot has moved
# forward and turned right to face the wall. Rotates left until it finds an
# opening (which may entail 0 rotations), then transitions to move_forward.
  LABEL find_opening
# Check if the robot is blocked by something
A = IS_BLOCKED
D = A
A = robot
D = D & *A
A = turn_left_and_retry
# Robot is blocked, so turn_left -> wait -> find_opening
D ; JNE
A = move_forward
# Robot not blocked, so move_forward
A ; JMP
# end find_opening

# find_opening has found a wall in front o the robot. Schedule a left turn and
# then wait; after waiting, go back to find_opening and try again.
  LABEL turn_left_and_retry
A = GO_LEFT
D = A
A = robot
*A = D
# turn_left_and_retry is only ever called from find_opening, and find_opening
# is only ever called from this or from wait, so next_fn should already be set
# to find_opening. Because of this we can just go straight to wait and skip
# this code to set the continuation.
#A = find_opening
#D = A
#A = next_fn
#*A = D
A = wait
A ; JMP
# end turn_left_and_retry

# We found an opening! We should move forward, and then turn right to check if
# we're still following the wall.
# This just issues a GO_FORWARD command, then queues up turn_right using next_fn
# and hands off to wait.
  LABEL move_forward
A = GO_FORWARD
D = A
A = robot
*A = D
# Set up the continuation so that after waiting out the move we will turn_right.
A = turn_right
D = A
A = next_fn
*A = D
# Wait for the move to complete
A = wait
A ; JMP
# end move_forward

# We've just finished a move. We should turn right and then go back to find_opening.
# Similar deal to move_forward -- issue command, queue next operation, call wait.
  LABEL turn_right
A = GO_RIGHT
D = A
A = robot
*A = D
# Continuation should bring us back to find_opening
A = find_opening
D = A
A = next_fn
*A = D
# And wait
A = wait
A ; JMP
# end turn_right
