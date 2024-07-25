/*
 * FreeRTOS Kernel V10.2.1
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

/*-----------------------------------------------------------
 * Implementation of functions defined in portable.h for the RISC-V RV32 port.
 *----------------------------------------------------------*/

#ifdef __CHERI_PURE_CAPABILITY__
#include <cheric.h>
#endif

/* Scheduler includes. */
#include "FreeRTOSConfig.h"
#include "FreeRTOS.h"
#include "task.h"
#include "portmacro.h"

/* Standard includes. */
#include "string.h"

#ifdef configCLINT_BASE_ADDRESS
	#warning The configCLINT_BASE_ADDRESS constant has been deprecated.  configMTIME_BASE_ADDRESS and configMTIMECMP_BASE_ADDRESS are currently being derived from the (possibly 0) configCLINT_BASE_ADDRESS setting.  Please update to define configMTIME_BASE_ADDRESS and configMTIMECMP_BASE_ADDRESS dirctly in place of configCLINT_BASE_ADDRESS.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-RISC-V.html
#endif

#ifndef configMTIME_BASE_ADDRESS
	#warning configMTIME_BASE_ADDRESS must be defined in FreeRTOSConfig.h.  If the target chip includes a memory-mapped mtime register then set configMTIME_BASE_ADDRESS to the mapped address.  Otherwise set configMTIME_BASE_ADDRESS to 0.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-RISC-V.html
#endif

#ifndef configMTIMECMP_BASE_ADDRESS
	#warning configMTIMECMP_BASE_ADDRESS must be defined in FreeRTOSConfig.h.  If the target chip includes a memory-mapped mtimecmp register then set configMTIMECMP_BASE_ADDRESS to the mapped address.  Otherwise set configMTIMECMP_BASE_ADDRESS to 0.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-RISC-V.html
#endif

#ifndef configMTIME_HZ
	#define configMTIME_HZ configCPU_CLOCK_HZ
#endif

/* Let the user override the pre-loading of the initial LR with the address of
prvTaskExitError() in case it messes up unwinding of the stack in the
debugger. */
#ifdef configTASK_RETURN_ADDRESS
	#define portTASK_RETURN_ADDRESS	configTASK_RETURN_ADDRESS
#else
	#define portTASK_RETURN_ADDRESS	prvTaskExitError
#endif

/* The stack used by interrupt service routines.  Set configISR_STACK_SIZE_WORDS
to use a statically allocated array as the interrupt stack.  Alternative leave
configISR_STACK_SIZE_WORDS undefined and update the linker script so that a
linker variable names __freertos_irq_stack_top has the same value as the top
of the stack used by main.  Using the linker script method will repurpose the
stack that was used by main before the scheduler was started for use as the
interrupt stack after the scheduler has started. */
#ifdef configISR_STACK_SIZE_WORDS
	static __attribute__ ((aligned(16))) StackType_t xISRStack[ configISR_STACK_SIZE_WORDS ] = { 0 };
#ifdef __CHERI_PURE_CAPABILITY__
	const StackType_t *xISRStackTop = &( xISRStack[ configISR_STACK_SIZE_WORDS & ~portBYTE_ALIGNMENT_MASK ] );
#else
	const StackType_t xISRStackTop = ( StackType_t ) &( xISRStack[ configISR_STACK_SIZE_WORDS & ~portBYTE_ALIGNMENT_MASK ] );
#endif

	/* Don't use 0xa5 as the stack fill bytes as that is used by the kernerl for
	the task stacks, and so will legitimately appear in many positions within
	the ISR stack. */
	#define portISR_STACK_FILL_BYTE	0xee	
#else
#ifdef __CHERI_PURE_CAPABILITY__
	const StackType_t *xISRStackTop;
#else
	extern const uint32_t __freertos_irq_stack_top[];
	const StackType_t xISRStackTop = ( StackType_t ) __freertos_irq_stack_top;
#endif
#endif

