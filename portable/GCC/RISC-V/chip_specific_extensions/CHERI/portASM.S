/*
 * FreeRTOS Kernel V10.2.1
 * Copyright (C) 2020 Hesham Almatary
 * Copyright (C) 2019 Amazon.com, Inc. or its affiliates.  All Rights Reserved.
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
 * http://www.FreeRTOS.org
 * http://aws.amazon.com/freertos
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
	#define portWORD_SIZE 16
	#define store_x csc
	#define load_x clc
#elif __riscv_xlen == 32
	#define portWORD_SIZE 8
	#define store_x csc
	#define load_x clc
#else
	#error Assembler did not define __riscv_xlen
#endif

#include "freertos_risc_v_chip_specific_extensions.h"

/* Check the freertos_risc_v_chip_specific_extensions.h and/or command line
definitions. */
#if defined( portasmHAS_CLINT ) && defined( portasmHAS_MTIME )
	#error The portasmHAS_CLINT constant has been depracted.  Please replace it with portasmHAS_CLINT.  portasmHAS_CLINT and portasmHAS_MTIME cannot both be defined at once.
#endif

#ifdef portasmHAS_CLINT
	#warning The portasmHAS_CLINT constant has been depracted.  Please replace it with portasmHAS_CLINT.  For now portasmHAS_MTIME is derived from portasmHAS_CLINT.
	#define portasmHAS_MTIME portasmHAS_CLINT
#endif

#ifndef portasmHAS_MTIME
	#error freertos_risc_v_chip_specific_extensions.h must define portasmHAS_MTIME to either 1 (MTIME clock present) or 0 (MTIME clock not present).
#endif

#ifndef portasmHANDLE_INTERRUPT
	#error portasmHANDLE_INTERRUPT must be defined to the function to be called to handle external/peripheral interrupts.  portasmHANDLE_INTERRUPT can be defined on the assmbler command line or in the appropriate freertos_risc_v_chip_specific_extensions.h header file.
#endif

/* Only the standard core registers are stored by default.  Any additional
registers must be saved by the portasmSAVE_ADDITIONAL_REGISTERS and
portasmRESTORE_ADDITIONAL_REGISTERS macros - which can be defined in a chip
specific version of freertos_risc_v_chip_specific_extensions.h.  See the notes
at the top of this file. */
#ifdef __CHERI_PURE_CAPABILITY__
#define portCONTEXT_SIZE (36 * portWORD_SIZE)
#endif

.global xPortStartFirstTask
.global freertos_risc_v_trap_handler
.global pxPortInitialiseStack
.global xPortCompartmentEnter
.global pxPortCompartmentGetReturnTrampoline
.global xPortCompartmentReturn
.global cheri_seal_cap
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

#if configPORT_ALLOW_APP_EXCEPTION_HANDLERS
.extern vPortExceptionHandler
#endif

/*-----------------------------------------------------------*/

.align 8
.type freertos_risc_v_trap_handler, %function
freertos_risc_v_trap_handler:
	cincoffset        csp, csp, -portCONTEXT_SIZE

	store_x           c1, 1 * portWORD_SIZE(csp)
	store_x           c3, 3 * portWORD_SIZE(csp)
	store_x           c4, 4 * portWORD_SIZE(csp)
	store_x           c5, 5 * portWORD_SIZE(csp)
	store_x           c6, 6 * portWORD_SIZE(csp)
	store_x           c7, 7 * portWORD_SIZE(csp)
	store_x           c8, 8 * portWORD_SIZE(csp)
	store_x           c9, 9 * portWORD_SIZE(csp)
	store_x           c10, 10 * portWORD_SIZE(csp)
	store_x           c11, 11 * portWORD_SIZE(csp)
	store_x           c12, 12 * portWORD_SIZE(csp)
	store_x           c13, 13 * portWORD_SIZE(csp)
	store_x           c14, 14 * portWORD_SIZE(csp)
	store_x           c15, 15 * portWORD_SIZE(csp)
	store_x           c16, 16 * portWORD_SIZE(csp)
	store_x           c17, 17 * portWORD_SIZE(csp)
	store_x           c18, 18 * portWORD_SIZE(csp)
	store_x           c19, 19 * portWORD_SIZE(csp)
	store_x           c20, 20 * portWORD_SIZE(csp)
	store_x           c21, 21 * portWORD_SIZE(csp)
	store_x           c22, 22 * portWORD_SIZE(csp)
	store_x           c23, 23 * portWORD_SIZE(csp)
	store_x           c24, 24 * portWORD_SIZE(csp)
	store_x           c25, 25 * portWORD_SIZE(csp)
	store_x           c26, 26 * portWORD_SIZE(csp)
	store_x           c27, 27 * portWORD_SIZE(csp)
	store_x           c28, 28 * portWORD_SIZE(csp)
	store_x           c29, 29 * portWORD_SIZE(csp)
	store_x           c30, 30 * portWORD_SIZE(csp)
	store_x           c31, 31 * portWORD_SIZE(csp)

	csrr              t0, mstatus # Required for MPIE bit.
	store_x           ct0, 32 * portWORD_SIZE(csp)

	cspecialr         ct0, ddc
	store_x           ct0, 33 * portWORD_SIZE(csp)

	# Save the current CompID
	csrr              a0, mscratch
	store_x           ca3, 34 * portWORD_SIZE(csp)

	portasmSAVE_ADDITIONAL_REGISTERS /* Defined in freertos_risc_v_chip_specific_extensions.h to save any registers unique to the RISC-V implementation. */

	clgc              ct0, pxCurrentTCB # Load pxCurrentTCB.
	clc               ct0, 0(ct0) # Load pxCurrentTCB.
	store_x           csp, 0(ct0) # Write sp to first TCB member.

	csrr              a0, mcause
	cspecialr         ca1, mepcc # Read mepcc.

