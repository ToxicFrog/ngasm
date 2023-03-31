next: next/ngasm.hex

clean:
	rm next/*

# Build the 'next' version of the compiler, i.e. build the current source
# code using the latest stable version of the compiler.
next/ngasm.hex: next/ngasm.asm
	./ngasm $< $@

next/ngasm.asm: compiler/*.asm
	cat compiler/*.asm > next/ngasm.asm

# Build the next version of the compiler twice, once using the stable version
# and once using itself, and compare the differences.
diff: next
	ROM=next/ngasm.hex ./ngasm next/ngasm.asm next/diff.hex
	diff -u --color=always next/ngasm.hex next/diff.hex

.PHONY: next clean
