# ECEN 2360 Project 2b: Stopwatch
# Matthew Gorbold McCardle
# choosen option 3b

.section .reset, "ax" 	
.global _start
.equ O_UART_DATA, 	0x1000
.equ O_UART_CTRL, 	0x1004
.equ O_7SEG_LO, 	0x20
.equ O_7SEG_HI, 	0x30
.equ BTN1_HI_BTN0_LO,	0b10
.equ BTN1_HI_BTN0_HI,	0b11
.equ BTN1_LO_BTN0_HI, 	0b01

_start:
	movia 	sp, 0x01000000 			# 16MB stack
	movia 	gp, 0xff200000 			# MMIO base address
	br 		main
	
.section .exceptions, "ax" 

	rdctl	et, ipending
	bne		et, r0, ISR
	eret

.text

ISR:
	subi	ea, ea, 4				# Rewind to restart cancelled instruction
	subi 	sp, sp, 20				# prologue
	stw		r2, 0(sp)				# stores r2, r3, r4, ra on stack
	stw		r3, 4(sp)
	stw		r4, 8(sp)
	stw		ra, 12(sp)
	stw		r21, 16(sp)
	
	andi	r2, et, BTN1_HI_BTN0_LO	# if (IRQ1) {
	beq		r2, r0, NotIRQ1
	
	#### Handle pushbutton ISR for IRQ#0 ####
	ldwio	r3, 0x5c(gp)			# Read edgecapture register
	stwio	r3, 0x5c(gp)			# reset edgecaputre bits: deassert IRQ
	
	andi	r2, r3, BTN1_LO_BTN0_HI
	beq		r2, r0, NotButton0		#	if (Button0) {
	
	ldw		r2, Pause(r0)			# 		Button0: stop/start
	xori	r2, r2, 0x1
	stw		r2, Pause(r0)
	br		B1_NotButton1
NotButton0:							# } else {
	andi	r2, et, BTN1_HI_BTN0_LO
	beq		r3, r0, B1_NotButton1			# Button1: stop/start
	
	ldw		r2, Pause(r0)			#	if (Pause) { // Reset
	beq		r2, r0, B1_NotPaused
	
	stw		r0, Frozen(r0)			# Frozen = 0;
	stw 	r0, Hund(r0)			# Hund = 0;
	br		B1_NotButton1
B1_NotPaused:						# 	} else {  // Lap
	ldw		r2, Frozen(r0)
	xori	r2, r2, 0x1
	stw		r2, Frozen(r0)
	beq		r2, r0, B1_NoLapReport
	
	movi	r2, 1
	stw		r2, LapFlag(r0)			#		LapFlag = 1;
B1_NoLapReport:	
	
B1_NotButton1: 					# }
NotIRQ1:    ####------------- IRQ0 ---------------------
	andi	r2, et, BTN1_LO_BTN0_HI	# if (IRQ0) {
	beq		r2, r0, NotIRQ0
	
	stwio	r0, 0x2000(gp)			#		Silence Timeout interrupt
	
	ldw		r2, Pause(r0)
	bne		r2, r0, NotRunning		#	if (Running) {
	ldw		r2, Hund(r0)
	addi	r2, r2, 1				#		time++;
	stw		r2, Hund(r0)
	
NotRunning:							# 	}
NotIRQ0:							# }

ISR_END:
	ldw		r2, 0(sp)				# epilogue: restore all used registers
	ldw		r3, 4(sp)
	ldw		r4, 8(sp)
	ldw		ra, 12(sp)
	ldw		r21, 16(sp)
	addi	sp, sp, 20
	eret
	

main:
	#### interrupt setup ####
	movi	r2, BTN1_HI_BTN0_HI		# both button 0 & 1 generate IRQ#1
	stwio 	r2, 0x58(gp)			# pushbutton ppi interrupt mask
	
	movia	r2, 1000000				# 100MHz / 1M = 100Hz
	stwio	r2, 0x2008(gp)			# Counter start value (low 16 bits)
	srli	r2, r2, 16
	stwio	r2, 0x200c(gp)			# Counter start value (high 16 bits)
	movi	r2, 0b0111				# START | CONT | ITO
	stwio	r2, 0x2004(gp)
	
	movi	r2, 0b11
	wrctl	ienable, r2				# ienable <- 2
	
	movi	r2, 1					# statius.PIE - 1
	wrctl	status, r2
	#########################
	
    movia   r4, Greeting1       	# Print initial greeting message
    call    puts

    movi    r4, '\n'           		# Print newline
    call    putchar

 	mov     r4, r0             		# Reset all registers to 0
    mov     r19, r0            		# r19 = elapsed time on stopwatch
    mov     r20, r0            		# r20 = stopwatch running state (0: stopped, 1: running)
    mov     r21, r0            		# r21 = pause (0: active, 1: paused)
    movi    r22, Pause            	# r22 = state of button 0 (stop/start switch)
    movi    r23, Frozen            	# r23 = state of button 1 (display updating)
    call    segTime            		# Update displayed time to 00:00:00

