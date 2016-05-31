#ifndef HOST_INTERFACE_HPP
#define HOST_INTERFACE_HPP

#include <semaphore.h>
#include <queue>
#include "HostInterfaceIndication.h"
#include "HostInterfaceRequest.h"
#include "GeneratedTypes.h"

class HostInterface : public HostInterfaceIndicationWrapper {
    public:
        HostInterface(unsigned int indicationId, unsigned int requestId);
        ~HostInterface();

        // called by HostInterfaceIndication thread
        void toHost(const uint64_t v);

        // called by the main thread to access tohost/fromhost
        bool getToHostMessage(uint64_t *msg);
        void putFromHostMessage(uint64_t msg);

    private:
        // only used by main thread
        HostInterfaceRequestProxy *hostInterfaceRequest;

        // used by both threads
        std::queue<uint64_t> toHostMessages;
        pthread_mutex_t mutex;
};

#endif
