/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * xpd_auth CLI — verify a charger digest, or print the expected digest.
 *
 * Usage:
 *   xpd_auth verify <digest-hex64> <model> <adapter-id> <seed-hex32>
 *   xpd_auth expect <model> <adapter-id> <seed-hex32>
 *   xpd_auth selftest
 *
 * <adapter-id> is the raw text of /sys/class/usbpd/usbpd0/adapter_id.
 * <model> is the charger model number, 0..9.
 */

#include "xpd_auth.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int hex2bin(const char *hex, uint8_t *out, size_t outlen)
{
	size_t i;

	if (strlen(hex) != outlen * 2)
		return -1;
	for (i = 0; i < outlen; i++) {
		int hi, lo;
		char a = hex[i * 2], b = hex[i * 2 + 1];

		hi = (a >= '0' && a <= '9') ? a - '0'
		   : (a >= 'a' && a <= 'f') ? a - 'a' + 10
		   : (a >= 'A' && a <= 'F') ? a - 'A' + 10 : -1;
		lo = (b >= '0' && b <= '9') ? b - '0'
		   : (b >= 'a' && b <= 'f') ? b - 'a' + 10
		   : (b >= 'A' && b <= 'F') ? b - 'A' + 10 : -1;
		if (hi < 0 || lo < 0)
			return -1;
		out[i] = (uint8_t)((hi << 4) | lo);
	}
	return 0;
}

static void bin2hex(const uint8_t *b, size_t n, char *out)
{
	static const char h[] = "0123456789abcdef";
	size_t i;

	for (i = 0; i < n; i++) {
		out[i * 2]     = h[b[i] >> 4];
		out[i * 2 + 1] = h[b[i] & 0xf];
	}
	out[n * 2] = '\0';
}

static int parse_model(const char *s, unsigned *out)
{
	char *end;
	long v = strtol(s, &end, 0);

	if (*end != '\0' || v < 0 || v >= (long)XPD_INDEX_COUNT)
		return -1;
	*out = (unsigned)v;
	return 0;
}

static int cmd_verify(int argc, char **argv)
{
	uint8_t seed[16], expected[32], word[4];
	char hex[65];
	unsigned model;
	int rc, verified = 0;

	if (argc < 6) {
		fprintf(stderr,
			"usage: %s verify <digest-hex64> <model> <adapter-id> <seed-hex32>\n",
			argv[0]);
		return 2;
	}

	if (parse_model(argv[3], &model) != 0) {
		fprintf(stderr, "bad model (expected 0..%d)\n", XPD_INDEX_COUNT - 1);
		return 2;
	}
	if (hex2bin(argv[5], seed, sizeof(seed)) != 0) {
		fprintf(stderr, "bad seed hex\n");
		return 2;
	}

	rc = xpd_build_index_word((const uint8_t *)argv[4], strlen(argv[4]), word);
	if (rc != XPD_OK)
		return 1;

	rc = xpd_expected_digest(model, seed, word, expected);
	if (rc != XPD_OK) {
		fprintf(stderr, "digest computation failed: %d\n", rc);
		return 1;
	}
	bin2hex(expected, sizeof(expected), hex);

	rc = xpd_verify(argv[2], model, seed, word, &verified);
	if (rc != XPD_OK) {
		fprintf(stderr, "verify failed: %d\n", rc);
		return 1;
	}

	printf("model     : %u\n", model);
	printf("adapter id: %s\n", argv[4]);
	printf("index word: %02x%02x%02x%02x\n",
	       word[0], word[1], word[2], word[3]);
	printf("expected  : %s\n", hex);
	printf("charger   : %s\n", argv[2]);
	printf("result    : %s\n", verified ? "AUTHENTIC" : "REJECTED");

	return verified ? 0 : 1;
}

static int cmd_expect(int argc, char **argv)
{
	uint8_t seed[16], expected[32], word[4];
	char hex[65];
	unsigned model;
	int rc;

	if (argc < 5) {
		fprintf(stderr, "usage: %s expect <model> <adapter-id> <seed-hex32>\n",
			argv[0]);
		return 2;
	}

	if (parse_model(argv[2], &model) != 0) {
		fprintf(stderr, "bad model (expected 0..%d)\n", XPD_INDEX_COUNT - 1);
		return 2;
	}
	if (hex2bin(argv[4], seed, sizeof(seed)) != 0) {
		fprintf(stderr, "bad seed hex\n");
		return 2;
	}

	rc = xpd_build_index_word((const uint8_t *)argv[3], strlen(argv[3]), word);
	if (rc != XPD_OK)
		return 1;

	rc = xpd_expected_digest(model, seed, word, expected);
	if (rc != XPD_OK)
		return 1;

	bin2hex(expected, sizeof(expected), hex);
	printf("%s\n", hex);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr,
			"usage: %s <verify|expect|selftest> ...\n"
			"\n"
			"  verify <digest64> <model> <adapter-id> <seed32>\n"
			"  expect <model> <adapter-id> <seed32>\n"
			"  selftest\n",
			argv[0]);
		return 2;
	}

	if (!strcmp(argv[1], "verify"))
		return cmd_verify(argc, argv);
	if (!strcmp(argv[1], "expect"))
		return cmd_expect(argc, argv);
	if (!strcmp(argv[1], "selftest")) {
		int rc = system("./test_xpd_auth");
		return rc;
	}

	fprintf(stderr, "unknown command: %s\n", argv[1]);
	return 2;
}