main_loop:
#call    delay10ms           		# Small delay for button polling stability
	# Check for LapFlag
	ldw		r2, LapFlag(r0)
	beq		r2, r0, NoLapReport
	stw		r0, LapFlag(r0)
	
	movia	r4, Laptime				# print laptime:
	call	puts
	
	ldw		r4, Mins(r0)
	call 	printNum
	
	movi	r4, ':'
	call	putchar
	
	ldw		r4, Hund(r0)			
	call	printNum
	
	movi	r4, '\n'
	call	putchar
	
NoLapReport:

	ldw		r2, Frozen(r0)
	bne		r2, r0, main_loop
	
	ldw		r4, Hund(r0)
	#ldw		r4, Mins(r0)
	call 	segTime
	br main_loop


##############################################
# void displayTime(int n) 
segTime:
    subi    sp, sp, 12
    stw     ra, 8(sp)
	stw		r16,4(sp)
    stw     r4, 0(sp)      # Save total centiseconds
    
    # Calculate and display minutes
    movia   r16, 6000       # centiseconds per minute
    div     r4, r4, r16
    call    segHighNumber
    
    # Calculate seconds and centiseconds using remainder
    ldw     r4, 0(sp)      # Restore total centiseconds
    div     r2, r4, r16     # r2 = total / 6000
    mul     r2, r2, r16     # r2 = minutes * 6000
    sub     r4, r4, r2     # r4 = remainder (sec.centisec)
    call    segLowNumber
    
	ldw		r16,4(sp)
    ldw     ra, 8(sp)
    addi    sp, sp, 12
    ret
	
##############################################
# Display minutes on segments 5-6
segHighNumber:
    subi    sp, sp, 4      # prologue
    stw     ra, 0(sp)      
    call    num2bits       # Convert input to segment bits
    
	movhi   r3, 0x80       # Set decimal point bit
    or      r2, r2, r3     
    stwio   r2, O_7SEG_HI(gp)  # Update display
    ldw     ra, 0(sp)      # epilogue
    addi    sp, sp, 4      
    ret
##############################################
# Display on segments 1-4 (seconds and centiseconds)
segLowNumber:
    subi    sp, sp, 4      # prologue
    stw     ra, 0(sp)      
    call    num2bits       # Convert input to segment bits
	
    movhi   r3, 0x80       # Set decimal point bit
    or      r2, r2, r3    
    stwio   r2, O_7SEG_LO(gp)  # Update display
    ldw     ra, 0(sp)      # epilogue
    addi    sp, sp, 4      
    ret
	
#################################################
# function to delay 10ms
# delay 10ms 10MHz / (100Hz * 3) = 33332
# Originally thought delay = 33332 but through testing 100000 runs closer to 1 second
delay:
    movia   r4, 10
    call    delay10ms
    ret

delay10ms:
    movia   r2, 100000 # Clock cycles for 1 ms
    mul     r2, r2, r4 # Total delay in clock cycles
  delay_loop:
    subi    r2, r2, 1
    bne     r2, r0, delay_loop
    ret

##########################################
# void showNum(int n) -- turn n [0 -> 999999] to seven segment bits
showNum:
	subi 	sp, sp, 4
	stw		ra, 0(sp)				#prologue
	
	call	num2bits
	stwio	r2, O_7SEG_LO(gp)
	
	ldw		ra, 0(sp)				#epilogue
	addi	sp, sp, 4
	ret

##########################################
# int num2bits(int n) -- turn n [0 -> 9999] to seven segment bits
num2bits:
	movi	r2, 0
	movi 	r10, 10
	movi 	r7, 4
  n2b_loop:
	div		r3, r4, r10				# r4 is quotient n / 10
	mul 	r5, r3, r10
	sub		r5, r4, r5				# r5 is remainder n % 10
	ldbu	r6, Bits7seg(r5)		# get 7seg bits for digit (n % 10)
	or		r2, r2, r6
	roli	r2, r2, (32-8)			# rori r8, r8, 8
	mov		r4, r3
	subi 	r7, r7, 1
	bgt		r7, r0, n2b_loop
	ret

##########################################
# void putchar(char c) - writes a single char to UART
putchar:
	ldwio	r2, O_UART_CTRL(gp)
	srli	r2, r2, 16
	beq		r2, r0, putchar
	stwio	r4, O_UART_DATA(gp)
	ret
	
##########################################
# char getchar(void) - reads a single char from UART
getchar:
	ldwio	r2, O_UART_DATA(gp)
	andi	r3, r2, 0x8000
	beq		r3, r0, getchar
	andi	r2, r2, 0xFF
	ret
	
