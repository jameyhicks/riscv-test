#!/usr/bin/env python
# coding=utf-8

import sys

def read_file(filename):
    results = []
    with open(filename, 'r') as f:
        for line in f:
            # remove comments and extra whitespace
            line = line.split('#', 1)[0]
            line = line.strip()
            # only look at non-empty lines
            if len(line) != 0: 
                tokens = line.split()
                results.append(tokens)
    return results

def bsv_match_mask_val(match, mask, width):
    assert match & mask == match, "match has bits that aren't set in mask"
    assert mask >> width == 0, 'mask is wider than width'
    bsv_val = ''
    for i in range(width):
        if (mask >> i) & 1 == 1:
            if (match >> i) & 1 == 1:
                bsv_val = '1' + bsv_val
            else:
                bsv_val = '0' + bsv_val
        else:
            bsv_val = '?' + bsv_val
    bsv_val = str(width) + "'b" + bsv_val
    return bsv_val

def parse_instructions(meta):
    args = list(map( lambda x : x[0], meta['args'] ))
    opcodes = list(map( lambda x : x[0], meta['opcodes'] ))
    codecs = list(map( lambda x : x[0], meta['codecs'] ))
    parsed_insts = []

    for instline in meta['opcodes']:
        # initial values
        inst_args = []
        inst_opcode = []
        inst_extension = []
        inst_mask = 0
        inst_match = 0

        # get inst_name
        inst_name = instline[0]
        if '@' in inst_name:
            # not a real instruction
            continue
        instline.pop(0)

        assert len(instline) > 0, 'unexpected end of instline during parsing'

        while instline[0] not in codecs:
            if instline[0] in args:
                # known arg
                inst_args.append(instline[0])
            else:
                # bit constraint
                (bits, val) = instline[0].split('=', 1)
                if val != 'ignore':
                    match = 0
                    mask = 0
                    if '..' in bits:
                        # range of bits
                        (hi, lo) = map(int, bits.split('..', 1))
                        numbits = hi - lo + 1
                        mask = ((1 << numbits) - 1) << lo
                        match = int(val, 0) << lo
                    else:
                        # one bit
                        bindx = int(bits)
                        mask = 1 << bindx
                        match = int(val, 0) << bindx
                    assert mask & match == match, 'value too large for mask in instruction %s' % inst_name
                    assert inst_mask & mask == 0, 'multiple constraints for same bit in instruction %s' % isnt_name
                    inst_mask = inst_mask | mask
                    inst_match = inst_match | match
            instline.pop(0)
            assert len(instline) > 0, 'unexpected end of instline during parsing'

        assert len(instline) > 0, 'unexpected end of instline during parsing'

        # instline[0] == codec
        instline.pop(0)

        # rest of instline is extensions
        inst_extension = instline

        # now finish parsing the line
        bsv_val = bsv_match_mask_val(inst_match, inst_mask, 32)
        # print '%s: %s, args %s, extension %s' % (inst_name, bsv_val, str(inst_args), str(inst_extension))
        parsed_insts.append((inst_name, bsv_val, inst_args, inst_extension))
    return parsed_insts

def get_inst_types(args):
    def get_reg_type(reg, args):
        if reg in args:
            return 'i'
        elif 'f' + reg in args:
            return 'f'
        else:
            return 'n'
    def get_imm_type(args):
        imm_mapping = {
                'imm20'   : 'U',
                'jimm20'  : 'UJ',
                'imm12'   : 'I',
                'simm12'  : 'S',
                'sbimm12' : 'SB',
                'zimm'    : 'Z',
                'shamt5'  : 'I',
                'shamt6'  : 'I'
                }
        for imm_name in imm_mapping:
            if imm_name in args:
                return imm_mapping[imm_name]
        return 'None'

    rd  = get_reg_type('rd',  args)
    rs1 = get_reg_type('rs1', args)
    rs2 = get_reg_type('rs2', args)
    rs3 = get_reg_type('rs3', args)
    imm = get_imm_type(args)

    return (rd, rs1, rs2, rs3, imm)

if __name__ == '__main__':
    riscv_meta_dir = '../riscv-meta/meta/'
    meta_files = ['args', 'codecs', 'compression', 'constraints', 'csrs', 'descriptions', 'enums', 'extensions', 'formats', 'instructions', 'instructions-alt', 'opcodes', 'registers', 'types']
    meta = {}
    for f in meta_files:
        meta[f] = read_file(riscv_meta_dir + f)

    ## TODO: make these inputs for this script
    base = 'rv64'
    extension_letters = 'imafd'
    extensions = [base + ext for ext in extension_letters]

    insts = parse_instructions(meta)
    print 'extensions = ' + str(extensions)

    decoder = 'function InstType decode(Bit#(32) inst);\n'
    decoder = decoder + '    Maybe#(RegType) i = tagged Valid Gpr;\n'
    decoder = decoder + '    Maybe#(RegType) f = tagged Valid Fpu;\n'
    decoder = decoder + '    Maybe#(RegType) n = tagged Invalid;\n'
    decoder = decoder + '    return (case (inst) matches\n'
    macro_definitions = ''

    defined_macros = []
    skipped_macros = []
    for (inst_name, bsv_val, inst_args, inst_extension) in insts:
        macro_name = inst_name.replace('.','_').upper()
        (rd, rs1, rs2, rs3, imm) = get_inst_types(inst_args)
        if reduce( lambda x, y: x or y, [x == y for x in inst_extension for y in extensions] ):
            decoder = decoder + '            %-16sInstType{rs1: %s, rs2: %s, rs3: %s, dst: %s, imm: %-4s};\n' % ('`' + macro_name + ':',rs1,rs2,rs3,rd,imm)
            macro_definitions = macro_definitions + '`define %s %s\n' % (macro_name, bsv_val)
            defined_macros.append(macro_name)
        else:
            skipped_macros.append(macro_name)
    decoder = decoder + '            default:        ?;\n        endcase);\nendfunction'

    # finish up macro definitions
    for macro_name in skipped_macros:
        if macro_name not in defined_macros:
            macro_definitions = macro_definitions + '`define %s //\n' % macro_name
            defined_macros.append(macro_name)

    with open('Opcodes.bsv', 'w') as f:
        f.write(decoder)
    with open('Opcodes.defines', 'w') as f:
        f.write(macro_definitions)

