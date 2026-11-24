# Free Pascal compiler runtime

Both kernels declare their FPC entry points in `src/arch/common/system.compilerprocs.inc`. The selected `system.pas` includes those declarations so the compiler can resolve calls that it generates implicitly. Shared implementations in `system.runtime.inc` cover heap allocation, overlapping memory moves, bounded short-string assignment, exception frame registration and runtime error dispatch.

| Operation | Native behavior |
| --- | --- |
| Typed `New` and `Dispose` | Delegate to the kernel heap with a native-width size. |
| 64-bit multiply, division and remainder | Use AMD64 integer operations. The division helper takes the divisor first. |
| `Trunc` and `Round` | Convert the Double in XMM0 to Int64. Trunc rounds toward zero and Round uses the current SSE rounding mode. |
| Setjmp and longjmp | Save and restore the AMD64 callee-saved integer registers, stack pointer and return address. Each scheduled process retains its own exception frame chain. |
| Compiler runtime errors | Record the FPC error code, report it over early serial and halt. Pascal raise and reraise use error 217. |

The stack-check and I/O-check hooks retain i386's empty implementations. Hardware stack guards protect the native bootstrap and emergency stacks. The regression profile exercises compiler-generated heap and short-string calls and tests jump restoration, arithmetic, rounding and overlapping moves. [Build and validation profiles](../../../planning/x86_64.md#production-and-regression-images)
