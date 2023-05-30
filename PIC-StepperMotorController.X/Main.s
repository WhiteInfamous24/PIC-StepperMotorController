#include "xc.inc"

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; starting position of the program < -pRESET_VECT=0h >
psect RESET_VECT, class=CODE, delta=2
RESET_VECT:
    GOTO    setup

; memory location to go when a interrupt happens < -pINT_VECT=4h >
psect INT_VECT, class=CODE, delta=2
INT_VECT:
    
    ; save context
    MOVWF   W_TMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TMP
    
    ; keyboard interruption
    BTFSC   INTCON, 0		; check RBIF bit
    CALL    keyboardISR
    
    ; TMR0 interruption
    BTFSC   INTCON, 2		; check T0IF bit
    CALL    TMR0ISR
    
    ; return previous context
    SWAPF   STATUS_TMP, W
    MOVWF   STATUS
    SWAPF   W_TMP, F
    SWAPF   W_TMP, W
    RETFIE

; program variables
W_TMP		EQU 0x20
STATUS_TMP	EQU 0x21
TMR0_CNTR	EQU 0x22

; keyboard
KYBRD_BTN	EQU 0x23
KYBRD_FND_F	EQU 0x24

; stepper motor
STPR_MOTOR	EQU 0x25
TMR0_CNTR_REF	EQU 0x26

; program setup
setup:
    
    ; PORTB configuration
    BANKSEL TRISB
    MOVLW   0b00001111		; set <RB0:RB3> PORTB pins as inputs to control keyboard -rows-
    MOVWF   TRISB
    BANKSEL ANSELH
    CLRF    ANSELH		; set PORTB as digital
    
    ; PORTC configuration
    BANKSEL TRISC
    MOVLW   0b00000000		; set <RC0:RC7> PORTC pins as outputs to control LEDs and stepper motors
    MOVWF   TRISC
    
    ; PORTD configuration
    BANKSEL TRISD
    MOVLW   0b00000000		; set <RD4:RD7> PORTD pins as outputs to control keyboard -columns-
    MOVWF   TRISD
    
    ; general port configuration
    BANKSEL OPTION_REG		; enable global pull-ups and set pre-scaler (100) 
    MOVLW   0b00000100		; | /RBPU | INTEDG | T0CS | T0SE | PSA | PS2 | PS1 | PS0 |
    MOVWF   OPTION_REG
    BANKSEL WPUB
    MOVLW   0b00001111		; enable pull-ups in <RB0:RB3> pins
    MOVWF   WPUB
    
    ; interruption configuration
    BANKSEL INTCON		; enable global interruptions and interruptions in PORTB
    MOVLW   0b10111000		; | GIE | PEIE | T0IE | INTE | RBIE | T0IF | INTF | RBIF |
    MOVWF   INTCON
    BANKSEL IOCB
    MOVLW   0b00001111		; enable interruptions in <RB0:RB3> pins
    MOVWF   IOCB
    
    ; TMR0 initialization
    BANKSEL TMR0
    CLRF    TMR0
    
    ; PORTB initialization
    BANKSEL PORTB
    MOVLW   0b00000000
    MOVWF   PORTB
    
    ; PORTC initialization
    BANKSEL PORTC
    MOVLW   0b00000000
    MOVWF   PORTC
    
    ; PORTD initialization
    BANKSEL PORTD
    MOVLW   0b00000000
    MOVWF   PORTD
    
    ; variables initialization
    CLRF    TMR0_CNTR
    CLRF    KYBRD_BTN
    CLRF    KYBRD_FND_F
    CLRF    STPR_MOTOR

; main program loop
main:
    
    ; show pressed button
    CALL    moveStepperMotor
    
    GOTO    main
    
; interruption subroutine to control TMR0
TMR0ISR:
    BANKSEL TMR0
    CLRF    TMR0		; reset TMR0
    INCF    TMR0_CNTR, F	; increment TMR0 counter variable
    CALL    blinkRD0
    BCF	    INTCON, 2		; clear T0IF bit
    RETURN

; blink LED
blinkRD0:
    BANKSEL PORTD
    BTFSS   PORTD, 0
    GOTO    setRD0
    GOTO    clearRD0
    
    ; turn on LED
    setRD0:
	BSF	    PORTD, 0
	RETURN

    ; turn off LED
    clearRD0:
	BCF	    PORTD, 0
	RETURN

; interruption subroutine to get pressed button in keyboard
keyboardISR:
    
    ; select memory bank 0 <00>
    BCF	    STATUS, 5		; clear RP0 bit
    BCF	    STATUS, 6		; clear RP1 bit
    
    ; clear previous pressed button and found flag
    CLRF    KYBRD_BTN
    CLRF    KYBRD_FND_F
    
    ; search in column 0
    BCF	    PORTD, 4		; active only column 0
    BSF	    PORTD, 5
    BSF	    PORTD, 6
    BSF	    PORTD, 7
    MOVLW   0b00000001		; save current column
    MOVWF   KYBRD_BTN
    CALL    searchInRow		; find if the row is found with the current column
    BTFSC   KYBRD_FND_F, 0	; if the keyboard found flag is set return
    GOTO    returnFromKeyboard
    
    ; search in column 1
    BSF	    PORTD, 4
    BCF	    PORTD, 5		; active only column 1
    BSF	    PORTD, 6
    BSF	    PORTD, 7
    MOVLW   0b00000010		; save current column
    MOVWF   KYBRD_BTN
    CALL    searchInRow		; find if the row is found with the current column
    BTFSC   KYBRD_FND_F, 0	; if the keyboard found flag is set return
    GOTO    returnFromKeyboard
    
    ; search in column 2
    BSF	    PORTD, 4
    BSF	    PORTD, 5
    BCF	    PORTD, 6		; active only column 2
    BSF	    PORTD, 7
    MOVLW   0b00000100		; save current column
    MOVWF   KYBRD_BTN
    CALL    searchInRow		; find if the row is found with the current column
    BTFSC   KYBRD_FND_F, 0	; if the keyboard found flag is set return
    GOTO    returnFromKeyboard
    
    ; search in column 3
    BSF	    PORTD, 4
    BSF	    PORTD, 5
    BSF	    PORTD, 6
    BCF	    PORTD, 7		; active only column 3
    MOVLW   0b00001000		; save current column
    MOVWF   KYBRD_BTN
    CALL    searchInRow		; find if the row is found with the current column
    BTFSC   KYBRD_FND_F, 0	; if the keyboard found flag is set, return
    GOTO    returnFromKeyboard
    
    ; case if there is no match
    CLRF    KYBRD_BTN
    
    ; return from getKeyboard subroutine
    returnFromKeyboard:
	CLRF	PORTD
	BCF	INTCON, 1	; clear INTF bit
	BCF	INTCON, 0	; clear RBIF bit
	RETURN
    
