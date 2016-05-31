#ifndef SPIKE_TANDEM_VERIFIER_HPP
#define SPIKE_TANDEM_VERIFIER_HPP

#include <string>
#include <vector>
#include <pthread.h>
#include "spike/sim.h"
#include "spike/disasm.h"
#include "CircularBuffer.hpp"
#include "TandemVerifier.hpp"

class SpikeTandemVerifier : public TandemVerifier {
    public:
        SpikeTandemVerifier(std::vector<std::string> htifArgsIn, size_t memSzIn);
        ~SpikeTandemVerifier();

        // called by VerificationIndication
        bool checkVerificationPacket(VerificationPacket p);
        bool shouldAbort();

        // called by main thread (probably?)
        void printStatus();

    private:
        void initSim();
        void synchronize(VerificationPacket p);
        VerificationPacket synchronizedSimStep(VerificationPacket p);
        bool comparePackets(VerificationPacket procP, VerificationPacket spikeP);
        std::string verificationPacketToString(VerificationPacket p);

        std::vector<std::string> htifArgs;
        size_t memSz;
        sim_t *sim;
        disassembler_t *disassembler;
        pthread_mutex_t mutex;

        // number of packets seen
        unsigned int packets;
        // number of instructions retired
        unsigned int instructions;
        // if too many errors have been seen
        bool abort;
        
        CircularBuffer outBuffer;
};

#endif
