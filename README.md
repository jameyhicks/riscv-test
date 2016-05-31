riscy-release-candidate
=======================

How to use:

1) `git submodule update --init --recursive`
2) Edit setup.sh so RISCV_HOME points to the riscy-release-candidate directory
3) `source ./setup.sh`
4) `cd riscv-tools`
5) `./build.sh`
6) `cd ../procs/RV64G_redux
7) `make build.verilator`
8) `./runtests.sh`
9) select which tests you want to run
