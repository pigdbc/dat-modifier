#!/usr/bin/env python3
"""为dat-modifier生成示例文件 (BigEndianUnicode编码)"""
import os

RECORD_SIZE = 1300

def create_record(first_byte, phone1, phone2):
    record = bytearray(b' ' * RECORD_SIZE)
    record[0] = first_byte
    # Phone-1: 100-139字节 (旧格式: 电话+10个0, BigEndianUnicode每字符2字节, 共20字符*2=40字节)
    phone1_data = (phone1 + "0" * 10).encode('utf-16-be')
    record[99:99+len(phone1_data)] = phone1_data
    # Phone-2: 200-239字节 (旧格式: 电话+10个0, BigEndianUnicode每字符2字节)
    phone2_data = (phone2 + "0" * 10).encode('utf-16-be')
    record[199:199+len(phone2_data)] = phone2_data
    return record

# 获取脚本所在目录
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(BASE_DIR, "in"), exist_ok=True)

data = bytearray()
data.extend(create_record(ord('1'), "0000000000", "0000000000"))  # Header
data.extend(create_record(ord('2'), "1381234567", "1391234567"))
data.extend(create_record(ord('2'), "1382345678", "1392345678"))
data.extend(create_record(ord('2'), "1383456789", "1393456789"))

output_file = os.path.join(BASE_DIR, "in", "data.dat")
with open(output_file, "wb") as f:
    f.write(data)
print(f"Created: {output_file} ({len(data)} bytes)")