test_if_asynchronous:
	srli              a2, a0, __riscv_xlen - 1 /* MSB of mcause is 1 if handing an asynchronous interrupt - shift to LSB to clear other bits. */
	beq               a2, x0, handle_synchronous /* Branch past interrupt handing if not asynchronous. */

	store_x           ca1, 0(csp) /* Asynch so save unmodified exception return address. */

handle_asynchronous:

#if( portasmHAS_MTIME != 0 )

	test_if_mtimer: /* If there is a CLINT then the mtimer is used to generate the tick interrupt. */

		addi            t0, x0, 1

		slli            t0, t0, __riscv_xlen - 1 /* LSB is already set, shift into MSB.  Shift 31 on 32-bit or 63 on 64-bit cores. */
		addi            t1, t0, 7 /* 0x8000[]0007 == machine timer interrupt. */
		bne             a0, t1, test_if_external_interrupt

		clgc            ct0, pullMachineTimerCompareRegister # Load cap to cap to compare register into t0.
		clc             ct0, 0(ct0) # Load the actual cap to compare register.
		clgc            ct1, pullNextTime # Same as above.
		clc             ct1, 0(ct1)

		#if( __riscv_xlen == 32 )

			/* Update the 64-bit mtimer compare match value in two 32-bit writes. */
			clw           t2, 0(ct1) # Load the low word of ullNextTime into t2.
			clw           t3, 4(ct1) # Load the high word of ullNextTime into t3.
			addi          t4, zero, -1
			csw           t4, 4(ct0) # Prevent spurious interrupts.
			csw           t2, 0(ct0) # Store low word of ullNextTime into compare register.
			csw           t3, 4(ct0) # Store high word of ullNextTime into compare register.
			clgc          ct0, uxTimerIncrementsForOneTick # Load the cap to ullTimerIncrementForOneTick into t0 (could this be optimized by storing in an array next to pullNextTime?).
			clw           t0, 0(ct0) # Load the actual value.

			add           t4, t0, t2 /* Add the low word of ullNextTime to the timer increments for one tick (assumes timer increment for one tick fits in 32-bits). */
			sltu          t5, t4, t2 /* See if the sum of low words overflowed (what about the zero case?). */
			add           t6, t3, t5 /* Add overflow to high word of ullNextTime. */

			csw           t4, 0(ct1) # Store new low word of ullNextTime.
			csw           t6, 4(ct1) # Store new high word of ullNextTime.

		#endif /* __riscv_xlen == 32 */

		#if( __riscv_xlen == 64 )

			/* Update the 64-bit mtimer compare match value. */
			cld           t2, 0(ct1) /* Load ullNextTime into t2. */
			csd           t2, 0(ct0) /* Store ullNextTime into compare register. */
			clgc          ct0, uxTimerIncrementsForOneTick /* Load the cap to ullTimerIncrementForOneTick into t0 (could this be optimized by storing in an array next to pullNextTime?). */
			cld           t0, 0(ct0) /* Load the actual value. */
			add           t4, t0, t2 /* Add ullNextTime to the timer increments for one tick. */
			csd           t4, 0(ct1) /* Store ullNextTime. */

		#endif /* __riscv_xlen == 64 */

		clgc            ct0, xISRStackTop # Switch to ISR stack before function call.
		clc             csp, 0(ct0)

		clgc            ct0, xTaskIncrementTick
		cjalr           cra, ct0

		beqz            a0, 1f /* Don't switch context if incrementing tick didn't unblock a task. */
		clgc            ct0, vTaskSwitchContext
		cjalr           cra, ct0

