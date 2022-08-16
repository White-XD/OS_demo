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

times 60 dq 0 ; Define Quad word(8 bytes)，预留60个描述符空位

; total_mem_bytes用于保存内存容量，以字节为单位
; 当前偏移loader.bin文件头0x203字节(3+4*8+60*8=3+32+480=3+512=0x203)
; loader.bin的加载地址是0x900，所以total_mem_bytes实际保存在0xb03
total_mem_bytes dd 0

; 选择子都是16bit
SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0 ;(0x0001<<3)代表Index索引，相当于(CODE_DESC-GDT_BASE)/8
SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0

; 以下是定义gdt的指针，前2字节是gdt界限，后4字节是gdt起始地址
gdt_ptr dw GDT_LIMIT ; 31(10进制)=0x001f
         dd GDT_BASE ; 0x00000903

; 人工对齐：total_mem_bytes(4)+gdt_ptr(6)+ards_buff(244)+ards_nr(2)，共256字节
; 仅仅为了好看，但是我们这里有jmp loader_start和loadermsg，就无法保证loader_start在文件内偏移位0x300了
ards_buff times 244 db 0
ards_nr dw 0 ; number_record 用于记录ARDS(Address Range Descriptor Structure)结构体数量

loadermsg db "detecting memory"

loader_start:
    ;---------------------------------------
    ;清屏
    ;清屏利用0x06功能，上卷全部行，则可清屏
    ;INT x010 功能号：0x06 功能描述：上行卷窗口
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

    ;---------------------------------------
    ;打印字符串
    ;调用13号子功能打印字符串
    mov bp, loadermsg ;ES:BP为串首地址，ES此时同CS一致，开头时已经为sreg初始化

    ;光标位置要用到DX寄存器中的内容，CX中的光标位置可忽略
    mov cx, 16 ; CX为串长度，不包括结束符0的字符个数
    mov ax, 0x1301 ; 子功能号为13，存入AH寄存器，AL = Write mode这里AL=01：显示字符串，光标跟随移动
    mov bx, 0x001f ; BH = Page Number, BL = Color，蓝底白字
    mov dx, 0x0000 ; DH = Row, DL = Column
    int 0x10


    ;---------------------------------------
    ; 使用0x15中断获取物理内存信息
    ; int 0x15 eax=0x0000E820, edx=0x534D4150
    xor ebx, ebx ; 第一次调用时，ebx值要为0
    mov edx, 0x534D4150 ; edx只赋值一次，循环体中不会改变
    mov di, ards_buff ; ards结构缓冲区

.e820_mem_get_loop:
    mov eax, 0x0000E820 ; 执行int 0x15后，eax值变为0x0x534D4150，所以每次执行int前都要更新为子功能号
    mov ecx, 20 ; ARDS地址范围结构描述符大小是20字节
    int 0x15
    jc .e820_mem_failed_try_e801 ; 若cf位为1则有错误发生，尝试0xe801子功能
    add di, cx ; 使di增加20字节指向缓冲区中新的ARDS结构位置
    inc word [ards_nr]; 记录ARDS数量
    cmp ebx, 0 ;若ebx为0且cf不为1，这说明ards全部返回，当前已是最后一个
    jnz .e820_mem_get_loop

    ; 在所有ARDS结构中，找出(base_add_low+length_low)的最大值，即内存的容量
    mov cx, [ards_nr]
    ; 遍历每一个ADRS结构体，循环次数是ARDS的数量
    mov ebx, ards_buff
    xor edx, edx ; edx用于记录最大内容容量，先清0
.find_max_mem_area:
    ; 无需判断type是否为1，因为最大的内存块一定是可用的
    ; 遍历缓冲区，记录最大值到edx
    mov eax, [ebx] ; base_add_low
    add eax, [ebx+8] ; base_add_low+length_low，这里为什么要基地址+长度呢，记录最大内存块不应该直接比较长度吗？
    add ebx, 20 ; ebx指向缓冲区的下一个ARDS结构
    cmp edx, eax
    ; edx>=aex
    jge .next_ards 
    ; 否则，记录最大值到edx
    mov edx, eax
