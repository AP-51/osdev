org 0x7C00
bits 16

%define NEWLINE 0x0D, 0x0A

;
; FAT12 header
;
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number, value doesn't matter
ebr_volume_label:           db 'AP51     OS'        ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '           ; 8 bytes


start:
	; setup data segments
	mov ax, 0			; can't set value for ds/es directly
	mov ds,ax
	mov es,ax

	; setup stack
	mov	ss, ax
	mov sp, 0x7C00 		; stack grows downwards from start of OS

	; some BIOSes might start at 07C0:0000 instead of 0000:7C00, make sure we are in the 
	; expected location

	push es
	push word .after
	retf

.after:

	; read something from floppy disk
	; BIOS should set DL to drive number
	mov [ebr_drive_number], dl

	;show loading message
	mov si, msg_loading
	call puts

	;read drive parameters (sectors per track and head count),
	;instead of reading from disk, as disk can get corrupted

	push es;
	mov ah, 08h
	int 13h
	jc floppy_error
	pop es

	and cl, 0x3F			; remove top two bits
	xor ch,ch
	mov [bdb_sectors_per_track],cx ;sector count

	inc dh
	mov [bdb_heads], dh		; head count

	; compute LBA of root directory = reserved+fat*sectors_per_fat

	mov ax,[bdb_sectors_per_fat]
	mov bl,[bdb_fat_count]
	xor bh,bh
	mul bx							; ax = (fat*sectors_per_fat)
	add ax,[bdb_reserved_sectors] 	; ax = LBA of root directory
	push ax
	
	; compute size of root directory = (32*number_of_entries)/bytes_per_sector
	mov ax,[bdb_dir_entries_count]
	shl ax,5						; ax *=32  shifting bits by 5 places
	xor dx,dx						; dx = 0
	div word [bdb_bytes_per_sector]	; number of sectors we need to read

	test dx,dx						; if dx!=0 add 1
	jz .root_dir_after
	inc ax 							; division remainder !=0, add 1
									; remainder!=0 implies we have a partially filled sector

.root_dir_after:

	; read root directory
	mov cl,al						; cl = number of sectors to read = size of root directory
	pop ax 							; ax = LBA of root directory
	mov dl,[ebr_drive_number]		; dl = drive number
	mov bx,buffer					; es:bx = buffer
	call disk_read

	; search for kernel.bin
	xor bx,bx
	mov di,buffer

.search_kernel:
	mov si, file_kernel_bin
	mov cx, 11						; compare up to 11 characters (FAT12 specification)
	push di
	repe cmpsb						; cmpsb: compares two bytes located at ds:si and es:di
	pop di							; repe : repeats a string instruction while the operands are equal or until cx = 0
	je .found_kernel				; cx-- on each iter

	add di,32
	inc bx
	cmp bx,[bdb_dir_entries_count]
	jl .search_kernel

	; kernel not found
	jmp kernel_not_found_error

.found_kernel:
	
	; di should hace the address to the entry
	mov ax,[di+26]			; first logical cluster field (offset 26)
	mov [kernel_cluster], ax

	; load FAT data from disk to memory
	mov ax, [bdb_reserved_sectors]
	mov bx, buffer
	mov cl, [bdb_sectors_per_fat]
	mov dl, [ebr_drive_number]
	call disk_read

	; read kernel and process the FAT chain
	mov bx, KERNEL_LOAD_SEGMENT
	mov es,bx
	mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:

	; Read next Cluster
	mov ax, [kernel_cluster]

	; unfortunately hardcoded value
	add ax, 31 						; first cluster = (kernel_cluster-2)*sectors_per_cluster+start_sector
									; start sector = reserved+fats+root directory size = 1+18+14=33
	mov cl,1
	mov dl, [ebr_drive_number]
	call disk_read

	add bx,[bdb_bytes_per_sector]

	; compute location of next cluster
	mov ax,[kernel_cluster]
	mov cx, 3
	mul cx
	mov cx, 2
	div cx							; ax = index of entry in FAT, dx = cluster%2

	mov si,buffer
	add si,ax
	mov ax,[ds:si]			; reada entry from FAT table at index ax

	or dx,dx
	jz .even

.odd:
	shr ax,4
	jmp .next_cluster_after

