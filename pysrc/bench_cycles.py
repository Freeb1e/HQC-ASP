#!/usr/bin/env python3
"""Benchmark cycle counts for all HQC standards and weight variants."""

import numpy as np
import subprocess
import os
import sys

SIM_BIN = "./obj_dir_fst/VTEST_PLATFORM"
BIN_DIR = "bin"

CONFIGS = [
    {"name": "HQC1",    "mode": 2, "n_bits": 17669, "n_words": 138, "weight": 66},
    {"name": "HQC1_re", "mode": 3, "n_bits": 17669, "n_words": 138, "weight": 75},
    {"name": "HQC2",    "mode": 4, "n_bits": 35851, "n_words": 280, "weight": 100},
    {"name": "HQC2_re", "mode": 5, "n_bits": 35851, "n_words": 280, "weight": 114},
    {"name": "HQC3",    "mode": 6, "n_bits": 57637, "n_words": 450, "weight": 131},
    {"name": "HQC3_re", "mode": 7, "n_bits": 57637, "n_words": 450, "weight": 149},
]

def generate_dense(n_bits, n_words):
    np.random.seed(42)
    bits = np.random.randint(0, 2, size=n_bits, dtype=np.uint8)
    total_words = n_words + 1
    data = bytearray(total_words * 16)
    for i in range(total_words):
        val = 0
        for b in range(128):
            idx = i * 128 + b
            if idx < n_bits and bits[idx]:
                val |= (1 << b)
        for byte_idx in range(16):
            data[i * 16 + byte_idx] = (val >> (byte_idx * 8)) & 0xFF
    return bytes(data)

def generate_sparse(n_bits, weight):
    rng = np.random.RandomState(seed=123)
    positions = rng.randint(0, n_bits, size=weight).tolist()
    n_words = (weight + 7) // 8
    data = bytearray(n_words * 16)
    for i, pos in enumerate(positions):
        offset = i * 2
        data[offset] = pos & 0xFF
        data[offset + 1] = (pos >> 8) & 0xFF
    return bytes(data)

def run_sim(mode):
    result = subprocess.run(
        [SIM_BIN, str(mode)],
        capture_output=True, timeout=30
    )
    stdout = result.stdout.decode()
    for line in stdout.strip().split('\n'):
        if 'cycles' in line.lower():
            parts = line.split()
            for i, p in enumerate(parts):
                if p.isdigit():
                    return int(p)
            for p in parts:
                try:
                    return int(p)
                except ValueError:
                    continue
    return None

def main():
    os.makedirs(BIN_DIR, exist_ok=True)
    print(f"{'Standard':<10} {'Mode':<6} {'Weight':<8} {'N_WORDS':<8} {'Cycles':<10}")
    print("-" * 50)

    for cfg in CONFIGS:
        dense_data = generate_dense(cfg["n_bits"], cfg["n_words"])
        with open(os.path.join(BIN_DIR, "dense.bin"), "wb") as f:
            f.write(dense_data)

        sparse_data = generate_sparse(cfg["n_bits"], cfg["weight"])
        with open(os.path.join(BIN_DIR, "sparse.bin"), "wb") as f:
            f.write(sparse_data)

        cycles = run_sim(cfg["mode"])
        if cycles is not None:
            print(f"{cfg['name']:<10} {cfg['mode']:<6} {cfg['weight']:<8} {cfg['n_words']:<8} {cycles:<10}")
        else:
            print(f"{cfg['name']:<10} {cfg['mode']:<6} {cfg['weight']:<8} {cfg['n_words']:<8} {'FAILED':<10}")

if __name__ == "__main__":
    main()
