import struct, sys

def align(v,a): return (v+a-1)//a*a

def make_pe(command: str, out: str, setup_env: bool=False):
    cmd = command.encode('ascii') + b'\0'
    file_align=0x200; sec_align=0x1000; imagebase=0x140000000
    text_rva=0x1000; rdata_rva=0x2000

    imports = ['WinExec','ExitProcess']
    if setup_env:
        imports = ['GetModuleFileNameA','GetCommandLineA','SetEnvironmentVariableA','WinExec','ExitProcess']

    r=bytearray()
    cmd_off=len(r); r += cmd
    setup_path_name_off = setup_cmd_name_off = None
    if setup_env:
        setup_path_name_off=len(r); r += b'RLR_SELF_EXE\0'
        setup_cmd_name_off=len(r); r += b'RLR_SELF_CMDLINE\0'
    while len(r)%8: r+=b'\0'
    desc_off=len(r); r += b'\0'*40
    while len(r)%8: r+=b'\0'
    int_off=len(r); r += b'\0'*(8*(len(imports)+1))
    iat_off=len(r); r += b'\0'*(8*(len(imports)+1))
    hn_offsets=[]
    for name in imports:
        off=len(r); hn_offsets.append(off)
        r += struct.pack('<H',0)+name.encode('ascii')+b'\0'
        if len(r)%2: r+=b'\0'
    dll_off=len(r); r += b'KERNEL32.dll\0'

    thunk_rvas=[rdata_rva+x for x in hn_offsets]+[0]
    struct.pack_into('<'+'Q'*len(thunk_rvas),r,int_off,*thunk_rvas)
    struct.pack_into('<'+'Q'*len(thunk_rvas),r,iat_off,*thunk_rvas)
    struct.pack_into('<IIIII',r,desc_off,rdata_rva+int_off,0,0,rdata_rva+dll_off,rdata_rva+iat_off)

    iat_rva={name:rdata_rva+iat_off+8*i for i,name in enumerate(imports)}
    code=bytearray()

    def rip_lea_rcx(target_rva):
        nonlocal code
        insn_rva=text_rva+len(code); next_rva=insn_rva+7
        code += b'\x48\x8D\x0D'+struct.pack('<i',target_rva-next_rva)
    def rip_call(target_rva):
        nonlocal code
        insn_rva=text_rva+len(code); next_rva=insn_rva+6
        code += b'\xFF\x15'+struct.pack('<i',target_rva-next_rva)

    if setup_env:
        # 4096-byte path buffer + shadow/alignment area; RSP is 8 mod 16 on entry,
        # subtracting 0x1028 makes it 0 mod 16 for calls.
        code += b'\x48\x81\xEC\x28\x10\x00\x00'  # sub rsp, 0x1028
        code += b'\x31\xC9'                          # xor ecx, ecx (hModule=NULL)
        code += b'\x48\x8D\x54\x24\x20'          # lea rdx, [rsp+0x20]
        code += b'\x41\xB8\x00\x10\x00\x00'    # mov r8d, 4096
        rip_call(iat_rva['GetModuleFileNameA'])
        rip_lea_rcx(rdata_rva+setup_path_name_off)
        code += b'\x48\x8D\x54\x24\x20'          # lea rdx, [rsp+0x20]
        rip_call(iat_rva['SetEnvironmentVariableA'])
        rip_call(iat_rva['GetCommandLineA'])         # rax = cmdline
        code += b'\x48\x89\xC2'                    # mov rdx, rax
        rip_lea_rcx(rdata_rva+setup_cmd_name_off)
        rip_call(iat_rva['SetEnvironmentVariableA'])
    else:
        code += b'\x48\x83\xEC\x28'              # sub rsp, 0x28

    rip_lea_rcx(rdata_rva+cmd_off)
    code += b'\xBA\x05\x00\x00\x00'              # mov edx, SW_SHOW
    rip_call(iat_rva['WinExec'])
    code += b'\x31\xC9'                            # xor ecx,ecx
    rip_call(iat_rva['ExitProcess'])
    code += b'\xCC'

    dos=bytearray(0x80); dos[0:2]=b'MZ'; struct.pack_into('<I',dos,0x3c,0x80)
    pe=bytearray(b'PE\0\0')
    num_sections=2; opt_size=0xF0
    pe += struct.pack('<HHIIIHH',0x8664,num_sections,0,0,0,opt_size,0x0022)
    opt=bytearray(opt_size)
    struct.pack_into('<H',opt,0,0x20B); opt[2]=14
    size_code=align(len(code),file_align); size_rdata=align(len(r),file_align)
    struct.pack_into('<III',opt,4,size_code,size_rdata,0)
    struct.pack_into('<II',opt,16,text_rva,text_rva)
    struct.pack_into('<Q',opt,24,imagebase)
    struct.pack_into('<II',opt,32,sec_align,file_align)
    struct.pack_into('<HHHHHH',opt,40,6,0,0,0,6,0)
    size_headers=align(len(dos)+4+20+opt_size+num_sections*40,file_align)
    size_image=align(rdata_rva+len(r),sec_align)
    struct.pack_into('<III',opt,56,size_image,size_headers,0)
    struct.pack_into('<HH',opt,68,2,0x0100)
    struct.pack_into('<QQQQ',opt,72,0x100000,0x1000,0x100000,0x1000)
    struct.pack_into('<II',opt,104,0,16)
    struct.pack_into('<II',opt,112+8*1,rdata_rva+desc_off,40)
    struct.pack_into('<II',opt,112+8*12,rdata_rva+iat_off,8*(len(imports)+1))
    pe += opt

    raw_text=size_headers; raw_rdata=raw_text+size_code
    def sh(name,vsize,vaddr,rsize,rptr,chars):
        return name.encode('ascii')[:8].ljust(8,b'\0')+struct.pack('<IIIIIIHHI',vsize,vaddr,rsize,rptr,0,0,0,0,chars)
    pe += sh('.text',len(code),text_rva,size_code,raw_text,0x60000020)
    pe += sh('.rdata',len(r),rdata_rva,size_rdata,raw_rdata,0x40000040)
    data=dos+pe+b'\0'*(size_headers-(len(dos)+len(pe)))
    data += code+b'\0'*(size_code-len(code))
    data += r+b'\0'*(size_rdata-len(r))
    with open(out,'wb') as f:f.write(data)
    return len(data)

if __name__=='__main__':
    mode=False
    if len(sys.argv)>3 and sys.argv[3]=='--setup-env': mode=True
    n=make_pe(sys.argv[1],sys.argv[2],mode)
    print(sys.argv[2],n,'bytes')