#if configPORT_ALLOW_APP_EXCEPTION_HANDLERS
	static uintptr_t riscv_exceptions_table[64] = {NULL};

	void vPortSetExceptionHandler( UBaseType_t  ulExceptiontNumber, uint32_t (*pvHandler)( uintptr_t *pvParameter) )
	{
		configASSERT(ulExceptiontNumber <= 64);
		riscv_exceptions_table[ulExceptiontNumber] = pvHandler;
	}

	UBaseType_t vPortExceptionHandler( UBaseType_t  ulExceptiontNumber, uintptr_t ulmepc, uintptr_t *exception_frame )
	{
		uint32_t (*handler)( void *pvParam ) =  (void *) riscv_exceptions_table[ulExceptiontNumber];

		if( handler )
		{
			return handler( exception_frame );
		}
	}
#endif

#ifdef __CHERI_PURE_CAPABILITY__
void *pvAlmightyDataCap;
void *pvAlmightyCodeCap;

#define COMPARTMENT_RETURN_OTYPE (configCOMPARTMENTS_NUM - 1)
#endif

#if ( configENABLE_MPU == 1 )

/**
 * @brief Setup the Memory Protection Unit (MPU).
 */
    static void prvSetupMPU( void ) PRIVILEGED_FUNCTION;
#endif /* configENABLE_MPU */

/*
 * Setup the timer to generate the tick interrupts.  The implementation in this
 * file is weak to allow application writers to change the timer used to
 * generate the tick interrupt.
 */
void vPortSetupTimerInterrupt( void ) __attribute__(( weak ));

/*-----------------------------------------------------------*/

/* Used to program the machine timer compare register. */
uint64_t ullNextTime = 0ULL;
const uint64_t *pullNextTime = &ullNextTime;
const size_t uxTimerIncrementsForOneTick = ( size_t ) ( ( configMTIME_HZ ) / ( configTICK_RATE_HZ ) ); /* Assumes increment won't go over 32-bits. */
uint32_t const ullMachineTimerCompareRegisterBase = configMTIMECMP_BASE_ADDRESS;
volatile uint64_t * pullMachineTimerCompareRegister = NULL;

/* Set configCHECK_FOR_STACK_OVERFLOW to 3 to add ISR stack checking to task
stack checking.  A problem in the ISR stack will trigger an assert, not call the
stack overflow hook function (because the stack overflow hook is specific to a
task stack, not the ISR stack). */
#if defined( configISR_STACK_SIZE_WORDS ) && ( configCHECK_FOR_STACK_OVERFLOW > 2 )
	#warning This path not tested, or even compiled yet.

	static const uint8_t ucExpectedStackBytes[] = {
									portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE,		\
									portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE,		\
									portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE,		\
									portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE,		\
									portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE, portISR_STACK_FILL_BYTE };	\

	#define portCHECK_ISR_STACK() configASSERT( ( memcmp( ( void * ) xISRStack, ( void * ) ucExpectedStackBytes, sizeof( ucExpectedStackBytes ) ) == 0 ) )
#else
	/* Define the function away. */
	#define portCHECK_ISR_STACK()
#endif /* configCHECK_FOR_STACK_OVERFLOW > 2 */

/*-----------------------------------------------------------*/

