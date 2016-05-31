#ifndef TANDEM_VERIFIER_HPP
#define TANDEM_VERIFIER_HPP

#include "GeneratedTypes.h"

class TandemVerifier {
    public:
        TandemVerifier() : errors(0) {}
        virtual ~TandemVerifier() {}
        virtual bool checkVerificationPacket(VerificationPacket p) { return true; }
        virtual void printStatus() {}
        virtual unsigned int getNumErrors() { return errors; }
        virtual bool shouldAbort() { return false; }
    protected:
        // number of errors seen
        unsigned int errors;
};

#endif // TANDEM_VERIFIER_HPP
