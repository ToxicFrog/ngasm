next: next/ngasm.hex

clean:
	rm next/*

# Build the 'next' version of the compiler, i.e. build the current source
# code using the latest stable version of the compiler.
next/ngasm.hex: next/ngasm.asm
	@echo "Building 'next' using 'stable'..."
	./ngasm $< $@

next/ngasm.asm: compiler/*.asm
	cat compiler/*.asm > next/ngasm.asm

next/diff.hex: next/ngasm.hex next/ngasm.asm
	@echo "Building 'next' using 'next-built-by-stable'..."
	ROM=next/ngasm.hex SRC=next/ngasm.asm ./ngasm next/ngasm.asm next/diff.hex

# Build the next version of the compiler twice, once using the stable version
# and once using itself, and compare the differences.
diff: next/ngasm.hex next/diff.hex
	@echo "Diffing both ROMs: next-built-by-stable vs. next-built-by-next"
	./nglist next/diff.hex next/ngasm.asm > diff-next.list 2>/dev/null
	./nglist next/ngasm.hex next/ngasm.asm > diff-stable.list 2>/dev/null
	diff -u --color=always diff-stable.list diff-next.list | less -RF

.PHONY: next clean
