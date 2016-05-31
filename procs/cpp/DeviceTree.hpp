#ifndef DEVICE_TREE_HPP
#define DEVICE_TREE_HPP

#include <vector>
#include <string>

// This function makes a device tree that matches spike
std::vector<char> makeDeviceTree(size_t memSz, unsigned int numProcs, std::string isa);

#endif
