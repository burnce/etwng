#!/usr/bin/env python3

import struct, os, sys
import argparse
import re

# For easy file reading and writing interactions
def read_long(fhandle):
  return struct.unpack('<l', fhandle.read(4))[0]

def read_cstr(handle):
  char = ''
  filename = b''
  flen = 0
  while char != b'\x00':
    char = handle.read(1)
    if (char != b'\x00'):
      filename += char
    flen += 1
  return (filename.decode("iso-8859-1"), flen)


def removeDir(path):
  # remove all files in a folder
  if not (os.path.isdir(path)):
    return True
  files = os.listdir(path)
  for x in files:
    fullpath=os.path.join(path, x)
    if os.path.isfile(fullpath):
      os.remove(fullpath)
    elif os.path.isdir(fullpath):
      removeDir(fullpath)
  os.rmdir(path)

def copy_data(source, dest, offset, length):
  source.seek(offset)
  for i in range(length//(2**20)):
    dest.write(source.read(2**20))
  j = (length%(2**20))
  if j:
    dest.write(source.read(j))


def saveFile(handle, outputdir, path, length, offset):
  print('Exporting '+path+', length: '+str(length)+', at offset: '+str(offset))

  # create output directory
  dir = os.path.split(os.path.join(outputdir, path))[0]
  if not os.path.isdir(dir):
    os.makedirs(dir)

  output = open(os.path.join(outputdir, path), 'wb')
  copy_data(handle, output, offset, length)
  output.close()

def unpackPackArchive(pack_path, outputdir, args):
  handle      = open(pack_path,"rb")
  magic       = handle.read(4)
  mod_type    = read_long(handle)
  deps_count  = read_long(handle)
  deps_len    = read_long(handle)
  files_count = read_long(handle)
  files_len   = read_long(handle)

  file_extra = (mod_type & 0x40 != 0)
  file_extra_len = 8
  mod_type = mod_type & 0x3F

  if magic == b"PFH2" or magic == b"PFH3":
    header_len = 32 + deps_len + files_len
    handle.seek(32 + deps_len)
  elif magic == b"PFH4": # Rome 2
    header_len = 28 + deps_len + files_len
    handle.seek(28 + deps_len)
    file_extra_len = 4
  elif magic == b"PFH1" or magic == b"PFH0":
    header_len = 24 + deps_len + files_len
    handle.seek(24 + deps_len)
  else:
    raise Exception("Unknown magic number %s" % magic)

  offset = header_len
  files = []
  for i in range(files_count):
    # read length of file
    data_len = read_long(handle)
    if file_extra:
      handle.read(file_extra_len)
    fn, fn_len = read_cstr(handle)
    files.append((fn, data_len, offset))
    offset += data_len

  # fnmatch is basically broken
  for (path, length, offset) in files:
    path = path.replace("\\", "/")
    if args.glob:
      if not re.match(args.glob, path):
        continue
    saveFile(handle, outputdir, path, length, offset)

parser = argparse.ArgumentParser(description="Unpack Total War *.pack archives")
parser.add_argument('-g', '--glob', help='only extract files matching regexp', type=str)
parser.add_argument('files', type=argparse.FileType('r'), nargs='+')

args = parser.parse_args()

# main
for fn in args.files:
  dn = "unpacked/" + fn.name.split("/")[-1].replace(".pack", "")
  if dn:
    removeDir(dn)
  unpackPackArchive(fn.name, dn, args)