1:
		clgc            ct1, pxCurrentTCB # Load cap to pxCurrentTCB.
		clc             ct1, 0(ct1) # Load pxCurrentTCB.
		load_x          csp, 0(ct1) # Read sp from first TCB member.
		beq             zero, zero, processed_source

	test_if_external_interrupt: /* If there is a CLINT and the mtimer interrupt is not pending then check to see if an external interrupt is pending. */
		addi            t1, t1, 4 /* 0x80000007 + 4 = 0x8000000b == Machine external interrupt. */
		bne             a0, t1, as_yet_unhandled /* Something as yet unhandled. */

#endif /* portasmHAS_MTIME */

	clgc              ct0, xISRStackTop # Switch to ISR stack before function call.
	clc               csp, 0(ct0)
	clgc              ct0, portasmHANDLE_INTERRUPT
	cjalr             cra, ct0 # Jump to the interrupt handler if there is no CLINT or if there is a CLINT and it has been determined that an external interrupt is pending.

	clgc              ct1, pxCurrentTCB # Load cap to pxCurrentTCB.
	clc               ct1, 0(ct1) # Load pxCurrentTCB.
	load_x            csp, 0(ct1) # Read sp from first TCB member.
	beq               zero, zero, processed_source

handle_synchronous:
	cincoffset        ca1, ca1, 4 # Synchronous so updated exception return address to the instruction after the instruction that generated the exeption.
	store_x           ca1, 0(csp) # Save updated exception return address.

test_if_environment_call:
	li                t0, 11 /* 11 == environment call. */
	bne               a0, t0, is_exception /* Not an M environment call, so some other exception. */

	clgc              ct0, xISRStackTop # Switch to ISR stack before function call.
	clc               csp, 0(ct0)

	clgc              ct0, vTaskSwitchContext
	cjalr             cra, ct0

	clgc              ct1, pxCurrentTCB # Load cap to pxCurrentTCB.
	clc               ct1, 0(ct1) # Load pxCurrentTCB.
	load_x            csp, 0(ct1) # Read sp from first TCB member.

	beq               zero, zero, processed_source

is_exception:
	#csrr              t1, mccsr
	#li                t0, (0x19  << 5) # CCall
	#and               t1, t0, t1
	#bne               t0, t1, 1f

#if configPORT_ALLOW_APP_EXCEPTION_HANDLERS
	/* a0 and a1 should already have mcause and mepcc,
	 * put exception frame in a2 as a third argument to vPortExceptionHandler. */
	cmove             ca2, csp
	clgc              ct0, vPortExceptionHandler
	cjalr             cra, ct0
	j                 processed_source
#endif /* configPORT_ALLOW_APP_EXCEPTION_HANDLERS */

.Ltest_if_in_compartment:
	csrr              t0, mscratch
	li                t1, configCOMPARTMENTS_NUM - 1
	bne               t0, t1, xPortCompartmentTrapReturn

.Lbreak_on_exception:
	csrr              t0, mcause /* For viewing in the debugger only. */
	csrr              t1, mepc /* For viewing in the debugger only */
	csrr              t2, mstatus
	ebreak
	j                 .Lbreak_on_exception

as_yet_unhandled:
	ebreak
	beq               zero, zero, as_yet_unhandled

