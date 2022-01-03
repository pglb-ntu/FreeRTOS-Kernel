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
 * RISC-V ISA), and code which tailors the port to a specific RISC-V chip:
 *
 * + The code that is common to all RISC-V chips is implemented in
 *   FreeRTOS\Source\portable\GCC\RISC-V-RV32\portASM.S.  There is only one
 *   portASM.S file because the same file is used no matter which RISC-V chip is
 *   in use.
 *
 * + The code that tailors the kernel's RISC-V port to a specific RISC-V
 *   chip is implemented in freertos_risc_v_chip_specific_extensions.h.  There
 *   is one freertos_risc_v_chip_specific_extensions.h that can be used with any
 *   RISC-V chip that both includes a standard CLINT and does not add to the
 *   base set of RISC-V registers.  There are additional
 *   freertos_risc_v_chip_specific_extensions.h files for RISC-V implementations
 *   that do not include a standard CLINT or do add to the base set of RISC-V
 *   registers.
 *
 * CARE MUST BE TAKEN TO INCLDUE THE CORRECT
 * freertos_risc_v_chip_specific_extensions.h HEADER FILE FOR THE CHIP
 * IN USE.  To include the correct freertos_risc_v_chip_specific_extensions.h
 * header file ensure the path to the correct header file is in the assembler's
 * include path.
 *
 * This freertos_risc_v_chip_specific_extensions.h is for use on RISC-V chips
 * that include a standard CLINT and do not add to the base set of RISC-V
 * registers.
 *
 */
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

#if __waf__
#include <waf_config.h>
#endif /* __waf__ */

#include "freertos_risc_v_chip_specific_extensions.h"

/* Check the freertos_risc_v_chip_specific_extensions.h and/or command line
definitions. */
#if defined( portasmHAS_CLINT ) && defined( portasmHAS_MTIME )
	#error The portasmHAS_CLINT constant has been deprecated.  Please replace it with portasmHAS_MTIME.  portasmHAS_CLINT and portasmHAS_MTIME cannot both be defined at once.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-RISC-V.html
#endif

#ifdef portasmHAS_CLINT
	#warning The portasmHAS_CLINT constant has been deprecated.  Please replace it with portasmHAS_MTIME and portasmHAS_SIFIVE_CLINT.  For now portasmHAS_MTIME and portasmHAS_SIFIVE_CLINT are derived from portasmHAS_CLINT.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-RISC-V.html
	#define portasmHAS_MTIME portasmHAS_CLINT
	#define portasmHAS_SIFIVE_CLINT portasmHAS_CLINT
#endif

#ifndef portasmHAS_MTIME
	#error freertos_risc_v_chip_specific_extensions.h must define portasmHAS_MTIME to either 1 (MTIME clock present) or 0 (MTIME clock not present).  See https://www.FreeRTOS.org/Using-FreeRTOS-on-RISC-V.html
#endif

#ifndef portasmHANDLE_INTERRUPT
	#error portasmHANDLE_INTERRUPT must be defined to the function to be called to handle external/peripheral interrupts.  portasmHANDLE_INTERRUPT can be defined on the assembler command line or in the appropriate freertos_risc_v_chip_specific_extensions.h header file.  https://www.FreeRTOS.org/Using-FreeRTOS-on-RISC-V.html
#endif

#ifndef portasmHAS_SIFIVE_CLINT
	#define portasmHAS_SIFIVE_CLINT 0
#endif

/* Only the standard core registers are stored by default.  Any additional
registers must be saved by the portasmSAVE_ADDITIONAL_REGISTERS and
portasmRESTORE_ADDITIONAL_REGISTERS macros - which can be defined in a chip
specific version of freertos_risc_v_chip_specific_extensions.h.  See the notes
at the top of this file. */
#define portCONTEXT_SIZE ( 30 * portWORD_SIZE )
#ifdef configMPU_COMPARTMENTALIZATION
#define portCOMPARTMENT_CONTEXT_SIZE (18 * portWORD_SIZE)
#endif

.global xPortStartFirstTask
.global freertos_risc_v_trap_handler
.global pxPortInitialiseStack
.extern pxCurrentTCB
.extern ulPortTrapHandler
.extern vTaskSwitchContext
.extern xTaskIncrementTick
.extern Timer_IRQHandler
.extern pullMachineTimerCompareRegister
.extern pullNextTime
.extern uxTimerIncrementsForOneTick /* size_t type so 32-bit on 32-bit core and 64-bits on 64-bit core. */
.extern xISRStackTop
.extern portasmHANDLE_INTERRUPT

#ifdef configTASK_RETURN_ADDRESS
	.extern configTASK_RETURN_ADDRESS
#endif /* configTASK_RETURN_ADDRESS */

#if configPORT_ALLOW_APP_EXCEPTION_HANDLERS
	.extern vPortExceptionHandler
#endif

#if (configENABLE_MPU == 1)
.global xIsPrivileged
.global vRaisePrivilege
.global vResetPrivilege
/*-----------------------------------------------------------*/

#if (configMPU_COMPARTMENTALIZATION == 1)
.global xPortGetCurrentCompartmentID
.global xPortGetCurrentCompartmentStack
.global xPortGetCurrentCompartmentReturn
.global xPortCompartmentTrampSetup
.global xPortCompartmentEnterTrampoline
.global xPortCompartmentEnterTrampolineEnd
.global vSetupMPUPerComp