##########################################	
# void puts(char *str){
# char c;
# 	while (((c == *buf++) != '\0'){
#		putchar(c);
#	}
# }
puts:	# writes until null terminator
	ldbu	r3, (r4)				# c = *buf;
	addi	r4, r4, 1				# buf++;
	beq		r3, r0, puts_done
	######### putchar() #########
	ldwio	r2, O_UART_CTRL(gp)
	srli	r2, r2, 16				# validate WSPACE > 0
	beq		r2, r0, putchar
	stwio	r3, O_UART_DATA(gp)
	######### putchar() #########
	br 		puts
  puts_done:
	ret
	
##########################################
# void gets(char *str){ -- read a line up to a '\n', return string
# 	char c;
# 	while (((c == getchar()) != '\n'){
#		*buf++ = c;
#	}
# 	*buf = '\0';
# }
gets:	# reads until newline
	######### getchar() #########
	ldwio	r2, O_UART_DATA(gp)
	andi	r3, r2, 0x8000
	beq		r3, r0, gets
	andi	r2, r2, 0xFF
	######### getchar() #########
	stwio	r2, O_UART_DATA(gp)
	movi	r3, '\n'
	beq		r2, r3, gets_done 
	stb		r2, (r4)
	addi	r4, r4, 1
	br		gets
  gets_done:
	stb		r0, (r4)				# *buf = '\0'
	ret
	
##########################################
# int atoi(char *str){	-- convert string to number using horner's algorithm
# char c;
# int negate = 0;
# int sum = 0;
# if (*str == '-'){
# 	negate = 1;
# 	str++;
# }
# while ((c = *str++) >= '0' && c <= '0'){
# 	sum += 10;
# 	sum += c - '0';
# }
# return negatve ? -sum : sum; }
atoi:
	movi 	r2, 0				# sum = 0;
	movi	r3, 0				# negate = 0;
	ldbu	r5, (r4)			# *str
	cmpeqi	r6, r5, '-' 		# *str == '-'
	beq 	r6, r0, no_negate
	movi	r3, 1				# negate = 1;
  atoi_loop:
	addi 	r4, r4, 1 			# str++
	ldbu	r5, (r4)			# *str
  no_negate:
	movi	r6, '0'
	blt		r5, r6, atoi_done
	movi	r6, '9'
	bgt		r5, r6, atoi_done
	
	muli 	r2, r2, 10			# sum += 10;
	subi 	r5, r5, '0'			# sum += c - '0'
	add		r2, r2, r5
	br		atoi_loop
  atoi_done:
	beq		r3, r0, dont_negate
	sub		r2, r0, r2			# -sum
  dont_negate:
	ret
	
##########################################
# void printNum(int n){ -- print number to UART
# 	if (n < 0) {
# 		putchar('-');
# 		n = -n;
# }
#	if ( n < 10) putchar('0' + n);
# 	else {
# 		printNum(n / 10);
#		putchar('0' + (n % 10));
# 	}
printNum:
	subi 	sp, sp, 8
	stw		ra, 4(sp)
	
	bge		r4, r0, not_neg
	sub 	r4, r0, r4
	stw		r4, 0(sp)
	movi	r4, '-'
	call 	putchar
	ldw 	r4, 0(sp)
  not_neg:
	movi 	r10, 10				# if (n < 10)
	bge		r4, r10, not_base
	addi 	r4, r4, '0'			# putchar('0' + n)
	call 	putchar
	br		printNum_done
  not_base:
  	movi 	r10, 10
  	div		r3, r4, r10			# r3 = n /10;
	mul 	r5, r3, r10
	sub		r5, r4, r5			# r5 = n % 10;
	stw 	r5, 0(sp)
	mov		r4, r3
	call 	printNum			# printNum (n / 10)
	ldw		r5, 0(sp)
	addi	r4, r5, '0'
	call 	putchar				# putchar('0' + n)
  printNum_done:
	ldw		ra, 4(sp)
	addi 	sp, sp, 8
	ret
	
.data

Pause:
	.word 1 # pause state

Frozen:
	.word 0 # frozen state
	
Hund:
	.word 0	# Hundredths of seconds 0000 .. 5999
	
Mins:
	.word 0 # minutes count 00 ... 99
	
LapFlag:
	.word 0

Buffer: 
	.space 	100, 0

MyVar: 
	.word 123 # MyVar example variable: purpose described her
	
Greeting1: 
	.asciz "Welcome to the Stopwatch Program:\n"
	
Laptime:
	.asciz "Laptime: "

Bits7seg:
#			  0 	1	  2	    3	  4 	5	  6		7	  8		9
	.byte	0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x67
	.byte	0x77, 0x7c, 0x39, 0x5E, 0x79, 0x71
#			  A     B     C     D     E     F
.end