#!/usr/bin/env python3
"""
Regression test for HQC-ASP multi-coefficient sparse*dense multiplication.
Tests the full polynomial multiplication: result = XOR of (dense << pos_i) for all i.

Usage:
    python3 pysrc/regression_test_multi.py                # default 10 random tests
    python3 pysrc/regression_test_multi.py --num-tests 50
    python3 pysrc/regression_test_multi.py --seed 123
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
WEIGHT = 66

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


def pack_sparse_positions(positions):
    """Pack 16-bit positions into 128-bit words, 8 per word."""
    n_words_needed = (len(positions) + 7) // 8
    words = []
    for i in range(n_words_needed):
        val = 0
        for j in range(8):
            idx = i * 8 + j
            if idx < len(positions):
                val |= (positions[idx] & 0xFFFF) << (j * 16)
        words.append(val)
    return words


def compute_expected(dense_bits, positions):
    """Compute XOR of all cyclic shifts."""
    result = np.zeros(N_BITS, dtype=np.uint8)
    for pos in positions:
        shifted = cyclic_shift_xor(dense_bits, pos)
        result ^= shifted
    return result


def write_test_vectors(dense_bits, positions):
    os.makedirs(BIN_DIR, exist_ok=True)

    dense_words = bits_to_words(dense_bits, TOTAL_WORDS)
    dense_bytes = words_to_bytes(dense_words)
    with open(os.path.join(BIN_DIR, 'dense.bin'), 'wb') as f:
        f.write(dense_bytes)

    sparse_words = pack_sparse_positions(positions)
    sparse_bytes = words_to_bytes(sparse_words)
    with open(os.path.join(BIN_DIR, 'sparse.bin'), 'wb') as f:
        f.write(sparse_bytes)


def run_sim():
    result = subprocess.run(
        [SIM_BIN],
        capture_output=True, timeout=30
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
    parser = argparse.ArgumentParser(description='HQC-ASP multi-coefficient regression test')
    parser.add_argument('--num-tests', type=int, default=10)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--weight', type=int, default=WEIGHT)
    parser.add_argument('--stop-on-fail', action='store_true', default=True)
    parser.add_argument('--no-stop', action='store_true')
    args = parser.parse_args()

    if args.no_stop:
        args.stop_on_fail = False

    rng = np.random.default_rng(args.seed)

    print(f"=== HQC-ASP Multi-Coefficient Regression Test ===")
    print(f"Weight: {args.weight}, Tests: {args.num_tests}, Seed: {args.seed}")
    print()

    passed = 0
    failed = 0

    for test_idx in range(args.num_tests):
        dense_bits = rng.integers(0, 2, size=N_BITS, dtype=np.uint8)
        positions = sorted(rng.choice(N_BITS, size=args.weight, replace=False).tolist())

        write_test_vectors(dense_bits, positions)

        expected_bits = compute_expected(dense_bits, positions)
        expected_words = bits_to_words(expected_bits, TOTAL_WORDS)

        if not run_sim():
            print(f"  FAIL test {test_idx}: simulator crashed")
            failed += 1
            if args.stop_on_fail:
                break
            continue

        got_data = read_result()
        if len(got_data) < RESULT_BYTES:
            print(f"  FAIL test {test_idx}: result.bin too short ({len(got_data)} bytes)")
            failed += 1
            if args.stop_on_fail:
                break
            continue

        mismatches = compare_results(got_data, expected_words)
        if mismatches:
            print(f"  FAIL test {test_idx}: {len(mismatches)} word(s) wrong")
            print(f"    positions[0:5] = {positions[:5]}")
            for i, got, exp in mismatches[:3]:
                print(f"    word[{i}] got=0x{got:032x} exp=0x{exp:032x}")
            if len(mismatches) > 3:
                print(f"    ... and {len(mismatches)-3} more")
            failed += 1
            if args.stop_on_fail:
                break
        else:
            passed += 1
            print(f"  [{test_idx+1}/{args.num_tests}] PASS")

    print()
    print(f"=== Results: {passed} passed, {failed} failed out of {passed+failed} tests ===")
    if failed:
        sys.exit(1)
    else:
        print("ALL PASSED")
        sys.exit(0)


if __name__ == '__main__':
    main()
