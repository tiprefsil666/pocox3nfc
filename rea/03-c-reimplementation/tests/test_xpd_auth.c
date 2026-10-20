/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Self-tests for the xpd_auth reimplementation.
 *
 * The SHA-256 and HMAC vectors are the published RFC/FIPS test vectors, so
 * they check the primitives independently of anything Xiaomi wrote. The
 * xpd-level vectors are generated from the binary by
 * ../04-tools/gen_test_vectors.py, which also cross-checks against the
 * independent Python transcription in ../04-tools/xpd_model.py.
 */

#include "xpd_auth.h"
#include "vectors.h"

#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...) do {					\
	if (!(cond)) {						\
		failures++;					\
		printf("FAIL %s:%d: ", __FILE__, __LINE__);	\
		printf(__VA_ARGS__);				\
		printf("\n");					\
	}							\
} while (0)

static void hexdump(const uint8_t *b, size_t n, char *out)
{
	static const char h[] = "0123456789abcdef";
	size_t i;

	for (i = 0; i < n; i++) {
		out[i * 2]     = h[b[i] >> 4];
		out[i * 2 + 1] = h[b[i] & 0xf];
	}
	out[n * 2] = '\0';
}

static void test_sha256_vectors(void)
{
	/* FIPS 180-4 / NIST test vectors. */
	static const struct {
		const char *msg;
		const char *want;
	} v[] = {
		{ "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
		{ "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
		{ "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
		  "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
	};
	size_t i;

	for (i = 0; i < sizeof(v) / sizeof(v[0]); i++) {
		uint8_t d[32];
		char hex[65];

		xpd_sha256((const uint8_t *)v[i].msg, strlen(v[i].msg), d);
		hexdump(d, 32, hex);
		CHECK(strcmp(hex, v[i].want) == 0,
		      "sha256(\"%s\") = %s, want %s", v[i].msg, hex, v[i].want);
	}
}

static void test_sha256_long(void)
{
	static uint8_t buf[1000];
	uint8_t d[32];
	char hex[65];

	memset(buf, 'a', sizeof(buf));
	xpd_sha256(buf, sizeof(buf), d);
	hexdump(d, 32, hex);
	CHECK(strcmp(hex,
		"41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3") == 0,
		"sha256(1000*'a') = %s", hex);
}

static void test_hmac_vectors(void)
{
	uint8_t d[32];
	char hex[65];
	size_t i;

	for (i = 0; i < sizeof(g_rfc_vectors) / sizeof(g_rfc_vectors[0]); i++) {
		const struct xpd_hmac_vector *v = &g_rfc_vectors[i];

		xpd_hmac_sha256(v->key, v->keylen, v->data, v->datalen, d);
		hexdump(d, 32, hex);
		CHECK(strcmp(hex, v->expected) == 0,
		      "hmac vector %zu = %s, want %s", i, hex, v->expected);
	}
}

static void test_key_table(void)
{
	static const uint8_t zeros[32] = { 0 };
	const uint8_t *k;
	int i, nonzero = 0;

	for (i = 0; i < XPD_INDEX_COUNT; i++) {
		k = xpd_key_table((unsigned)i);
		CHECK(k != NULL, "slot %d NULL", i);
		if (!k)
			continue;
		if (memcmp(k, zeros, 32) != 0)
			nonzero++;
	}
	/*
	 * A public build carries a redacted (all-zero) key table, so the
	 * count is only meaningful in a private build.
	 */
	if (nonzero != 0)
		CHECK(nonzero == XPD_INDEX_COUNT,
		      "expected %d non-empty table entries, got %d",
		      XPD_INDEX_COUNT, nonzero);
	else
		printf("  key table is redacted in this build\n");
	CHECK(xpd_key_table(XPD_INDEX_COUNT) == NULL, "out-of-range slot must be NULL");
}

static void test_index_word(void)
{
	uint8_t word[4];
	char hex[9];

	xpd_build_index_word(g_xpd_adapter, sizeof(g_xpd_adapter), word);
	hexdump(word, 4, hex);
	CHECK(strcmp(hex, "10325467") == 0,
	      "index word = %s, want 10325467", hex);
}

static void test_seed_swap(void)
{
	uint8_t msg[XPD_MESSAGE_LEN];
	uint8_t word[4] = { 0, 0, 0, 0 };
	int i;

	xpd_build_message(g_xpd_seed, word, msg);

	/* The seed is byte-swapped per 32-bit word: 03 02 01 00 ... 0f 0e 0d 0c */
	CHECK(msg[0] == 0x03 && msg[1] == 0x02 && msg[2] == 0x01 && msg[3] == 0x00,
	      "seed swap wrong at start: %02x %02x %02x %02x",
	      msg[0], msg[1], msg[2], msg[3]);
	CHECK(msg[12] == 0x0f && msg[13] == 0x0e && msg[14] == 0x0d && msg[15] == 0x0c,
	      "seed swap wrong at end: %02x %02x %02x %02x",
	      msg[12], msg[13], msg[14], msg[15]);

	for (i = 16; i < 20; i++)
		CHECK(msg[i] == 0, "index byte %d = %02x, want 0", i, msg[i]);
}

static void test_expected_digest_vectors(void)
{
	uint8_t word[4];
	uint8_t d[32];
	char hex[65];
	size_t i;
	int redacted = 0;

	xpd_build_index_word(g_xpd_adapter, sizeof(g_xpd_adapter), word);

	for (i = 0; i < sizeof(g_xpd_vectors) / sizeof(g_xpd_vectors[0]); i++) {
		if (g_xpd_vectors[i].expected[0] == '<')
			redacted = 1;
	}

	if (redacted) {
		/*
		 * The published tree carries redacted xpd vectors, because they
		 * are HMAC values computed with Xiaomi's keys.  Check only that
		 * the pipeline runs and that the key table is the right shape.
		 */
		printf("  xpd vectors are redacted in this build; "
		       "checking shape only\n");
		for (i = 0; i < sizeof(g_xpd_vectors) / sizeof(g_xpd_vectors[0]); i++) {
			int rc = xpd_expected_digest(g_xpd_vectors[i].slot,
			                             g_xpd_seed, word, d);
			CHECK(rc == XPD_OK, "expected_digest rc=%d", rc);
		}
		return;
	}

	for (i = 0; i < sizeof(g_xpd_vectors) / sizeof(g_xpd_vectors[0]); i++) {
		unsigned slot = g_xpd_vectors[i].slot;
		int rc, verified = -1;

		rc = xpd_expected_digest(slot, g_xpd_seed, word, d);
		CHECK(rc == XPD_OK, "expected_digest rc=%d", rc);
		hexdump(d, 32, hex);
		/* Only the first 16 bytes are compared by the vendor. */
		CHECK(strncmp(hex, g_xpd_vectors[i].expected, XPD_CMP_LEN) == 0,
		      "slot %u digest = %s, want %s...",
		      slot, hex, g_xpd_vectors[i].expected);

		/* Verify against the digest we just computed. */
		rc = xpd_verify(hex, slot, g_xpd_seed, word, &verified);
		CHECK(rc == XPD_OK, "verify rc=%d", rc);
		CHECK(verified == 1, "self-verify failed for slot %u", slot);

		/* A corrupted digest must be rejected. */
		hex[0] = (hex[0] == 'a') ? 'b' : 'a';
		rc = xpd_verify(hex, slot, g_xpd_seed, word, &verified);
		CHECK(rc == XPD_OK, "verify rc=%d", rc);
		CHECK(verified == 0, "corrupted digest accepted for slot %u", slot);
	}
}

static void test_wrong_seed_rejected(void)
{
	uint8_t seed2[16];
	uint8_t word[4];
	uint8_t d[32];
	char hex[65];
	int rc, verified = -1;

	memcpy(seed2, g_xpd_seed, sizeof(seed2));
	seed2[0] ^= 0xff;

	xpd_build_index_word(g_xpd_adapter, sizeof(g_xpd_adapter), word);
	xpd_expected_digest(0, g_xpd_seed, word, d);
	hexdump(d, 32, hex);

	rc = xpd_verify(hex, 0, seed2, word, &verified);
	CHECK(rc == XPD_OK, "verify rc=%d", rc);
	CHECK(verified == 0, "digest accepted for wrong seed");
}

static void test_index_range(void)
{
	uint8_t seed[16] = { 0 };
	uint8_t word[4] = { 0 };
	uint8_t d[32];
	int rc;

	rc = xpd_expected_digest(XPD_INDEX_COUNT, seed, word, d);
	CHECK(rc == XPD_ERR_RANGE, "out-of-range slot should fail, rc=%d", rc);
}

int main(void)
{
	printf("xpd_auth self-test\n");
	test_sha256_vectors();
	test_sha256_long();
	test_hmac_vectors();
	test_key_table();
	test_index_word();
	test_seed_swap();
	test_expected_digest_vectors();
	test_wrong_seed_rejected();
	test_index_range();

	if (failures) {
		printf("\n%d check(s) FAILED\n", failures);
		return 1;
	}
	printf("\nall checks passed\n");
	return 0;
}
