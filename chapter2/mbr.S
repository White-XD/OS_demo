;主引导程序
SECTION MBR vstart=0x7c00
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp, 0x7c00

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

;获取光标位置开始
;.get_cursor获取当前光标位置，在光标位置处打印字符
    mov ah, 3  ; 输入：3号子功能是获取光标位置，需要存入AH寄存器
    mov bh, 0  ; BH寄存器存储的事待获取光标的页号

    int 0x10  ; 输出：CH=光标开始行，CL=光标结束行
              ; DH=光标所在行号，DL=光标所在列号

;获取光标位置结束

;打印字符串开始
;调用13号子功能打印字符串
    mov ax, message
    mov bp, ax ;ES:BP为串首地址，ES此时同CS一致，开头时已经为sreg初始化

    ;光标位置要用到DX寄存器中的内容，CX中的光标位置可忽略
    mov cx, 13 ;CX为串长度，不包括结束符0的字符个数
    mov ax, 0x1301 ;子功能号为13，存入AH寄存器，AL = Write mode这里AL=01：显示字符串，光标跟随移动
    mov bx, 0x2; BH = Page Number, BL = Color，这里BL=02黑底绿字

    int 0x10
;打印字符串结束

jmp $
message db "My first MBR!"
times 510-($-$$) db 0 ; 用0将本扇区的除后两个字节外剩余位置填0
db 0x55, 0xaa



