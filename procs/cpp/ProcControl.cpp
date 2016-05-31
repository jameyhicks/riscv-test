#include "ProcControl.hpp"

ProcControl::ProcControl(unsigned int indicationId, unsigned int requestId) :
        ProcControlIndicationWrapper(indicationId),
        verificationPacketsToIgnore(0),
        sendSynchronizationPackets(false) {
    procControlRequest = new ProcControlRequestProxy(requestId);
    sem_init(&resetSem, 0, 0);
}

ProcControl::~ProcControl() {
    sem_destroy(&resetSem);
    delete procControlRequest;
}

// TODO: only configure the processor in one place
void ProcControl::reset() {
    // request for the processor to reset
    procControlRequest->reset();
    // wait for reset to finish
    sem_wait(&resetSem);
    // configure processor
    procControlRequest->configure(this->miobase);
}

// configure and start
void ProcControl::start(const uint64_t startPc) {
    procControlRequest->configure(this->miobase);
    procControlRequest->start(startPc, verificationPacketsToIgnore, (int) sendSynchronizationPackets);
}

void ProcControl::stop() {
    procControlRequest->stop();
}

void ProcControl::configure(const uint64_t miobase) {
    this->miobase = miobase;
    procControlRequest->configure(miobase);
}

void ProcControl::initSharedMem(const uint32_t refPointer, const uint64_t memSize) {
    procControlRequest->initSharedMem(refPointer, memSize);
}

void ProcControl::configureVerificationPackets(const uint64_t verificationPacketsToIgnoreIn, const bool sendSynchronizationPacketsIn) {
    verificationPacketsToIgnore = verificationPacketsToIgnoreIn;
    sendSynchronizationPackets = sendSynchronizationPacketsIn;
}

void ProcControl::resetDone() {
    // signal that reset is done
    sem_post(&resetSem);
}