processed_source:

	portasmRESTORE_ADDITIONAL_REGISTERS	/* Defined in freertos_risc_v_chip_specific_extensions.h to restore any registers unique to the RISC-V implementation. */

	load_x            ct0, 0 * portWORD_SIZE(csp)
	cspecialw         mepcc, ct0 # Write mepcc.

	load_x            ct0, 33 * portWORD_SIZE(csp)
	cspecialrw        cnull, ddc, ct0

	/* Load mstatus with the interrupt enable bits used by the task. */
	load_x            ct0, 32 * portWORD_SIZE(csp)
	csrw              mstatus, t0 /* Required for MPIE bit. */

	load_x            c1, 1 * portWORD_SIZE(csp)
	load_x            c3, 3 * portWORD_SIZE(csp)
	load_x            c4, 4 * portWORD_SIZE(csp)
	load_x            c5, 5 * portWORD_SIZE(csp)
	load_x            c6, 6 * portWORD_SIZE(csp)
	load_x            c7, 7 * portWORD_SIZE(csp)
	load_x            c8, 8 * portWORD_SIZE(csp)
	load_x            c9, 9 * portWORD_SIZE(csp)
	load_x            c10, 10 * portWORD_SIZE(csp)
	load_x            c11, 11 * portWORD_SIZE(csp)
	load_x            c12, 12 * portWORD_SIZE(csp)
	load_x            c13, 13 * portWORD_SIZE(csp)
	load_x            c14, 14 * portWORD_SIZE(csp)
	load_x            c15, 15 * portWORD_SIZE(csp)
	load_x            c16, 16 * portWORD_SIZE(csp)
	load_x            c17, 17 * portWORD_SIZE(csp)
	load_x            c18, 18 * portWORD_SIZE(csp)
	load_x            c19, 19 * portWORD_SIZE(csp)
	load_x            c20, 20 * portWORD_SIZE(csp)
	load_x            c21, 21 * portWORD_SIZE(csp)
	load_x            c22, 22 * portWORD_SIZE(csp)
	load_x            c23, 23 * portWORD_SIZE(csp)
	load_x            c24, 24 * portWORD_SIZE(csp)
	load_x            c25, 25 * portWORD_SIZE(csp)
	load_x            c26, 26 * portWORD_SIZE(csp)
	load_x            c27, 27 * portWORD_SIZE(csp)
	load_x            c28, 28 * portWORD_SIZE(csp)
	load_x            c29, 29 * portWORD_SIZE(csp)
	load_x            c30, 30 * portWORD_SIZE(csp)
	load_x            c31, 31 * portWORD_SIZE(csp)

	cincoffset        csp, csp, portCONTEXT_SIZE

	mret
.size freertos_risc_v_trap_handler, . - freertos_risc_v_trap_handler
/*-----------------------------------------------------------*/

.align 8
.type xPortStartFirstTask, %function
xPortStartFirstTask:
	clgc              ct0, pxCurrentTCB # Load the cap to pxCurrentTCB.
	clc               ct0, 0(ct0) # Load pxCurrentTCB.
	load_x            csp, 0(ct0) # Read sp from first TCB member.

	portasmRESTORE_ADDITIONAL_REGISTERS /* Defined in freertos_risc_v_chip_specific_extensions.h to restore any registers unique to the RISC-V implementation. */

	load_x            ct0, 0 * portWORD_SIZE(csp)
	cspecialw         mepcc, ct0 # Write mepcc.

	load_x            ct0, 34 * portWORD_SIZE(csp)
	csrw              mscratch, t0

	load_x            ct0, 33 * portWORD_SIZE(csp)
	cspecialw         ddc, ct0

	load_x            ct0, 32 * portWORD_SIZE(csp) # mstatus
	csrw              mstatus, t0 /* Required for MPIE bit. */

	# Put compID of configCOMPARTMENTS_NUM -1 (non-compartment) in mscratchc
	li                t0, configCOMPARTMENTS_NUM - 1
	csrw              mscratch, t0

	load_x            c1, 1 * portWORD_SIZE(csp)
	load_x            c3, 3 * portWORD_SIZE(csp)
	load_x            c4, 4 * portWORD_SIZE(csp)
	load_x            c5, 5 * portWORD_SIZE(csp)
	load_x            c6, 6 * portWORD_SIZE(csp)
	load_x            c7, 7 * portWORD_SIZE(csp)
	load_x            c8, 8 * portWORD_SIZE(csp)
	load_x            c9, 9 * portWORD_SIZE(csp)
	load_x            c10, 10 * portWORD_SIZE(csp)
	load_x            c11, 11 * portWORD_SIZE(csp)
	load_x            c12, 12 * portWORD_SIZE(csp)
	load_x            c13, 13 * portWORD_SIZE(csp)
	load_x            c14, 14 * portWORD_SIZE(csp)
	load_x            c15, 15 * portWORD_SIZE(csp)
	load_x            c16, 16 * portWORD_SIZE(csp)
	load_x            c17, 17 * portWORD_SIZE(csp)
	load_x            c18, 18 * portWORD_SIZE(csp)
	load_x            c19, 19 * portWORD_SIZE(csp)
	load_x            c20, 20 * portWORD_SIZE(csp)
	load_x            c21, 21 * portWORD_SIZE(csp)
	load_x            c22, 22 * portWORD_SIZE(csp)
	load_x            c23, 23 * portWORD_SIZE(csp)
	load_x            c24, 24 * portWORD_SIZE(csp)
	load_x            c25, 25 * portWORD_SIZE(csp)
	load_x            c26, 26 * portWORD_SIZE(csp)
	load_x            c27, 27 * portWORD_SIZE(csp)
	load_x            c28, 28 * portWORD_SIZE(csp)
	load_x            c29, 29 * portWORD_SIZE(csp)
	load_x            c30, 30 * portWORD_SIZE(csp)
	load_x            c31, 31 * portWORD_SIZE(csp)
	cincoffset        csp, csp, portCONTEXT_SIZE

	mret							/* Interrupts enabled from here! */
