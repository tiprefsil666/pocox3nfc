/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * xpd_auth — clean-room reimplementation of the Xiaomi USB-PD charger
 *            authentication handshake, as observed in MIUI's
 *            vendor/bin/batterysecret (Xiaomi POCO X3 NFC / surya).
 *
 * This is a reimplementation from observed behaviour. It is not derived
 * from Xiaomi source code.
 *
 * See ../02-notes/batterysecret-hvdcp.md for the analysis this is based on.
 */

#ifndef XPD_AUTH_H
#define XPD_AUTH_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define XPD_SEED_LEN        16  /* session seed, bytes                          */
#define XPD_DIGEST_LEN      32  /* HMAC-SHA-256 output, bytes                   */
#define XPD_DIGEST_HEX_LEN  64  /* digest, lowercase hex + NUL                  */
#define XPD_ADAPTER_ID_LEN  16  /* bytes read from adapter_id                   */
#define XPD_INDEX_COUNT     10  /* entries in the key table                     */
#define XPD_INDEX_KEY_LEN   32  /* bytes per key table entry                    */
#define XPD_CMP_LEN         16  /* bytes actually compared (truncated!)         */
#define XPD_HMAC_BLOCK_LEN  64  /* SHA-256 block size                           */
#define XPD_MESSAGE_LEN     20  /* inner HMAC message length                    */

enum xpd_status {
	XPD_OK              =  0,
	XPD_ERR_ARG        = -1,
	XPD_ERR_HEX        = -2,
	XPD_ERR_RANGE      = -3, /* model index outside the key table */
	XPD_ERR_MISMATCH   = -4, /* digest did not verify              */
	XPD_ERR_INTERNAL   = -5,
};

/*
 * Build the 4-byte "index word" from the charger's adapter_id.
 *
 * Transcribed from the AArch64 at 0x2ba4-0x2ce8. The vendor consumes the
 * first 8 bytes of the adapter_id string and packs them into a 32-bit word
 * with two *different* hex decoders, one of which is not a nibble decoder at
 * all:
 *
 *     byte 0 = A(c[0]) + (B(c[1]) << 4)
 *     byte 1 = A(c[2]) + (B(c[3]) << 4)
 *     byte 2 = A(c[4]) + (B(c[5]) << 4)
 *     byte 3 = B(c[7]) + (A(c[6]) << 4)      <- nibble order reversed
 *
 * where
 *
 *     A(c) = (c - '0')            if toupper(c) is a digit
 *          = toupper(c) + 9        otherwise
 *     B(c) = (c - '0')            if toupper(c) is a digit
 *          = toupper(c) - 0x37     otherwise
 *
 * A() and B() agree for digits, and for letters A() returns the ASCII code
 * plus 9 rather than the nibble. Both quirks are the vendor's actual code
 * and are reproduced here verbatim, because a reimplementation has to be
 * byte-compatible with it. Callers should not rely on A() being sane.
 *
 * out_word must be at least 4 bytes.
 */
int xpd_build_index_word(const uint8_t *adapter_id, size_t len,
                         uint8_t out_word[4]);

/*
 * Byte-swap a 16-byte seed from the host's little-endian u32 layout into
 * big-endian byte order, matching the vendor's four `rev` instructions at
 * 0x2b20-0x2b4c.
 */
void xpd_seed_to_be(const uint8_t seed[XPD_SEED_LEN], uint8_t out[XPD_SEED_LEN]);

/*
 * Build the 20-byte HMAC message: the byte-swapped seed followed by the
 * 4-byte index word, little-endian.
 *
 * The vendor's inner-hash length argument is 0x14 (20) at 0x2cdc, and the
 * message pointer is sp+0x70, which is where the byte-swapped seed is
 * stored. The index word is written to sp+0x80, immediately after it.
 */
void xpd_build_message(const uint8_t seed[XPD_SEED_LEN],
                       const uint8_t index_word[4],
                       uint8_t out[XPD_MESSAGE_LEN]);

/*
 * Compute the expected digest for a given key slot.
 *
 * The observed algorithm is:
 *
 *     message  = byte_swap32(seed) || index_word_le32
 *     expected = HMAC-SHA256( key = table[slot], message )
 *
 * The vendor's HMAC helper is sub_26e4, whose structure is textbook
 * HMAC-SHA-256: keys longer than 64 bytes are hashed first, the key is
 * zero-padded to 64 bytes, and the ipad (0x36) / opad (0x5c) blocks bracket
 * the message.
 *
 * out_digest must be at least XPD_DIGEST_LEN bytes.
 */
int xpd_expected_digest(unsigned slot,
                        const uint8_t seed[XPD_SEED_LEN],
                        const uint8_t index_word[4],
                        uint8_t out_digest[XPD_DIGEST_LEN]);

/*
 * Full verification, mirroring the vendor's decision at the call site
 * (0x2d48-0x2d58: a 16-byte memcmp of the first 16 bytes of the digest).
 *
 * charger_digest_hex must be 64 lowercase/uppercase hex characters.
 * On success out_verified is set to 1 or 0.
 */
int xpd_verify(const char *charger_digest_hex,
                unsigned slot,
                const uint8_t seed[XPD_SEED_LEN],
                const uint8_t index_word[4],
                int *out_verified);

/*
 * Access to the key table. Returns NULL for an out-of-range slot.
 */
const uint8_t *xpd_key_table(unsigned slot);

/* SHA-256, exposed for testing. */
int xpd_sha256(const uint8_t *data, size_t len, uint8_t out[32]);

/* HMAC-SHA-256, exposed for testing. */
int xpd_hmac_sha256(const uint8_t *key, size_t keylen,
                    const uint8_t *data, size_t len,
                    uint8_t out[32]);

#ifdef __cplusplus
}
#endif

#endif /* XPD_AUTH_H */