.macro getCurrentPerTCBCompartmentRegions reg_return
	csrr              \reg_return, mscratch
	load_x            \reg_return, 1 * portWORD_SIZE(\reg_return)
	load_x            \reg_return, 3 * portWORD_SIZE(\reg_return) # Read xCompRegions from xCOMPARTMENT_CONTEXT.
.endm
/*-----------------------------------------------------------*/

.macro getCurrentPerTCBCompartment reg_return
	csrr              \reg_return, mscratch
	load_x            \reg_return, 1 * portWORD_SIZE(\reg_return)
	load_x            \reg_return, 2 * portWORD_SIZE(\reg_return) # Read xCompID from xCOMPARTMENT_CONTEXT.
.endm
/*-----------------------------------------------------------*/

.macro getCurrentPerTCBCompartmentStack reg_return
	csrr              \reg_return, mscratch
	load_x            \reg_return, 1 * portWORD_SIZE(\reg_return)
	load_x            \reg_return, 1 * portWORD_SIZE(\reg_return) # Read return stack from second xCOMPARTMENT_CONTEXT.
.endm
/*-----------------------------------------------------------*/

.macro getCurrentPerTCBCompartmentReturn reg_return
	csrr              \reg_return, mscratch
	load_x            \reg_return, 1 * portWORD_SIZE(\reg_return)
	load_x            \reg_return, 0 * portWORD_SIZE(\reg_return) # Read return cap from xCOMPARTMENT_CONTEXT.
.endm
/*-----------------------------------------------------------*/

#endif
#endif
/*-----------------------------------------------------------*/

.section privileged_functions, "wax", @progbits
.align 8
freertos_risc_v_trap_handler:
	addi sp, sp, -portCONTEXT_SIZE - (portasmADDITIONAL_CONTEXT_SIZE * portWORD_SIZE)
	store_x x1, 1 * portWORD_SIZE( sp )
	store_x x5, 2 * portWORD_SIZE( sp )
	store_x x6, 3 * portWORD_SIZE( sp )
	store_x x7, 4 * portWORD_SIZE( sp )
	store_x x8, 5 * portWORD_SIZE( sp )
	store_x x9, 6 * portWORD_SIZE( sp )
	store_x x10, 7 * portWORD_SIZE( sp )
	store_x x11, 8 * portWORD_SIZE( sp )
	store_x x12, 9 * portWORD_SIZE( sp )
	store_x x13, 10 * portWORD_SIZE( sp )
	store_x x14, 11 * portWORD_SIZE( sp )
	store_x x15, 12 * portWORD_SIZE( sp )
	store_x x16, 13 * portWORD_SIZE( sp )
	store_x x17, 14 * portWORD_SIZE( sp )
	store_x x18, 15 * portWORD_SIZE( sp )
	store_x x19, 16 * portWORD_SIZE( sp )
	store_x x20, 17 * portWORD_SIZE( sp )
	store_x x21, 18 * portWORD_SIZE( sp )
	store_x x22, 19 * portWORD_SIZE( sp )
	store_x x23, 20 * portWORD_SIZE( sp )
	store_x x24, 21 * portWORD_SIZE( sp )
	store_x x25, 22 * portWORD_SIZE( sp )
	store_x x26, 23 * portWORD_SIZE( sp )
	store_x x27, 24 * portWORD_SIZE( sp )
	store_x x28, 25 * portWORD_SIZE( sp )
	store_x x29, 26 * portWORD_SIZE( sp )
	store_x x30, 27 * portWORD_SIZE( sp )
	store_x x31, 28 * portWORD_SIZE( sp )

	csrr t0, mstatus					/* Required for MPIE bit. */
	store_x t0, 29 * portWORD_SIZE( sp )

	portasmSAVE_ADDITIONAL_REGISTERS	/* Defined in freertos_risc_v_chip_specific_extensions.h to save any registers unique to the RISC-V implementation. */

	la       t0, pxCurrentTCB			/* Load pxCurrentTCB. */
	load_x   t0, 0(t0)
	store_x  sp, 0( t0 )				/* Write sp to first TCB member. */

	csrr a0, mcause
	csrr a1, mepc

test_if_asynchronous:
	srli a2, a0, __riscv_xlen - 1		/* MSB of mcause is 1 if handing an asynchronous interrupt - shift to LSB to clear other bits. */
	beq a2, x0, handle_synchronous		/* Branch past interrupt handing if not asynchronous. */
	store_x a1, 0( sp )					/* Asynch so save unmodified exception return address. */

handle_asynchronous:

