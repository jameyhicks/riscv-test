#!/bin/bash

export RISCV_HOME=$PWD
export RISCV_BUILD=$RISCV_HOME/build
export RISCV_TOOLS=$RISCV_HOME/riscv
export RISCV=$RISCV_TOOLS

export PATH=$RISCV/bin:$PATH
export LD_LIBRARY_PATH=$RISCV/lib

(cd riscv-tools; . build.common; \
echo "Starting RISC-V Toolchain build process"; \
build_project riscv-fesvr --prefix=$RISCV; \
build_project riscv-isa-sim --prefix=$RISCV --with-fesvr=$RISCV; \
build_project riscv-gnu-toolchain --prefix=$RISCV --enable-linux; \
CC= CXX= build_project riscv-pk --prefix=$RISCV/riscv64-unknown-elf --host=riscv64-unknown-elf; \
build_project riscv-tests --prefix=$RISCV/riscv64-unknown-elf; \
echo -e "\\nRISC-V Toolchain installation completed!")
#(cd procs/RV64G_multicycle; make gen.verilator && make -j8 -C verilator bits) || exit 2
#(cd procs/RV64G_multicycle; make -C verilator exe) || exit 3
#cd procs; ./runtests.sh
