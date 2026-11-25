# FPGA timing exceptions and reset review

Scope: the explicit combined board source list, existing Arty A7 pins, 100 MHz input and MMCM-derived 50 MHz design clock. This is a structural RTL and constraints review. Final routed gate evidence must be attached separately. No clock, pin, exception or CDC architecture is changed by this review.

| Boundary | Observed implementation | Meaning and limit |
|---|---|---|
| Main clock | MMCME2_BASE with multiplication 10 and output division 20; BUFG feedback and output | One 20 ns functional clock; final gate checks the generated clock, master and part |
| Reset button | Two sampled stages `rst_sync`, followed by a reset hold counter | Human asynchronous input is sampled before normal reset release; MMCM lock loss separately asserts wrapper reset asynchronously |
| Reattest and revoke buttons | Two sampled stages `b1_s` and `b2_s`, then debounce and edge detection | Single-bit human controls; not a multi-bit CDC protocol |
| UART select switch | Two sampled stages `sw0_s`, then registered UART output selection | Change the switch between messages; switching during a byte may corrupt that byte and is not a lossless UART channel switch |
| CPU reset | Synchronous two-stage `rst_pipe_q` in each CPU tile | No independent CPU clock domain; reset begins on a design-clock edge and deasserts through its pipeline |
| Attestation subsystem reset | `rst_bridge` asynchronous assertion and two-clock synchronous deassertion | Crypto active-low resets are derived from this local reset; reset recovery needs live clock edges |
| External outputs | Registered LEDs and UART TX; no synchronous external capture clock | Human display and asynchronous USB-UART receiver assumptions; not an ASIC IO timing specification |

The XDC cuts paths from button/switch ports and to LED/UART ports. The input cuts are justified only by the observed single-bit synchronization/debounce structures; they do not justify bypassing a synchronizer or introducing a new bus crossing. Internal register-to-register paths remain timed. Zero input/output delays were added historically for complete `check_timing` bookkeeping while these board IO paths remain false; those values are not a measured board interface budget.

The synchronizer registers do not carry explicit ASYNC_REG attributes in the inspected wrapper/reset helpers. This review therefore does not claim recognized CDC-tool synchronizer coverage, metastability MTBF, analog reset sign-off, or a formal CDC/RDC proof. The approved scope retains the existing architecture. Final physical reports, generated-clock proof and active-transaction reset tests provide separate evidence within their stated limits.

ASIC handover must replace the FPGA MMCM/BUFG and initialization assumptions and establish real library/corner/IO constraints. Copying the human-IO exceptions or zero delays into ASIC sign-off would not be justified.

HARDWARE_VALIDATED=NO. FORMAL_PROOF=NO. ASIC_SIGNOFF=NO.
