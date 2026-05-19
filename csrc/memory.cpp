#include "memory.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include "config.h"
//#define DEBUG_MESSAGE
#ifdef DEBUG_MESSAGE
#define MEM_ERR_PRINTF(...) printf(__VA_ARGS__)
#else
#define MEM_ERR_PRINTF(...) ((void)0)
#endif

uint8_t dense_ram[RAM_SIZE] = {0};
uint8_t sparse_ram[RAM_SIZE] = {0};
uint8_t result_ram[RAM_SIZE] = {0};
uint8_t (&sp_ram)[RAM_SIZE] = sparse_ram;

static bool is_128bit_aligned(uint32_t value, const char* name) {
    if ((value & 0xf) == 0) {
        return true;
    }

    printf("[DPI Error] %s 0x%x is not 128-bit aligned\n", name, value);
    return false;
}

static bool get_bin_file_size(const char* filename, long* file_size) {
    FILE* fp = fopen(filename, "rb");
    if (fp == nullptr) {
        printf("[DPI Error] Cannot open file: %s\n", filename);
        return false;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        printf("[DPI Error] Failed to seek file: %s\n", filename);
        fclose(fp);
        return false;
    }

    long size = ftell(fp);
    fclose(fp);
    if (size < 0) {
        printf("[DPI Error] Failed to get file size: %s\n", filename);
        return false;
    }

    *file_size = size;
    return true;
}

static size_t min_size(size_t lhs, size_t rhs) {
    return lhs < rhs ? lhs : rhs;
}

extern "C" {

static uint8_t* get_ram_info(int bramid, uint32_t* size_out) {
    *size_out = RAM_SIZE;

    switch (bramid) {
    case 0:
        return dense_ram;
    case 1:
        return sparse_ram;
    case 2:
        return result_ram;
    default:
        *size_out = 0;
        return nullptr;
    }
}

void pmem_read(int raddr, int bramid, long long* rdata) {
    uint32_t max_size = 0;
    uint8_t* mem = get_ram_info(bramid, &max_size);
    uint32_t addr = (uint32_t)raddr>>3;
    addr = addr << 3; // 64-bit aligned
    if (mem == nullptr || (addr + 8 > max_size)) {
        *rdata = 0; 
        MEM_ERR_PRINTF("[DPI Error] Read Out of Bounds! ID=%d, Addr=0x%x\n", bramid, addr);
        return;
    }

    uint64_t val = 0;
    val |= (uint64_t)mem[addr + 0] << 0;
    val |= (uint64_t)mem[addr + 1] << 8;
    val |= (uint64_t)mem[addr + 2] << 16;
    val |= (uint64_t)mem[addr + 3] << 24;
    val |= (uint64_t)mem[addr + 4] << 32;
    val |= (uint64_t)mem[addr + 5] << 40;
    val |= (uint64_t)mem[addr + 6] << 48;
    val |= (uint64_t)mem[addr + 7] << 56;

    *rdata = (long long)val;
}

void pmem_write(int waddr, int bramid, long long wdata, char wmask) {
    uint32_t max_size = 0;
    uint8_t* mem = get_ram_info(bramid, &max_size);
    
    uint32_t addr = (uint32_t)waddr>>3;
    addr = addr << 3; // 64-bit aligned
    uint64_t data = (uint64_t)wdata;
    uint8_t  mask = (uint8_t)wmask;

    if (mem == nullptr || (addr + 8 > max_size)) {
        MEM_ERR_PRINTF("[DPI Error] Write Out of Bounds! ID=%d, Addr=0x%x\n", bramid, addr);
        return;
    }

    for (int i = 0; i < 8; i++) {
        if ((mask >> i) & 1) {
            mem[addr + i] = (uint8_t)((data >> (i * 8)) & 0xFF);
        }
    }
}



}

bool load_bin_to_ram(const char* filename, uint8_t* ram_ptr, uint32_t max_size, uint32_t offset) {
    FILE* fp = fopen(filename, "rb");
    if (fp == nullptr) {
        printf("[DPI Error] Cannot open file: %s\n", filename);
        return false;
    }
    fseek(fp, 0, SEEK_END); 
    long file_size = ftell(fp);
    rewind(fp);            
    if (offset >= max_size) {
        printf("[DPI Error] Offset 0x%x is out of RAM range (Size: 0x%x)\n", offset, max_size);
        fclose(fp);
        return false;
    }
    if (offset + file_size > max_size) {
        printf("[DPI Error] File %s is too large! (File: %ld + Offset: %d > RAM: %d)\n", 
               filename, file_size, offset, max_size);
        fclose(fp);
        return false;
    }
    size_t result = fread(ram_ptr + offset, 1, file_size, fp);
    if (result != (size_t)file_size) {
        printf("[DPI Error] Reading file failed.\n");
        fclose(fp);
        return false;
    }
    fclose(fp);
    printf("[DPI Info] Loaded %s to RAM @ Offset 0x%x (Size: %ld bytes)\n", filename, offset, file_size);
    return true;
}

