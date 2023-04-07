This directory contains a VM implementation for the NANDgame core. It is object
code compatible with the one on the nandgame website.

To run it, run the `vm` shell script. You must have luaJIT or another Lua 5.2
compatible implementation installed. Once it loads, you can use `help` to get a
list of commands, or view detailed help for specific commands.

You can also run it in batch mode by providing a series of commands to run as
command line arguments; see the `ngasm` script in the root of this repository
for an example.

It can:
- load ROM images in both binary and `xxd` format
- attach files on the host machine to the VM as memory-mapped stream IO devices
- single-step, run, and trace program execution
- watch memory edits to specific addresses
- load source code and correlate the labels in it with the ROM's included symbol
  table, if present
- disassemble the contents of ROM

See the builtin help for details on all of these capbilities.
