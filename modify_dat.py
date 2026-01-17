#!/usr/bin/env python3
"""
DAT文件多字段修改脚本 (Python - FileStream版)
支持：多字段修改 | in/out文件夹 | 日志记录 | 流式读写
"""
import os
import sys
from datetime import datetime

# ==================== 基本配置 ====================
FILE_NAME = sys.argv[1] if len(sys.argv) > 1 else "test.dat"
IN_FOLDER = "in"
OUT_FOLDER = "out"
LOG_FOLDER = "log"

RECORD_SIZE = 1300
HEADER_MARKER = ord('1')
DATA_MARKER = ord('2')

# ==================== 修改规则配置 ====================
MODIFY_RULES = [
    {
        "name": "Phone-1",
        "start_byte": 100,
        "phone_length": 10,
        "old_leading_zeros": 0,
        "old_trailing_zeros": 10,
        "new_leading_zeros": 6,
        "new_trailing_zeros": 4,
    },
    {
        "name": "Phone-2",
        "start_byte": 200,
        "phone_length": 10,
        "old_leading_zeros": 0,
        "old_trailing_zeros": 10,
        "new_leading_zeros": 6,
        "new_trailing_zeros": 4,
    },
    # 添加更多规则...
]

# ==================== 脚本逻辑 ====================
timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
input_file = os.path.join(IN_FOLDER, FILE_NAME)
output_file = os.path.join(OUT_FOLDER, FILE_NAME)
log_file = os.path.join(LOG_FOLDER, f"{FILE_NAME.replace('.dat','')}{timestamp}.log")

for folder in [OUT_FOLDER, LOG_FOLDER]:
    os.makedirs(folder, exist_ok=True)

if not os.path.exists(input_file):
    print(f"错误: 文件 '{input_file}' 不存在！")
    sys.exit(1)

log_lines = []
def log(msg):
    log_lines.append(msg)
    print(msg)

log("╔══════════════════════════════════════════════════════════════╗")
log("║  DAT File Modifier (Python - FileStream)                     ║")
log("╠══════════════════════════════════════════════════════════════╣")
log(f"║  Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S'):50}║")
log(f"║  Input:  {input_file:50}║")
log(f"║  Output: {output_file:50}║")
log("╚══════════════════════════════════════════════════════════════╝")
log("")

file_size = os.path.getsize(input_file)
record_count = file_size // RECORD_SIZE

log(f"File Size: {file_size} bytes")
log(f"Records: {record_count} | Rules: {len(MODIFY_RULES)}")
log("─" * 64)
log("")

modified_count = 0

# 使用FileStream流式读写
with open(input_file, "rb") as fin, open(output_file, "wb") as fout:
    for i in range(record_count):
        # 精确读取1300字节
        record = bytearray(fin.read(RECORD_SIZE))
        
        if len(record) != RECORD_SIZE:
            log(f"[#{i+1:4}] ERROR - 读取字节不足: {len(record)} / {RECORD_SIZE}")
            fout.write(record)
            continue
        
        record_num = i + 1
        first_byte = record[0]
        
        if first_byte == HEADER_MARKER:
            log(f"[#{record_num:4}] HEADER - Skipped")
        elif first_byte == DATA_MARKER:
            changes = []
            has_change = False
            
            for rule in MODIFY_RULES:
                field_offset = rule["start_byte"] - 1
                
                # 读取整个字段
                total_len = rule["old_leading_zeros"] + rule["phone_length"] + rule["old_trailing_zeros"]
                old_field = record[field_offset:field_offset + total_len].decode("ascii")
                
                # 检查是否已经是新格式
                expected_leading = "0" * rule["new_leading_zeros"]
                expected_trailing = "0" * rule["new_trailing_zeros"]
                expected_len = rule["new_leading_zeros"] + rule["phone_length"] + rule["new_trailing_zeros"]
                
                is_new_format = (
                    old_field.startswith(expected_leading) and 
                    old_field.endswith(expected_trailing) and
                    len(old_field) == expected_len
                )
                
                if is_new_format:
                    changes.append(f"  {rule['name']}: 没有变化")
                else:
                    # 按旧格式提取电话号码
                    phone_offset = field_offset + rule["old_leading_zeros"]
                    phone = record[phone_offset:phone_offset + rule["phone_length"]]
                    
                    # 构建新字段并直接写入record
                    new_field = (b'0' * rule["new_leading_zeros"] + 
                                phone + 
                                b'0' * rule["new_trailing_zeros"])
                    
                    record[field_offset:field_offset + len(new_field)] = new_field
                    changes.append(f"  {rule['name']}: [{old_field}] → [{new_field.decode()}]")
                    has_change = True
            
            if has_change:
                log(f"[#{record_num:4}] MODIFIED")
                modified_count += 1
            else:
                log(f"[#{record_num:4}] NO CHANGE")
            for c in changes:
                log(c)
        
        # 写入输出流（无论是否修改）
        fout.write(record)

log("")
log("─" * 64)
log(f"Summary: Modified {modified_count} / {record_count} records")
log("─" * 64)

with open(log_file, "w", encoding="utf-8") as f:
    f.write("\n".join(log_lines))

print(f"\n✓ Output: {output_file}")
print(f"✓ Log:    {log_file}")