#if( portasmHAS_MTIME != 0 )

	test_if_mtimer:						/* If there is a CLINT then the mtimer is used to generate the tick interrupt. */

		addi t0, x0, 1

		slli t0, t0, __riscv_xlen - 1   /* LSB is already set, shift into MSB.  Shift 31 on 32-bit or 63 on 64-bit cores. */
		addi t1, t0, 7					/* 0x8000[]0007 == machine timer interrupt. */
		bne a0, t1, test_if_external_interrupt

		load_x t0, pullMachineTimerCompareRegister  /* Load address of compare register into t0. */
		load_x t1, pullNextTime  		/* Load the address of ullNextTime into t1. */

		#if( __riscv_xlen == 32 )

			/* Update the 64-bit mtimer compare match value in two 32-bit writes. */
			li t4, -1
			lw t2, 0(t1)				/* Load the low word of ullNextTime into t2. */
			lw t3, 4(t1)				/* Load the high word of ullNextTime into t3. */
			sw t4, 0(t0)				/* Low word no smaller than old value to start with - will be overwritten below. */
			sw t3, 4(t0)				/* Store high word of ullNextTime into compare register.  No smaller than new value. */
			sw t2, 0(t0)				/* Store low word of ullNextTime into compare register. */
			lw t0, uxTimerIncrementsForOneTick	/* Load the value of ullTimerIncrementForOneTick into t0 (could this be optimized by storing in an array next to pullNextTime?). */
			add t4, t0, t2				/* Add the low word of ullNextTime to the timer increments for one tick (assumes timer increment for one tick fits in 32-bits). */
			sltu t5, t4, t2				/* See if the sum of low words overflowed (what about the zero case?). */
			add t6, t3, t5				/* Add overflow to high word of ullNextTime. */
			sw t4, 0(t1)				/* Store new low word of ullNextTime. */
			sw t6, 4(t1)				/* Store new high word of ullNextTime. */

		#endif /* __riscv_xlen == 32 */

		#if( __riscv_xlen == 64 )

			/* Update the 64-bit mtimer compare match value. */
			ld t2, 0(t1)			 	/* Load ullNextTime into t2. */
			sd t2, 0(t0)				/* Store ullNextTime into compare register. */
			ld t0, uxTimerIncrementsForOneTick  /* Load the value of ullTimerIncrementForOneTick into t0 (could this be optimized by storing in an array next to pullNextTime?). */
			add t4, t0, t2				/* Add ullNextTime to the timer increments for one tick. */
			sd t4, 0(t1)				/* Store ullNextTime. */

		#endif /* __riscv_xlen == 64 */

		load_x sp, xISRStackTop			/* Switch to ISR stack before function call. */
		la t0, xTaskIncrementTick
		jalr t0
		beqz a0, processed_source		/* Don't switch context if incrementing tick didn't unblock a task. */
		la t0, vTaskSwitchContext
		jalr t0
		j processed_source

	test_if_external_interrupt:			/* If there is a CLINT and the mtimer interrupt is not pending then check to see if an external interrupt is pending. */
		addi t1, t1, 4					/* 0x80000007 + 4 = 0x8000000b == Machine external interrupt. */
		bne a0, t1, as_yet_unhandled	/* Something as yet unhandled. */

#endif /* portasmHAS_MTIME */

	load_x sp, xISRStackTop				/* Switch to ISR stack before function call. */
	la t0, portasmHANDLE_INTERRUPT
	jalr t0						/* Jump to the interrupt handler if there is no CLINT or if there is a CLINT and it has been determined that an external interrupt is pending. */
	j processed_source

handle_synchronous:
	addi a1, a1, 4						/* Synchronous so updated exception return address to the instruction after the instruction that generated the exeption. */
	store_x a1, 0( sp )					/* Save updated exception return address. */

test_if_environment_call:
#if (configENABLE_MPU == 1)
	li   t0, 8                          /* 8 == user environment call. */
	bne  a0, t0, mmode                  /* Not an M environment call, so some other exception. */
	li   t1, 1                          /* yield syscall number */
	beq  a7, t1, yield
	li   t1, 3                          /* raise priv syscall number */
	bne  a7, t1, is_exception

	load_x  t0, 29 * portWORD_SIZE( sp )
	li   t1, 0x1800
	or   t0, t0, t1
	store_x  t0, 29 * portWORD_SIZE( sp )
	j processed_source
#endif
mmode:
	li t0, 11 							/* 11 == environment call. */
	bne a0, t0, is_exception			/* Not an M environment call, so some other exception. */
#if (configENABLE_MPU == 1)
	li   t1, 1                          /* yield syscall number */
	beq  a7, t1, yield
	li   t1, 4                          /* comp MPU reconfig */
	beq  a7, t1, 1f
	li   t1, 3                          /* raise priv syscall number */
	bne  a7, t1, is_exception
1:
	j processed_source
#endif
yield:
	load_x sp, xISRStackTop				/* Switch to ISR stack before function call. */
	la t0, vTaskSwitchContext
	jalr t0
	j processed_source

is_exception:
	#csrr t0, mcause						/* For viewing in the debugger only. */
	#csrr t1, mepc						/* For viewing in the debugger only */
	#csrr t2, mstatus
	#j is_exception						/* No other exceptions handled yet. */

#if configPORT_ALLOW_APP_EXCEPTION_HANDLERS
    /* a0 and a1 should already have mcause and mepcc,
     * put exception frame in a2 as a third argument to vPortExceptionHandler. */
	mv                a2, sp
	la                t0, vPortExceptionHandler
	jalr              ra, t0
#if configMPU_COMPARTMENTALIZATION
	beqz              a0, .Ltest_if_in_compartment /* Don't switch context if fault handler didn't block/unblock a task. */
#else
	beqz              a0, .Lbreak_on_exception /* Don't switch context if fault handler didn't block/unblock a task. */
#endif
	la                t0, vTaskSwitchContext
	jalr              ra, t0
	beq               zero, zero, processed_source
#endif /* configPORT_ALLOW_APP_EXCEPTION_HANDLERS */

#if configMPU_COMPARTMENTALIZATION
.Ltest_if_in_compartment:
	getCurrentPerTCBCompartment t0
	li                t1, configCOMPARTMENTS_NUM - 1
	bne               t0, t1, return_compartment
#endif

.Lbreak_on_exception:
	csrr              t0, mcause /* For viewing in the debugger only. */
	csrr              t1, mepc /* For viewing in the debugger only */
	csrr              t2, mstatus
	ebreak
	j                 .Lbreak_on_exception

