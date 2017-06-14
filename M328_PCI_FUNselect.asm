
;	Darrell Harriman  harrimand@gmail.com   05/08/2017
;
;Example Program to demonstrate KEYpad decoding using Pin Change Interrupt 
;4 input connections for KEYpad rows on PINC 3..0
;3 input connections for KEYpad columns on PINB 2..0
;4 Outputs to LEDs  Bits 3..0 on PB7, PB6, PC5, PC4
;Copy table of function addresses from FLASH to SRAM
;Configure Output Pins, Input Pins and Pull-Up Resistors
;Pin change interrupt enabled on button pins PC3..0
;Enable Sleep Mode (Sleep instruction in MAIN)
;
;Each button selects a different function that outputs to PB7..6 and PC5..4.
;
;Pin Change Interrupt ISR
;	Debounce Button input pins
;
;	If no button pressed when interrupt triggered, return without executing 
;        function
;
;	Using LSR to shift bits into carry.  Increment Shift Counter.  Test cary 
;        and if not low repeat LSR
;
;	When Carry Flag is Low the button position is found.  Adjust counter so
;         range is 0 -> Number of buttons  (Counter - 1) 
;
;	Shift Counter Left (Double) to get Word Offset and add to Function 
;        Address Base in XL
;
;	Load Address Low and High byte from Function Address table to ZL and ZH
;
;	Use ICALL instruction to go to function at program address in Z
;
/*  KeyPad details:  http://www.robotshop.com/en/sfe-keypad-12-button.html
    Button Presses connect Rows and Columns with about 90 Ohms resistance

    MCU     KEYpad
    pin      pin
                    /---------------\
                    |               |
    PC0     2       |   1   2   3   |
                    |               |               
    PC1     7       |   4   5   6   |
                    |               |
    PC2     6       |   7   8   9   |
                    |               |
    PC3     4       |   *   0   #   |
                    |               |
                    \---------------/
                      |___________|
                        3   1   5
                       PB0 PB1 PB2
*/

.nolist
.include "m328pdef.inc"
.list

.def	TEMP = R16
.def	Buttons = R17
.def	DBcounter = R18
.def	KEY = R20

.equ	FUNaddBase = SRAM_START + $10
.equ	DBcount = $32

.ORG	$0000
        rjmp	RESET
.ORG	PCI1addr
        rjmp	PINchgISR
.ORG	INT_VECTORS_SIZE

RESET:
        ldi 	TEMP, high(RAMEND)
        out 	SPH, TEMP
        ldi 	TEMP, low(RAMEND)
        out 	SPL, TEMP

;------------------------------------------------------------------------------
//Copy Function Address Table to SRAM
        ldi 	ZH,  high(FUNtable << 1) ;Program Memory Word Address
        ldi 	ZL,  low(FUNtable << 1)  ;   Converted to Byte Address

        ldi 	XH, high(FUNaddBase)	;Sram Memory Address
        ldi 	Xl, low(FUNaddBase)

        ldi 	YH,  high(FUNtableEnd << 1) ;Table End Address to compare with
        ldi 	YL,  low(FUNtableEnd << 1)  ;Z so we know when we reach the end
CopyTable:
        lpm 	TEMP, Z+
        st  	X+, TEMP
        cp  	ZL, YL
        cpc 	ZH, YH
        brne	CopyTable

;------------------------------------------------------------------------------
        ldi 	TEMP, (1<<PB7)|(1<<PB6)|(1<<PB2)|(1<<PB1)|(1<<PB0)
        out 	DDRB, TEMP	   ;LED 3..2 out, KEY Column pins

        ldi 	TEMP, (1<<PORTC5)|(1<<PORTC4)	
        out 	DDRC, TEMP        ;LED 1..0 out

        ldi 	TEMP, $0F
        out 	PORTC, TEMP        ;Enable Pull-Up Resistors

        ldi 	TEMP, (1<<PCINT11)|(1<<PCINT10)|(1<<PCINT9)|(1<<PCINT8)
        sts 	PCMSK1, TEMP	;Mask to enable interrupts on pins PINC 3..0

        ldi 	TEMP, (1<<PCIE1)	;PORTC Pin Change Interrupt Enabled
        sts 	PCICR, TEMP

        ldi 	TEMP, (0<<SM2)|(0<<SM1)|(0<<SM0)|(1<<SE)
        out 	SMCR, TEMP	;Sleep Mode 0 (Idle) enabled.

        sei

