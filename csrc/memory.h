#pragma once

#include <cstdint>

#include "VTEST_PLATFORM__Dpi.h"

extern bool load_bin_to_ram(const char* filename, uint8_t* ram_ptr, uint32_t max_size, uint32_t offset);
extern bool load_bin_to_ram_128bit(const char* filename, uint8_t* ram_ptr, uint32_t max_size, uint32_t offset);
extern bool dump_ram_to_bin(const char* filename, const uint8_t* ram_ptr, uint32_t max_size, uint32_t start_offset, uint32_t write_len);
extern bool dump_ram_to_bin_128bit(const char* filename, const uint8_t* ram_ptr, uint32_t max_size, uint32_t start_offset, uint32_t write_len);

#define RAM_SIZE    (64 * 1024)

extern uint8_t dense_ram[RAM_SIZE];  // 对应 bramid = 0
extern uint8_t sparse_ram[RAM_SIZE]; // 对应 bramid = 1
extern uint8_t result_ram[RAM_SIZE]; // 对应 bramid = 2
extern uint8_t (&sp_ram)[RAM_SIZE];  // 兼容旧名字，对应 sparse_ram
