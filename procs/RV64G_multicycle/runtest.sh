#!/bin/bash

echo "\$RISCV_HOME = $RISCV_HOME"
echo "\$RISCV_BUILD = $RISCV_BUILD"
echo "\$RISCV_TOOLS = $RISCV_TOOLS"
echo "\$RISCV = $RISCV"

if [ "$#" -eq 0 ] ; then
    echo "Please select a set of tests:"
    echo "1) rv64ui-p-add"
    echo "2) rv64ui-p-*"
    echo "3) rv64uf-p-*"
    echo "4) rv64mi-p-*"
    echo "5) rv64si-p-*"
    echo "6) rv64mi-p-dirty"
    echo "7) linux"
    read OPTION
else
    OPTION=$1
fi

RUNEXE=./verilator/bin/ubuntu.exe

rm -rf out/
mkdir -p out

case "$OPTION" in
    1) $RUNEXE $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-add
       files=
       ;;
    2) files=`find $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-* -type f ! -name "*.*"`
       ;;
    3) files=`find $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64uf-p-* -type f ! -name "*.*"`
       ;;
    4) files=`find $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64mi-p-* -type f ! -name "*.*"`
       ;;
    5) files=`find $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64si-p-* -type f ! -name "*.*"`
       ;;
    6) files=$RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64mi-p-dirty
       ;;
    7) $RUNEXE +ramdisk=$RISCV_HOME/root.bin $RISCV/riscv64-unknown-elf/bin/bbl $RISCV_HOME/linux-4.1.17/vmlinux > out/linux.out
       files=
       ;;
    *) echo "Invalid Test Code"
       exit
       ;;
esac

for hexfile in $files ; do
    basehexfile=$(basename "$hexfile")
    ./verilator/bin/ubuntu.exe $hexfile &> out/${basehexfile}.out
    # check return value
    errorcode=$?
    if [ $errorcode -ne 0 ] ; then
        echo "$basehexfile FAILED $errorcode"
        # exit 1
    else
        echo "$basehexfile OK"
    fi
done
rm SOCK.*
