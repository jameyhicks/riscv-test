#ifndef VERIFICATION_HPP
#define VERIFICATION_HPP

#include "VerificationIndication.h"
#include "TandemVerifier.hpp"
#include "GeneratedTypes.h"

class Verification : public VerificationIndicationWrapper {
    public:
        Verification(unsigned int id, TandemVerifier *tandemVerifierIn);
        virtual ~Verification();

        // these are called by the main thread
        // XXX: none for now

        // called by ProcControlIndication thread
        void getVerificationPacket(VerificationPacket p);
        void printStatus();

    private:
        TandemVerifier *tandemVerifier;
};

#endif
