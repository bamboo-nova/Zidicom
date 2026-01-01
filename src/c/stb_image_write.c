#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <stdlib.h>
#include <string.h>

// Custom memory writer for WASM
typedef struct {
    unsigned char* data;
    size_t size;
    size_t capacity;
} WriteContext;

static void write_callback(void* context, void* data, int size) {
    WriteContext* ctx = (WriteContext*)context;

    // Grow buffer if needed
    if (ctx->size + size > ctx->capacity) {
        size_t new_capacity = (ctx->capacity == 0) ? 4096 : ctx->capacity * 2;
        while (new_capacity < ctx->size + size) {
            new_capacity *= 2;
        }
        unsigned char* new_data = (unsigned char*)realloc(ctx->data, new_capacity);
        if (!new_data) {
            return; // Allocation failed
        }
        ctx->data = new_data;
        ctx->capacity = new_capacity;
    }

    memcpy(ctx->data + ctx->size, data, size);
    ctx->size += size;
}

// Wrapper function for PNG encoding to memory
int stb_write_png_to_memory(
    unsigned char** output,
    size_t* output_len,
    int w, int h, int comp,
    const void* data, int stride_in_bytes
) {
    WriteContext ctx = { NULL, 0, 0 };

    int result = stbi_write_png_to_func(write_callback, &ctx, w, h, comp, data, stride_in_bytes);

    if (result && ctx.size > 0) {
        *output = ctx.data;
        *output_len = ctx.size;
        return 1;
    }

    // Cleanup on failure
    if (ctx.data) {
        free(ctx.data);
    }
    return 0;
}

// Wrapper function for JPEG encoding to memory
int stb_write_jpg_to_memory(
    unsigned char** output,
    size_t* output_len,
    int w, int h, int comp,
    const void* data, int quality
) {
    WriteContext ctx = { NULL, 0, 0 };

    int result = stbi_write_jpg_to_func(write_callback, &ctx, w, h, comp, data, quality);

    if (result && ctx.size > 0) {
        *output = ctx.data;
        *output_len = ctx.size;
        return 1;
    }

    // Cleanup on failure
    if (ctx.data) {
        free(ctx.data);
    }
    return 0;
}
