# Memory-mapped IO
# Wire is read only, see the _BIT constants.
DEFINE wire 0x6001
# Screen is read-write, 512x256, 16px per address.
DEFINE screen 0x4000

# Constants
DEFINE DATA_BIT 0x0001
DEFINE SYNC_BIT 0x0002
DEFINE WORDS_PER_LINE 32

# Variables
DEFINE sync   0x0001
DEFINE data   0x0002
DEFINE eof    0x0003
DEFINE buf    0x0004
DEFINE bits   0x0005
DEFINE pen    0x0006

# Continuations
DEFINE after_read_bit 0x1000

# Startup
# Position the pen at (16,16). +1 moves it 16px right and +32 (512/16) moves it
# 1px down, so we need to add (1 + 16*32) = 513 to the base screen address.
A = 513
D = A
A = screen
D = D + A
A = pen
*A = D
# Start by reading a word; program will bounce back and forth between read_word
# and draw_word.
A = read_word
A ; JMP


# Procedure for blitting a single word to the screen and then moving the screen
# draw pointer down one line.
# Assumes that the location to draw to is at *pen and the word to draw is at
# *buf.
# Calls read_word afterwards.
  LABEL draw_word
A = buf
D = *A
A = pen
A = *A
*A = D
A = WORDS_PER_LINE
D = A
A = pen
*A = D + *A
A = read_word
A ; JMP

# Procedure for reading an entire word.
# Transmissions consist of either:
# a 1, followed by 16 bits of data, or
# a 0, signifying end of transmission.
# In the former case, it will fill *buf and then return.
# In the latter, it will set *eof to non-zero. The contents of *buf are undefined.
  LABEL read_word
# Startup - read one bit and continue to check_header
A = check_header
D = A
A = after_read_bit
*A = D
A = read_bit
A ; JMP
  LABEL check_header
# If the bit we just read is 0, end the program
A = data
D = *A
A = exit
D ; JEQ
# It's 1, so we can expect 16 more bits of data. Set *bits to the number of bits
# we expect and clear *buf.
A = 16
D = A
A = bits
*A = D
A = buf
*A = 0
  LABEL next_bit
# This is the main bit-reading loop. It looks something like:
# while (*bits != 0) {
#   *buf <<= 1
#   *buf += read_bit()
#   *bits -= 1
# }
# If *bits is 0, we're done reading this word and should bail out.
A = bits
D = *A
A = draw_word
D ; JEQ
# It's not zero, so shift buf to make room by adding it to itself.
A = buf
D = *A
D = D + *A
*A = D
# read in the next bit. Set the continuation to pack_bit.
A = pack_bit
D = A
A = after_read_bit
*A = D
A = read_bit
A ; JMP
  LABEL pack_bit
# Add the bit we just read to the buf.
A = data
D = *A
A = buf
*A = D + *A
# Decrement the number of bits left.
A = bits
*A = *A - 1
# And start a new loop iteration.
A = next_bit
A ; JMP


# Procedure for reading a single bit from the wire.
# Blocks until a bit is read, then leaves the bit in *data.
  LABEL read_bit
# get the current sync signal so we can watch for differences:
# *sync = (SYNC_BIT & *wire)
A = SYNC_BIT
D = A
A = wire
D = D & *A
A = sync
*A = D
  LABEL wait_for_sync
# Read the wire and compare the sync bit to the stored version.
# Loop until they are different.
A = SYNC_BIT
D = A
A = wire
D = D & *A
A = sync
D = D - *A
# If sync hasn't changed, keep waiting
A = wait_for_sync
D ; JEQ
  LABEL read_bit_actual
# Sync has changed, so read the data bit off the wire and write it to *data.
A = DATA_BIT
D = A
A = wire
D = D & *A
A = data
*A = D
# Return to caller.
A = after_read_bit
A = *A
A ; JMP

  LABEL exit
