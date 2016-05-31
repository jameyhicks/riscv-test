#include <errno.h>
#include <stdio.h>
#include <cstring>
#include <cassert>
#include <fcntl.h>
#include <string.h>
#include <iostream>
#include <sys/stat.h>
#include <unistd.h>
#include <semaphore.h>
#include <vector>
#include <string>
#include <sstream>
#include <list>
#include <signal.h>
#include "dmaManager.h"

#include "ProcControl.hpp"
#include "HostInterface.hpp"
#include "Verification.hpp"
#include "PerfMonitor.hpp"
#include "HTIF.hpp"
#include "DeviceTree.hpp"

#include "NullTandemVerifier.hpp"
#include "SpikeTandemVerifier.hpp"

#include "GeneratedTypes.h"

#ifdef NDEBUG
#error fesvr will not work with NDEBUG defined
#endif

#define CONNECTAL_MEMORY

#define BLURT fprintf (stderr, "CPPDEBUG: %s(%s):%d\n",\
                      __func__, __FILE__, __LINE__)

// main stuff
static ProcControl *procControl = NULL;
static HostInterface *hostInterface = NULL;
static Verification *verification = NULL;
static PerfMonitor *perfMonitor = NULL;
static HTIF *htif = NULL;

uint64_t *sharedMemBuffer;
// the amount of RAM attached to the processor. 64 MB by default
size_t memSz = 64*1024*1024;
// sharedMemSz is larger than memSize to contain a read-only region for the
// device tree. Right now the region has an upperbound of 4 KB per processor.
// TODO: make the number of processors a variable.
size_t sharedMemSz = memSz + 4096 * 1;

// What do we do with this?
static void handle_signal(int sig) {
    fprintf(stderr, "\n>> Ctrl-C: Exiting...\n");
    if (verification != NULL) {
        verification->printStatus();
    }
    exit(1);
}

void printHelp(const char *prog)
{
    fprintf(stderr, "Usage: %s [--just-run] HTIF_ARGS\n", prog);
}

int main(int argc, char * const *argv) {
    // command line argument parsing
    // strip prog_name off of the command line arguments
    const char *prog_name = argv[0];
    argc--;
    argv++;
    // if the first argument is "-h" or "--help", print help
    if (argc > 0 && ((strcmp(argv[0], "-h") == 0) || (strcmp(argv[0], "--help") == 0))) {
        printHelp(prog_name);
        exit(0);
    }
    // if the next argument is "--just-run" remove it and set just_run to true
    bool just_run = false;
    if (argc > 0 && strcmp(argv[0], "--just-run") == 0) {
        just_run = true;
        argc--;
        argv++;
    }

    signal(SIGINT, &handle_signal);

    long actualFrequency = 0;
    long requestedFrequency = 1e9 / MainClockPeriod;

#ifdef SIMULATION // safe to always do this, but it's only useful for simulation
    char socket_name[128];
    snprintf(socket_name, sizeof(socket_name), "SOCK.%d", getpid());
    setenv("BLUESIM_SOCKET_NAME", socket_name, 0);
    setenv("SOFTWARE_SOCKET_NAME", socket_name, 0);
#endif

    // format htif args
    std::vector<std::string> htif_args;
    fprintf(stderr, "htif_args: ");
    for (int i = 0 ; i < argc ; i++ ) {
        // adding argument
        htif_args.push_back(argv[i]);
        // printing arguments
        fprintf(stderr, "%s", argv[i]);
        if (i == argc-1) {
            fprintf(stderr, "\n");
        } else {
            fprintf(stderr, ", ");
        }
    }

    // objects for controlling the interaction with the processor
    procControl = new ProcControl(IfcNames_ProcControlIndicationH2S, IfcNames_ProcControlRequestS2H);
    hostInterface = new HostInterface(IfcNames_HostInterfaceIndicationH2S, IfcNames_HostInterfaceRequestS2H);
    if (just_run) {
        verification = new Verification(IfcNames_VerificationIndicationH2S, new NullTandemVerifier());
    } else {
        verification = new Verification(IfcNames_VerificationIndicationH2S, new SpikeTandemVerifier(htif_args, memSz));
    }
    perfMonitor = new PerfMonitor(IfcNames_PerfMonitorIndicationH2S, IfcNames_PerfMonitorRequestS2H);

    int status = setClockFrequency(0, requestedFrequency, &actualFrequency);
    printf("Requested main clock frequency %5.2f, actual clock frequency %5.2f MHz status=%d errno=%d\n",
        (double)requestedFrequency * 1.0e-6,
        (double)actualFrequency * 1.0e-6,
        status, (status != 0) ? errno : 0);

    DmaManager *dma = platformInit();
    int memAlloc = portalAlloc(sharedMemSz, 0);
    sharedMemBuffer = (uint64_t*)portalMmap(memAlloc, sharedMemSz);
    unsigned int ref_memAlloc = dma->reference(memAlloc);

    procControl->initSharedMem(ref_memAlloc, sharedMemSz);

    // miobase is in the shared memory just after the RAM
    procControl->configure(memSz);
    // now add the device tree
    // TODO: make number of processors a variable (currently 1)
    // TODO: make ISA string a variable
    std::vector<char> devicetree = makeDeviceTree(memSz, 1, "rv64IMAFD");
    // XXX: stack overflow said this would work
    if (memSz + devicetree.size() > sharedMemSz) {
        fprintf(stderr, "ERROR: device tree too long\n");
        fprintf(stderr, "devicetree.size() = %llu\n", (long long unsigned) devicetree.size());
        fprintf(stderr, "memSz = %llu\n", (long long unsigned) memSz);
        fprintf(stderr, "sharedMemSz = %llu\n", (long long unsigned) sharedMemSz);
        exit(1);
    }
    memcpy( (void *) &sharedMemBuffer[memSz / sizeof(uint64_t)], (void *) &devicetree[0], devicetree.size());

    // Connect an HTIF module up to the procControl and hostInterface interfaces
    htif = new HTIF(htif_args, sharedMemBuffer, memSz, procControl, hostInterface);

    // This function loads the specified program, and runs the test
    int result = htif->run();
    perfMonitor->setEnable(0);

    if (result == 0) {
        fprintf(stderr, "[32mPASSED[39m\n");
    } else {
        fprintf(stderr, "[31mFAILED %d[39m\n", (int) result);
    }

#ifdef SIMULATION
    unlink(socket_name);
#endif

    fprintf(stderr, "---- Verification results: ------------------------------------------\n");
    verification->printStatus();
    fprintf(stderr, "\n");
    fprintf(stderr, "---- PerfMonitor results: -------------------------------------------\n");
    perfMonitor->printPerformance("verilator/Proc.perfmon.txt");
    fprintf(stderr, "\n");

    fflush(stdout);
    fflush(stderr);

    return result;
}