#if ( configENABLE_MPU == 1 )
    static void prvSetupMPU( void ) /* PRIVILEGED_FUNCTION */
    {
        extern size_t __privileged_functions_start__[];
        extern size_t __privileged_functions_end__[];
        extern size_t __privileged_data_start__[];
        extern size_t __privileged_data_end__[];
        extern size_t __syscalls_flash_start__[];
        extern size_t __syscalls_flash_end__[];
        extern size_t __unprivileged_flash_start__[];
        extern size_t __unprivileged_flash_end__[];
        extern size_t __unprivileged_sram_start__[];
        extern size_t __unprivileged_sram_end__[];

        size_t pmpaddr0 = 0, pmpaddr1 = 0, pmpaddr2 = 0, pmpaddr3 = 0, pmpaddr4 = 0,
               pmpaddr5 = 0, pmpaddr6 = 0, pmpaddr7 = 0;
        size_t pmpcfg0 = 0;
        size_t pmpcfg1 = 0;

        pmpaddr0 = (size_t)&__privileged_functions_start__>> portMPU_REGION_ADDRESS_SHIFT;
        pmpaddr1 = (size_t)&__privileged_functions_end__ >> portMPU_REGION_ADDRESS_SHIFT;

        // syscall base and bounds
        pmpaddr2 = (size_t)&__syscalls_flash_start__ >> portMPU_REGION_ADDRESS_SHIFT;
        pmpaddr3 = (size_t)&__syscalls_flash_end__ >> portMPU_REGION_ADDRESS_SHIFT;

        // unprivileged_flash base and bounds
        pmpaddr4 = (size_t)&__unprivileged_flash_start__ >> portMPU_REGION_ADDRESS_SHIFT;
        pmpaddr5 = (size_t)&__unprivileged_flash_end__ >> portMPU_REGION_ADDRESS_SHIFT;

        // unprivileged_flash base and bounds
        pmpaddr6 = (size_t)&__unprivileged_sram_start__ >> portMPU_REGION_ADDRESS_SHIFT;
        pmpaddr7 = (size_t)&__unprivileged_sram_end__ >> portMPU_REGION_ADDRESS_SHIFT;

        pmpcfg0 |= portMPU_REGION_TOR << 8; // protect privileged_functions

        printf("PMP static region: __privileged_functions <0x%x:0x%x>\n",
            (unsigned) pmpaddr0 << portMPU_REGION_ADDRESS_SHIFT,
            (unsigned) pmpaddr1 << portMPU_REGION_ADDRESS_SHIFT);
        printf("PMP static region: __syscalls_flash <0x%x:0x%x>\n",
            (unsigned) pmpaddr2 << portMPU_REGION_ADDRESS_SHIFT,
            (unsigned) pmpaddr3 << portMPU_REGION_ADDRESS_SHIFT);
        printf("PMP static region: __unprivileged_flash <0x%x:0x%x>\n",
            (unsigned) pmpaddr4 << portMPU_REGION_ADDRESS_SHIFT,
            (unsigned) pmpaddr5 << portMPU_REGION_ADDRESS_SHIFT);
        printf("PMP static region: __unprivileged_sram <0x%x:0x%x>\n",
            (unsigned) pmpaddr6 << portMPU_REGION_ADDRESS_SHIFT,
            (unsigned) pmpaddr7 << portMPU_REGION_ADDRESS_SHIFT);

        pmpcfg0 |= (portMPU_REGION_TOR | portMPU_REGION_READ_ONLY | portMPU_REGION_EXECUTE) << 24;  // Allow syscalls

#if __riscv_xlen == 32
        pmpcfg1 |= (portMPU_REGION_TOR | portMPU_REGION_READ_ONLY | portMPU_REGION_EXECUTE) << 8;  // Allow user code
        pmpcfg1 |= (portMPU_REGION_TOR  | portMPU_REGION_READ_WRITE) << 24;                        // Allow user data
#else
        pmpcfg0 |= (portMPU_REGION_TOR | portMPU_REGION_READ_ONLY | portMPU_REGION_EXECUTE) << 40;  // Allow user code
        pmpcfg0 |= (portMPU_REGION_TOR | portMPU_REGION_READ_WRITE) << 56;                          // Allow user data
#endif

        asm volatile(
            "csrw pmpaddr0, %0\t\n"
            "csrw pmpaddr1, %1\t\n"
            "csrw pmpaddr2, %2\t\n"
            "csrw pmpaddr3, %3\t\n"
            "csrw pmpaddr4, %4\t\n"
            "csrw pmpaddr5, %5\t\n"
            "csrw pmpaddr6, %6\t\n"
            "csrw pmpaddr7, %7\t\n"
            "csrw pmpcfg0, %8\t\n"
#if __riscv_xlen == 32
            "csrw pmpcfg1, %9\t\n"
#endif
            :
            : "r"(pmpaddr0),
              "r"(pmpaddr1),
              "r"(pmpaddr2),
              "r"(pmpaddr3),
              "r"(pmpaddr4),
              "r"(pmpaddr5),
              "r"(pmpaddr6),
              "r"(pmpaddr7),

              "r"(pmpcfg0),
              "r"(pmpcfg1)
            :
        );
    }