.even:
	and ax, 0x0FFF

.next_cluster_after:
	cmp ax, 0x0FF8    		; end of the FAT chain
	jae .read_finish

	mov [kernel_cluster], ax
	jmp .load_kernel_loop

.read_finish:

	; jump to our kernel
	mov dl,[ebr_drive_number] 	; boot device in dl

	mov ax, KERNEL_LOAD_SEGMENT ; set segment registers
	mov ds,ax
	mov es,ax

	jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

	jmp wait_key_and_reboot		; should ideally never happen

	cli 						; disable interrupts, before halting the CPU
	hlt

;
; Error Handlers
;

floppy_error:
	mov si,msg_read_failed
	call puts
	jmp wait_key_and_reboot

kernel_not_found_error:
	mov si,msg_kernel_not_found
	call puts
	jmp wait_key_and_reboot

wait_key_and_reboot:
	mov ah,0
	int 16h 		; wait for keypress
	jmp 0FFFFh:0	; jump to beginning of BIOS, essentialy a reboot

.halt:
	cli 			; disable interrupts before calling halt
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
	jz .done1
		
	mov ah, 0x0E	; call BIOS interrupt to print
	mov bh, 0	; set page number to 0 for current page
	int 0x10	; BIOS interrupt
	jmp .loop

.done1:
	pop bx
	pop ax
	pop si
	ret

;
;  Disk routines
;

; Converts an LBA adress to a CHS address
; params:
; 	- ax: LBA Address
; returns:
;	- cx [bits 0-5]: sector number
;	- cx [bits 6-15]: cylinder
; 	- dh: head
;

lba_to_chs:

	push ax
	push dx

	xor dx,dx 				        ; dx = 0
	div word[bdb_sectors_per_track] ; ax = LBA/SectorsPerTrack
									; dx = LBA%SectorsPerTrack

	inc dx 							; dx = (LBA%SectorsPerTrack + 1) = sector
	mov cx,dx 						; cx = sector

	xor dx,dx 						; dx = 0
	div word [bdb_heads] 			; ax = (LBA/SectorsPerTrack)/Heads  = cylinder
									; dx = (LBA/SectorsPerTrack)%Heads = head

	mov dh,dl 						;dx = head
	mov ch,al 						; ch = cylinder (lower 8-bits)
	shl ah,6						; bitwise shift by 6 places
	or cl,ah

	pop ax
	mov dl,al						; restore DL
	pop ax
	ret

;
; Reads sectors from a disk
; params:
; 	- ax : LBA adress
; 	- cl: number of sectors to read (up to 128)
; 	- dl: drive number
;	- es:bx : memory address where to store read data

disk_read:

	push ax 					; saving register on stack
	push bx
	push cx
	push dx
	push di

	push cx 					; temporarily save CL (number or sectors to read)
	call lba_to_chs 			; compute CHS value from LBA
	pop ax 						; AL = number of sectors to read

	mov ah, 02h
	mov di,3 					; retry count

.retry:
	pusha 						; save all registers to stack, as we don't know which ones the BIOS modifies
	stc 						; set carry flag, some BIOSes don't set it
	int 13h 					; carry flag cleared
	jnc .done2 					; jump if carry not set

	;read failed
	popa
	call disk_reset

	dec di
	test di,di
	jnz .retry

.fail:
	; all attempts are exhausted
	jmp floppy_error

.done2:
	popa

	pop di		; restore pushed registers back from stack
	pop dx
	pop cx
	pop bx
	pop ax
	ret

;
; Resets Disk controller
; params: 
;	dl: drive number
;

disk_reset:
	pusha
	mov ah, 0
	stc 			; again set carry flag
	int 13h
	jc floppy_error
	popa
	ret


msg_loading: 			db 'Loading....',NEWLINE,0
msg_read_failed: 		db 'Read from disk failed!',NEWLINE,0
msg_kernel_not_found:	db 'KERNEL.BIN file not found!',NEWLINE,0
file_kernel_bin:		db 'KERNEL  BIN'
kernel_cluster:			dw 0

KERNEL_LOAD_SEGMENT:	equ 0x2000
KERNEL_LOAD_OFFSET:		equ 0


times 510-($-$$) db 0
dw 0AA55h

buffer:
