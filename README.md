# Nexora X3: A High-Performance Heterogeneous AI SoC

Nexora X3 is a high-performance, heterogeneous System-on-Chip (SoC) written in SystemVerilog. Built from the ground up for ASIC implementations, Nexora X3 integrates multi-core RISC-V Out-of-Order (OoO) CPUs, SIMT GPU clusters, Systolic-Array-based Tensor processing units, a 4x4 mesh Network-on-Chip (NoC), and an AXI4-compliant HBM cache-coherent memory subsystem with Processing-In-Memory (PIM) capabilities.

---

## 🚀 Key Features & Architecture

```
                                  Nexora X3 SoC Top
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│ ┌────────────────┐ ┌────────────────┐ ┌────────────────┐ ┌─────────────┐ │
│ │  CPU Clusters  │ │  GPU Clusters  │ │Tensor Clusters │ │ DSP Cluster │ │
│ │   (4 x Cores)  │ │   (8 x SIMT)   │ │  (4 x Systolic)│ │   (High-P)  │ │
│ └───────┬────────┘ └───────┬────────┘ └───────┬────────┘ └──────┬──────┘ │
│         │                  │                  │                 │        │
│ ┌───────▼──────────────────▼──────────────────▼─────────────────▼──────┐ │
│ │                         4x4 Mesh Network-on-Chip                     │ │
│ └───────────────────────────────────┬──────────────────────────────────┘ │
│                                     │                                    │
│ ┌───────────────────────────────────▼──────────────────────────────────┐ │
│ │             Cache Subsystem (L1/L2 MESI Cache Coherence)             │ │
│ └───────────────────────────────────┬──────────────────────────────────┘ │
│                                     │                                    │
│ ┌───────────────────────────────────▼──────────────────────────────────┐ │
│ │        HBM Controller & Processing-in-Memory (PIM) Accelerator       │ │
│ └───────────────────────────────────┬──────────────────────────────────┘ │
│                                     │                                    │
│ ┌───────────────────────────────────▼──────────────────────────────────┐ │
│ │                     Debug (JTAG) & Power Subsystems                  │ │
│ └──────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

### 🧠 1. Out-of-Order RISC-V CPU Cores (4 Clusters)
* **Execution Paradigm:** Out-of-Order (OoO) execution utilizing Reorder Buffers (ROBs), Reservation Stations, and instruction dispatch queues.
* **Microarchitecture:** 4-wide superscalar dispatch pipeline (`ISSUE_WIDTH = 4`), up to 16 parallel ALU execution units, dynamic load-store units (LSUs), and branch prediction units.
* **Hierarchy:** 4 CPU clusters connected via a local quad-arbiter interface, feeding into the global NoC.

### 🎮 2. SIMT GPU Clusters (8 Clusters)
* **Execution Model:** Single Instruction, Multiple Threads (SIMT) running 4 warps × 32 threads per warp (128 concurrent threads per cluster, 1024 threads total).
* **Datapath:** Per-lane parallel execution lanes, scoreboard-based hazard detection/interlocking, and Local Data Share (LDS) scratchpad memory.
* **PIM Integration:** Native instruction-level support for delegating HBM Processing-In-Memory (PIM) operations directly from the GPU wavefront.

### 📐 3. Systolic-Array Tensor Clusters (4 Clusters)
* **Compute Engine:** Matrix-Multiplication acceleration driven by an $8 \times 8$ Systolic Array Processing Element (PE) matrix (8-bit weights/activations, 32-bit accumulation).
* **Memory Buffer:** On-chip weight buffers, activation buffers, and double-buffered result registers to hide DRAM read latency.

### 🌐 4. 4x4 Mesh Network-on-Chip (NoC)
* **Topology:** 2D grid structure connecting CPU, GPU, Tensor, DSP, and memory fabric.
* **Routing Scheme:** XY dimension-ordered routing with multi-virtual-channel (VC) buffers to guarantee deadlock-free packet traversal.
* **Transport:** Packetized flit-based transactions (Head, Body, Tail flits) supporting prioritized traffic classes.

### 💾 5. HBM & Directory-Based Coherent Memory
* **High-Bandwidth Memory:** 128-bit wide AXI4 HBM interface.
* **Coherence Protocol:** Directory-based MESI (Modified, Exclusive, Shared, Invalid) hardware cache coherence across CPU and GPU cache hierarchies.
* **PIM (Processing-in-Memory):** In-memory ALU/vector engines to execute bulk data arithmetic directly inside the HBM fabric, minimizing data movement.

---

## 📂 Directory Layout

```
├── rtl/
│   ├── core/           # RISC-V OoO CPU core, ALU, schedulers, and L1/L2 caches
│   ├── dma/            # System DMA engine
│   ├── dsp/            # High-performance DSP hardware multipliers
│   ├── gpu/            # SIMT wavefront controllers, registers, warp schedulers
│   ├── memory/         # Cache subsystems, directory coherence, and HBM/PIM controllers
│   ├── noc/            # Flit routers, Network Interfaces (NI), and routing logic
│   ├── system/         # Power controller and debug/JTAG subsystems
│   ├── tensor/         # Systolic Array matrix multiplication processors
│   ├── top/            # Top-level SoC wrappers (Full SoC and Lite configurations)
│   └── nexora_x3_pkg.sv # Main configurations, enums, structs, and parameters
│
├── verification/       # Self-checking SystemVerilog testbenches
│   ├── tb_soc_top.sv         # Comprehensive top-level SoC simulation
│   ├── tb_noc_routing.sv     # 2D Mesh NoC flit routing tests
│   ├── tb_gpu_wavefront.sv   # GPU SIMT execution and thread masking
│   ├── tb_tensor_matmul.sv   # Systolic Array matmul validation
│   ├── tb_hbm_transfers.sv   # HBM memory controller load testing
│   └── fibonacci.mem         # Sample firmware payload for CPU boot verification
│
├── run_lint.tcl        # Vivado RTL compilation check (Linting)
├── run_synth_full.tcl  # Full SoC Vivado synthesis wrapper
└── run_synth.tcl       # Lite-build Vivado synthesis script
```

---

## 🛠️ Compilation & RTL Linting

The Nexora X3 codebase is developed with standard SystemVerilog, ensuring compatibility with major ASIC synthesis tools (e.g., Synopsys Design Compiler, Cadence Genus) and FPGA compilers (Xilinx Vivado).

### 🔍 Running RTL Elaboration/Lint (Vivado)
To run a fast RTL elaboration to verify syntax correctness, interface mappings, and packaging:
```powershell
vivado -mode batch -nojournal -nolog -source run_lint.tcl
```
This loads `nexora_x3_pkg.sv` and compiles all sub-modules to perform RTL Elaboration on `nexora_x3_soc_top`.

### ⚡ Out-of-Context Synthesis
To run full out-of-context synthesis for timing and resource estimation:
```powershell
vivado -mode batch -nojournal -nolog -source run_synth_full.tcl
```

---

## 🧪 Simulation & Verification

The `verification/` folder contains a comprehensive suite of self-checking testbenches.

| Testbench | Focus Area | Command |
|---|---|---|
| `tb_soc_top.sv` | Full SoC validation: Boots CPU, loads `.mem` program, checks NoC mesh, GPU thread activity, and heartbeat signals. | Runs top-level checks |
| `tb_noc_routing.sv` | Validates flit routing across the 4x4 mesh and monitors VC utilization. | Verifies NoC grid |
| `tb_gpu_wavefront.sv` | Simulates warp scheduling, lane masking, and barrier sync cycles. | Verifies SIMT pipeline |
| `tb_tensor_matmul.sv` | Exercises the Systolic Array matrix processing pipeline. | Verifies Tensor Cores |
| `tb_hbm_transfers.sv` | Evaluates HBM controller read/write throughput and latency. | Verifies AXI4 Interface |

To run these testbenches in Vivado Simulator (xsim):
1. Open the Vivado GUI.
2. Add the target files under `rtl/` and `verification/`.
3. Set the chosen testbench as the simulation top-level and run simulation.

---

## ⚠️ Vivado Array Elaboration Limits Note (ASIC vs. Tooling)

> [!NOTE]  
> Because Nexora X3 is designed for **ASIC tape-out**, the default configurations use substantial cache footprints (e.g., 128KB L1 cache per core and 4MB shared L2 cache).
> 
> However, Vivado RTL Elaboration features an internal hard limit of **1 million elements** for single array variables. To allow this massive design to pass elaboration without syntax errors in Vivado, the cache sizes in this repository have been temporarily scaled down:
> * **L1 Cache:** Scaled down to 16KB (`l1_cache.sv` & `cpu_core.sv`)
> * **L2 Cache:** Scaled down to 64KB (`l2_cache_shared.sv`)
> 
> **For ASIC synthesis, tape-out, or advanced simulators (Synopsys VCS / Cadence Xcelium):** Restore cache parameters to their original design specifications as marked by comments in their respective files.

---

## 🤝 Contributing

Contributions are welcome! Please ensure any code changes:
1. Are fully compliant with standard SystemVerilog (avoid vendor-specific primitives).
2. Pass the standard linter check (`run_lint.tcl`).
3. Include an updated/new self-checking testbench if adding new hardware blocks.

---

## 📄 License
This project is licensed under the Apache License 2.0. See the `LICENSE` file for details.
