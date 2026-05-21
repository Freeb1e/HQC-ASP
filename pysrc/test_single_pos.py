#!/usr/bin/env python3
"""
Single-position simulation test for HQC-ASP shift-and-add.

Usage:
    python3 pysrc/test_single_pos.py 1234
    python3 pysrc/test_single_pos.py 1234 --seed 99
    python3 pysrc/test_single_pos.py 1234 --verbose
"""

import numpy as np
import subprocess
import argparse
import sys
import os

N_BITS = 17669
N_WORDS = 138
NMOD = 5
TOTAL_WORDS = N_WORDS + 1
WORD_BITS = 128
RESULT_BYTES = TOTAL_WORDS * 16

SIM_BIN = "./obj_dir_fst/VTEST_PLATFORM"
BIN_DIR = "bin"


def bits_to_words(bits, n_words):
    words = []
    for i in range(n_words):
        val = 0
        for b in range(WORD_BITS):
            bit_idx = i * WORD_BITS + b
            if bit_idx < len(bits) and bits[bit_idx]:
                val |= (1 << b)
        words.append(val)
    return words


def words_to_bytes(words):
    result = bytearray()
    for w in words:
        result += w.to_bytes(16, byteorder='little')
    return bytes(result)


def bytes_to_words(data, n_words):
    words = []
    for i in range(n_words):
        w = int.from_bytes(data[i*16:(i+1)*16], byteorder='little')
        words.append(w)
    return words


def cyclic_shift_xor(dense_bits, position):
    n = len(dense_bits)
    result = np.zeros(n, dtype=np.uint8)
    for i in range(n):
        dst = (i + position) % n
        result[dst] ^= dense_bits[i]
    return result


def main():
    parser = argparse.ArgumentParser(description='HQC-ASP single-position test')
    parser.add_argument('pos', type=int, help=f'Position to test (0 to {N_BITS-1})')
    parser.add_argument('--seed', type=int, default=42, help='RNG seed for dense polynomial')
    parser.add_argument('--verbose', '-v', action='store_true', help='Print all words on mismatch')
    args = parser.parse_args()

    if not (0 <= args.pos < N_BITS):
        print(f"Error: pos must be in [0, {N_BITS-1}], got {args.pos}")
        sys.exit(1)

    pos = args.pos
    c = pos // WORD_BITS
    d = pos % WORD_BITS
    print(f"Testing pos={pos} (word={c}, bit={d}), seed={args.seed}")

    np.random.seed(args.seed)
    dense_bits = np.random.randint(0, 2, size=N_BITS, dtype=np.uint8)

    dense_words = bits_to_words(dense_bits, TOTAL_WORDS)
    dense_bytes = words_to_bytes(dense_words)
    os.makedirs(BIN_DIR, exist_ok=True)
    with open(os.path.join(BIN_DIR, 'dense.bin'), 'wb') as f:
        f.write(dense_bytes)

    sparse_bytes = pos.to_bytes(16, byteorder='little')
    with open(os.path.join(BIN_DIR, 'sparse.bin'), 'wb') as f:
        f.write(sparse_bytes)

    expected_bits = cyclic_shift_xor(dense_bits, pos)
    expected_words = bits_to_words(expected_bits, TOTAL_WORDS)

    print("Building simulator...")
    build = subprocess.run(["make", "build"], capture_output=True)
    if build.returncode != 0:
        print(f"FAIL: build failed")
        print(build.stderr.decode())
        sys.exit(1)

    result = subprocess.run([SIM_BIN], capture_output=True, timeout=10)
    if result.returncode != 0:
        print(f"FAIL: simulator crashed")
        print(f"  stderr: {result.stderr.decode()}")
        sys.exit(1)

    got_data = read_result()
    if len(got_data) < RESULT_BYTES:
        print(f"FAIL: result.bin too short ({len(got_data)} bytes, expected {RESULT_BYTES})")
        sys.exit(1)

    got_words = bytes_to_words(got_data, TOTAL_WORDS)
    nmod_mask = (1 << NMOD) - 1
    got_words[N_WORDS] &= nmod_mask

    mismatches = []
    for i in range(TOTAL_WORDS):
        exp = expected_words[i]
        if i == N_WORDS:
            exp &= nmod_mask
        if got_words[i] != exp:
            mismatches.append((i, got_words[i], exp))

    if mismatches:
        print(f"FAIL: {len(mismatches)} word(s) mismatch")
        limit = len(mismatches) if args.verbose else min(len(mismatches), 10)
        for i, got, exp in mismatches[:limit]:
            xor = got ^ exp
            print(f"  word[{i:3d}] got=0x{got:032x}")
            print(f"           exp=0x{exp:032x}")
            print(f"           xor=0x{xor:032x}")
        if not args.verbose and len(mismatches) > 10:
            print(f"  ... and {len(mismatches)-10} more (use --verbose to show all)")
        sys.exit(1)
    else:
        print("PASS")
        sys.exit(0)


def read_result():
    path = os.path.join(BIN_DIR, 'result.bin')
    with open(path, 'rb') as f:
        return f.read()


if __name__ == '__main__':
    main()
