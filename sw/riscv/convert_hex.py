from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

memory = {}
address = 0

for line in src.read_text().splitlines():
    for token in line.split():
        if token.startswith("@"):
            address = int(token[1:], 16)
        else:
            memory[address] = int(token, 16)
            address += 1

if not memory:
    raise SystemExit("No data found in input file.")

start = min(memory)
end = max(memory)

if start % 4 != 0:
    raise SystemExit("Starting address is not word-aligned.")

with dst.open("w") as f:
    f.write(f"@{start // 4:08X}\n")

    for base in range(start, end + 1, 4):
        word = sum(
            memory.get(base + i, 0) << (8 * i)
            for i in range(4)
        )
        f.write(f"{word:08X}\n")

print(f"Converted {src} to {dst}")