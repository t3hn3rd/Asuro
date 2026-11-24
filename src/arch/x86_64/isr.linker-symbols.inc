// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

    tssDescriptor: TTSSDescriptor; external name 'bootstrap_tss_descriptor';
    entryTable: array[0..255] of uint64; external name 'x64_isr_table';
    kernelStackTop: uint8; external name 'stack_top';
    overflowPush: uint8; external name 'x64_stack_overflow_push';
    kernelBottom: uint8; external name 'stack_bottom';
    nmiBottom: uint8; external name 'x64_nmi_stack_bottom';
    mcBottom: uint8; external name 'x64_mc_stack_bottom';
    dfBottom: uint8; external name 'x64_df_stack_bottom';
    dfTop: uint8; external name 'x64_df_stack_top';
    nmiTop: uint8; external name 'x64_nmi_stack_top';
    mcTop: uint8; external name 'x64_mc_stack_top';
    breakpointReturn: uint8; external name 'x64_test_breakpoint_return';
    expectedRSP: uint64; external name 'x64_test_expected_rsp';
    pageFaultInstruction: uint8; external name 'x64_test_page_fault_instruction';
    pageFaultReturn: uint8; external name 'x64_test_page_fault_return';
