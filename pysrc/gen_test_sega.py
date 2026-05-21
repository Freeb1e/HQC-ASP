#!/usr/bin/env python3
"""
Generate HQC-1 test vectors for SEG_A wrap-around XOR verification.

HQC-1 parameters:
  n = 17669 bits
  n_words = 138 (full 128-bit words)
  nmod = 5 (remaining bits in word[138])
  Total words stored: 0..138, word[138] has only bits[4:0] valid

Test strategy:
  Pick a sparse position with c > 0 so SEG_A has multiple iterations.
  Compute the full cyclic shift result in Python, then compare the
  SEG_A portion (result blocks 0..c-1) against RTL output.
"""

import numpy as np
import os
import struct

# HQC-1 parameters
N_BITS = 17669
N_WORDS = 138       # n / 128
NMOD = 5            # n % 128
TOTAL_WORDS = N_WORDS + 1  # words 0..138
WORD_BITS = 128

# Test position: configurable via command line or default
import sys
if len(sys.argv) > 1:
    TEST_POSITION = int(sys.argv[1])
else:
    TEST_POSITION = 1000

def bits_to_words(bits, n_words):
    """Convert a bit array to list of 128-bit integers (little-endian bit order within word)."""
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
    """Convert list of 128-bit integers to bytes (little-endian)."""
    result = bytearray()
    for w in words:
        result += w.to_bytes(16, byteorder='little')
    return bytes(result)

def cyclic_shift_xor(dense_bits, position):
    """Compute dense << position mod (x^n - 1) in GF(2)."""
    n = len(dense_bits)
    result = np.zeros(n, dtype=np.uint8)
    for i in range(n):
        dst = (i + position) % n
        result[dst] ^= dense_bits[i]
    return result

def main():
    np.random.seed(42)

    # Generate random dense polynomial (n bits)
    dense_bits = np.random.randint(0, 2, size=N_BITS, dtype=np.uint8)

    # Compute expected result: dense shifted by TEST_POSITION
    expected_bits = cyclic_shift_xor(dense_bits, TEST_POSITION)

    # Convert to 128-bit words
    dense_words = bits_to_words(dense_bits, TOTAL_WORDS)
    expected_words = bits_to_words(expected_bits, TOTAL_WORDS)

    # Sparse polynomial: just one position for this test
    # Stored as 16-bit values, 8 per 128-bit word
    sparse_word = TEST_POSITION  # single 16-bit position
    sparse_128 = sparse_word  # only position 0 in the first word (idx=0)

    # Print test info
    c = TEST_POSITION // WORD_BITS
    d = TEST_POSITION % WORD_BITS
    bdbias = 1 if d > NMOD else 0
    shift_amount = (WORD_BITS + NMOD - d) if bdbias else (NMOD - d)

    print(f"=== HQC-1 SEG_A Test Vector ===")
    print(f"N_BITS = {N_BITS}")
    print(f"N_WORDS = {N_WORDS}, NMOD = {NMOD}")
    print(f"TEST_POSITION = {TEST_POSITION}")
    print(f"  c (block) = {c}")
    print(f"  d (mod)   = {d}")
    print(f"  bdbias    = {bdbias}")
    print(f"  shift_amount = {shift_amount}")
    print(f"  SEG_A processes result blocks 0..{c-1} ({c} blocks)")
    print(f"  Dense read starts at word {N_WORDS - c - bdbias}")
    print()

    # Show first few expected result words (SEG_A region)
    print(f"Expected result words (SEG_A region, blocks 0..{c-1}):")
    for i in range(c):
        print(f"  word[{i}] = 0x{expected_words[i]:032x}")
    print()

    # Create output directory
    out_dir = os.path.join(os.path.dirname(__file__), '..', 'bin')
    os.makedirs(out_dir, exist_ok=True)

    # Write dense polynomial bin
    dense_bytes = words_to_bytes(dense_words)
    dense_path = os.path.join(out_dir, 'dense.bin')
    with open(dense_path, 'wb') as f:
        f.write(dense_bytes)
    print(f"Written: {dense_path} ({len(dense_bytes)} bytes)")

    # Write sparse polynomial bin (one 128-bit word with the position)
    sparse_bytes = sparse_128.to_bytes(16, byteorder='little')
    sparse_path = os.path.join(out_dir, 'sparse.bin')
    with open(sparse_path, 'wb') as f:
        f.write(sparse_bytes)
    print(f"Written: {sparse_path} ({len(sparse_bytes)} bytes)")

    # Write expected result bin (full result for comparison)
    expected_bytes = words_to_bytes(expected_words)
    expected_path = os.path.join(out_dir, 'expected.bin')
    with open(expected_path, 'wb') as f:
        f.write(expected_bytes)
    print(f"Written: {expected_path} ({len(expected_bytes)} bytes)")

    # Write SEG_A expected subset (just blocks 0..c-1) for quick comparison
    sega_bytes = words_to_bytes(expected_words[:c])
    sega_path = os.path.join(out_dir, 'expected_sega.bin')
    with open(sega_path, 'wb') as f:
        f.write(sega_bytes)
    print(f"Written: {sega_path} ({len(sega_bytes)} bytes)")

    # Write SEG_B expected (block c, 1 word) for boundary verification
    segb_bytes = words_to_bytes(expected_words[c:c+1])
    segb_path = os.path.join(out_dir, 'expected_segb.bin')
    with open(segb_path, 'wb') as f:
        f.write(segb_bytes)
    print(f"Written: {segb_path} ({len(segb_bytes)} bytes)")
    print(f"  SEG_B expected word[{c}] = 0x{expected_words[c]:032x}")

if __name__ == '__main__':
    main()
