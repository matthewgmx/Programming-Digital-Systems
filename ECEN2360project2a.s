# ECEN 2360 Project 2: Stopwatch
# Matthew Gorbold McCardle
# choosen option 3b

.section .reset, "ax" 	
.global _start
.equ O_UART_DATA, 	0x1000
.equ O_UART_CTRL, 	0x1004
.equ O_7SEG_LO, 	0x20
.equ O_7SEG_HI, 	0x30

_start:
	movia 	sp, 0x01000000 			# 16MB stack
	movia 	gp, 0xff200000 			# MMIO base address
	br 		main
	
.section .exceptions, "ax" 

main:
    movia   r4, Greeting1       	# Print initial greeting message
    call    puts

    movi    r4, '\n'           		# Print newline
    call    putchar

 	mov     r4, r0             		# Reset all registers to 0
    mov     r19, r0            		# r16 = elapsed time on stopwatch
    mov     r20, r0            		# r17 = stopwatch running state (0: stopped, 1: running)
    mov     r21, r0            		# r18 = pause (0: active, 1: paused)
    mov     r22, r0            		# r19 = state of button 0 (stop/start switch)
    mov     r23, r0            		# r20 = state of button 1 (display updating)
    call    segTime            		# Update displayed time to 00:00:00

main_loop:
    movia   r4, 1
    call    delay10ms           	# Small delay for button polling stability
    ldwio   r2, 0x50(gp) 			# access buttons
    andi    r3, r2, 0b1        		# Button 0 (Start/Stop Button)
    bne     r3, r0, Btn0_pressed  	
    bne     r22, r0, start_stop 	# If previously pressed, toggle start/stop
    br      Btn0_end      		

Btn0_pressed:
    movi    r22, 1             		# button 0 pressed
    br      Btn0_end 

start_stop:
    mov     r22, r0            		# Reset button 0 state
    bne     r20, r0, stop_watch 	# If running, stop the stopwatch
    movi     r20, 1             	# Set running state
    br      Btn0_end

stop_watch:
    movi     r20, 0             	# Clear running state

Btn0_end:
    andi    r3, r2, 0b10       		# only read button 1 state (Freeze/Reset switch)
    bne     r3, r0, Btn1_pressed  	# Branch if button 1 is pressed
    bne     r23, r0, handle_Btn1 	# If previously pressed, handle action
    br      Btn1_end      		# Otherwise, check if it was recently released

Btn1_pressed:
    movi    r23, 1             		# button 1 pressed
    br      Btn1_end

handle_Btn1:
    mov     r23, r0            		# Reset button 1 state
    bne     r20, r0, reset_watch 	# If stopped, reset stopwatch
    bne     r21, r0, unfreeze_watch # If frozen, unfreeze

freeze_watch:
    movi    r21, 1             		# Set freeze state
    br      Btn1_end

unfreeze_watch:
    mov     r21, r0            		# Clear freeze state
    br      Btn1_end

reset_watch:
    mov     r19, r0            		# Reset elapsed time
    mov     r4, r19            		# Update display
    call    segTime

Btn1_end:
    bne     r20, r0, main_loop 		# Skip time increment if stopped
    addi    r19, r19, 1				# Increment elapsed time
    bne     r21, r0, main_loop 		# Skip display update if paused
    mov     r4, r19            		# Update display with new time
    call    segTime
    br      main_loop          		# Restart main loop

##############################################
# -- display time on the stop watch --
# -- convert from total centiseconds ellapsed (n) to minutes, seconds, centiseconds --
# void displayTime(int n) 
segTime:
    subi    sp, sp, 8
    stw     ra, 4(sp)
    stw     r4, 0(sp)      # Save total centiseconds
    
    # Calculate and display minutes
    movia   r5, 6000       # centiseconds per minute
    div     r4, r4, r5
    call    segHighNumber
    
    # Calculate seconds and centiseconds using remainder
    ldw     r4, 0(sp)      # Restore total centiseconds
    div     r2, r4, r5     # r2 = total / 6000
    mul     r2, r2, r5     # r2 = minutes * 6000
    sub     r4, r4, r2     # r4 = remainder (sec.centisec)
    call    segLowNumber
    
    ldw     ra, 4(sp)
    addi    sp, sp, 8
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

Buffer: 
	.space 	100, 0

MyVar: 
	.word 123 # MyVar example variable: purpose described her
	
Greeting1: 
	.asciz "Welcome to the Stopwatch Program:\n"

Bits7seg:
#			  0 	1	  2	    3	  4 	5	  6		7	  8		9
	.byte	0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x67
	.byte	0x77, 0x7c, 0x39, 0x5E, 0x79, 0x71
#			  A     B     C     D     E     F
.end