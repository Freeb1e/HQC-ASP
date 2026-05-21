#!/usr/bin/env python3
"""
Regression test for HQC-ASP across all three security levels (HQC-1/3/5).

Usage:
    python3 pysrc/regression_test_all.py                    # all modes, 10 tests each
    python3 pysrc/regression_test_all.py --num-tests 50
    python3 pysrc/regression_test_all.py --mode 1           # HQC-1 only
    python3 pysrc/regression_test_all.py --mode 3           # HQC-3 only
    python3 pysrc/regression_test_all.py --mode 5           # HQC-5 only
"""

import numpy as np
import subprocess
import argparse
import sys
import os

HQC_PARAMS = {
    1: {'n_words': 138, 'nmod': 5,  'weight': 66,  'hqc_mode': 0b010,
        'n_bits': 138 * 128 + 5},
    3: {'n_words': 280, 'nmod': 11, 'weight': 100, 'hqc_mode': 0b100,
        'n_bits': 280 * 128 + 11},
    5: {'n_words': 450, 'nmod': 37, 'weight': 131, 'hqc_mode': 0b110,
        'n_bits': 450 * 128 + 37},
}

WORD_BITS = 128
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


def compute_expected(dense_bits, positions):
    result = np.zeros(len(dense_bits), dtype=np.uint8)
    for pos in positions:
        shifted = cyclic_shift_xor(dense_bits, pos)
        result ^= shifted
    return result


def pack_sparse_positions(positions):
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


def write_test_vectors(dense_bits, positions, total_words):
    os.makedirs(BIN_DIR, exist_ok=True)
    dense_words = bits_to_words(dense_bits, total_words)
    with open(os.path.join(BIN_DIR, 'dense.bin'), 'wb') as f:
        f.write(words_to_bytes(dense_words))
    sparse_words = pack_sparse_positions(positions)
    with open(os.path.join(BIN_DIR, 'sparse.bin'), 'wb') as f:
        f.write(words_to_bytes(sparse_words))


def run_sim(hqc_mode):
    result = subprocess.run(
        [SIM_BIN, str(hqc_mode)],
        capture_output=True, timeout=60
    )
    if result.returncode != 0:
        print(f"  Simulator error: {result.stderr.decode()}")
        return False
    return True


def compare_results(got_data, expected_words, n_words, nmod):
    total_words = n_words + 1
    got_words = bytes_to_words(got_data, total_words)
    nmod_mask = (1 << nmod) - 1
    got_words[n_words] &= nmod_mask

    mismatches = []
    for i in range(total_words):
        exp = expected_words[i]
        if i == n_words:
            exp &= nmod_mask
        if got_words[i] != exp:
            mismatches.append((i, got_words[i], exp))
    return mismatches


def run_mode_tests(level, params, num_tests, seed, stop_on_fail):
    n_bits = params['n_bits']
    n_words = params['n_words']
    nmod = params['nmod']
    weight = params['weight']
    hqc_mode = params['hqc_mode']
    total_words = n_words + 1
    result_bytes = total_words * 16

    print(f"--- HQC-{level}: n_bits={n_bits}, n_words={n_words}, "
          f"nmod={nmod}, weight={weight}, mode=0b{hqc_mode:03b} ---")

    rng = np.random.default_rng(seed)
    passed = 0
    failed = 0

    for test_idx in range(num_tests):
        dense_bits = rng.integers(0, 2, size=n_bits, dtype=np.uint8)
        positions = sorted(rng.choice(n_bits, size=weight, replace=False).tolist())

        write_test_vectors(dense_bits, positions, total_words)
        expected_bits = compute_expected(dense_bits, positions)
        expected_words = bits_to_words(expected_bits, total_words)

        if not run_sim(hqc_mode):
            print(f"  FAIL test {test_idx}: simulator crashed")
            failed += 1
            if stop_on_fail:
                return passed, failed
            continue

        got_data = read_result()
        if len(got_data) < result_bytes:
            print(f"  FAIL test {test_idx}: result.bin too short "
                  f"({len(got_data)} bytes, need {result_bytes})")
            failed += 1
            if stop_on_fail:
                return passed, failed
            continue

        mismatches = compare_results(got_data, expected_words, n_words, nmod)
        if mismatches:
            print(f"  FAIL test {test_idx}: {len(mismatches)} word(s) wrong")
            print(f"    positions[0:5] = {positions[:5]}")
            for i, got, exp in mismatches[:3]:
                print(f"    word[{i}] got=0x{got:032x} exp=0x{exp:032x}")
            if len(mismatches) > 3:
                print(f"    ... and {len(mismatches)-3} more")
            failed += 1
            if stop_on_fail:
                return passed, failed
        else:
            passed += 1
            print(f"  [{test_idx+1}/{num_tests}] PASS")

    return passed, failed


def read_result():
    with open(os.path.join(BIN_DIR, 'result.bin'), 'rb') as f:
        return f.read()


def main():
    parser = argparse.ArgumentParser(
        description='HQC-ASP regression test for all security levels')
    parser.add_argument('--num-tests', type=int, default=10)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--mode', type=int, choices=[1, 3, 5], default=None,
                        help='Test only one level (1, 3, or 5)')
    parser.add_argument('--no-stop', action='store_true',
                        help='Continue on failure')
    parser.add_argument('--no-build', action='store_true',
                        help='Skip make build')
    args = parser.parse_args()

    if not args.no_build:
        print("Building simulator...")
        build = subprocess.run(["make", "build"], capture_output=True)
        if build.returncode != 0:
            print(f"Build failed:\n{build.stderr.decode()}")
            sys.exit(1)
        print("Build OK\n")

    modes = [args.mode] if args.mode else [1, 3, 5]
    stop_on_fail = not args.no_stop

    total_passed = 0
    total_failed = 0

    for level in modes:
        params = HQC_PARAMS[level]
        p, f = run_mode_tests(level, params, args.num_tests, args.seed,
                              stop_on_fail)
        total_passed += p
        total_failed += f
        if f and stop_on_fail:
            break
        print()

    print(f"=== Total: {total_passed} passed, {total_failed} failed "
          f"out of {total_passed + total_failed} tests ===")
    if total_failed:
        sys.exit(1)
    print("ALL PASSED")
    sys.exit(0)


if __name__ == '__main__':
    main()