#endif /* configENABLE_MPU */
/*-----------------------------------------------------------*/

#if( configMTIME_BASE_ADDRESS != 0 ) && ( configMTIMECMP_BASE_ADDRESS != 0 )

	void vPortSetupTimerInterrupt( void )
	{
	uint32_t ulCurrentTimeHigh, ulCurrentTimeLow;
#ifdef __CHERI_PURE_CAPABILITY__
	volatile uint32_t * pulTimeHigh = cheri_setoffset(pvAlmightyDataCap, configMTIME_BASE_ADDRESS+4UL);
	pulTimeHigh = cheri_csetbounds((void*)pulTimeHigh, sizeof(uint32_t));
	volatile uint32_t * pulTimeLow = cheri_setoffset(pvAlmightyDataCap, configMTIME_BASE_ADDRESS);
	pulTimeLow = cheri_csetbounds((void*)pulTimeLow, sizeof(uint32_t));
	volatile uint32_t ulHartId;

		__asm volatile( "csrr %0, mhartid" : "=r"( ulHartId ) );
		pullMachineTimerCompareRegister = cheri_setoffset(pvAlmightyDataCap, ( ullMachineTimerCompareRegisterBase + ( ulHartId * sizeof( uint64_t ) )));
		pullMachineTimerCompareRegister = cheri_csetbounds((void*)pullMachineTimerCompareRegister, sizeof(uint64_t));
#else
	volatile uint32_t * const pulTimeHigh = ( volatile uint32_t * const ) ( ( configMTIME_BASE_ADDRESS ) + 4UL ); /* 8-byte typer so high 32-bit word is 4 bytes up. */
	volatile uint32_t * const pulTimeLow = ( volatile uint32_t * const ) ( configMTIME_BASE_ADDRESS );
	volatile uint32_t ulHartId;

		__asm volatile( "csrr %0, mhartid" : "=r"( ulHartId ) );
		pullMachineTimerCompareRegister  = ( volatile uint64_t * ) ( ullMachineTimerCompareRegisterBase + ( ulHartId * sizeof( uint64_t ) ) );
#endif
		do
		{
			ulCurrentTimeHigh = *pulTimeHigh;
			ulCurrentTimeLow = *pulTimeLow;
		} while( ulCurrentTimeHigh != *pulTimeHigh );

		ullNextTime = ( uint64_t ) ulCurrentTimeHigh;
		ullNextTime <<= 32ULL; /* High 4-byte word is 32-bits up. */
		ullNextTime |= ( uint64_t ) ulCurrentTimeLow;
		ullNextTime += ( uint64_t ) uxTimerIncrementsForOneTick;
		*pullMachineTimerCompareRegister = ullNextTime;

		/* Prepare the time to use after the next tick interrupt. */
		ullNextTime += ( uint64_t ) uxTimerIncrementsForOneTick;
	}

#endif /* ( configMTIME_BASE_ADDRESS != 0 ) && ( configMTIME_BASE_ADDRESS != 0 ) */
/*-----------------------------------------------------------*/

#ifdef __CHERI_PURE_CAPABILITY__
	#if ( configCHERI_COMPARTMENTALIZATION == 1 )
	void ( * pxPortCompartmentReturnTrampoline ) ( void );
	void ( * pxPortCompartmentReturnFunc ) ( BaseType_t xReturn );
	BaseType_t *pxPortCompartmentReturnData;

	static void vPortCompartmentSetup( void )
	{
	extern void ( * pxPortCompartmentGetReturnTrampoline( void ) ) ( void );
	extern void xPortCompartmentReturn( BaseType_t xReturn );
	void *pvReturnSealer;

		pxPortCompartmentReturnTrampoline = pxPortCompartmentGetReturnTrampoline();

		pvReturnSealer = cheri_setaddress( pvAlmightyDataCap, COMPARTMENT_RETURN_OTYPE );
		pxPortCompartmentReturnFunc = cheri_setaddress( pvAlmightyCodeCap, ( ptraddr_t )  xPortCompartmentReturn );
		pxPortCompartmentReturnFunc = cheri_seal( pxPortCompartmentReturnFunc, pvReturnSealer );
		pxPortCompartmentReturnData = cheri_seal( pvAlmightyDataCap, pvReturnSealer );
	}
	#endif
