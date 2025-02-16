# ECEN 2360 Project 1: Adding Machine
# Matthew Gorbold McCardle

.section .reset, "ax"
.global _start
.equ O_UART_DATA, 	0x1000
.equ O_UART_CTRL, 	0x1004
.equ O_7SEG_LO, 	0x20
.equ SW1_HI_SW0_LO,	0b10
.equ SW0_HI_SW2_HI,	0b11

##########################################
_start:
	movia 	sp, 0x01000000 # Stack at 16MB point
	movia 	gp, 0xff200000 # Base address for MMIO
	br 	main

##########################################
# Interrupt Handler Setup
# when button is pressed
#	reads edge capture register
# 	resets edge capture bits
# 	clears total sum

.section .exceptions, "ax"

	rdctl	et, ipending
	bne		et, r0, ISR
	eret
	
ISR:
	subi	ea, ea, 4
	subi 	sp, sp, 16			# prologue
	stw		r2, 0(sp)			# stores r2, r3, r4, ra on stack
	stw		r3, 4(sp)
	stw		r4, 8(sp)
	stw		ra, 12(sp)
	
	andi	r2, et, SW1_HI_SW0_LO
	beq		r2, r0, NotIRQ1
	
	#### Handle pushbutton ISR for IRQ#1 ####
	ldwio	r3, 0x5c(gp)		# Read edgecapture register
	stwio	r3, 0x5c(gp)		# reset edgecaputre bits: deassert IRQ
	
	movia	r4, SumTotal
	ldw		r5, (r4)
	stw 	r0, (r4) 
	
NotIRQ1:
	
ISR_END:
	ldw		r2, 0(sp)			# epilogue: restore all used registers
	ldw		r3, 4(sp)
	ldw		r4, 8(sp)
	ldw		ra, 12(sp)
	addi	sp, sp, 16
	eret
	
##########################################

.text
##########################################
# main() - Adding Machine main program
main:
	#### interrupt setup ####
	movi	r2, SW0_HI_SW2_HI	# both button 0 & 1 generate IRQ#1
	stwio 	r2, 0x58(gp)		# pushbutton ppi interrupt mask
	
	movi	r2, SW1_HI_SW0_LO		# enable IRQ#1
	wrctl	ienable, r2			# ienable <- 2
	
	movi	r2, 1				# statius.PIE - 1
	wrctl	status, r2
	#########################
	
	movia	r4, Prompt			# asks for string input from UART
	call 	puts
	
	movia 	r4, Buffer			# gives 100 byte space for input
	call 	gets
	
	movia	r4, Response		# store entered string from UART
	call 	puts
	
	movia	r4, Buffer
	call 	puts
	
	movia 	r4, Buffer
	call 	atoi			
	
	mov		r9, r2
	
	movia	r4, SumTotal		#  total sum
	
	ldw 	r11, (r4)	
	add 	r11, r11, r9 	
	stw		r11, (r4)		
	
	movia 	r4, Sum				# print sum to UART:
	call 	puts
	
	movi	r4, '['
	call 	putchar
	
	mov		r4, r11
	call 	printNum			# print number to seven seg
	
	movi	r4, ']'
	call 	putchar
	
	mov 	r4, r11
	call 	showNum				# show on seven seg

stop: 	
	br 		main				# loop back for next input

##########################################
# void showNum(int n) -- turn n [0 -> 999999] to seven segment bits
showNum:
	subi 	sp, sp, 4
	stw		ra, 0(sp)	#prologue
	
	call	num2bits
	stwio	r2, O_7SEG_LO(gp)
	
	ldw		ra, 0(sp)	#epilogue
	addi	sp, sp, 4
	ret

##########################################
# int num2bits(int n) -- turn n [0 -> 9999] to seven segment bits
num2bits:
	movi	r2, 0
	movi 	r10, 10
	movi 	r7, 4
  n2b_loop:
	div		r3, r4, r10			# r4 is quotient n / 10
	mul 	r5, r3, r10
	sub		r5, r4, r5			# r5 is remainder n % 10
	ldbu	r6, Bits7seg(r5)	# get 7seg bits for digit (n % 10)
	or		r2, r2, r6
	roli	r2, r2, (32-8)		# rori r8, r8, 8
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
	movi 	r2, 0			# sum = 0;
	movi	r3, 0			# negate = 0;
	ldbu	r5, (r4)		# *str
	cmpeqi	r6, r5, '-' 	# *str == '-'
	beq 	r6, r0, no_negate
	movi	r3, 1			# negate = 1;
  atoi_loop:
	addi 	r4, r4, 1 		# str++
	ldbu	r5, (r4)		# *str
  no_negate:
	movi	r6, '0'
	blt		r5, r6, atoi_done
	movi	r6, '9'
	bgt		r5, r6, atoi_done
	
	muli 	r2, r2, 10		# sum += 10;
	subi 	r5, r5, '0'		# sum += c - '0'
	add		r2, r2, r5
	br		atoi_loop
  atoi_done:
	beq		r3, r0, dont_negate
	sub		r2, r0, r2		# -sum
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
	movi 	r10, 10			# if (n < 10)
	bge		r4, r10, not_base
	addi 	r4, r4, '0'		# putchar('0' + n)
	call 	putchar
	br		printNum_done
  not_base:
  	movi 	r10, 10
  	div		r3, r4, r10		# r3 = n /10;
	mul 	r5, r3, r10
	sub		r5, r4, r5		# r5 = n % 10;
	stw 	r5, 0(sp)
	mov		r4, r3
	call 	printNum		# printNum (n / 10)
	ldw		r5, 0(sp)
	addi	r4, r5, '0'
	call 	putchar			# putchar('0' + n)
  printNum_done:
	ldw		ra, 4(sp)
	addi 	sp, sp, 8
	ret

###########################################
# Data Segment

.data

SumTotal: 
	.word 	0 # SumTotal example variable's purpose described here

Buffer: 
	.space 	100, 0

Prompt: 
	.asciz 	"\nEnter number: "

Sum:
	.asciz	"\nSum: "
	
Response: 
	.asciz 	"You typed: "

Bits7seg:
#			  0 	1	  2	    3	  4 	5	  6		7	  8		9
	.byte	0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x67
	.byte	0x77, 0x7c, 0x39, 0x5E, 0x79, 0x71
#			  A     B     C     D     E     F
.end