#!/bin/bash

export RISCV_HOME=$PWD
export RISCV_BUILD=$RISCV_HOME/build
export RISCV_TOOLS=$RISCV_HOME/riscv
export RISCV=$RISCV_TOOLS

export PATH=$RISCV/bin:$PATH
export LD_LIBRARY_PATH=$RISCV/lib

(cd riscv-tools; ./build.sh > /dev/null) || exit 1
(cd riscv-tools; make -C riscv-gnu-toolchain/build -j2 linux)
#(cd procs/RV64G_multicycle; make gen.verilator && make -j8 -C verilator bits) || exit 2
#(cd procs/RV64G_multicycle; make -C verilator exe) || exit 3
#cd procs; ./runtests.sh
