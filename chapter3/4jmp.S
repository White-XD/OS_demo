; 16位实模式直接绝对远转移
section jmp_test vstart=0x900
jmp 0:start
times 128 db 1
start:
    mov ax, 0x1234
    jmp $