.next_ards:
    loop .find_max_mem_area
    jmp .mem_get_ok


    
.e820_mem_failed_try_e801:
    ;---------------------------------------
    ; 使用0x15中断获取物理内存信息
    ; int 0x15 eax=0x0000E801 最大支持4G
    ; 返回后，ax和cx值一样，以KB为单位；bx和dx值一样，以64KB为单位
    ; 在ax/cx寄存器中为低16MB，在bx/dx寄存器中为16M到4GB
    mov ax, 0xE801
    int 0x15
    jc .e801_failed

    ; 1.先算出低15MB的内存，ax/cx记录以KB为单位的内存数量，将其转换为以byte为单位
    mov cx, 0x400 ; cx=2^10，cx和ax一致，用于乘数
    mul cx
    shl edx, 16
    and eax, 0x0000FFFF
    or edx, eax 
    add edx, 0x100000 ; ax只是15MB，故要加上1MB
    mov esi, edx ; 先把低15MB的内存容量存入esi寄存器备份
    ; 2.再将16MB以上的内存转换为byte
    xor eax, eax ; 清零
    mov ax, bx
    mov ecx, 0x10000 ; 0x10000=2^16=64KB
    mul ecx ; 32位乘法，默认的被乘数是eax，积为64位，高32位存入edx，低32位存入eax

    add esi, eax ; 此方法只能测出4GB以内的内存，故32位eax足够，而edx肯定为0
    mov edx, esi ; edx为总内存大小
    jmp .mem_get_ok

.e801_failed:
    mov byte [gs:160], 'F'
    mov byte [gs:162], 'a'
    mov byte [gs:164], 'i'
    mov byte [gs:166], 'l'
    mov byte [gs:168], 'e'
    mov byte [gs:170], 'd'
    jmp $

.mem_get_ok:
    mov [total_mem_bytes], edx

enable_protected:
    ;---------------------------------------
    ; 准备进入保护模式
    ; 1.打开A20地址总线
    ; 2.加载gdt
    ; 3.将CR0的pe位置1

    ; 1.打开A20
    in al, 0x92
    or al, 00000010b
    out 0x92, al

    ; 2.加载gdt
    lgdt [gdt_ptr]

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
    mov byte [gs:162], ' '
    mov byte [gs:164], 'm'
    mov byte [gs:166], 'o'
    mov byte [gs:168], 'd'
    mov byte [gs:170], 'e'

    ; 加载kernel
    mov eax, KERNEL_START_SECTOR ; kernel.bin所在扇区号
    mov ebx, KERNEL_BIN_BASE_ADDR ; 写入的位置

    mov ecx, 200 ; 读入的扇区数

    call rd_disk_m_32


    ; 创建页目录和页表并初始化页内存位图
    call setup_page

    ; 要将描述符表地址及偏移量写入内存gdt_ptr，一会用新地址重新加载
    sgdt [gdt_ptr] ; 储存到原来gdt所有的位置

    ; 将gdt描述符中视频段描述符中的段基址+0xc0000000
    mov ebx, [gdt_ptr+2]
    or dword [ebx+0x18+4], 0xc0000000
    ; 视频段是第3个段描述符，每个描述符是8字节，故0x18
    ; 段描述符的高4字节的最高位是段基址的第31-24位

    ; 将gdt的基址加上0xc0000000使其成为内核所在的高地址
    add dword[gdt_ptr+2], 0xc0000000

    add esp, 0xc0000000 ; 将栈指针同样映射到内核地址

    ; 把页目录地址赋给cr3
    mov eax, PAGE_DIR_TABLE_POS
    mov cr3, eax

    ; 打开cr0的pg位（第31位）
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ; 在开启分页后，用gdt新的地址重新加载
    lgdt [gdt_ptr]

    mov byte [gs:160], 'P'
    mov byte [gs:162], '&'
    mov byte [gs:164], 'V'
    mov byte [gs:166], ' '
    mov byte [gs:168], 'm'
    mov byte [gs:170], 'o'
    mov byte [gs:172], 'd'
    mov byte [gs:174], 'e'

    ; 由于一直在32位下，原则上不需要强制刷新流水线
    ; 保险起见，刷新也可以
    jmp SELECTOR_CODE:enter_kernel

