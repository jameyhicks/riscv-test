#include "Verification.hpp"
#include "SpikeTandemVerifier.hpp"

Verification::Verification(unsigned int id, TandemVerifier *tandemVerifierIn)
        : VerificationIndicationWrapper(id), tandemVerifier(tandemVerifierIn) {
}

Verification::~Verification() {
    if (tandemVerifier != NULL) {
        delete tandemVerifier;
    }
}

void Verification::getVerificationPacket(VerificationPacket p) {
    if (tandemVerifier != NULL) {
        tandemVerifier->checkVerificationPacket(p);
    }
}

void Verification::printStatus() {
    if (tandemVerifier != NULL) {
        fprintf(stderr, "Verification::printStatus():\n");
        tandemVerifier->printStatus();
    } else {
        fprintf(stderr, "Verification::printStatus(): tandemVerifier == NULL\n");
    }
}
