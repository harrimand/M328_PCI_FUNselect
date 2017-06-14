;M328 ADC Recorder
 
.nolist
.include "m328pdef.inc"
.list
 
.def	TEMP = R16
.def	ADCin = R24
.def	ButtonInput = R18
.def	DBcount = R17

.equ	SamplePer = 48
.equ	ADCwriteAdd = SRAM_START + $10
.equ	ADCreadAdd = SRAM_START + $12
.equ	ADCtable = SRAM_START + $20
.equ	ADCtableEnd = $07FF
.equ	PWmin = 800

.ORG	$0000
		rjmp	RESET
.ORG	INT0addr
		rjmp	Record
.ORG	INT1addr
		rjmp	Play
.ORG	OC0Aaddr
		reti
.ORG	OVF0addr
		rjmp	PlayNextValue
.ORG	ADCCaddr
		rjmp	ADCcomplete
.ORG	INT_VECTORS_SIZE

RESET:
		ldi 	TEMP, high(RAMEND)
		out 	SPH, TEMP
		ldi 	TEMP, low(RAMEND)
		out 	SPL, TEMP
		
		ldi 	YH, high(ADCwriteAdd)
		ldi 	YL, low(ADCwriteAdd)
		ldi 	TEMP, low(ADCtable)
		st  	Y+, TEMP
		ldi 	TEMP, high(ADCtable)
		st  	Y, TEMP

		sbi 	DDRB, PB0	;Record Indicator
		sbi 	PORTD, PD2	;INT0 Record Start/Stop
		sbi 	PORTD, PD3	;INT1 Play Start/Stop
		
		ldi  	TEMP, (1<<ISC11)|(1<<ISC01)
		sts 	EICRA, TEMP

		sbi 	EIMSK, INT0
		sbi 	EIMSK, INT1	

		ldi 	TEMP, (1<<REFS1)|(1<<ADLAR)
		sts 	ADMUX, TEMP
 
		ldi 	TEMP, (1<<ADTS1)|(1<<ADTS0)
		sts 	ADCSRB, TEMP
 
;		ldi 	TEMP, (1<<ADEN)|(1<<ADATE)|(1<<ADIE)|(1<<ADPS1)|(1<<ADPS0)
;		sts 	ADCSRA, TEMP
 
		ldi 	TEMP, SamplePer
		out 	OCR0A, TEMP
 
		ldi 	TEMP, (1<<WGM02)|(1<<WGM01)|(1<<WGM00)
		out 	TCCR0A, TEMP

		ldi 	TEMP, (1<<OCIE0A)|(0<<TOIE0)
		sts 	TIMSK0, TEMP

;		ldi 	TEMP, (1<<WGM02)|(1<<CS02)|(0<<CS01)|(1<<CS00)
;		out 	TCCR0B, TEMP
 
		sei
 
MAIN:
		nop
		nop
		nop
		nop
		rjmp	MAIN
;------------------------------------------------------------------------------
ADCcomplete:	;ADC Start triggered by TO Overflow  OCR0A = TOP
		lds  	ADCin, ADCH
		ldi 	YH, high(ADCwriteAdd)
		ldi 	YL, low(ADCwriteAdd)
		ld  	XL, Y+
		ld  	XH, Y
		ldi 	TEMP, low(ADCtableEnd)
		cp  	XL, TEMP
		ldi 	TEMP, high(ADCtableEnd)
		cpc 	XH, TEMP
		breq	RecordFull
		andi	XH, $07
		st  	X+, ADCin
		st  	Y, XH
		st  	-Y, XL
		nop
		reti

RecordFull:
		clr 	TEMP
		out 	TCCR0B, TEMP	;Stop T0
		ldi 	TEMP, (0<<ADEN)|(0<<ADATE)|(0<<ADIE)|(1<<ADPS1)|(1<<ADPS0)
		sts 	ADCSRA, TEMP	;Stop ADC
		ldi 	YH, high(ADCwriteAdd)
		ldi 	YL, low(ADCwriteAdd)
		ldi 	TEMP, low(ADCtable)
		st  	Y+, TEMP
		ldi 	TEMP, high(ADCtable)
		st  	Y, TEMP		;Reset ADCwriteAdd to ADCtable begin
		reti

;------------------------------------------------------------------------------
Record:	;INT0 isr   Enable ADC and start T0
		rcall	DBint
		sbic	GPIOR0, 0
		rjmp	StopRecord
		ldi 	TEMP, (1<<ADEN)|(1<<ADATE)|(1<<ADIE)|(1<<ADPS1)|(1<<ADPS0)
		sts 	ADCSRA, TEMP
		ldi 	TEMP, (1<<WGM02)|(1<<CS02)|(0<<CS01)|(1<<CS00)
		out 	TCCR0B, TEMP

		sbi 	PORTB, PB0	;Record Indicator On
		sbi 	GPIOR0, 0
		reti
StopRecord:
		clr 	TEMP
		out 	TCCR0B, TEMP	;Stop T0
		cbi 	PORTB, PB0	;Record Indicator Off
		cbi 	GPIOR0, 0
		reti		


;------------------------------------------------------------------------------
;Get ADC data table index stored in SRAM at ADCreadAdd
;Enable OVF0 interrupt and Start T0 

Play:	;INT1 isr  
		rcall	DBint
		sbic	GPIOR0, 1
		rjmp	StopPlay

		lds 	XH, high(ADCreadAdd)
		lds 	XL, low(ADCreadAdd)

		lds 	YH, high(ADCwriteAdd)
		lds 	YL, low(ADCwriteAdd)

		cp  	YL, XL
		cpc 	YH, XH
		breq	StopPlay
		ldi 	TEMP, low(ADCtableEnd)
		cp  	XL, TEMP
		ldi 	TEMP, high(ADCtableEnd)
		cpc 	XH, TEMP
		breq	StopPlay		

		cbi 	EIMSK, INT0
		ldi 	TEMP, (1<<TOIE0)
		sts 	TIMSK0, TEMP	

		ldi 	TEMP, (1<<WGM02)|(1<<CS02)|(0<<CS01)|(1<<CS00)
		out 	TCCR0B, TEMP		
		sbi 	GPIOR0, 1
		reti			
StopPlay:
		;Enable OCIE1A  OCIE1A function stops T1 clock after OC1A Pin goes Low
		;    and disables OCIE1A for one time event.
		;Stop T0 clock 
		lds 	YH, high(ADCreadAdd)
		lds 	YL, low(ADCreadAdd)
		sbi 	EIMSK, INT0
		reti

;------------------------------------------------------------------------------
;Check if at end of written data or end of table
;Read ADC Data, Multiply by 6 and output to OCR1A
PlayNextValue:

;TODO  Read values and write to OCR1A
		ld  	ADCin, X+
		ldi 	TEMP, $06
		mul 	ADCin, TEMP
		ldi 	TEMP, low(PWmin)
		add 	R0, TEMP
		ldi 	TEMP, high(PWmin)
		adc 	R1, TEMP
		sts 	OCR1AH, R1
		sts 	OCR1AL, R0

		reti

;------------------------------------------------------------------------------
DBint:
		ldi 	DBcount, $50
		in  	ButtonInput, PIND
		andi	ButtonInput, $C0
NextRead:
		in  	TEMP, PIND
		andi	TEMP, $C0
		cp  	TEMP, ButtonInput
		brne	DBint
		dec 	DBcount
		brne	NextRead
		sbi 	EIFR, INTF0
		ret






		
