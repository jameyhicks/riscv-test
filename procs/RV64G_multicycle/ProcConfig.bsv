`define CONNECTAL_MEMORY
`define IN_ORDER
`define rv64 True
`define m True
`define a True
`define f True
`define d True

// Set this define to use the FMA for Add and Mul
`define REUSE_FMA

// Defines to match spike's behavior
// `define CYCLE_COUNT_EQ_INST_COUNT
`define DISABLE_STIP
`define LOOK_LIKE_A_ROCKET

// Debugging infrastructure
`define VERIFICATION_PACKETS

// Workarounds
// `define WORKAROUND_ISSUE_27
// `define SERIALIZE_MEM_REQS
`define FLUSH_CACHES_ON_HTIF