as_yet_unhandled:
	csrr t0, mcause						/* For viewing in the debugger only. */
	j as_yet_unhandled

processed_source:
	la      t1, pxCurrentTCB			/* Load pxCurrentTCB. */
	load_x  t1, 0(t1)

#if (configMPU_COMPARTMENTALIZATION == 1)
	csrw    mscratch, t1

	# Test if it's already an ecall to reconfigure the MPU
	li      t0, 4
	beq     a7, t0, 1f

	getCurrentPerTCBCompartment t0
	li                t2, configCOMPARTMENTS_NUM - 1
	beq               t0, t2, 1f

	getCurrentPerTCBCompartmentRegions x4

	load_x            t2, 1 * portWORD_SIZE(t1)
	load_x            t2, 4 * portWORD_SIZE(t2)
2:
	li t4, 1
	la t3, vSetupMPUPerComp
	jalr t3
	csrr   t1, mscratch
1:
#endif

	load_x  sp, 0( t1 )				 	/* Read sp from first TCB member. */

	/* Load mret with the address of the next instruction in the task to run next. */
	load_x t0, 0( sp )
	csrw mepc, t0

	portasmRESTORE_ADDITIONAL_REGISTERS	/* Defined in freertos_risc_v_chip_specific_extensions.h to restore any registers unique to the RISC-V implementation. */

	/* Load mstatus with the interrupt enable bits used by the task. */
	load_x  t0, 29 * portWORD_SIZE( sp )
	csrw mstatus, t0						/* Required for MPIE bit. */

	load_x  x1, 1 * portWORD_SIZE( sp )
	load_x  x5, 2 * portWORD_SIZE( sp )		/* t0 */
	load_x  x6, 3 * portWORD_SIZE( sp )		/* t1 */
	load_x  x7, 4 * portWORD_SIZE( sp )		/* t2 */
	load_x  x8, 5 * portWORD_SIZE( sp )		/* s0/fp */
	load_x  x9, 6 * portWORD_SIZE( sp )		/* s1 */
	load_x  x10, 7 * portWORD_SIZE( sp )	/* a0 */
	load_x  x11, 8 * portWORD_SIZE( sp )	/* a1 */
	load_x  x12, 9 * portWORD_SIZE( sp )	/* a2 */
	load_x  x13, 10 * portWORD_SIZE( sp )	/* a3 */
	load_x  x14, 11 * portWORD_SIZE( sp )	/* a4 */
	load_x  x15, 12 * portWORD_SIZE( sp )	/* a5 */
	load_x  x16, 13 * portWORD_SIZE( sp )	/* a6 */
	load_x  x17, 14 * portWORD_SIZE( sp )	/* a7 */
	load_x  x18, 15 * portWORD_SIZE( sp )	/* s2 */
	load_x  x19, 16 * portWORD_SIZE( sp )	/* s3 */
	load_x  x20, 17 * portWORD_SIZE( sp )	/* s4 */
	load_x  x21, 18 * portWORD_SIZE( sp )	/* s5 */
	load_x  x22, 19 * portWORD_SIZE( sp )	/* s6 */
	load_x  x23, 20 * portWORD_SIZE( sp )	/* s7 */
	load_x  x24, 21 * portWORD_SIZE( sp )	/* s8 */
	load_x  x25, 22 * portWORD_SIZE( sp )	/* s9 */
	load_x  x26, 23 * portWORD_SIZE( sp )	/* s10 */
	load_x  x27, 24 * portWORD_SIZE( sp )	/* s11 */
	load_x  x28, 25 * portWORD_SIZE( sp )	/* t3 */
	load_x  x29, 26 * portWORD_SIZE( sp )	/* t4 */
	load_x  x30, 27 * portWORD_SIZE( sp )	/* t5 */
	load_x  x31, 28 * portWORD_SIZE( sp )	/* t6 */
	addi sp, sp, portCONTEXT_SIZE + (portasmADDITIONAL_CONTEXT_SIZE * portWORD_SIZE)

	mret

