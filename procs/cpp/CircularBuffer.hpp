#ifndef CIRCULAR_BUFFER_HPP
#define CIRCULAR_BUFFER_HPP

#include <list>
#include <ostream>
#include <string>

class CircularBuffer {
    public:
        CircularBuffer(size_t maxSizeIn) : maxSize(maxSizeIn), entriesToPrint(0), ostreamForPrinting(NULL), data() {}

        void addLine(std::string stringIn) {
            if (entriesToPrint > 0) {
                (*ostreamForPrinting) << stringIn << std::endl;
                entriesToPrint--;
            } else {
                data.push_back(stringIn);
                if (data.size() > maxSize) {
                    data.pop_front();
                }
            }
        }

        void printToOStream(std::ostream * o, size_t extraEntriesToPrint) {
            // dump the current circular buffer
            while (data.size() > 0) {
                (*o) << data.front() << std::endl;
                data.pop_front();
            }
            // if extraEntriesToPrint > 0, then future lines will be printed
            // as they are added
            ostreamForPrinting = o;
            entriesToPrint = extraEntriesToPrint;
        }

    private:
        size_t maxSize;
        size_t entriesToPrint;
        std::ostream *ostreamForPrinting;
        std::list<std::string> data;
};
#endif
