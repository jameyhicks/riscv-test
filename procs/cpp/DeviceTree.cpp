#include <cstring>
#include <inttypes.h>
#include "fesvr/htif.h"
#include "spike/devicetree.h"
#include "DeviceTree.hpp"

// This function makes a device tree that matches spike

// temporary define
#define NCSR 4096

std::vector<char> makeDeviceTree(size_t memSz, unsigned int numProcs, std::string isa) {
    char buf[32];
    size_t max_devtree_size = numProcs * 4096; // sloppy upper bound
    size_t cpu_size = NCSR * 64 / 8; // this assumes RV64
    reg_t cpu_addr = memSz + max_devtree_size;

    device_tree dt;
    dt.begin_node("");
    dt.add_prop("#address-cells", 2);
    dt.add_prop("#size-cells", 2);
    dt.add_prop("model", "Spike");
        dt.begin_node("memory@0");
            dt.add_prop("device_type", "memory");
            dt.add_reg({0, memSz});
        dt.end_node();
        dt.begin_node("cpus");
            dt.add_prop("#address-cells", 2);
            dt.add_prop("#size-cells", 2);
            for (size_t i = 0; i < numProcs; i++) {
                sprintf(buf, "cpu@%" PRIx64, cpu_addr);
                dt.begin_node(buf);
                    dt.add_prop("device_type", "cpu");
                    dt.add_prop("compatible", "riscv");
                    dt.add_prop("isa", isa);
                    dt.add_reg({cpu_addr});
                dt.end_node();

                // bus.add_device(cpu_addr, procs[i]);
                cpu_addr += cpu_size;
            }
        dt.end_node();
    dt.end_node();

    return dt.finalize();
}
