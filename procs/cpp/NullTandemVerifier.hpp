#ifndef NULL_TANDEM_VERIFIER_HPP
#define NULL_TANDEM_VERIFIER_HPP
#include <inttypes.h>
#include <fstream>
#include "TandemVerifier.hpp"

class NullTandemVerifier : public TandemVerifier {
    public:
        NullTandemVerifier() : TandemVerifier() {
            packets = 0;
        }
        ~NullTandemVerifier() {
        }
        bool checkVerificationPacket(VerificationPacket p) {
            packets++;
            lastPc = p.pc;
            return true;
        }
        void printStatus() {
            fprintf(stderr, "NullTandemVerifier::printStatus() - %llu packets seen. Last pc = 0x%llx\n", (long long unsigned) packets, (long long int) lastPc);
        }
    private:
        uint64_t packets;
        uint64_t lastPc;
};

#endif // TANDEM_VERIFIER_HPP
