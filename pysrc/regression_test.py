#!/usr/bin/env python3
"""
Regression test for HQC-ASP single-position shift-and-add.
Tests all positions from 0 to N_BITS-1 (or a subset via --start/--end/--step).

Usage:
    python3 pysrc/regression_test.py                    # full sweep
    python3 pysrc/regression_test.py --step 100         # every 100th position
    python3 pysrc/regression_test.py --start 0 --end 200
"""

import numpy as np
import subprocess
import struct
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


def write_sparse_bin(positions):
    """Write sparse.bin with multiple 16-bit positions packed into 128-bit words."""
    n_pos = len(positions)
    n_words = (n_pos + 7) // 8
    data = bytearray(n_words * 16)
    for i, pos in enumerate(positions):
        offset = i * 2
        data[offset] = pos & 0xFF
        data[offset + 1] = (pos >> 8) & 0xFF
    with open(os.path.join(BIN_DIR, 'sparse.bin'), 'wb') as f:
        f.write(bytes(data))


def run_sim():
    result = subprocess.run(
        [SIM_BIN],
        capture_output=True, timeout=10
    )
    if result.returncode != 0:
        print(f"  Simulator error: {result.stderr.decode()}")
        return False
    return True


def read_result():
    path = os.path.join(BIN_DIR, 'result.bin')
    with open(path, 'rb') as f:
        data = f.read()
    return data


def compare_results(got_data, expected_words):
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
    return mismatches


def main():
    parser = argparse.ArgumentParser(description='HQC-ASP regression test')
    parser.add_argument('--start', type=int, default=0)
    parser.add_argument('--end', type=int, default=N_BITS - 1)
    parser.add_argument('--step', type=int, default=1)
    parser.add_argument('--stop-on-fail', action='store_true', default=True)
    parser.add_argument('--no-stop', action='store_true')
    args = parser.parse_args()

    if args.no_stop:
        args.stop_on_fail = False

    np.random.seed(42)
    dense_bits = np.random.randint(0, 2, size=N_BITS, dtype=np.uint8)

    dense_words = bits_to_words(dense_bits, TOTAL_WORDS)
    dense_bytes = words_to_bytes(dense_words)
    os.makedirs(BIN_DIR, exist_ok=True)
    with open(os.path.join(BIN_DIR, 'dense.bin'), 'wb') as f:
        f.write(dense_bytes)

    WEIGHT = 66  # HQC1 weight

    positions = range(args.start, args.end + 1, args.step)
    total = len(positions)
    passed = 0
    failed = 0
    fail_positions = []

    print(f"=== HQC-ASP Regression Test ===")
    print(f"Positions: {args.start} to {args.end}, step {args.step} ({total} tests)")
    print(f"Weight: {WEIGHT}")
    print()

    for idx, pos in enumerate(positions):
        # Generate WEIGHT random sparse positions with a deterministic seed per test
        rng = np.random.RandomState(seed=pos + 1000)
        sparse_positions = rng.randint(0, N_BITS, size=WEIGHT).tolist()

        # Compute expected: XOR of all cyclic shifts
        expected_bits = np.zeros(N_BITS, dtype=np.uint8)
        for sp in sparse_positions:
            expected_bits ^= cyclic_shift_xor(dense_bits, sp)
        expected_words = bits_to_words(expected_bits, TOTAL_WORDS)

        write_sparse_bin(sparse_positions)

        if not run_sim():
            print(f"  FAIL pos={pos}: simulator crashed")
            failed += 1
            fail_positions.append(pos)
            if args.stop_on_fail:
                break
            continue

        got_data = read_result()
        if len(got_data) < RESULT_BYTES:
            print(f"  FAIL pos={pos}: result.bin too short ({len(got_data)} bytes)")
            failed += 1
            fail_positions.append(pos)
            if args.stop_on_fail:
                break
            continue

        mismatches = compare_results(got_data, expected_words)
        if mismatches:
            c = pos // WORD_BITS
            d = pos % WORD_BITS
            print(f"  FAIL pos={pos} (c={c}, d={d}): {len(mismatches)} word(s) wrong")
            for i, got, exp in mismatches[:3]:
                print(f"    word[{i}] got=0x{got:032x} exp=0x{exp:032x}")
            if len(mismatches) > 3:
                print(f"    ... and {len(mismatches)-3} more")
            failed += 1
            fail_positions.append(pos)
            if args.stop_on_fail:
                break
        else:
            passed += 1
            if (idx + 1) % 100 == 0 or idx == total - 1:
                print(f"  [{idx+1}/{total}] pos={pos} PASS (total passed: {passed})")

    print()
    print(f"=== Results: {passed} passed, {failed} failed out of {passed+failed} tests ===")
    if fail_positions:
        print(f"Failed positions: {fail_positions[:20]}")
        sys.exit(1)
    else:
        print("ALL PASSED")
        sys.exit(0)


if __name__ == '__main__':
    main()
