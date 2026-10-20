# SPDX-License-Identifier: GPL-2.0-or-later
#
# Clean-room reimplementation of the Xiaomi USB-PD authentication handshake.
#
#   make          build the library, the CLI and the test binary
#   make test     build and run the self-tests
#   make clean

CC      ?= cc
CFLAGS  ?= -O2 -g -std=c11 -Wall -Wextra -Wpedantic
CPPFLAGS += -Iinclude -Itests -D_POSIX_C_SOURCE=200809L
LDFLAGS ?=

BUILD   := build
BIN     := $(BUILD)/xpd_auth
TESTBIN := $(BUILD)/test_xpd_auth

SRC     := src/sha256.c src/xpd_auth.c src/xpd_keytable.c
OBJ     := $(patsubst src/%.c,$(BUILD)/%.o,$(SRC))

.PHONY: all test clean

all: $(BIN) $(TESTBIN)

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

$(BUILD)/%.o: tests/%.c | $(BUILD)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

$(BIN): $(BUILD)/xpd_auth_cli.o $(OBJ)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

$(TESTBIN): $(BUILD)/test_xpd_auth.o $(OBJ)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

test: $(TESTBIN)
	./$(TESTBIN)

clean:
	rm -rf $(BUILD)
