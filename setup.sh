#!/bin/bash
export RISCV_HOME=$HOME/riscy-processors
export RISCV_BUILD=$RISCV_HOME/build
export RISCV_TOOLS=$RISCV_HOME/riscv
export RISCV=$RISCV_TOOLS

export PATH=$RISCV/bin:$PATH
export LD_LIBRARY_PATH=$RISCV/lib

