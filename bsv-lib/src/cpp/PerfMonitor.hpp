#ifndef PERFORMANCE_HPP
#define PERFORMANCE_HPP

#include <semaphore.h>
#include <string>
#include "PerfMonitorIndication.h"
#include "PerfMonitorRequest.h"
#include "GeneratedTypes.h"

class PerfMonitor : public PerfMonitorIndicationWrapper {
    public:
        PerfMonitor(unsigned int indicationId, unsigned int requestId);
        ~PerfMonitor();

        // these are called by the main thread
        void printPerformance(std::string filename);
        void setEnable(const int x);
        uint64_t readMonitor(const uint32_t index);

        // theses are called by the PerformanceIndication thread
        void resp(const uint64_t x);

    private:
        PerfMonitorRequestProxy *performanceRequest;

        // used by both threads
        sem_t respSem;
        uint64_t prevResp;

        bool verbose;
};

#endif
