#!/usr/bin/env python3
"""为dat-modifier生成示例文件"""
import os

RECORD_SIZE = 1300

def create_record(first_byte, phone1, phone2):
    record = bytearray(b' ' * RECORD_SIZE)
    record[0] = first_byte
    # Phone-1: 100-119字节 (旧格式: 电话+10个0)
    record[99:119] = (phone1 + "0" * 10).encode()
    # Phone-2: 200-219字节 (旧格式: 电话+10个0)
    record[199:219] = (phone2 + "0" * 10).encode()
    return record

data = bytearray()
data.extend(create_record(ord('1'), "0000000000", "0000000000"))  # Header
data.extend(create_record(ord('2'), "1381234567", "1391234567"))
data.extend(create_record(ord('2'), "1382345678", "1392345678"))
data.extend(create_record(ord('2'), "1383456789", "1393456789"))

with open("in/sample.dat", "wb") as f:
    f.write(data)
print(f"Created: in/sample.dat ({len(data)} bytes)")