enter_kernel:
    call kernel_init
    mov esp, 0xc009f000 ; 选择0x9f000既接近最大可用地址0x9fbff，并且能满足pcb的4KB对齐的要求
    mov byte [gs:320], 'I'
    mov byte [gs:322], 'n'
    mov byte [gs:324], ' '
    mov byte [gs:326], 'K'
    mov byte [gs:328], 'e'
    mov byte [gs:330], 'r'
    mov byte [gs:332], 'n'
    mov byte [gs:334], 'e'
    mov byte [gs:336], 'l'

    jmp KERNEL_ENTRY_POINT ; 用地址0x1500访问测试

; 将kernel.bin中的segment拷贝到编译的地址
kernel_init:
    xor eax, eax
    xor ebx, ebx ; ebx记录程序头表地址
    xor ecx, ecx ; cx记录程序头表中的program header数量
    xor edx, edx ; dx记录program header大小，即e_phentsize

    mov dx, [KERNEL_BIN_BASE_ADDR+42] ; 偏移42字节处的属性是e_phentsize，表示program header table entry的大小，即0x20=32 byte
    mov ebx, [KERNEL_BIN_BASE_ADDR+28] ; 偏移文件开始部分28字节的地方是e_phoff，表示第一个program header在文件中的偏移量，其值应该是0x34 = 52

    add ebx, KERNEL_BIN_BASE_ADDR
    mov cx, [KERNEL_BIN_BASE_ADDR+44] ; 偏移文件开始部分44字节的地方是e_phnum，表示有几个program header，本例中为0x5
    ; 注意这里不能用ecx，因为e_phnum是2字节大小的值

.each_segment:
    cmp byte [ebx+0], PT_NULL ; 若p_type等于PT_NULL，说明此program header未使用
    je .PT_NULL

    ; 为函数memcpy压入参数，参数是从右往左依次压入
    ; 函数原型类似于memcpy(dst, src, size)
    push dword [ebx+16] ; program header中偏移16字节的地方是p_filesz，押入memcpy()的第三个参数：size

    mov eax, [ebx+4] ; 距离program header偏移量为4字节的位置是p_offset
    add eax, KERNEL_BIN_BASE_ADDR ; 加上kernel.bin被加载到的物理地址，eax为该段的物理地址
    push eax ; 押入函数memcpy的第二个参数：源地址
    push dword [ebx+8] ; 偏移程序头8字节的位置时p_vaddr，押入函数memcpy的第一个参数：目的地址

    call mem_cpy ; 调用mem_cpy完成段复制
    add esp, 12 ; 清理栈中押入的三个参数

.PT_NULL:
    add ebx, edx ; edx为program header的大小，即e_phentsize，在此ebx指向下一个program header
    loop .each_segment
    ret

; 逐字节拷贝mem_cpy(dst, src, size)
; 输入：栈中的三个参数（dst, src, size）
; 输出：无
mem_cpy:
    cld
    push ebp ; 不确定外层是否有使用，但是保险起见还是入栈保存
    mov ebp, esp
    push ecx ; rep指令用到了ecx，但ecx对外层段的循环还有用，故先入栈备份
    mov edi, [ebp+8] ; dst
    mov esi, [ebp+12] ; src
    mov ecx, [ebp+16] ; size

    rep movsb ; 逐字节拷贝

    ; 恢复环境
    pop ecx
    pop ebp
    ret