;------------------------------------------------------------------------------
MAIN:
        nop
        nop
        sleep
        nop
        rjmp	MAIN

;------------------------------------------------------------------------------
PINchgISR:
        push	TEMP
        push	BUTTONS
        push	KEY
        push	XH
        push	XL
        push	ZH
        push	ZL

//Check to see if No buttons pressed.
        rcall	DBbuttons	;Call Debounce Function
        in  	BUTTONS, PINC	;Read Button input pins
        andi	BUTTONS, $0F	;Mask out untested bits
        ldi 	TEMP, $0F
        eor 	TEMP, BUTTONS	;1 XOR 1 = 0 
        breq	RETURN        ;Return if no buttons pressed

//If Button pressed, Do This
        clr 	TEMP
ChkButton:
        inc 	TEMP        	;Count Shifts
        lsr 	BUTTONS        	;Shift to set or clear Carry Flag
        brcs	ChkButton        ;Check Cary.  If Clear Button Press Found
        dec 	TEMP        	;Adjust counter to start at 0
        ldi 	KEY, $03
        mul 	KEY, TEMP
        mov 	KEY, R0
        rcall	COLinit
        in  	BUTTONS, PINB
        andi	BUTTONS, (1<<PB2)|(1<<PB1)|(1<<PB0)
        clr 	TEMP
ChkColumn:
        inc 	TEMP
        lsr 	BUTTONS
        brcs	ChkColumn
        dec 	TEMP
        add 	KEY, TEMP
        ldi 	XH, high(FUNaddBase) ;Load Base Address for Function table
        ldi  	Xl, low(FUNaddBase)
        lsl 	KEY         	;Shift Byte for Word Address
        add 	XL, KEY        ;Add Word Offset to Base Address
        ld  	ZL, X+	;Load Function Address into Z
        ld  	ZH, X
        icall        	;Call Function pointed to by Z
        rcall	ROWinit
        sbi 	PCIFR, PCIF1	;Clear Pending PinChange INT Flags.
RETURN:
        pop 	ZL
        pop 	ZH
        pop 	XL
        pop 	XH
        pop 	KEY
        pop 	BUTTONS
        pop 	TEMP
        reti

;------------------------------------------------------------------------------
ROWinit:	;Configure Pins for KEYpad to test Rows
        ldi 	TEMP, (1<<PC5)|(1<<PC4)|(0<<PC3)|(0<<PC2)|(0<<PC1)|(0<<PC0)
        out 	DDRC, TEMP        ;LED Output PORTC 5,4 Inputs 3..0
        
        in  	TEMP, DDRB
        ori 	TEMP, (1<<PB2)|(1<<PB1)|(1<<PB0)
        out 	DDRB, TEMP	;PORTB 2..0 Output Pins

        cbi 	PORTB, PB2	;PORTB 2..0 Output Low
        cbi 	PORTB, PB1
        cbi 	PORTB, PB0
        
        in  	TEMP, PINC
        ori 	TEMP, (1<<PC3)|(1<<PC2)|(1<<PC1)|(1<<PC0)
        out 	PORTC, TEMP        ;Enable Pull-Up Resistors
        ret

;------------------------------------------------------------------------------
COLinit:	;Configure Pins for KEYpad to test Columns
        ldi 	TEMP, (1<<PC5)|(1<<PC4)|(1<<PC3)|(1<<PC2)|(1<<PC1)|(1<<PC0)
        out 	DDRC, TEMP	;PORTC 5,4,3..0 output

        in      TEMP, PINC
        andi	TEMP, $F0
        out 	PORTC, TEMP        ;PORTC 3..0 Output Low

        in  	TEMP, DDRB
        andi	TEMP, $F8        ;PORTB 2..0 Input
        out 	DDRB, TEMP

        in  	TEMP, PINB
        ori 	TEMP, (1<<PB2)|(1<<PB1)|(1<<PB0)
        out 	PORTB, TEMP        ;PORTB 2..0 Enable Pull-Ups
        nop
