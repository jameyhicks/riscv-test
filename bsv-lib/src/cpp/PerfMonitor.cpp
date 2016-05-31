#include <iostream>
#include <fstream>
#include <streambuf>
#include <sstream>

#include "PerfMonitor.hpp"

PerfMonitor::PerfMonitor(unsigned int indicationId, unsigned int requestId) :
        PerfMonitorIndicationWrapper(indicationId) {
    performanceRequest = new PerfMonitorRequestProxy(requestId);
    sem_init(&respSem, 0, 0);
}

void PerfMonitor::printPerformance(std::string filename) {
    std::ifstream file(filename);
    std::string line;
    std::string name;
    uint32_t index;

    while (std::getline(file, line)) {
        size_t commaIndex = line.find(','); 
        if (commaIndex != std::string::npos) {
            if (line.substr(0,2) == "0x") {
                std::istringstream s(line.substr(2, commaIndex));
                s >> std::hex >> index;
            } else {
                std::istringstream s(line.substr(0, commaIndex));
                s >> index;
            }
            name = line.substr(commaIndex+1);
            std::cout << name << " = " << readMonitor(index) << std::endl;
        }
    }
}

void PerfMonitor::setEnable(const int x) {
    performanceRequest->setEnable(x);
}

uint64_t PerfMonitor::readMonitor(const uint32_t index) {
    performanceRequest->req((uint64_t) index);
    // set semaphore
    sem_wait(&respSem);
    uint64_t resp = prevResp;
    return resp;
}

void PerfMonitor::resp(const uint64_t x) {
    prevResp = x;
    sem_post(&respSem);
}
