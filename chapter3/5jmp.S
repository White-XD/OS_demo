; 16位实模式间接绝对远转移
section jmp_test vstart=0x900
jmp far [addr]
times 128 db 0
addr dw start, 0
start: 
    mov ax, 0x1234
    jmp $
    