xPortStartFirstTaskEnd:
.size xPortStartFirstTask, xPortStartFirstTaskEnd - xPortStartFirstTask
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
 * (unused)
 * compid
 * ddc
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
 * x10 (pvParameters)
 * x9
 * x8
 * x7
 * x6
 * x5
 * x4
 * x3
 * (unused x2)
 * x1 (null return capability)
 * [chip specific registers go here]
 * pxCode
 */
.align 8
.type pxPortInitialiseStack, %function
pxPortInitialiseStack:

	cincoffset        ca0, ca0, -portCONTEXT_SIZE
	store_x           cnull, 1 * portWORD_SIZE(ca0) # return address onto the stack, could be portTASK_RETURN_ADDRESS
	store_x           ca2, 10 * portWORD_SIZE(ca0) # Task parameters (pvParameters parameter) go into register X10/a0 on the stack.

	addi              t0, x0, 0x188 /* Generate the value 0x1880, which are the MPIE and MPP bits to set in mstatus. */
	slli              t0, t0, 4
	store_x           ct0, 32 * portWORD_SIZE(ca0) # mstatus onto the stack.
	store_x           cnull, 33 * portWORD_SIZE(ca0) # Default to null DDC

	addi              t0, zero, portasmADDITIONAL_CONTEXT_SIZE /* The number of chip specific additional registers. */

chip_specific_stack_frame: /* First add any chip specific registers to the stack frame being created. */
	beq               t0, zero, 1f /* No more chip specific registers to save. */
	store_x           cnull, 0 * portWORD_SIZE(ca0) /* Give the chip specific register an initial value of zero. */
	cincoffset        ca0, ca0, -portWORD_SIZE /* Make space for chip specific register (replaced pxCode). */
	addi              t0, t0, -1 /* Decrement the count of chip specific registers remaining. */
	j chip_specific_stack_frame /* Until no more chip specific registers. */
1:
	store_x           ca1, 0 * portWORD_SIZE(ca0) # mret value (pxCode parameter) onto the stack
	cret

pxPortInitialiseStackEnd:
.size pxPortInitialiseStack, pxPortInitialiseStackEnd - pxPortInitialiseStack
/*-----------------------------------------------------------*/


