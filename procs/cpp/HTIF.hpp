#ifndef HTIF_HPP
#define HTIF_HPP

#include "fesvr/htif.h"
#include "ProcControl.hpp"
#include "HostInterface.hpp"

class HTIF : public htif_t {
    public:
        HTIF(const std::vector<std::string>& args,
                uint64_t *membuffIn,
                size_t memszIn,
                ProcControl *procControlIn,
                HostInterface *hostInterfaceIn);
        ~HTIF();

        // the original implementation (htif_t) uses packets to implement
        // read_cr, write_cr, read_chunk, and write_chunk. That uses the
        // read and write methods to read and write packets. Instead our
        // implementation provides implementations of read_cr, write_cr,
        // read_chunk, and write_chunk to directly perform the action and
        // avoid using packets.

        // XXX: This is the main way things are run:
        // int run();
        // bool done();
        // int exit_code();

        // these can be redefined, but they don't need to be
        virtual void start(); // performs load_program() and reset()
        virtual void stop();

    private:
        virtual reg_t read_cr(uint32_t coreid, uint16_t regnum);
        virtual reg_t write_cr(uint32_t coreid, uint16_t regnum, reg_t val);

        void read_chunk(addr_t taddr, size_t len, void* dst);
        void write_chunk(addr_t taddr, size_t len, const void* src);

        size_t chunk_align() { return sizeof(uint64_t); }
        size_t chunk_max_size() { return (sizeof(uint64_t) * 1024); }

        ssize_t read(void* buf, size_t max_size) { return 0; }
        ssize_t write(const void* buf, size_t size) { return 0; }

        virtual void load_program();
        virtual void reset();

        uint64_t *memBuffer;
        size_t memSz;

        ProcControl *procControl;
        HostInterface *hostInterface;

        bool verbose;
};

#endif
