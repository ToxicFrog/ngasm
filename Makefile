next: next/ngasm.hex

clean:
	rm next/*

next/ngasm.asm: compiler/*.asm
	cat compiler/*.asm > next/ngasm.asm

# Build the 'next' version of the compiler, i.e. build the current source
# code using the latest stable version of the compiler.
next/ngasm.stable.next.hex next/ngasm.stable.next.bin: next/ngasm.asm
	@echo "Building 'next' using 'stable'..."
	./ngasm $< next/ngasm.stable.next

# Self-build the 'next' version, using the stable.next compiler ROM.
next/ngasm.next.next.hex next/ngasm.next.next.bin: next/ngasm.stable.next.hex next/ngasm.asm
	@echo "Building 'next' using 'next-built-by-stable'..."
	ROM=next/ngasm.stable.next.hex SRC=next/ngasm.asm ./ngasm next/ngasm.asm next/ngasm.next.next

# Build the next version of the compiler twice, once using the stable version
# and once using itself, and compare the differences.
diff: next/ngasm.stable.next.hex next/ngasm.next.next.hex
	@echo "Diffing both ROMs: next-built-by-stable vs. next-built-by-next"
	./nglist next/ngasm.stable.next.hex next/ngasm.asm > next/ngasm.stable.next.list 2>/dev/null
	./nglist next/ngasm.next.next.hex next/ngasm.asm > next/ngasm.next.next.list 2>/dev/null
	diff -u --color=always next/ngasm.stable.next.list next/ngasm.next.next.list | less -RF

# Build the stable.next version of the compiler, then load it into the debugger.
debug: next/ngasm.stable.next.hex
	@echo "Entering debugger."
	ROM=next/ngasm.stable.next.hex SRC=next/ngasm.asm rlwrap ./ngasm next/ngasm.asm /dev/null info shell

.PHONY: next clean debug
