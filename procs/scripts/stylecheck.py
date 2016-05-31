#!/usr/bin/env python3

import sys
import os

def print_usage():
    print("%s bsvfile" % sys.argv[0])
    print("    checks the style for the provided file")
    print("%s bsvdirectory" % sys.argv[0])
    print("    checks the style for all bsv files in the directory")

def get_bsv_files(foldername):
    bsvfiles = []
    contents = list(map(lambda f : foldername + '/' + f, os.listdir(foldername)))
    for f in contents:
        if os.path.isdir(f):
            bsvfiles = bsvfiles + get_bsv_files(f)
        elif os.path.isfile(f):
            if f.endswith('.bsv'):
                bsvfiles = bsvfiles + [f]
    return bsvfiles

def check_file(filename):
    error = False
    newline_error = False
    with open(filename, 'r') as f:
        linenum = 0
        for line in f:
            linenum = linenum + 1
            # Rule 0 - lines end with '\n'
            if not newline_error:
                if ('\r\n' in f.newlines) or ('\r' in f.newlines):
                    print("[%s:%d] [rule 0 - only unix newlines]" % (os.path.basename(filename), linenum))
                    error = True
                    newline_error = True
            # strip newline characters if it exists
            if len(line) > 1:
                if line[-1] == '\n':
                    line = line[:-1]
            # Rule 1 - no tab characters
            if '\t' in line:
                error = True
                print("[%s:%d] [rule 1 - no tab characters] %s" % (os.path.basename(filename), linenum, line.replace('\t','--->')))
            # Rule 2 - no XXX, TODO, or FIXME messages
            upperline = line.upper()
            if ('XXX' in upperline) or ('TODO' in upperline) or ('FIXME' in upperline):
                error = True
                print("[%s:%d] [rule 2 - no XXX, TODO, or FIXME] %s" % (os.path.basename(filename), linenum, line))
            # Rule 3 - lines don't end wtih whitespace
            if len(line) > 1:
                if line[-1].isspace():
                    print("[%s:%d] [rule 3 - no whitespace at end of line] %s" % (os.path.basename(filename), linenum, line))
                    error = True
            # Rule 4 - lines aren't longer than 80 characters
            if len(line) > 80:
                print("[%s:%d] [rule 4 - line too long] %s" % (os.path.basename(filename), linenum, line))
                error = True
    return error

if __name__ == "__main__":
    if len(sys.argv) <= 1:
        print_usage()
        sys.exit(1)

    for arg in sys.argv[1:]:
        files = []
        if os.path.isdir(arg):
            files = get_bsv_files(arg)
        elif os.path.isfile(arg):
            files = [arg]
        else:
            print("[ERROR] Can't find " + arg)
            sys.exit(1)

        for f in files:
            check_file(f)