#if (configMPU_COMPARTMENTALIZATION == 1)
return_compartment:
	la                t0, pxCurrentTCB # Load cap to pxCurrentTCB.
	load_x            t0, 0(t0) # Load pxCurrentTCB.
	csrw              mscratch, t0

	load_x  sp, 0( t0 )				 	/* Read sp from first TCB member. */

	portasmRESTORE_ADDITIONAL_REGISTERS	/* Defined in freertos_risc_v_chip_specific_extensions.h to restore any registers unique to the RISC-V implementation. */

	load_x            t0, 0 * portWORD_SIZE(sp)
	csrw              mepc, t0 # Write mepc.

	/* Load mstatus with the interrupt enable bits used by the task. */
	load_x  t0, 29 * portWORD_SIZE( sp )
	csrw mstatus, t0						/* Required for MPIE bit. */

	load_x  x1, 1 * portWORD_SIZE( sp )
	load_x  x5, 2 * portWORD_SIZE( sp )		/* t0 */
	load_x  x6, 3 * portWORD_SIZE( sp )		/* t1 */
	load_x  x7, 4 * portWORD_SIZE( sp )		/* t2 */
	load_x  x8, 5 * portWORD_SIZE( sp )		/* s0/fp */
	load_x  x9, 6 * portWORD_SIZE( sp )		/* s1 */
	load_x  x10, 7 * portWORD_SIZE( sp )	/* a0 */
	load_x  x11, 8 * portWORD_SIZE( sp )	/* a1 */
	load_x  x12, 9 * portWORD_SIZE( sp )	/* a2 */
	load_x  x13, 10 * portWORD_SIZE( sp )	/* a3 */
	load_x  x14, 11 * portWORD_SIZE( sp )	/* a4 */
	load_x  x15, 12 * portWORD_SIZE( sp )	/* a5 */
	load_x  x16, 13 * portWORD_SIZE( sp )	/* a6 */
	load_x  x17, 14 * portWORD_SIZE( sp )	/* a7 */
	load_x  x18, 15 * portWORD_SIZE( sp )	/* s2 */
	load_x  x19, 16 * portWORD_SIZE( sp )	/* s3 */
	load_x  x20, 17 * portWORD_SIZE( sp )	/* s4 */
	load_x  x21, 18 * portWORD_SIZE( sp )	/* s5 */
	load_x  x22, 19 * portWORD_SIZE( sp )	/* s6 */
	load_x  x23, 20 * portWORD_SIZE( sp )	/* s7 */
	load_x  x24, 21 * portWORD_SIZE( sp )	/* s8 */
	load_x  x25, 22 * portWORD_SIZE( sp )	/* s9 */
	load_x  x26, 23 * portWORD_SIZE( sp )	/* s10 */
	load_x  x27, 24 * portWORD_SIZE( sp )	/* s11 */
	load_x  x28, 25 * portWORD_SIZE( sp )	/* t3 */
	load_x  x29, 26 * portWORD_SIZE( sp )	/* t4 */
	load_x  x30, 27 * portWORD_SIZE( sp )	/* t5 */
	load_x  x31, 28 * portWORD_SIZE( sp )	/* t6 */
	addi sp, sp, portCONTEXT_SIZE + (portasmADDITIONAL_CONTEXT_SIZE * portWORD_SIZE)

	getCurrentPerTCBCompartmentStack sp

	mret
#endif
/*-----------------------------------------------------------*/

.align 8
xPortStartFirstTask:

#if( portasmHAS_SIFIVE_CLINT != 0 )
	/* If there is a clint then interrupts can branch directly to the FreeRTOS
	trap handler.  Otherwise the interrupt controller will need to be configured
	outside of this file. */
	la t0, freertos_risc_v_trap_handler
	csrw mtvec, t0
#endif /* portasmHAS_CLILNT */

	la      t0, pxCurrentTCB			/* Load pxCurrentTCB. */
	load_x  t0, 0( t0 )

#if (configMPU_COMPARTMENTALIZATION == 1)
	csrw    mscratch, t0
#endif

	load_x  sp, 0( t0 )				 	/* Read sp from first TCB member. */

	load_x  x1, 0( sp ) /* Note for starting the scheduler the exception return address is used as the function return address. */

	portasmRESTORE_ADDITIONAL_REGISTERS	/* Defined in freertos_risc_v_chip_specific_extensions.h to restore any registers unique to the RISC-V implementation. */

	load_x  x6, 3 * portWORD_SIZE( sp )		/* t1 */
	load_x  x7, 4 * portWORD_SIZE( sp )		/* t2 */
	load_x  x8, 5 * portWORD_SIZE( sp )		/* s0/fp */
	load_x  x9, 6 * portWORD_SIZE( sp )		/* s1 */
	load_x  x10, 7 * portWORD_SIZE( sp )	/* a0 */
	load_x  x11, 8 * portWORD_SIZE( sp )	/* a1 */
	load_x  x12, 9 * portWORD_SIZE( sp )	/* a2 */
	load_x  x13, 10 * portWORD_SIZE( sp )	/* a3 */
	load_x  x14, 11 * portWORD_SIZE( sp )	/* a4 */
	load_x  x15, 12 * portWORD_SIZE( sp )	/* a5 */
	load_x  x16, 13 * portWORD_SIZE( sp )	/* a6 */
	load_x  x17, 14 * portWORD_SIZE( sp )	/* a7 */
	load_x  x18, 15 * portWORD_SIZE( sp )	/* s2 */
	load_x  x19, 16 * portWORD_SIZE( sp )	/* s3 */
	load_x  x20, 17 * portWORD_SIZE( sp )	/* s4 */
	load_x  x21, 18 * portWORD_SIZE( sp )	/* s5 */
	load_x  x22, 19 * portWORD_SIZE( sp )	/* s6 */
	load_x  x23, 20 * portWORD_SIZE( sp )	/* s7 */
	load_x  x24, 21 * portWORD_SIZE( sp )	/* s8 */
	load_x  x25, 22 * portWORD_SIZE( sp )	/* s9 */
	load_x  x26, 23 * portWORD_SIZE( sp )	/* s10 */
	load_x  x27, 24 * portWORD_SIZE( sp )	/* s11 */
	load_x  x28, 25 * portWORD_SIZE( sp )	/* t3 */
	load_x  x29, 26 * portWORD_SIZE( sp )	/* t4 */
	load_x  x30, 27 * portWORD_SIZE( sp )	/* t5 */
	load_x  x31, 28 * portWORD_SIZE( sp )	/* t6 */

	load_x  x5, 29 * portWORD_SIZE( sp )	/* Initial mstatus into x5 (t0) */
#if (configENABLE_MPU == 1)
	addi x5, x5, 0x80						/* Set MPIE bit so the task starts with interrupts enabled */
#else
	addi x5, x5, 0x08						/* Set MIE bit so the first task starts with interrupts enabled - required as returns with ret not eret. */