/* BaseType_t xPortCompartmentEnter( BaseType_t ( * pxFunction ) ( void ), void *pxData, xCOMPARTMENT_ARGS *pxArgs, BaseType_t xCompID ) PRIVILEGED_FUNCTION; */
.align 8
.type xPortCompartmentEnter, %function
xPortCompartmentEnter:
	/*
	 * Save entire context to stack. Also writes null to mepcc slot (0) since
	 * we will be using cret rather than mret. We could optimise this by not
	 * saving callee-saved registers that we don't use.
	 */
	cincoffset        csp, csp, -portCONTEXT_SIZE
	store_x           c0, 0 * portWORD_SIZE(csp)
	store_x           c1, 1 * portWORD_SIZE(csp)
	/* c2 is csp */
	store_x           c3, 3 * portWORD_SIZE(csp)
	store_x           c4, 4 * portWORD_SIZE(csp)
	store_x           c5, 5 * portWORD_SIZE(csp)
	store_x           c6, 6 * portWORD_SIZE(csp)
	store_x           c7, 7 * portWORD_SIZE(csp)
	store_x           c8, 8 * portWORD_SIZE(csp)
	store_x           c9, 9 * portWORD_SIZE(csp)
	store_x           c10, 10 * portWORD_SIZE(csp)
	store_x           c11, 11 * portWORD_SIZE(csp)
	store_x           c12, 12 * portWORD_SIZE(csp)
	store_x           c13, 13 * portWORD_SIZE(csp)
	store_x           c14, 14 * portWORD_SIZE(csp)
	store_x           c15, 15 * portWORD_SIZE(csp)
	store_x           c16, 16 * portWORD_SIZE(csp)
	store_x           c17, 17 * portWORD_SIZE(csp)
	store_x           c18, 18 * portWORD_SIZE(csp)
	store_x           c19, 19 * portWORD_SIZE(csp)
	store_x           c20, 20 * portWORD_SIZE(csp)
	store_x           c21, 21 * portWORD_SIZE(csp)
	store_x           c22, 22 * portWORD_SIZE(csp)
	store_x           c23, 23 * portWORD_SIZE(csp)
	store_x           c24, 24 * portWORD_SIZE(csp)
	store_x           c25, 25 * portWORD_SIZE(csp)
	store_x           c26, 26 * portWORD_SIZE(csp)
	store_x           c27, 27 * portWORD_SIZE(csp)
	store_x           c28, 28 * portWORD_SIZE(csp)
	store_x           c29, 29 * portWORD_SIZE(csp)
	store_x           c30, 30 * portWORD_SIZE(csp)
	store_x           c31, 31 * portWORD_SIZE(csp)

	cmove             ct0, ca0 /* ca0: BaseType_t ( * pxFunction ) ( void ) */
	/* Put in IDC (already unsealed since we are trusted) */
	cmove             ct6, ca1 /* ca1: void *pxData */
	cmove             ct1, ca2 /* ca2: xCOMPARTMENT_ARGS *pxArgs */
	mv                t2, a3 /* a3: BaseType_t xCompID */

	csrr              a0, mstatus
	store_x           ca0, 32 * portWORD_SIZE(csp)

	cspecialr         ca0, ddc
	store_x           ca0, 33 * portWORD_SIZE(csp)

	# Save current CompID
	csrr              a0, mscratch
	store_x           ca3, 34 * portWORD_SIZE(csp)

	portasmSAVE_ADDITIONAL_REGISTERS

	/* Register changes beyond this point will NOT be visible on return */

	/* Seal the caller's stack cap and put it in cs1 to be used on return */
	clgc              ct3, pxCurrentTCB # Load pxCurrentTCB.
	clc               ct3, 0(ct3) # Load pxCurrentTCB.
	store_x           csp, 1 * portWORD_SIZE(ct3) # Write the caller's compartment stack.

	cmove             ca0, csp
	li                a1, configCOMPARTMENTS_NUM - 1
	clgc              ct3, cheri_seal_cap
	cjalr             cra, ct3
	cmove             cs1, ca0

	clgc              ct3, pxPortCompartmentReturnData
	store_x           csp, 0(ct3)

	# Set the current compartment ID in mscratch
	csrw              mscratch, a3

	/* Load arguments for compartment */
	clc               ca0, 0 * portWORD_SIZE(ct1)
	clc               ca1, 1 * portWORD_SIZE(ct1)
	clc               ca2, 2 * portWORD_SIZE(ct1)
	clc               ca3, 3 * portWORD_SIZE(ct1)
	clc               ca4, 4 * portWORD_SIZE(ct1)
	clc               ca5, 5 * portWORD_SIZE(ct1)
	clc               ca6, 6 * portWORD_SIZE(ct1)
	clc               ca7, 7 * portWORD_SIZE(ct1)

	/* Load additional arguments for compartment */
	/* ct0 is still pxFunction */
	/* ct6 is still pxData */
	clgc              cra, pxPortCompartmentReturnTrampoline
	clc               cra, 0(cra)
	clgc              cs0, pxPortCompartmentReturnFunc
	clc               cs0, 0(cs0)

	/* Load the stack cap. ct6 has pxData which is the captable for the compartment
	 * The loader install the compartment's stack in the very first slot of the
	 * captable.
	 */
	clc               csp, 0 * portWORD_SIZE(ct6)

	/* Beyond this point we count as inside the compartment */

	/* Clear registers */
	/* c0 is cnull */
	/* c1 is cra - pxPortCompartmentReturnTrampoline */
	/* c3 is cgp and c31 is ct6 - pxData. Move c31 in cgp as it's the captable for this comp */
	cmove             c3, c31
	cmove             c4, cnull
	/* c5 is ct0 - pxFunction */
	cmove             c6, cnull
	cmove             c7, cnull
	/* c8 is cs0 - pxPortCompartmentReturnFunc */
	/* c9 is cs1 - returnStack */
	/* c10 is ca0 */
	/* c11 is ca1 */
	/* c12 is ca2 */
	/* c13 is ca3 */
	/* c14 is ca4 */
	/* c15 is ca5 */
	/* c16 is ca6 */
	/* c17 is ca7 */
	cmove             c18, cnull
	cmove             c19, cnull
	cmove             c20, cnull
	cmove             c21, cnull
	cmove             c22, cnull
	cmove             c23, cnull
	cmove             c24, cnull
	cmove             c25, cnull
	cmove             c26, cnull
	cmove             c27, cnull
	cmove             c28, cnull
	cmove             c29, cnull
	cmove             c30, cnull
	cmove             c31, cnull

	/* GO! */
	cjr               ct0
