/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * xpd_auth — the Xiaomi USB-PD charger authentication handshake.
 *
 * Reconstructed from static analysis of vendor/bin/batterysecret.
 * See ../02-notes/batterysecret-hvdcp.md.
 */

#include "xpd_auth.h"

#include <string.h>

static int hex_val(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

static unsigned char up(unsigned char c)
{
	if (c >= 'a' && c <= 'z')
		return (unsigned char)(c - 32);
	return c;
}

/*
 * Decoder A — the vendor's first nibble helper.
 *
 *   sub  w8, w0, #0x30        ; w8 = c - '0'
 *   and  w9, w8, #0xff        ; w9 = low byte of w8
 *   add  w10, w0, #9          ; w10 = c + 9
 *   cmp  w9, #9
 *   csel w25, w10, w8, hi     ; if w9 > 9 take w10
 *
 * For a letter this yields the ASCII code plus 9, not the nibble. That is
 * what the vendor's binary does, so it is reproduced exactly.
 */
static unsigned decoder_a(unsigned char c)
{
	unsigned w8, w9, w10;

	c = up(c);
	w8 = (unsigned)((int)c - 0x30) & 0xffffffffu;
	w9 = w8 & 0xffu;
	w10 = ((unsigned)c + 9u) & 0xffffffffu;

	return (w9 > 9u) ? w10 : w8;
}

/*
 * Decoder B — the vendor's second nibble helper.
 *
 *   sub  w8, w0, #0x30        ; w8 = c - '0'
 *   sub  w9, w0, #0x37        ; w9 = c - 0x37
 *   cmp  w10, #9
 *   csel w8, w9, w8, hi       ; if w10 > 9 take w9
 *
 * This one is a correct hex nibble decoder.
 */
static unsigned decoder_b(unsigned char c)
{
	unsigned w8, w9, w10;

	c = up(c);
	w8 = (unsigned)((int)c - 0x30) & 0xffffffffu;
	w9 = (unsigned)((int)c - 0x37) & 0xffffffffu;
	w10 = w8 & 0xffu;

	return (w10 > 9u) ? w9 : w8;
}

int xpd_build_index_word(const uint8_t *adapter_id, size_t len,
                         uint8_t out_word[4])
{
	uint8_t c[8];
	unsigned w25, w26, w27, w8;

	if (!adapter_id || !out_word)
		return XPD_ERR_ARG;

	memset(c, 0, sizeof(c));
	if (len)
		memcpy(c, adapter_id, len < sizeof(c) ? len : sizeof(c));

	/* byte 0 */
	w25 = decoder_a(c[0]) + (decoder_b(c[1]) << 4);
	/* byte 1 */
	w26 = decoder_a(c[2]) + (decoder_b(c[3]) << 4);
	/* byte 2 */
	w27 = decoder_a(c[4]) + (decoder_b(c[5]) << 4);
	/* byte 3 — the nibble order is reversed compared with bytes 0..2 */
	w8 = decoder_b(c[7]) + (decoder_a(c[6]) << 4);

	out_word[0] = (uint8_t)(w25 & 0xffu);
	out_word[1] = (uint8_t)(w26 & 0xffu);
	out_word[2] = (uint8_t)(w27 & 0xffu);
	out_word[3] = (uint8_t)(w8 & 0xffu);

	return XPD_OK;
}

void xpd_seed_to_be(const uint8_t seed[XPD_SEED_LEN], uint8_t out[XPD_SEED_LEN])
{
	int i;

	for (i = 0; i < XPD_SEED_LEN; i += 4) {
		out[i + 0] = seed[i + 3];
		out[i + 1] = seed[i + 2];
		out[i + 2] = seed[i + 1];
		out[i + 3] = seed[i + 0];
	}
}

void xpd_build_message(const uint8_t seed[XPD_SEED_LEN],
                       const uint8_t index_word[4],
                       uint8_t out[XPD_MESSAGE_LEN])
{
	xpd_seed_to_be(seed, out);
	memcpy(out + XPD_SEED_LEN, index_word, 4);
}

int xpd_expected_digest(unsigned slot,
                        const uint8_t seed[XPD_SEED_LEN],
                        const uint8_t index_word[4],
                        uint8_t out_digest[XPD_DIGEST_LEN])
{
	const uint8_t *key;
	uint8_t message[XPD_MESSAGE_LEN];
	int rc;

	if (!seed || !index_word || !out_digest)
		return XPD_ERR_ARG;

	key = xpd_key_table(slot);
	if (!key)
		return XPD_ERR_RANGE;

	xpd_build_message(seed, index_word, message);

	rc = xpd_hmac_sha256(key, XPD_INDEX_KEY_LEN, message, sizeof(message),
	                     out_digest);

	return rc;
}

int xpd_verify(const char *charger_digest_hex,
                unsigned slot,
                const uint8_t seed[XPD_SEED_LEN],
                const uint8_t index_word[4],
                int *out_verified)
{
	uint8_t expected[XPD_DIGEST_LEN];
	uint8_t got[XPD_DIGEST_LEN];
	int i, rc;

	if (!charger_digest_hex || !seed || !index_word || !out_verified)
		return XPD_ERR_ARG;

	*out_verified = 0;

	if (xpd_key_table(slot) == NULL)
		return XPD_ERR_RANGE;

	/* Decode the charger's 64 hex characters into 32 bytes. */
	for (i = 0; i < XPD_DIGEST_LEN; i++) {
		int hi = hex_val(charger_digest_hex[i * 2]);
		int lo = hex_val(charger_digest_hex[i * 2 + 1]);

		if (hi < 0 || lo < 0)
			return XPD_ERR_HEX;
		got[i] = (uint8_t)((hi << 4) | lo);
	}

	rc = xpd_expected_digest(slot, seed, index_word, expected);
	if (rc != XPD_OK)
		return rc;

	/*
	 * The vendor compares only the first 16 bytes of the 32-byte digest.
	 * This truncation is reproduced here so that a reimplementation is
	 * wire-compatible; it is documented, not endorsed.
	 */
	if (memcmp(got, expected, XPD_CMP_LEN) == 0)
		*out_verified = 1;

	return XPD_OK;
}
