#!/usr/bin/env python3
"""
DAT文件字段修改脚本 (Python版 - INI配置)
Reads configuration from config.ini
"""
import os
import sys
import configparser
from datetime import datetime

def load_config(config_file='config.ini'):
    """Load configuration from INI file"""
    config = configparser.ConfigParser()
    config.read(config_file, encoding='utf-8')
    
    settings = {
        'RecordSize': config.getint('Settings', 'RecordSize', fallback=1300),
        'HeaderMarker': config.getint('Settings', 'HeaderMarker', fallback=1),
        'DataMarker': config.getint('Settings', 'DataMarker', fallback=2),
    }
    
    rules = []
    for section in config.sections():
        if section.startswith('Rule-'):
            rule = {
                'name': config.get(section, 'Name', fallback=section),
                'start_byte': config.getint(section, 'StartByte'),
                'phone_length': config.getint(section, 'PhoneLength'),
                'old_leading_zeros': config.getint(section, 'OldLeadingZeros'),
                'old_trailing_zeros': config.getint(section, 'OldTrailingZeros'),
                'new_leading_zeros': config.getint(section, 'NewLeadingZeros'),
                'new_trailing_zeros': config.getint(section, 'NewTrailingZeros'),
            }
            rules.append(rule)
    
    return settings, rules

def main():
    # 使用脚本所在目录作为基础目录
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    
    filename = sys.argv[1] if len(sys.argv) > 1 else 'data.dat'
    config_file = os.path.join(BASE_DIR, sys.argv[2] if len(sys.argv) > 2 else 'config.ini')
    
    if not os.path.exists(config_file):
        print(f"Error: Config file {config_file} not found!")
        return 1
    
    settings, rules = load_config(config_file)
    
    RECORD_SIZE = settings['RecordSize']
    HEADER_MARKER = 0x30 + settings['HeaderMarker']
    DATA_MARKER = 0x30 + settings['DataMarker']
    ZERO_CHAR = '0'
    
    input_file = os.path.join(BASE_DIR, 'in', filename)
    output_file = os.path.join(BASE_DIR, 'out', filename)
    
    os.makedirs(os.path.join(BASE_DIR, 'out'), exist_ok=True)
    os.makedirs(os.path.join(BASE_DIR, 'log'), exist_ok=True)
    
    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found!")
        return 1
    
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    log_file = os.path.join(BASE_DIR, 'log', f'{filename.replace(".dat", "")}_{timestamp}.log')
    
    logs = []
    def log(msg):
        logs.append(msg)
        print(msg)
    
    log("╔══════════════════════════════════════════════════════════════╗")
    log("║  DAT Field Modifier (BigEndianUnicode) - INI Config          ║")
    log("╚══════════════════════════════════════════════════════════════╝")
    log(f"Config: {config_file}")
    log(f"Input:  {input_file}")
    log(f"Output: {output_file}")
    log("")
    
    file_size = os.path.getsize(input_file)
    record_count = file_size // RECORD_SIZE
    log(f"File size: {file_size} bytes, Records: {record_count}, Rules: {len(rules)}")
    log("")
    log("─" * 64)
    
    modified_count = 0
    
    with open(input_file, 'rb') as f_in, open(output_file, 'wb') as f_out:
        for i in range(record_count):
            record = bytearray(f_in.read(RECORD_SIZE))
            record_num = i + 1
            first_byte = record[0]
            
            if first_byte == HEADER_MARKER:
                log(f"[#{record_num:4d}] HEADER - Skip")
            elif first_byte == DATA_MARKER:
                changes = []
                has_change = False
                
                for rule in rules:
                    offset = rule['start_byte'] - 1
                    total_len = rule['old_leading_zeros'] + rule['phone_length'] + rule['old_trailing_zeros']
                    byte_len = total_len * 2  # BigEndianUnicode
                    
                    old_bytes = bytes(record[offset:offset+byte_len])
                    old_field = old_bytes.decode('utf-16-be', errors='replace')
                    
                    # Check if already new format
                    expected_leading = ZERO_CHAR * rule['new_leading_zeros']
                    expected_trailing = ZERO_CHAR * rule['new_trailing_zeros']
                    
                    is_new = (old_field.startswith(expected_leading) and 
                             old_field.endswith(expected_trailing))
                    
                    if is_new:
                        changes.append(f"  {rule['name']}: No change")
                    else:
                        # Extract phone from old format
                        phone_offset = offset + rule['old_leading_zeros'] * 2
                        phone_len = rule['phone_length'] * 2
                        phone = bytes(record[phone_offset:phone_offset+phone_len])
                        
                        # Build new field
                        leading = (ZERO_CHAR * rule['new_leading_zeros']).encode('utf-16-be')
                        trailing = (ZERO_CHAR * rule['new_trailing_zeros']).encode('utf-16-be')
                        new_field = leading + phone + trailing
                        
                        record[offset:offset+len(new_field)] = new_field
                        new_str = new_field.decode('utf-16-be')
                        changes.append(f"  {rule['name']}: [{old_field}] → [{new_str}]")
                        has_change = True
                
                if has_change:
                    log(f"[#{record_num:4d}] MODIFIED")
                    for c in changes:
                        log(c)
                    modified_count += 1
            
            f_out.write(record)
    
    log("")
    log("─" * 64)
    log(f"Summary: {modified_count}/{record_count} records modified")
    
    with open(log_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(logs))
    
    print(f"\n✓ Output: {output_file}")
    print(f"✓ Log: {log_file}")
    return 0

if __name__ == '__main__':
    sys.exit(main())
