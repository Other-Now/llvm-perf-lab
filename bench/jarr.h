#pragma once
#include <stdint.h>

// A Java array as the JIT lays it out: length header, then the elements.
typedef struct { int32_t len; int32_t data[]; } jarr;