bool load_bin_to_ram_128bit(const char* filename, uint8_t* ram_ptr, uint32_t max_size, uint32_t offset) {
    if (!is_128bit_aligned(offset, "Load offset")) {
        return false;
    }
    if (ram_ptr == nullptr) {
        printf("[DPI Error] RAM pointer is null\n");
        return false;
    }

    long file_size = 0;
    if (!get_bin_file_size(filename, &file_size)) {
        return false;
    }
    if (offset >= max_size) {
        printf("[DPI Error] Offset 0x%x is out of RAM range (Size: 0x%x)\n", offset, max_size);
        return false;
    }
    if ((uint64_t)offset + (uint64_t)file_size > max_size) {
        printf("[DPI Error] File %s is too large! (File: %ld + Offset: %d > RAM: %d)\n",
               filename, file_size, offset, max_size);
        return false;
    }
    if ((file_size & 0xf) != 0) {
        printf("[DPI Warning] File %s size %ld is not a multiple of 16 bytes; the last 128-bit word is partial\n",
               filename, file_size);
    }

    FILE* fp = fopen(filename, "rb");
    if (fp == nullptr) {
        printf("[DPI Error] Cannot open file: %s\n", filename);
        return false;
    }

    long remaining = file_size;
    uint32_t addr = offset;
    uint8_t word[16] = {0};
    while (remaining > 0) {
        size_t word_len = min_size((size_t)remaining, sizeof(word));
        memset(word, 0, sizeof(word));

        size_t result = fread(word, 1, word_len, fp);
        if (result != word_len) {
            printf("[DPI Error] Reading file failed.\n");
            fclose(fp);
            return false;
        }

        size_t low_len = min_size(word_len, 8);
        size_t high_len = word_len > 8 ? word_len - 8 : 0;

        memcpy(ram_ptr + addr, word, low_len);
        if (high_len > 0) {
            memcpy(ram_ptr + addr + 8, word + 8, high_len);
        }

        addr += 16;
        remaining -= (long)word_len;
    }

    fclose(fp);
    printf("[DPI Info] Loaded %s to 128-bit RAM @ Offset 0x%x (Size: %ld bytes)\n",
           filename, offset, file_size);
    return true;
}

bool dump_ram_to_bin(const char* filename, const uint8_t* ram_ptr, uint32_t max_size, uint32_t start_offset, uint32_t write_len) {
    if (start_offset >= max_size) {
        printf("[DPI Error] Dump start offset 0x%x out of range (Size: 0x%x)\n", start_offset, max_size);
        return false;
    }

    uint32_t actual_len = write_len;
    if (write_len == 0 || (start_offset + write_len > max_size)) {
        actual_len = max_size - start_offset;
        if (write_len != 0) {
            printf("[DPI Warning] Dump length truncated to 0x%x bytes\n", actual_len);
        }
    }

    FILE* fp = fopen(filename, "wb");
    if (fp == nullptr) {
        printf("[DPI Error] Cannot open file for writing: %s\n", filename);
        return false;
    }

    size_t written = fwrite(ram_ptr + start_offset, 1, actual_len, fp);
    
    fclose(fp);

    if (written == actual_len) {
        printf("[DPI Info] Dumped RAM to %s (Offset: 0x%x, Len: 0x%x bytes)\n", filename, start_offset, actual_len);
        return true;
    } else {
        printf("[DPI Error] Write failed. Expected 0x%x bytes, wrote 0x%lx bytes\n", actual_len, written);
        return false;
    }
}

bool dump_ram_to_bin_128bit(const char* filename, const uint8_t* ram_ptr, uint32_t max_size, uint32_t start_offset, uint32_t write_len) {
    if (!is_128bit_aligned(start_offset, "Dump start offset")) {
        return false;
    }
    if (ram_ptr == nullptr) {
        printf("[DPI Error] RAM pointer is null\n");
        return false;
    }
    if (start_offset >= max_size) {
        printf("[DPI Error] Dump start offset 0x%x out of range (Size: 0x%x)\n", start_offset, max_size);
        return false;
    }

    uint32_t actual_len = write_len;
    if (write_len == 0 || (start_offset + write_len > max_size)) {
        actual_len = max_size - start_offset;
        if (write_len != 0) {
            printf("[DPI Warning] Dump length truncated to 0x%x bytes\n", actual_len);
        }
    }
    if (write_len != 0 && (write_len & 0xf) != 0) {
        printf("[DPI Warning] Dump length 0x%x is not a multiple of 16 bytes; the last 128-bit word is partial\n",
               write_len);
    }

    FILE* fp = fopen(filename, "wb");
    if (fp == nullptr) {
        printf("[DPI Error] Cannot open file for writing: %s\n", filename);
        return false;
    }

    uint32_t addr = start_offset;
    uint32_t dumped_len = 0;
    uint8_t word[16] = {0};
    while (dumped_len < actual_len) {
        size_t word_len = min_size((size_t)(actual_len - dumped_len), sizeof(word));
        size_t low_len = min_size(word_len, 8);
        size_t high_len = word_len > 8 ? word_len - 8 : 0;

        memset(word, 0, sizeof(word));
        memcpy(word, ram_ptr + addr, low_len);
        if (high_len > 0) {
            memcpy(word + 8, ram_ptr + addr + 8, high_len);
        }

        size_t written = fwrite(word, 1, word_len, fp);
        if (written != word_len) {
            printf("[DPI Error] Write failed. Expected 0x%lx bytes, wrote 0x%lx bytes\n",
                   (unsigned long)word_len, (unsigned long)written);
            fclose(fp);
            return false;
        }

        addr += 16;
        dumped_len += (uint32_t)word_len;
    }

    fclose(fp);
    printf("[DPI Info] Dumped 128-bit RAM to %s (Offset: 0x%x, Len: 0x%x bytes)\n",
           filename, start_offset, actual_len);
    return true;
}