#endif
	csrrw x0, mstatus, x5					/* Interrupts enabled from here! */
	load_x x5, 2 * portWORD_SIZE( sp )		/* Initial x5 (t0) value. */

	addi	sp, sp, portCONTEXT_SIZE + (portasmADDITIONAL_CONTEXT_SIZE * portWORD_SIZE)
#if (configENABLE_MPU == 1)
	csrw mepc, x1
	mret
#else
	ret
#endif
/*-----------------------------------------------------------*/

/*
 * Unlike other ports pxPortInitialiseStack() is written in assembly code as it
 * needs access to the portasmADDITIONAL_CONTEXT_SIZE constant.  The prototype
 * for the function is as per the other ports:
 * StackType_t *pxPortInitialiseStack( StackType_t *pxTopOfStack, TaskFunction_t pxCode, void *pvParameters );
 *
 * As per the standard RISC-V ABI pxTopcOfStack is passed in in a0, pxCode in
 * a1, and pvParameters in a2.  The new top of stack is passed out in a0.
 *
 * RISC-V maps registers to ABI names as follows (X1 to X31 integer registers
 * for the 'I' profile, X1 to X15 for the 'E' profile, currently I assumed).
 *
 * Register		ABI Name	Description						Saver
 * x0			zero		Hard-wired zero					-
 * x1			ra			Return address					Caller
 * x2			sp			Stack pointer					Callee
 * x3			gp			Global pointer					-
 * x4			tp			Thread pointer					-
 * x5-7			t0-2		Temporaries						Caller
 * x8			s0/fp		Saved register/Frame pointer	Callee
 * x9			s1			Saved register					Callee
 * x10-11		a0-1		Function Arguments/return values Caller
 * x12-17		a2-7		Function arguments				Caller
 * x18-27		s2-11		Saved registers					Callee
 * x28-31		t3-6		Temporaries						Caller
 *
 * The RISC-V context is saved t FreeRTOS tasks in the following stack frame,
 * where the global and thread pointers are currently assumed to be constant so
 * are not saved:
 *
 * [chip specific registers go here]
 * mstatus
 * x31
 * x30
 * x29
 * x28
 * x27
 * x26
 * x25
 * x24
 * x23
 * x22
 * x21
 * x20
 * x19
 * x18
 * x17
 * x16
 * x15
 * x14
 * x13
 * x12
 * x11
 * pvParameters
 * x9
 * x8
 * x7
 * x6
 * x5
 * portTASK_RETURN_ADDRESS
 * pxCode
 */
.align 8
pxPortInitialiseStack:
	addi t0, x0, portasmADDITIONAL_CONTEXT_SIZE /* The number of chip specific additional registers. */
chip_specific_stack_frame:				/* First add any chip specific registers to the stack frame being created. */
	beq t0, x0, 1f						/* No more chip specific registers to save. */
	addi a0, a0, -portWORD_SIZE			/* Make space for chip specific register. */
	store_x x0, 0(a0)					/* Give the chip specific register an initial value of zero. */
	addi t0, t0, -1						/* Decrement the count of chip specific registers remaining. */
	j chip_specific_stack_frame			/* Until no more chip specific registers. */
1:
	csrr t0, mstatus					/* Obtain current mstatus value. */
	andi t0, t0, ~0x8					/* Ensure interrupts are disabled when the stack is restored within an ISR.  Required when a task is created after the schedulre has been started, otherwise interrupts would be disabled anyway. */
	addi t1, x0, 0x188					/* Generate the value 0x1880, which are the MPIE and MPP bits to set in mstatus. */
	slli t1, t1, 4

#if (configENABLE_MPU == 1)
#if (configMPU_COMPARTMENTALIZATION == 0)
	bnez a3, 2f
	li   t2, ~0x1800
	and  t1, t1, t2
#endif
#endif
2:
	or   t0, t0, t1						/* Set MPIE and MPP bits in mstatus value. */

	addi a0, a0, -portWORD_SIZE
	store_x t0, 0(a0)					/* mstatus onto the stack. */
	addi a0, a0, -(22 * portWORD_SIZE)	/* Space for registers x11-x31. */
	store_x a2, 0(a0)					/* Task parameters (pvParameters parameter) goes into register X10/a0 on the stack. */
	addi a0, a0, -(6 * portWORD_SIZE)	/* Space for registers x5-x9. */
	#ifdef configTASK_RETURN_ADDRESS
		la     t0, configTASK_RETURN_ADDRESS /* Return address onto the stack */
		store_x t0, 0(a0)
	#else
		store_x x0, 0(a0)				/* 0 Return address onto the stack (will fault if a task returns) */
	#endif /* configTASK_RETURN_ADDRESS */
	addi a0, a0, -portWORD_SIZE
	store_x a1, 0(a0)					/* mret value (pxCode parameter) onto the stack. */
	ret
/*-----------------------------------------------------------*/

#if (configENABLE_MPU == 1)
.section .text.unpriv, "wax", @progbits
.align 8
.type xIsPrivileged, @function
xIsPrivileged:
	la      t1, pxCurrentTCB			/* Load pxCurrentTCB. */
	load_x  t1, 0(t1)
	beqz    t1, 1f
#if (configMPU_COMPARTMENTALIZATION == 0)
	load_x  a0, 1*portWORD_SIZE( t1 ) 	/* Read xMPUSettings->xIsPrivileged from second TCB member. */
#else
	mv      a0, x0
#endif
1:
	ret
/*-----------------------------------------------------------*/