#endif

#if ( configENABLE_MPU == 1 )
    void vPortStoreTaskMPUSettings( xMPU_SETTINGS * xMPUSettings,
                                    const struct xMEMORY_REGION * const xRegions,
                                    StackType_t * pxBottomOfStack,
                                    uint32_t ulStackDepth )
    {
        intptr_t ulRegionStartAddress, ulRegionEndAddress, ulRegionNumber = 0;
        int32_t lIndex = 0;
        uint8_t cfg = 0;

       xMPUSettings->pmpcfg2 = 0;
#if __riscv_xlen == 32
       xMPUSettings->pmpcfg3 = 0;
#endif

        /* This function is called automatically when the task is created - in
         * which case the stack region parameters will be valid.  At all other
         * times the stack parameters will not be valid and it is assumed that
         * the stack region has already been configured. */
        if( ulStackDepth > 0 )
        {
            ulRegionStartAddress = ( uintptr_t ) pxBottomOfStack;
            ulRegionEndAddress = ( uintptr_t ) pxBottomOfStack + ( ulStackDepth * ( size_t ) sizeof( StackType_t ) ) - 1;

            /* Define the region that allows access to the stack. */
            xMPUSettings->xRegionsSettings[ 0 ].base = ulRegionStartAddress >> portMPU_REGION_ADDRESS_SHIFT;
            xMPUSettings->xRegionsSettings[ 0 ].top = ulRegionEndAddress >> portMPU_REGION_ADDRESS_SHIFT;

#if (DEBUG == 1)
            printf("PMP task region #0: <0x%x:0x%x>\n",
                   xMPUSettings->xRegionsSettings[ 0 ].top << portMPU_REGION_ADDRESS_SHIFT,
                   xMPUSettings->xRegionsSettings[ 0 ].base << portMPU_REGION_ADDRESS_SHIFT);
#endif

            xMPUSettings->pmpcfg2 = (portMPU_REGION_TOR | portMPU_REGION_READ_WRITE) << 8;
        }

        /* User supplied configurable regions. */
        for( ulRegionNumber = 1; ulRegionNumber <= portNUM_CONFIGURABLE_REGIONS; ulRegionNumber++ )
        {
            /* Only use PMP TOR mode for maximum granularity */
            cfg = portMPU_REGION_TOR;

            /* If xRegions is NULL i.e. the task has not specified any MPU
             * region, the else part ensures that all the configurable MPU
             * regions are invalidated. */
            if( ( xRegions != NULL ) && ( xRegions[ lIndex ].ulLengthInBytes > 0UL ) )
            {
                /* Translate the generic region definition contained in xRegions
                 * into the ARMv8 specific MPU settings that are then stored in
                 * xMPUSettings. */
                ulRegionStartAddress = ( ( uintptr_t ) xRegions[ lIndex ].pvBaseAddress );
                ulRegionEndAddress = ( uintptr_t ) xRegions[ lIndex ].pvBaseAddress + xRegions[ lIndex ].ulLengthInBytes - 1;

                /* Start address. */
                xMPUSettings->xRegionsSettings[ ulRegionNumber ].base = ulRegionStartAddress >> portMPU_REGION_ADDRESS_SHIFT;

                /* RO/RW. */
                if( ( xRegions[ lIndex ].ulParameters & tskMPU_REGION_READ_ONLY ) != 0 )
                {
                    cfg |= ( portMPU_REGION_READ_ONLY );
                }
                else
                {
                    cfg |= ( portMPU_REGION_READ_WRITE );
                }

                /* Execute */
                if( ( xRegions[ lIndex ].ulParameters & tskMPU_REGION_EXECUTE_NEVER ) == 0 )
                {
                    cfg |= ( portMPU_REGION_EXECUTE );
                }

                /* End Address. */
                xMPUSettings->xRegionsSettings[ ulRegionNumber ].top = ulRegionEndAddress >> portMPU_REGION_ADDRESS_SHIFT;

            }
            else
            {
                /* Invalidate the region. */
                xMPUSettings->xRegionsSettings[ ulRegionNumber ].top  = 0UL;
                xMPUSettings->xRegionsSettings[ ulRegionNumber ].base = 0UL;
                cfg = 0;
            }

           size_t shift = ((ulRegionNumber * 2) + 1) * 8;
#if __riscv_xlen == 32
           if (ulRegionNumber >= 2) {
               shift -=32;
               xMPUSettings->pmpcfg3 |= cfg << shift;
           } else {
               xMPUSettings->pmpcfg2 |= cfg << shift;
           }
#else
           xMPUSettings->pmpcfg2 |= cfg << shift;
#endif
            lIndex++;

#if (DEBUG == 1)
            printf("PMP task region #%d: <0x%x:0x%x>\n", ulRegionNumber,
                   xMPUSettings->xRegionsSettings[ ulRegionNumber ].top << portMPU_REGION_ADDRESS_SHIFT,
                   xMPUSettings->xRegionsSettings[ ulRegionNumber ].base << portMPU_REGION_ADDRESS_SHIFT);
#endif
        }
    }