;创建页目录和页表
setup_page:
;先把页目录占用的空间逐字节清0
    mov ecx, 4096
    mov esi, 0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0
    inc esi
    loop .clear_page_dir

;开始创建页目录项(PDE)
.create_pde: ; 创建Page Directory Entry
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x1000 ; 此时，eax是第一个页表的位置及属性
    mov ebx, eax ; 此处为eba赋值，是为.creare_pte作准备，ebx为基址

    ; 下面将页目录项0和0xc00都存为第一个页表的地址，每个页表表示4MB内存
    ; 这样0xc03fffff以下的地址和0x003fffff以下的地址都指向相同的页表
    ; 这样是为将地址映射为内核地址作准备
    or eax, PG_US_U | PG_RW_W | PG_P
    ; 页目录项的属性RW和P为1，US为1，表示用户属性，所有特权级别都可以访问
    mov [PAGE_DIR_TABLE_POS + 0x0], eax ; 第1个目录项
    ; 在页目录表中的第1个目录项写入第一个页表的位置(0x101000)及属性(7)

    ; 由于1个页目录项占用4B
    ; 0xc00表示第768个页目录项，0xc00以上的目录用于内核空间
    mov [PAGE_DIR_TABLE_POS + 0xc00], eax
    ; 也就是页表的0xc0000000 -> 0xffffffff共计1G属于内核
    ; 0x0 -> 0xbfffffff共计3G属于用户进程

    sub eax, 0x1000
    ; 使最后一个目录项指向页目录表自己的地址
    ; 为了将来能够动态操作页表（通过虚拟地址访问页表/页目录表）
    mov [PAGE_DIR_TABLE_POS + 4092], eax

; 开始创建页表项(PTE)
    mov ecx, 256 ; 只使用物理低端1M内存，1M内存 / 每页大小4k = 256
    mov esi, 0
    mov edx, PG_US_U | PG_RW_W | PG_P ; 属性为7，US=1, RW=1, P=1
.create_pte: ; 创建Page table entry
    mov [ebx+esi*4], edx ; 此处的ebx在.create_pde中已通过eax赋值为0x101000，也就是第一个页表的位置

    add edx, 0x1000 ; 自增4k，得到下一页的物理地址
    inc esi
    loop .create_pte

; 继续内核其他页表的PDE
; 目的是为了以最简单的方式实现内核在用户进程间的共享，即：
; 提前把内核的所有页目录项定下来，也就是提前把内核的页表固定下来
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x2000 ; 此时eax为第二个页表的位置
    or eax, PG_US_U | PG_RW_W | PG_P ; 页目录项的属性US、RW和P都是1
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254 ; 范围为第769 -> 1022的所有页目录项数量
    mov esi, 769
.create_kernel_pde:
    mov [ebx+esi*4], eax
    inc esi
    add eax, 0x1000
    loop .create_kernel_pde 
    ; 从函数setup_page返回
    ret


; 保护模式的硬盘读取函数
rd_disk_m_32:

    mov esi, eax
    mov di, cx

    mov dx, 0x1f2
    mov al, cl
    out dx, al

    mov eax, esi

    mov dx, 0x1f3
    out dx, al

    mov cl, 8
    shr eax, cl
    mov dx, 0x1f4
    out dx, al

    shr eax, cl
    mov dx, 0x1f5
    out dx, al

    shr eax, cl
    and al, 0x0f
    or al, 0xe0
    mov dx, 0x1f6
    out dx, al

    mov dx, 0x1f7
    mov al, 0x20
    out dx, al

.not_ready:
    nop
    in al, dx
    and al, 0x88
    cmp al, 0x08
    jnz .not_ready

    mov ax, di
    mov dx, 256
    mul dx
    mov cx, ax
    mov dx, 0x1f0

.go_on_read: ; 注意，这里应该使用ebx，因为我们处于保护模式！
    in ax, dx
    mov [ebx], ax
    add ebx, 2
    loop .go_on_read
    ret


