#!/usr/bin/env python3
"""Differential test: the C reimplementation against the Python transcription.

Runs the C CLI and 04-tools/xpd_model.py over a set of adapter ids, seeds and
model numbers, and checks that they agree.  The two implementations were
written from the same disassembly but by different routes, so agreement is
meaningful evidence that the transcription is right.

Usage: differential_test.py <path-to-xpd_auth-cli>
"""
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "xpd_model.py")


def python_digest(model_index, seed_hex, adapter_text):
    """Run the Python model and return the 16-byte digest for one model."""
    out = subprocess.run(
        [sys.executable, MODEL, adapter_text, seed_hex],
        capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("model %d ->" % model_index):
            return line.split("->")[1].split()[0]
    raise SystemExit("model output did not contain model %d" % model_index)


def c_digest(cli, model_index, seed_hex, adapter_text):
    out = subprocess.run(
        [cli, "expect", str(model_index), adapter_text, seed_hex],
        capture_output=True, text=True, check=True).stdout
    return out.strip()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cli = os.path.abspath(sys.argv[1])

    random.seed(0xC0FFEE)

    cases = []
    # Fixed cases first.
    for adapter in ("0123456789abcdef", "0000000000000000",
                    "ffffffffffffffff", "ABCDEF0123456789",
                    "12345678", "aabbccdd"):
        for seed in ("000102030405060708090a0b0c0d0e0f",
                     "fffefdfcfbfaf9f8f7f6f5f4f3f2f1f0",
                     "0102030405060708090a0b0c0d0e0f10"):
            cases.append((adapter, seed))

    # Random cases.
    for _ in range(40):
        adapter = "".join(random.choice("0123456789abcdefABCDEF")
                          for _ in range(random.randint(1, 16)))
        seed = "".join("%02x" % random.randrange(256) for _ in range(16))
        cases.append((adapter, seed))

    bad = 0
    checked = 0
    for adapter, seed in cases:
        for model in range(10):
            p = python_digest(model, seed, adapter)
            c = c_digest(cli, model, seed, adapter)
            checked += 1
            if p != c[:len(p)]:
                bad += 1
                print("MISMATCH model=%d adapter=%r seed=%s\n  py=%s\n  c =%s"
                      % (model, adapter, seed, p, c))
    print("\n%d comparisons, %d mismatches" % (checked, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
