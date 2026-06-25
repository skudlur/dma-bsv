#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "C_imports.h"

uint64_t c_malloc_and_init(uint64_t n_bytes, uint64_t init_from_file) {
    uint8_t *mem = (uint8_t *)malloc(n_bytes);
    if (!mem) return 0;
    if (init_from_file) {
        // Not implemented
    } else {
        for(uint64_t i = 0; i < n_bytes; i++) {
            mem[i] = i & 0xFF; // simple pattern
        }
    }
    return (uint64_t)mem;
}

uint64_t c_get_start_pc(void) { return 0; }
uint64_t c_get_min_addr(void) { return 0; }
uint64_t c_get_max_addr(void) { return 0; }
uint64_t c_get_min_text_addr(void) { return 0; }
uint64_t c_get_max_text_addr(void) { return 0; }

uint64_t c_read(uint64_t addr, uint64_t n_bytes) {
    uint64_t val = 0;
    uint8_t *p = (uint8_t *)addr;
    memcpy(&val, p, n_bytes);
    return val;
}

void c_write(uint64_t addr, uint64_t x, uint64_t n_bytes) {
    uint8_t *p = (uint8_t *)addr;
    memcpy(p, &x, n_bytes);
}

void c_write_strb(uint64_t addr, uint64_t x, uint8_t strb) {
    uint8_t *p = (uint8_t *)addr;
    uint8_t *d = (uint8_t *)&x;
    for (int i = 0; i < 8; i++) {
        if ((strb >> i) & 1) {
            p[i] = d[i];
        }
    }
}

void c_get_console_command(uint64_t *cmd_vec) {
    for(int i=0; i<10; i++) cmd_vec[i] = 0;
}
