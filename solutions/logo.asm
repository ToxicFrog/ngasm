DEFINE img 0x4F0F
DEFINE ptr 0x0100

# initialization
A = img
D = A
A = ptr
*A = D


LABEL start
# write the first word
A = 0b0101010101010101
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0101010101010101
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0000000000000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0000000000000001
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0101111111111100
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0000000100000000
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0000000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0000011011000001
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0100000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0000100100100000
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0000000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0001000000010001
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0100000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0001000000010000
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0000000011111000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0010000000001001
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0100000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0010000000001000
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0000000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0010000000001001
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0100000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0010000000001000
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0000000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0011111111111001
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0100000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0000100000100000
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0000000010000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0000100000100001
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0100000000000000
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0000000000000000
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
### write the next line
A = 0b0101010101010101
D = A
# read in the address of where to write
A = ptr
A = *A
*A = D
# increment the write address
A = ptr
*A = *A+1
# write the next word
A = 0b0101010101010101
D = A
A = ptr
A = *A
*A = D
# move the write pointer to the next line, by adding 31 to it
A = 31
D = A
A = ptr
*A = D + *A
# end
