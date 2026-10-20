/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * SHA-256 (FIPS 180-4) and HMAC-SHA-256 (RFC 2104), written from the
 * specifications, not from the disassembled binary.
 *
 * The disassembled binary's constants were verified byte-for-byte against
 * this implementation's reference values, and its HMAC structure was verified
 * against the ipad/opad block layout. See ../02-notes/batterysecret-hvdcp.md.
 */

#include "xpd_auth.h"

#include <string.h>

static const uint32_t k_sha256[64] = {
	0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
	0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
	0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
	0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
	0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
	0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
	0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
	0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
	0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
	0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
	0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
	0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
	0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
	0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
	0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
	0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
};

#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x, y, z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define BSIG0(x) (ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22))
#define BSIG1(x) (ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25))
#define SSIG0(x) (ROTR(x, 7) ^ ROTR(x, 18) ^ ((x) >> 3))
#define SSIG1(x) (ROTR(x, 17) ^ ROTR(x, 19) ^ ((x) >> 10))

/* A streaming SHA-256 context, mirroring the layout of the vendor's. */
struct sha256_ctx {
	uint32_t h[8];
	uint64_t total;
	uint8_t  buf[64];
	size_t   buflen;
};

static void sha256_compress(struct sha256_ctx *c, const uint8_t block[64])
{
	uint32_t w[64];
	uint32_t a, b, cc, d, e, f, g, h;
	int i;

	for (i = 0; i < 16; i++)
		w[i] = ((uint32_t)block[i * 4] << 24) |
		       ((uint32_t)block[i * 4 + 1] << 16) |
		       ((uint32_t)block[i * 4 + 2] << 8) |
		       ((uint32_t)block[i * 4 + 3]);
	for (i = 16; i < 64; i++)
		w[i] = SSIG1(w[i - 2]) + w[i - 7] + SSIG0(w[i - 15]) + w[i - 16];

	a = c->h[0]; b = c->h[1]; cc = c->h[2]; d = c->h[3];
	e = c->h[4]; f = c->h[5]; g = c->h[6]; h = c->h[7];

	for (i = 0; i < 64; i++) {
		uint32_t t1 = h + BSIG1(e) + CH(e, f, g) + k_sha256[i] + w[i];
		uint32_t t2 = BSIG0(a) + MAJ(a, b, cc);

		h = g; g = f; f = e; e = d + t1;
		d = cc; cc = b; b = a; a = t1 + t2;
	}

	c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d;
	c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += h;
}

static void sha256_init(struct sha256_ctx *c)
{
	c->h[0] = 0x6a09e667u; c->h[1] = 0xbb67ae85u;
	c->h[2] = 0x3c6ef372u; c->h[3] = 0xa54ff53au;
	c->h[4] = 0x510e527fu; c->h[5] = 0x9b05688cu;
	c->h[6] = 0x1f83d9abu; c->h[7] = 0x5be0cd19u;
	c->total = 0;
	c->buflen = 0;
}

static void sha256_update(struct sha256_ctx *c, const uint8_t *data, size_t len)
{
	c->total += (uint64_t)len;

	if (c->buflen) {
		size_t need = 64 - c->buflen;
		size_t take = (len < need) ? len : need;

		memcpy(c->buf + c->buflen, data, take);
		c->buflen += take;
		data += take;
		len -= take;

		if (c->buflen == 64) {
			sha256_compress(c, c->buf);
			c->buflen = 0;
		}
	}

	while (len >= 64) {
		sha256_compress(c, data);
		data += 64;
		len -= 64;
	}

	if (len) {
		memcpy(c->buf, data, len);
		c->buflen = len;
	}
}

static void sha256_final(struct sha256_ctx *c, uint8_t out[32])
{
	uint64_t bits = c->total * 8u;
	uint8_t pad[72];
	size_t padlen;
	int i;

	pad[0] = 0x80;
	padlen = 1;
	while ((c->buflen + padlen) % 64 != 56)
		pad[padlen++] = 0x00;

	for (i = 0; i < 8; i++)
		pad[padlen + i] = (uint8_t)(bits >> (56 - 8 * i));
	padlen += 8;

	sha256_update(c, pad, padlen);

	for (i = 0; i < 8; i++) {
		out[i * 4]     = (uint8_t)(c->h[i] >> 24);
		out[i * 4 + 1] = (uint8_t)(c->h[i] >> 16);
		out[i * 4 + 2] = (uint8_t)(c->h[i] >> 8);
		out[i * 4 + 3] = (uint8_t)(c->h[i]);
	}
}

int xpd_sha256(const uint8_t *data, size_t len, uint8_t out[32])
{
	struct sha256_ctx c;

	if (!out)
		return XPD_ERR_ARG;
	if (len && !data)
		return XPD_ERR_ARG;

	sha256_init(&c);
	sha256_update(&c, data, len);
	sha256_final(&c, out);

	return XPD_OK;
}

int xpd_hmac_sha256(const uint8_t *key, size_t keylen,
                    const uint8_t *data, size_t len,
                    uint8_t out[32])
{
	struct sha256_ctx c;
	uint8_t k[XPD_HMAC_BLOCK_LEN];
	uint8_t pad[XPD_HMAC_BLOCK_LEN];
	uint8_t inner[32];
	size_t i;

	if (!out)
		return XPD_ERR_ARG;
	if ((keylen && !key) || (len && !data))
		return XPD_ERR_ARG;

	memset(k, 0, sizeof(k));
	if (keylen > XPD_HMAC_BLOCK_LEN) {
		if (xpd_sha256(key, keylen, k) != XPD_OK)
			return XPD_ERR_INTERNAL;
	} else if (keylen) {
		memcpy(k, key, keylen);
	}

	/* inner = SHA256( (key ^ ipad) || data ) */
	for (i = 0; i < XPD_HMAC_BLOCK_LEN; i++)
		pad[i] = (uint8_t)(k[i] ^ 0x36);
	sha256_init(&c);
	sha256_update(&c, pad, XPD_HMAC_BLOCK_LEN);
	sha256_update(&c, data, len);
	sha256_final(&c, inner);

	/* outer = SHA256( (key ^ opad) || inner ) */
	for (i = 0; i < XPD_HMAC_BLOCK_LEN; i++)
		pad[i] = (uint8_t)(k[i] ^ 0x5c);
	sha256_init(&c);
	sha256_update(&c, pad, XPD_HMAC_BLOCK_LEN);
	sha256_update(&c, inner, sizeof(inner));
	sha256_final(&c, out);

	memset(k, 0, sizeof(k));
	memset(pad, 0, sizeof(pad));

	return XPD_OK;
}