.align 8
.type vRaisePrivilege, @function
vRaisePrivilege:
	li a7, 3
	ecall
	ret
/*-----------------------------------------------------------*/

.align 8
.type vResetPrivilege, @function
vResetPrivilege:
#if (configMPU_COMPARTMENTALIZATION == 0)
	la      t1, pxCurrentTCB			/* Load pxCurrentTCB. */
	load_x  t1, 0(t1)
	load_x  a0, 1*portWORD_SIZE( t1 ) 	/* Read xMPUSettings->xIsPrivileged from second TCB member. */
	beqz   a0, reset
#endif
	ret
reset:
	# Set MPIE according to current MIE bit
	csrr t1, mstatus
	andi t0, t1, 0x1
	slli t0, t0, 0x7

	# Set MPP to usermode and disable interrupts
	li   t2, ~0x1888
	and  t1, t1, t2

	# Write mstatus with MPIE, disable MIE, and MPP = usermode
	or   t0, t1, t0
	csrw mstatus, t0
	csrw mepc, ra
	mret

#if (configMPU_COMPARTMENTALIZATION == 1)
.section privileged_functions, "wax", @progbits

.macro saveCurrentPerTCBCompartmentContext reg_temp, reg_temp2, compid, ret_cap
	# Increase compartment stack level and store it to point to the current compartment context
	csrr              \reg_temp2, mscratch
	load_x            \reg_temp, 1 * portWORD_SIZE(\reg_temp2)
	addi              \reg_temp, \reg_temp, (portCOMPARTMENT_CONTEXT_SIZE)
	store_x           \reg_temp, 1 * portWORD_SIZE(\reg_temp2)

	# Save return compartment address (to use upon a per-compartment fault)
	store_x           \ret_cap, 0 * portWORD_SIZE(\reg_temp)
	# Save the caller's stack
	store_x           sp, 1 * portWORD_SIZE(\reg_temp)

	# Save new/current compid
	store_x               \compid, 2 * portWORD_SIZE(\reg_temp) # Store xCompID to xCOMPARTMENT_CONTEXT.

	# Save new/current xCompRegions
	store_x               x4, 3 * portWORD_SIZE(\reg_temp) # Store xCompID to xCOMPARTMENT_CONTEXT.

	/* Save cgp into the caller's context */
	store_x gp, 4 * portWORD_SIZE(\reg_temp)

	/* Save cra into the caller's context */
	store_x ra, 5 * portWORD_SIZE(\reg_temp)

	/* Save callee-saved context */
	store_x s0, 6 * portWORD_SIZE(\reg_temp)
	store_x s1, 7 * portWORD_SIZE(\reg_temp)
	store_x s2, 8 * portWORD_SIZE(\reg_temp)
	store_x s3, 9 * portWORD_SIZE(\reg_temp)
	store_x s4, 10 * portWORD_SIZE(\reg_temp)
	store_x s5, 11 * portWORD_SIZE(\reg_temp)
	store_x s6, 12 * portWORD_SIZE(\reg_temp)
	store_x s7, 13 * portWORD_SIZE(\reg_temp)
	store_x s8, 14 * portWORD_SIZE(\reg_temp)
	store_x s9, 15 * portWORD_SIZE(\reg_temp)
	store_x s10, 16 * portWORD_SIZE(\reg_temp)
	store_x s11, 17 * portWORD_SIZE(\reg_temp)
.endm
/*-----------------------------------------------------------*/

.macro restorePerTCBCompartmentContext reg_temp, reg_temp2
	csrr              \reg_temp2, mscratch
	load_x            \reg_temp, 1 * portWORD_SIZE(\reg_temp2)

	load_x gp, 4 * portWORD_SIZE(\reg_temp)

	load_x x4, 3 * portWORD_SIZE(\reg_temp)

	/* Setup the new compartment's MPU regions */
	mv t2, gp
	la t4, vSetupMPUPerComp
	jalr t4

	load_x ra, 5 * portWORD_SIZE(\reg_temp)

	/* Restore callee-saved context */
	load_x s0, 6 * portWORD_SIZE(\reg_temp)
	load_x s1, 7 * portWORD_SIZE(\reg_temp)
	load_x s2, 8 * portWORD_SIZE(\reg_temp)
	load_x s3, 9 * portWORD_SIZE(\reg_temp)
	load_x s4, 10 * portWORD_SIZE(\reg_temp)
	load_x s5, 11 * portWORD_SIZE(\reg_temp)
	load_x s6, 12 * portWORD_SIZE(\reg_temp)
	load_x s7, 13 * portWORD_SIZE(\reg_temp)
	load_x s8, 14 * portWORD_SIZE(\reg_temp)
	load_x s9, 15 * portWORD_SIZE(\reg_temp)
	load_x s10, 16 * portWORD_SIZE(\reg_temp)
	load_x s11, 17 * portWORD_SIZE(\reg_temp)

	# Decrease compartment stack level and store it to point to the caller's compartment context
	addi              \reg_temp, \reg_temp, -(portCOMPARTMENT_CONTEXT_SIZE)
	store_x           \reg_temp, 1 * portWORD_SIZE(\reg_temp2)
.endm

/* BaseType_t xPortGetCurrentCompartmentID( void ) PRIVILEGED_FUNCTION; */
.align 8
.type xPortGetCurrentCompartmentID, %function
xPortGetCurrentCompartmentID:
	getCurrentPerTCBCompartment a0
	ret
