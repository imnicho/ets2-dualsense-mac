#include "ipc.h"
_Static_assert(sizeof(struct Telemetry) % 8 == 0, "layout");
