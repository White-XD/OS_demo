%include "boot.inc"

section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR

jmp loader_start

; 构建gdt及其内部的描述符
GDT_BASE: dd 0x00000000
          dd 0x00000000

CODE_DESC: dd 0x0000FFFF
           dd DESC_CODE_HIGH4

DATA_STACK_DESC: dd 0x0000FFFF
                 dd DESC_DATA_HIGH4
; 显存段描述符，显存段基址是0xb8000
VIDEO_DESC: dd 0x8000_0007 ; limit=(0xbffff-0xb8000)/4k=0x7
            dd DESC_VIDEO_HIGH4

GDT_SIZE equ $-GDT_BASE ; 0x20
GDT_LIMIT equ GDT_SIZE-1 ; 0x1F

times 60 dq 0; Define Quad word(8 bytes)，预留60个描述符空位

; 选择子都是16bit
SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0 ;(0x0001<<3)代表Index索引，相当于(CODE_DESC-GDT_BASE)/8
SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0

; 以下是gdt的指针，前2字节是gdt界限，后4字节是gdt起始地址
gdtr_ptr dw GDT_LIMIT
         dd GDT_BASE

loadermsg db "loader in real mode"

loader_start:
    ;清屏
    ;清屏利用0x06功能，上卷全部行，则可清屏
    ;---------------------------------------
    ;INT x010 功能号：0x06 功能描述：上行卷窗口
    ;---------------------------------------
    ;输入
    ;AH功能号=0x06
    ;AL=上卷行数，若为0表示全部
    ;BH=上卷行属性
    ;(CL, CH)=窗口左上角的(X,Y)坐标
    ;(DL, DH)=窗口右下角的(X,Y)坐标
    ;无返回值
    mov ax, 0x0600
    mov bx, 0x0700
    mov cx, 0
    mov dx, 0x184f ;0x18=24, 0x4f=79

    int 0x10


    ;打印字符串开始
    ;调用13号子功能打印字符串
    mov bp, loadermsg ;ES:BP为串首地址，ES此时同CS一致，开头时已经为sreg初始化

    ;光标位置要用到DX寄存器中的内容，CX中的光标位置可忽略
    mov cx, 19 ; CX为串长度，不包括结束符0的字符个数
    mov ax, 0x1301 ; 子功能号为13，存入AH寄存器，AL = Write mode这里AL=01：显示字符串，光标跟随移动
    mov bx, 0x001f ; BH = Page Number, BL = Color，蓝底白字
    mov dx, 0x0000 ; DH = Row, DL = Column
    int 0x10
    ;打印字符串结束

    ; 准备进入保护模式
    ; 1.打开A20地址总线
    ; 2.加载gdt
    ; 3.将CR0的pe位置1

    ; 1.打开A20
    in al, 0x92
    or al, 00000010b
    out 0x92, al

    ; 2.加载gdt
    lgdt [gdtr_ptr]

    ; 3. CR0第0位置1
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    ; 此时CPU已进入32位保护模式，但是该指令依然被编译成16位指令
    ; 为了让其使用32位偏移地址，添加了dword伪指令，机器码前会添加0x66反转前缀
    jmp dword SELECTOR_CODE:p_mode_start ; 刷新流水线

[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP ;0x900
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    mov byte [gs:160], 'P'
    

    jmp $
