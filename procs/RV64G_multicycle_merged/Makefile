PROC=RV64G_multicycle_merged

# Suppress "duplicate folder" and "unfolding over ... steps" warnings
# CONNECTALFLAGS += --bscflags=" -suppress-warnings S0073:G0024 "

# Attempt to optimize the generated Verilog. In a small test with part of the
# decoder, this increased the post-synthesis area by 10% so we don't use these
# flags by default.
# CONNECTALFLAGS += --bscflags=" -opt-undetermined-vals -unspecified-to X "

include $(RISCV_HOME)/procs/Makefile.procs