; subroutine to find if there are any set bits in the row
searchInRow:
    BTFSS   PORTB, 0
    GOTO    setRow_0
    BTFSS   PORTB, 1
    GOTO    setRow_1
    BTFSS   PORTB, 2
    GOTO    setRow_2
    BTFSS   PORTB, 3
    GOTO    setRow_3
    RETURN
    setRow_0:
	BSF	KYBRD_BTN, 4
	BSF	KYBRD_FND_F, 0
	RETURN
    setRow_1:
	BSF	KYBRD_BTN, 5
	BSF	KYBRD_FND_F, 0
	RETURN
    setRow_2:
	BSF	KYBRD_BTN, 6
	BSF	KYBRD_FND_F, 0
	RETURN
    setRow_3:
	BSF	KYBRD_BTN, 7
	BSF	KYBRD_FND_F, 0
	RETURN
    
; subroutine to control the stepper motor on/off and direction
moveStepperMotor:
    CALL    keyboardToValueConverter
    BANKSEL PORTC
    CLRF    PORTC
    
    ; check if the pressed button equals 0x05
    MOVF    STPR_MOTOR, W
    SUBLW   0x05
    BTFSC   STATUS, 2
    GOTO    rotateUp
    
    ; check if the pressed button equals 0x06
    MOVF    STPR_MOTOR, W
    SUBLW   0x06
    BTFSC   STATUS, 2
    GOTO    rotateDown
    
    ; if the pressed button is other
    GOTO    stopRotation
    
    ; rotate one step up
    rotateUp:
	BSF	PORTC, 0	; set direction in HIGH
	CALL	getDelay
	BSF	PORTC, 1	; set pulse in HIGH
	CALL	getDelay
	BCF	PORTC, 1	; set pulse in LOW
	RETURN
    
    ; rotate one step down
    rotateDown:
	BCF	PORTC, 0	; set direction in LOW
	CALL	getDelay
	BSF	PORTC, 1	; set pulse in HIGH
	CALL	getDelay
	BCF	PORTC, 1	; set pulse in LOW
	RETURN
    
    ; no rotation
    stopRotation:
	BCF	PORTC, 0	; set direction in LOW
	CALL	getDelay
	BCF	PORTC, 1	; set pulse in LOW
	CALL	getDelay
	RETURN

; subroutine to make a delay
getDelay:
    
    ; set the reference value of TMR0
    MOVF    TMR0_CNTR, W
    MOVWF   TMR0_CNTR_REF
    
    ; compare the actual TMR0 counter with the reference to make a pulse
    MOVF    TMR0_CNTR, W
    SUBWF   TMR0_CNTR_REF, W
    BTFSC   STATUS, 2
    GOTO    $-3
    RETURN
    
; subroutine to convert a value in W by performing additions based on bit positions
keyboardToValueConverter:
    
    ; select memory bank 0 <00>
    BCF	    STATUS, 5		; clear RP0 bit
    BCF	    STATUS, 6		; clear RP1 bit
    
    ; clear W
    CLRW
    
    ; add bit 7 (accumulator + 0)
    BTFSS   KYBRD_BTN, 7
    GOTO    addBit_6
    ADDLW   0x00		; value to add
    
    ; add bit 6 (accumulator + 1)
    addBit_6:
	BTFSS   KYBRD_BTN, 6
	GOTO    addBit_5
	ADDLW   0x01		; value to add

    ; add bit 5 (accumulator + 2)
    addBit_5:
	BTFSS   KYBRD_BTN, 5
	GOTO    addBit_4
	ADDLW   0x02		; value to add
	
    ; add bit 4 (accumulator + 3)
    addBit_4:
	BTFSS   KYBRD_BTN, 4
	GOTO    addBit_3
	ADDLW   0x03		; value to add
	
    ; add bit 3 (accumulator + 0)
    addBit_3:
	BTFSS   KYBRD_BTN, 3
	GOTO    addBit_2
	ADDLW   0x00		; value to add
	
    ; add bit 2 (accumulator + 4)
    addBit_2:
	BTFSS   KYBRD_BTN, 2
	GOTO    addBit_1
	ADDLW   0x04		; value to add
	
    ; add bit 1 (accumulator + 8)
    addBit_1:
	BTFSS   KYBRD_BTN, 1
	GOTO    addBit_0
	ADDLW   0x08		; value to add
	
    ; add bit 0 (accumulator + 12)
    addBit_0:
	BTFSS   KYBRD_BTN, 0
	GOTO    addNULL
	ADDLW   0x0C		; value to add

    ; add null
    addNULL:
	MOVWF	STPR_MOTOR
	RETURN
	
END RESET_VECT