.size xPortCompartmentEnter, . - xPortCompartmentEnter
/*-----------------------------------------------------------*/

/*
 * This is just a convenience wrapper so compartmentalized functions can use the
 * standard ABI. Its presence (provided the capability to it is sufficiently
 * unprivileged, ie has tight bounds and the same permissions as the callee)
 * does not provide additional privilege to the untrusted code since the callee
 * could just include the ccall in its own body.
 */
.align 8
.type xPortCompartmentReturnTrampoline, %function
xPortCompartmentReturnTrampoline:
	/* cs0 - pxPortCompartmentReturnFunc (sealed) */
	/* cs1 - returnStack (sealed) */

	/* (Hopefully) return from the compartment */
	ccall             cs0, cs1
.LxPortCompartmentReturnTrampolineEnd:
.size xPortCompartmentReturnTrampoline, .LxPortCompartmentReturnTrampolineEnd - xPortCompartmentReturnTrampoline
/*-----------------------------------------------------------*/

/* void ( * pxPortCompartmentGetReturnTrampoline( void ) ) ( void ); */
.align 8
.type pxPortCompartmentGetReturnTrampoline, %function
pxPortCompartmentGetReturnTrampoline:
	/* Load a PCC-derived unsealed (non-sentry) cap to xPortCompartmentReturnTrampoline */
	cllc              ca0, xPortCompartmentReturnTrampoline

	/* Set bounds */
	li                a1, %lo(.LxPortCompartmentReturnTrampolineEnd - xPortCompartmentReturnTrampoline)
	csetboundsexact   ca0, ca0, a1

	/* Set permissions */
	li                t1, __CHERI_CAP_PERMISSION_GLOBAL__ | \
		                __CHERI_CAP_PERMISSION_PERMIT_EXECUTE__ | \
		                __CHERI_CAP_PERMISSION_PERMIT_LOAD__ | \
		                __CHERI_CAP_PERMISSION_PERMIT_LOAD_CAPABILITY__
	candperm          ca0, ca0, t1

	/* sealentry after setting bounds and permissions to avoid leaking a non-sentry. */
	csealentry        ca0, ca0

	cret
.size pxPortCompartmentGetReturnTrampoline, . - pxPortCompartmentGetReturnTrampoline
/*-----------------------------------------------------------*/

