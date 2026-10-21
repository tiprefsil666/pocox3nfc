/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * mmr — read and write MMIO registers through /dev/mem.
 *
 * The camera investigation needs to read the CSIPHY and the sensor
 * registers directly, and the phone's busybox has no devmem applet.  This
 * is the replacement: a small static aarch64 binary.
 *
 *   mmr r <addr>          read 32 bits
 *   mmr r8 <addr>         read 8 bits
 *   mmr r16 <addr>        read 16 bits
 *   mmr w <addr> <value>  write 32 bits
 *
 * Addresses are physical, and may be given with or without a leading 0x.
 *
 * Build (the host is already aarch64, so a static build is simplest):
 *   gcc -static -O2 -o mmr mmr.c
 *
 * IMPORTANT, from the camera notes
 * --------------------------------
 * Reading MMIO with the clock stopped gives zeros, or hangs.  Read *while*
 * the sensor is streaming, and read the same register twice to check that
 * the value is stable.  A register that reads zero during streaming and a
 * register that reads zero because the clock is off look the same otherwise.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define DEV_MEM "/dev/mem"

static long parse_addr(const char *s)
{
	char *end;
	long v;

	errno = 0;
	v = strtol(s, &end, 0);
	if (errno != 0 || end == s || *end != '\0') {
		fprintf(stderr, "bad address: %s\n", s);
		exit(2);
	}
	return v;
}

static long parse_value(const char *s)
{
	char *end;
	long v;

	errno = 0;
	v = strtol(s, &end, 0);
	if (errno != 0 || end == s || *end != '\0') {
		fprintf(stderr, "bad value: %s\n", s);
		exit(2);
	}
	return v;
}

static int open_mem(void)
{
	int fd = open(DEV_MEM, O_RDWR | O_SYNC);

	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", DEV_MEM, strerror(errno));
		fprintf(stderr,
			"Needs root.  On a phone without a devmem applet, use:\n"
			"  su -c 'setenforce 0'   # if the policy allows it\n");
		exit(1);
	}
	return fd;
}

static void *map_phys(int fd, long addr, size_t len)
{
	static const long page = 4096;
	long base = addr & ~(page - 1);
	off_t off = base;
	void *p;

	p = mmap(NULL, (size_t)(addr - base) + len, PROT_READ | PROT_WRITE,
	         MAP_SHARED, fd, off);
	if (p == MAP_FAILED) {
		fprintf(stderr, "mmap: %s\n", strerror(errno));
		exit(1);
	}
	return (char *)p + (addr - base);
}

int main(int argc, char **argv)
{
	int fd;
	long addr, value;
	void *p;

	if (argc < 3) {
		fprintf(stderr,
			"usage: %s r|r8|r16 <addr>\n"
			"       %s w <addr> <value>\n",
			argv[0], argv[0]);
		return 2;
	}

	fd = open_mem();

	if (!strcmp(argv[1], "w")) {
		if (argc < 4) {
			fprintf(stderr, "usage: %s w <addr> <value>\n", argv[0]);
			return 2;
		}
		addr = parse_addr(argv[2]);
		value = parse_value(argv[3]);
		p = map_phys(fd, addr, 4);
		*(volatile uint32_t *)p = (uint32_t)value;
		printf("0x%lx <= 0x%lx\n", addr, value);
		munmap(p - (addr & 4095), 4096);
		close(fd);
		return 0;
	}

	addr = parse_addr(argv[2]);
	if (!strcmp(argv[1], "r")) {
		p = map_phys(fd, addr, 4);
		printf("0x%lx = 0x%08x\n", addr, *(volatile uint32_t *)p);
	} else if (!strcmp(argv[1], "r8")) {
		p = map_phys(fd, addr, 1);
		printf("0x%lx = 0x%02x\n", addr, *(volatile uint8_t *)p);
	} else if (!strcmp(argv[1], "r16")) {
		p = map_phys(fd, addr, 2);
		printf("0x%lx = 0x%04x\n", addr, *(volatile uint16_t *)p);
	} else {
		fprintf(stderr, "unknown command: %s\n", argv[1]);
		return 2;
	}

	close(fd);
	return 0;
}
