/*
 * FreeRTOS Kernel V10.4.3
 * Copyright (C) 2020 Amazon.com, Inc. or its affiliates.  All Rights Reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * https://www.FreeRTOS.org
 * https://github.com/FreeRTOS
 *
 * 1 tab == 4 spaces!
 */

/*
 * The FreeRTOS kernel's RISC-V port is split between the the code that is
 * common across all currently supported RISC-V chips (implementations of the
 * RISC-V ISA), and code that tailors the port to a specific RISC-V chip:
 *
 * + FreeRTOS\Source\portable\GCC\RISC-V-RV32\portASM.S contains the code that
 *   is common to all currently supported RISC-V chips.  There is only one
 *   portASM.S file because the same file is built for all RISC-V target chips.
 *
 * + Header files called freertos_risc_v_chip_specific_extensions.h contain the
 *   code that tailors the FreeRTOS kernel's RISC-V port to a specific RISC-V
 *   chip.  There are multiple freertos_risc_v_chip_specific_extensions.h files
 *   as there are multiple RISC-V chip implementations.
 *
 * !!!NOTE!!!
 * TAKE CARE TO INCLUDE THE CORRECT freertos_risc_v_chip_specific_extensions.h
 * HEADER FILE FOR THE CHIP IN USE.  This is done using the assembler's (not the
 * compiler's!) include path.  For example, if the chip in use includes a core
 * local interrupter (CLINT) and does not include any chip specific register
 * extensions then add the path below to the assembler's include path:
 * FreeRTOS\Source\portable\GCC\RISC-V-RV32\chip_specific_extensions\RV32I_CLINT_no_extensions
 *
 */


#ifndef __FREERTOS_RISC_V_EXTENSIONS_H__
#define __FREERTOS_RISC_V_EXTENSIONS_H__

#define portasmHAS_SIFIVE_CLINT 1
#define portasmHAS_MTIME 1
#define portasmADDITIONAL_CONTEXT_SIZE 0 /* Must be even number on 32-bit cores. */

.macro portasmSAVE_ADDITIONAL_REGISTERS
	/* No additional registers to save, so this macro does nothing. */
	.endm

.macro portasmRESTORE_ADDITIONAL_REGISTERS
#if (configENABLE_MPU == 1 && configMPU_COMPARTMENTALIZATION == 0)
#if __riscv_xlen == 64
	#define portWORD_SIZE 8
	#define store_x sd
	#define load_x ld
#elif __riscv_xlen == 32
	#define store_x sw
	#define load_x lw
	#define portWORD_SIZE 4
#else
	#error Assembler did not define __riscv_xlen
#endif
    la      t1, pxCurrentTCB            /* Load pxCurrentTCB. */
    load_x  t1, 0(t1)
    addi    t0, t1, 3*portWORD_SIZE
#if __riscv_xlen == 32
    addi    t0, t0, portWORD_SIZE
#endif

    load_x  t2, 0*portWORD_SIZE( t0 )
    load_x  t3, 1*portWORD_SIZE( t0 )
    csrw    pmpaddr8, t2
    csrw    pmpaddr9, t3

    load_x  t2, 2*portWORD_SIZE( t0 )
    load_x  t3, 3*portWORD_SIZE( t0 )
    csrw    pmpaddr10, t2
    csrw    pmpaddr11, t3

    load_x  t2, 4*portWORD_SIZE( t0 )
    load_x  t3, 5*portWORD_SIZE( t0 )
    csrw    pmpaddr12, t2
    csrw    pmpaddr13, t3

    load_x  t2, 6*portWORD_SIZE( t0 )
    load_x  t3, 7*portWORD_SIZE( t0 )
    csrw    pmpaddr14, t2
    csrw    pmpaddr15, t3

    load_x  t2, 2*portWORD_SIZE( t1 )
    csrw    pmpcfg2, t2

#if __riscv_xlen == 32
    load_x  t2, 3*portWORD_SIZE( t1 )
    csrw    pmpcfg3, t2
#endif
#endif
	.endm

#endif /* __FREERTOS_RISC_V_EXTENSIONS_H__ */