#endif /* configENABLE_MPU */
/*-----------------------------------------------------------*/

BaseType_t xPortStartScheduler( void )
{
extern void xPortStartFirstTask( void );

	#if( configASSERT_DEFINED == 1 )
	{
		volatile uint32_t mtvec = 0;

		/* Check the least significant two bits of mtvec are 00 - indicating
		single vector mode. */
		__asm volatile( "csrr %0, mtvec" : "=r"( mtvec ) );
		configASSERT( ( mtvec & 0x03UL ) == 0 );

		/* Check alignment of the interrupt stack - which is the same as the
		stack that was being used by main() prior to the scheduler being
		started. */
		configASSERT( ( (size_t)xISRStackTop & portBYTE_ALIGNMENT_MASK ) == 0 );

		#ifdef configISR_STACK_SIZE_WORDS
		{
			memset( (size_t)xISRStack, portISR_STACK_FILL_BYTE, sizeof( xISRStack ) );
		}
		#endif	 /* configISR_STACK_SIZE_WORDS */
	}
	#endif /* configASSERT_DEFINED */

    #if ( configENABLE_MPU == 1 && configMPU_COMPARTMENTALIZATION == 0 )
        {
            /* Setup the Memory Protection Unit (MPU). */
            prvSetupMPU();
        }
    #endif /* configENABLE_MPU */

	/* If there is a CLINT then it is ok to use the default implementation
	in this file, otherwise vPortSetupTimerInterrupt() must be implemented to
	configure whichever clock is to be used to generate the tick interrupt. */
	vPortSetupTimerInterrupt();

	#if( ( configMTIME_BASE_ADDRESS != 0 ) && ( configMTIMECMP_BASE_ADDRESS != 0 ) )
	{
		/* Enable mtime and external interrupts.  1<<7 for timer interrupt, 1<<11
		for external interrupt.  _RB_ What happens here when mtime is not present as
		with pulpino? */
		__asm volatile( "csrs mie, %0" :: "r"(0x880) );
	}
	#else
	{
		/* Enable external interrupts. */
		__asm volatile( "csrs mie, %0" :: "r"(0x800) );
	}
	#endif /* ( configMTIME_BASE_ADDRESS != 0 ) && ( configMTIMECMP_BASE_ADDRESS != 0 ) */

	xPortStartFirstTask();

	/* Should not get here as after calling xPortStartFirstTask() only tasks
	should be executing. */
	return pdFAIL;
}
/*-----------------------------------------------------------*/

void vPortEndScheduler( void )
{
	/* Not implemented. */
	for( ;; );
}





