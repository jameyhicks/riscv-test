#ifndef PROC_CONTROL_HPP
#define PROC_CONTROL_HPP

#include <semaphore.h>
#include "ProcControlIndication.h"
#include "ProcControlRequest.h"
#include "GeneratedTypes.h"

class ProcControl : public ProcControlIndicationWrapper {
    public:
        ProcControl(unsigned int indicationId, unsigned int requestId);
        ~ProcControl();

        // these are called by the main thread
        void reset();
        void start(const uint64_t startPc);
        void stop();
        void configure(const uint64_t miobase);
        void initSharedMem(const uint32_t refPointer, const uint64_t memSize);

        // this sets the verification packet settings for the next time start
        // is called
        void configureVerificationPackets(const uint64_t verificationPacketsToIgnoreIn, const bool sendSynchronizationPacketsIn);

        // called by ProcControlIndication thread
        void resetDone();

    private:
        // only used by main thread
        ProcControlRequestProxy *procControlRequest;
        uint64_t verificationPacketsToIgnore;
        bool sendSynchronizationPackets;
        uint64_t miobase;

        // used by both threads
        sem_t resetSem;
};

#endif