//For Simulation make PB2..0 High Except selected column pin.
        ret

;------------------------------------------------------------------------------
DBbuttons:	;Debounce PORTC 3..0
        push	TEMP
        push	DBcounter
        push	BUTTONS
STARTcount:
        in  	TEMP, PINC	;First Read initial value to compare
        andi	TEMP, $0F	;Mask out untested bits
        ldi 	DBcounter, DBcount
NEXTread:
        in  	BUTTONS, PINC	;Read for comparison
        andi	BUTTONS, $0F
        cp  	BUTTONS, TEMP	;Compare with first read
        brne	STARTcount		;If not equal restart counter
        dec 	DBcounter		;Count matching read values
        brne	NEXTread
        pop 	BUTTONS
        pop 	DBcounter
        pop 	TEMP
        ret

;------------------------------------------------------------------------------
DBend:                 ;Not Required. Moving functions somewhere else in memory
.ORG	DBend + $40
;Test Functions selected by Z with ICALL instruction
; Bits 3..0 on PB7, PB6, PC5, PC4

ONE:	;Output 0001
        cbi 	PORTB, PB7
        cbi 	PORTB, PB6
        cbi 	PORTC, PC5
        sbi 	PORTC, PC4
        ret
TWO:	;Output 0010
        cbi 	PORTB, PB7
        cbi 	PORTB, PB6
        sbi 	PORTC, PC5
        cbi 	PORTC, PC4
        ret
THREE:	;Output 0011
        cbi 	PORTB, PB7
        cbi 	PORTB, PB6
        sbi 	PORTC, PC5
        sbi 	PORTC, PC4
        ret
FOUR:	;Output 0100
        cbi 	PORTB, PB7
        sbi 	PORTB, PB6
        cbi 	PORTC, PC5
        cbi 	PORTC, PC4
        ret
FIVE:	;Output 0101
        cbi 	PORTB, PB7
        sbi 	PORTB, PB6
        cbi 	PORTC, PC5
        sbi 	PORTC, PC4
        ret
SIX:	;Output 0110
        cbi 	PORTB, PB7
        sbi 	PORTB, PB6
        sbi 	PORTC, PC5
        cbi 	PORTC, PC4
        ret
SEVEN:	;Output 0111
        cbi 	PORTB, PB7
        sbi 	PORTB, PB6
        sbi 	PORTC, PC5
        sbi 	PORTC, PC4
        ret
EIGHT:	;Output 1000
        sbi 	PORTB, PB7
        cbi 	PORTB, PB6
        cbi 	PORTC, PC5
        cbi 	PORTC, PC4
        ret
NINE:	;Output 1001
        sbi 	PORTB, PB7
        cbi 	PORTB, PB6
        cbi 	PORTC, PC5
        sbi 	PORTC, PC4
        ret
STAR:	;Output 1010
        sbi 	PORTB, PB7
        cbi 	PORTB, PB6
        sbi 	PORTC, PC5
        cbi 	PORTC, PC4
        ret
ZERO:	;Output 0000
        cbi 	PORTB, PB7
        cbi 	PORTB, PB6
        cbi 	PORTC, PC5
        cbi 	PORTC, PC4
        ret
HASH:	;Output 1111
        sbi 	PORTB, PB7
        sbi 	PORTB, PB6
        sbi 	PORTC, PC5
        sbi 	PORTC, PC4
        ret

PROGend:

;Table of Function Address Words
.ORG	PROGend + $20
FUNtable:
.dw 	ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN
.dw 	EIGHT, NINE, STAR, ZERO, HASH
FUNtableEnd:


/*  KeyPad details:  http://www.robotshop.com/en/sfe-keypad-12-button.html
    Button Presses connect Rows and Columns with about 90 Ohms resistance

    MCU     KEYpad
    pin      pin
                    /---------------\
                    |               |
    PC0     2       |   1   2   3   |
                    |               |               
    PC1     7       |   4   5   6   |
                    |               |
    PC2     6       |   7   8   9   |
                    |               |
    PC3     4       |   *   0   #   |
                    |               |
                    \---------------/
                      |___________|
                        3   1   5
                       PB0 PB1 PB2
*/
