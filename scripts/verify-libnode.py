#!/usr/bin/env python3
"""verify-libnode.py — Check that libnode.so is a valid shared library for dlopen."""
import struct
import sys

p = sys.argv[1]
d = open(p, 'rb').read(64)
assert d[:4] == b'\x7fELF', f"Not an ELF: {p}"
le = d[5] == 1
fmt = '<' if le else '>'
etype   = struct.unpack(fmt + 'H', d[16:18])[0]
machine = struct.unpack(fmt + 'H', d[18:20])[0]
e_phoff = struct.unpack(fmt + 'Q', d[32:40])[0]
phentsize = struct.unpack(fmt + 'H', d[54:56])[0]
phnum   = struct.unpack(fmt + 'H', d[56:58])[0]

interp = False
with open(p, 'rb') as f:
    for i in range(phnum):
        f.seek(e_phoff + i * phentsize)
        ph = f.read(phentsize)
        if struct.unpack(fmt + 'I', ph[0:4])[0] == 3:
            interp = True
            break

arch_names = {183: 'AArch64', 62: 'x86-64'}
print(f"  ET type:    {etype} (3=ET_DYN)")
print(f"  Machine:    {arch_names.get(machine, machine)}")
print(f"  PT_INTERP:  {'YES (PIE executable - BAD!)' if interp else 'none (shared lib - OK)'}")

assert etype == 3, f"FAIL: Expected ET_DYN(3), got {etype}"
assert not interp, "FAIL: PT_INTERP found — this is a PIE executable, not a shared library!"
print("  ✓ Valid shared library for dlopen")