.align 8
.type xPortCompartmentReturn, %function
xPortCompartmentReturn:
	/* ccall puts IDC in c31 */
	cmove             csp, c31

	/* Beyond this point we count as outside the compartment */

	load_x            ct0, 34 * portWORD_SIZE(csp)
	csrw              mscratch, t0

	load_x            ct0, 33 * portWORD_SIZE(csp)
	cspecialw         ddc, ct0

	load_x            ct0, 32 * portWORD_SIZE(csp)
	csrw              mstatus, t0

	load_x            c1, 1 * portWORD_SIZE(csp)
	/* c2 is csp */
	load_x            c3, 3 * portWORD_SIZE(csp)
	load_x            c4, 4 * portWORD_SIZE(csp)
	load_x            c5, 5 * portWORD_SIZE(csp)
	load_x            c6, 6 * portWORD_SIZE(csp)
	load_x            c7, 7 * portWORD_SIZE(csp)
	load_x            c8, 8 * portWORD_SIZE(csp)
	load_x            c9, 9 * portWORD_SIZE(csp)
	/* c10 is ca0 - return value of compartment */
	li                x11, 1 /* c11 is ca1 - low bit of 1 iff compartment exited normally */
	load_x            c12, 12 * portWORD_SIZE(csp)
	load_x            c13, 13 * portWORD_SIZE(csp)
	load_x            c14, 14 * portWORD_SIZE(csp)
	load_x            c15, 15 * portWORD_SIZE(csp)
	load_x            c16, 16 * portWORD_SIZE(csp)
	load_x            c17, 17 * portWORD_SIZE(csp)
	load_x            c18, 18 * portWORD_SIZE(csp)
	load_x            c19, 19 * portWORD_SIZE(csp)
	load_x            c20, 20 * portWORD_SIZE(csp)
	load_x            c21, 21 * portWORD_SIZE(csp)
	load_x            c22, 22 * portWORD_SIZE(csp)
	load_x            c23, 23 * portWORD_SIZE(csp)
	load_x            c24, 24 * portWORD_SIZE(csp)
	load_x            c25, 25 * portWORD_SIZE(csp)
	load_x            c26, 26 * portWORD_SIZE(csp)
	load_x            c27, 27 * portWORD_SIZE(csp)
	load_x            c28, 28 * portWORD_SIZE(csp)
	load_x            c29, 29 * portWORD_SIZE(csp)
	load_x            c30, 30 * portWORD_SIZE(csp)
	load_x            c31, 31 * portWORD_SIZE(csp)

	cincoffset        csp, csp, portCONTEXT_SIZE

	cret
.size xPortCompartmentReturn, . - xPortCompartmentReturn
/*-----------------------------------------------------------*/

.align 8
.type xPortCompartmentTrapReturn, %function
xPortCompartmentTrapReturn:
	#clgc              ct0, pxCurrentTCB /* &pxCurrentTCB */
	#clc               ct0, 0(ct0) /* pxCurrentTCB */
	#clc               csp, 1 * portWORD_SIZE(ct0) # Read context

	clgc              csp, pxPortCompartmentReturnData
	clc               csp, 0(csp)

	/* Beyond this point we count as outside the compartment */

	load_x            ct0, 33 * portWORD_SIZE(csp)
	cspecialw         ddc, ct0

	load_x            ct0, 32 * portWORD_SIZE(csp)
	csrw              mstatus, t0

	load_x            ct0, 34 * portWORD_SIZE(csp)
	csrw              mscratch, t0

	load_x            c1, 1 * portWORD_SIZE(csp)
	/* c2 is csp */
	load_x            c3, 3 * portWORD_SIZE(csp)
	load_x            c4, 4 * portWORD_SIZE(csp)
	load_x            c5, 5 * portWORD_SIZE(csp)
	load_x            c6, 6 * portWORD_SIZE(csp)
	load_x            c7, 7 * portWORD_SIZE(csp)
	load_x            c8, 8 * portWORD_SIZE(csp)
	load_x            c9, 9 * portWORD_SIZE(csp)
	/* c10 is ca0 - cause information in event of trap */
	/* c11 is ca1 - epc */
	load_x            c12, 12 * portWORD_SIZE(csp)
	load_x            c13, 13 * portWORD_SIZE(csp)
	load_x            c14, 14 * portWORD_SIZE(csp)
	load_x            c15, 15 * portWORD_SIZE(csp)
	load_x            c16, 16 * portWORD_SIZE(csp)
	load_x            c17, 17 * portWORD_SIZE(csp)
	load_x            c18, 18 * portWORD_SIZE(csp)
	load_x            c19, 19 * portWORD_SIZE(csp)
	load_x            c20, 20 * portWORD_SIZE(csp)
	load_x            c21, 21 * portWORD_SIZE(csp)
	load_x            c22, 22 * portWORD_SIZE(csp)
	load_x            c23, 23 * portWORD_SIZE(csp)
	load_x            c24, 24 * portWORD_SIZE(csp)
	load_x            c25, 25 * portWORD_SIZE(csp)
	load_x            c26, 26 * portWORD_SIZE(csp)
	load_x            c27, 27 * portWORD_SIZE(csp)
	load_x            c28, 28 * portWORD_SIZE(csp)
	load_x            c29, 29 * portWORD_SIZE(csp)
	load_x            c30, 30 * portWORD_SIZE(csp)
	load_x            c31, 31 * portWORD_SIZE(csp)

	cincoffset        csp, csp, portCONTEXT_SIZE

	cret
.size xPortCompartmentTrapReturn, . - xPortCompartmentTrapReturn
/*-----------------------------------------------------------*/