.size xPortGetCurrentCompartmentID, . - xPortGetCurrentCompartmentID
/*-----------------------------------------------------------*/

/* uintcap_t xPortGetCurrentCompartmentStack( void ) PRIVILEGED_FUNCTION; */
.align 8
.type xPortGetCurrentCompartmentStack, %function
xPortGetCurrentCompartmentStack:
	getCurrentPerTCBCompartmentStack a0
	ret
.size xPortGetCurrentCompartmentStack, . - xPortGetCurrentCompartmentStack
/*-----------------------------------------------------------*/

/* uintcap_t xPortGetCurrentCompartmentReturn( void ) PRIVILEGED_FUNCTION; */
.align 8
.type xPortGetCurrentCompartmentReturn, %function
xPortGetCurrentCompartmentReturn:
	getCurrentPerTCBCompartmentReturn a0
	ret
.size xPortGetCurrentCompartmentReturn, . - xPortGetCurrentCompartmentReturn
/*-----------------------------------------------------------*/

.balign 16
.type xPortCompartmentTrampSetup, %function
xPortCompartmentTrampSetup:
.Lfunc:      .zero portWORD_SIZE
.Lcaptable:  .zero portWORD_SIZE
.Ltramp:     .zero portWORD_SIZE
.Lnum_regions: .zero portWORD_SIZE
setup_regs:
	.option push
	.option norvc
	addi t0, x0, configCOMPARTMENTS_NUM - 1
	.option pop
	la      t2, .Lfunc
	load_x  t1, 2*portWORD_SIZE(t2)
	jr      t1
.size xPortCompartmentTrampSetup, . - xPortCompartmentTrampSetup
/*-----------------------------------------------------------*/

/* BaseType_t xPortCompartmentEnterTrampoline PRIVILEGED_FUNCTION; */
.balign 16
.type xPortCompartmentEnterTrampoline, %function
xPortCompartmentEnterTrampoline:
	# Assume t2 is the start address of the metadata, and t0 has the dest compid
	# Load func
	load_x t1, 0(t2)

	# Load region count
	load_x x4, (3 * portWORD_SIZE) (t2)

	# Load captable
	load_x gp, (1 * portWORD_SIZE) (t2)
	mv     t2, gp

	/* Enter a critical section setting the new compartment context */
	csrrc t3, mstatus, 8 // Disable interrupts
	la    t4, compartment_return
	saveCurrentPerTCBCompartmentContext t5, t6, t0, t4

	/* Set the new compartment's cgp */
	la t4, vSetupMPUPerComp
	jalr t4

	csrw  mstatus, t3 // Retrieve previous mstatus pre-critical section
	/* Exit critical section */

#if 0
	mv             x18, x0
	mv             x19, x0
	mv             x20, x0
	mv             x21, x0
	mv             x22, x0
	mv             x23, x0
	mv             x24, x0
	mv             x25, x0
	mv             x26, x0
	mv             x27, x0
	mv             x28, x0
	mv             x29, x0
	mv             x30, x0
	mv             x31, x0
#endif

	/* Beyond this point, we are now in a new compartment */

	/* ------------------- */

compartment_call:
	/* GO! */
	jalr     ra, t1

	/* ------------------- */

compartment_return:
	/* Enter a critical section setting the old compartment context */
	csrrc t3, mstatus, 8 // Disable interrupts
	/* Compartment returned, retrieve caller's state */
	restorePerTCBCompartmentContext t0, t1
	csrw  mstatus, t3 // Retrieve previous mstatus pre-critical section
	/* Exit critical section */

	ret
xPortCompartmentEnterTrampolineEnd:
.size xPortCompartmentEnterTrampoline, . - xPortCompartmentEnterTrampoline
/*-----------------------------------------------------------*/
.align 8
.type vSetupMPUPerComp, @function
vSetupMPUPerComp:
    # t2 has the captable/mpu base address regions
    # t4 == 1 is reloaded from m-mode
    # x4 has the number of regions

	# Skip a trap if called from an external interrupt and thus jumping to a device driver compartment
	# in which case, we are already in m-mode
	li    t6, 0xb
	csrr  t5, mcause
	and   t5, t5, t6
	beq   t5, t6, 1f

	# Skip ecall if reloading from a context switcher, otherwise syscall if from a user trampoline
	li t5, 1
	beq t4, t5, 1f

	mv     t6, a7
	li     a7, 4
	ecall
	mv     a7, t6
1:
	li     t5, configMPU_REGIONS_NUM

	# Zero previous compartments MPU regions context
zero:
    beqz   t5, 1f
	csrw   pmpaddr0, x0
	addi   t5, t5, -1
	j      zero
1:

	# Reconfigure the MPU with the new compartment regions addresses/bounds
	mv      t5, x4
loop_addrs:
    beqz   t5, 1f
	load_x t4, (t2)
	csrw   pmpaddr0, t4
	addi   t5, t5, -1
	addi   t2, t2, portWORD_SIZE
	j      loop_addrs
1:

	#Note Emulate if the MPU has more N regions, we need to configure N / size_t CSR registers
	mv      t5, x4
#if __riscv_xlen == 32
	srli    t5, t5, 2
#else
	srli    t5, t5, 3
#endif
loop_configs:
	beqz   t5, 1f
	# Load config values
	load_x t4, -(portWORD_SIZE) (t2)
	csrw   pmpcfg0, x0
	addi   t5, t5, -1
	j      loop_configs

1:
	ret
#endif
#endif
/*-----------------------------------------------------------*/
