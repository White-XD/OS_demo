;主引导程序
%include "boot.inc"
section MBR vstart=0x7c00
; 由于BIOS通过jmp 0:0x7c00跳到MBR，所以此时CS=0
mov ax, cs
mov ds, ax
mov ss, ax
mov es, ax
mov fs, ax
mov sp, 0x7c00

mov ax, 0xb800
;显存中用于文本模式显示适配器的起始地址是0xB8000，大小32KB
mov gs, ax

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

;输出背景色绿色，前景色红色，并且跳动的字符串“My First MBR”
mov byte [gs:0x00],'M'
mov byte [gs:0x01],0xBF
mov byte [gs:0x02],'y'
mov byte [gs:0x03],0xBF

mov byte [gs:0x04],' '
mov byte [gs:0x05],0xBF

mov byte [gs:0x06],'F'
mov byte [gs:0x07],0xBF
mov byte [gs:0x08],'i'
mov byte [gs:0x09],0xBF
mov byte [gs:0x0A],'r'
mov byte [gs:0x0B],0xBF
mov byte [gs:0x0C],'s'
mov byte [gs:0x0D],0xBF
mov byte [gs:0x0E],'t'
mov byte [gs:0x0F],0xBF

mov byte [gs:0x10],' '
mov byte [gs:0x11],0xBF

mov byte [gs:0x12],'M'
mov byte [gs:0x13],0xBF
mov byte [gs:0x14],'B'
mov byte [gs:0x15],0xBF
mov byte [gs:0x16],'R'
mov byte [gs:0x17],0xBF

;准备读如loader.bin
mov eax, LOADER_START_SECTOR ;起始扇区LBA地址
mov bx, LOADER_BASE_ADDR ;写入的地址
mov cx, 3 ;待读入的扇区数，由于loader.bin大于512B，所以直接选择读如4个扇区
call rd_disk_m_16

; 跳转至loader
jmp LOADER_BASE_ADDR

;功能：读取硬盘n个扇区
rd_disk_m_16:
    mov esi, eax ;备份eax
    mov di, cx ; 备份
    ;读写硬盘
    ;1. 设置要读取的扇区数
    mov dx, 0x1f2
    mov al, cl
    out dx, al ;al保存读取的扇区数

    mov eax, esi ;恢复eax
    ;2. 将LBA地址存入0x1f3~0x1f6
    ;LBA的0-7位写入0x1f3
    mov dx, 0x1f3
    out dx, al

    ;LBA的8-15位写入0x1f4
    mov cl, 8
    shr eax, cl
    mov dx, 0x1f4
    out dx, al

    ;LBA的16-23位写入0x1f5
    shr eax, cl
    mov dx, 0x1f5
    out dx, al

    shr eax, cl
    and al, 0x0f ;al的低四位表示LBA的24-27位
    or al, 0xe0 ;设置al的高四位位1110，表示LBA模式
    mov dx, 0x1f6
    out dx, al

    ;3. 向0x1f7写入读命令:0x20
    mov al, 0x20
    mov dx, 0x1f7
    out dx, al

    ;4. 检测硬盘状态
.not_ready: ;同一端口，写时表示写入命令字，读时表示读入硬盘状态
    nop
    in al, dx
    and al, 0x88 ;第4位为1表示硬盘控制器已准备好数据传输，第7位表示硬盘忙
    cmp al, 0x08
    jnz .not_ready ;al不是0x08：循环

    ;5. 从0x1f0端口读数据
    mov ax, di ;ax是读取扇区数
    mov dx, 256
    mul dx
    mov cx, ax ;一个扇区512字节，每次从data寄存器读取一个字，一共要读取256*di次
    mov dx, 0x1f0

.go_on_read:
    in ax, dx
    mov [bx], ax
    add bx, 2 ;一次写入两字节
    loop .go_on_read

    ret

times 510-($-$$) db 0
db 0x55, 0xAA