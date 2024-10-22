org 0x0
bits 16

%define NEWLINE 0x0D, 0x0A

start:
	; print hello message
	mov si, msg_hello
	call puts
	
.halt:
	cli
	hlt

; puts prints a string to the screen
; a loop is used and the BIOS interrupt is called each time
; Params:
; 	ds:si points to string

puts:
	; push the registers that we will use to the stack
	push si
	push ax
	push bx

.loop:
	lodsb		; loads next character in al
	or al,al	; check if al is null, will set flag to zero
	jz .done
		
	mov ah, 0x0E	; call BIOS interrupt to print
	mov bh, 0	; set page number to 0 for current page
	int 0x10	; BIOS interrupt
	jmp .loop
.done:
	pop bx
	pop ax
	pop si
	ret

msg_hello: db 'Hello from the KERNEL asm file!',NEWLINE,0