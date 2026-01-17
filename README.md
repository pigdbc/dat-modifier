# DAT File Modifier / DAT文件修改工具

批量修改定长记录DAT文件中电话号码字段的工具。支持 BigEndianUnicode (UTF-16BE) 编码。

DATファイル内の電話番号フィールドを一括修正するツール。

---

## 📁 文件结构 / File Structure

```
3-dat-modifier/
├── in/                          ← 输入文件夹 (放置原始DAT文件)
├── out/                         ← 输出文件夹 (自动生成)
├── log/                         ← 日志文件夹 (自动生成)
├── config.ini                   ← 配置文件 (中文)
├── config_日本語.ini            ← 配置文件 (日本語)
├── modify_dat.py                ← Python脚本 (推荐)
├── modify_dat_中文版.ps1        ← PowerShell脚本
├── modify_dat_日文版.ps1        ← PowerShell脚本
└── README.md
```

---

## 🚀 快速开始 / Quick Start

### Python (推荐)

```bash
# 使用默认配置文件 config.ini
python3 modify_dat.py data.dat

# 使用日语配置文件
python3 modify_dat.py data.dat config_日本語.ini
```

### PowerShell (Windows)

```powershell
.\modify_dat_中文版.ps1 -FileName "data.dat"
```

---

## ⚙️ 配置文件说明 / Configuration

规则配置已从代码中分离，统一使用 `config.ini` 文件：

```ini
[Settings]
RecordSize = 1300
HeaderMarker = 1
DataMarker = 2

[Rule-1]
Name = Phone-1
StartByte = 100              # 起始位置 (1-indexed)
PhoneLength = 10             # 电话号码长度
OldLeadingZeros = 0          # 旧格式前置0数量
OldTrailingZeros = 10        # 旧格式后置0数量
NewLeadingZeros = 6          # 新格式前置0数量
NewTrailingZeros = 4         # 新格式后置0数量

[Rule-2]
Name = Phone-2
StartByte = 200
PhoneLength = 10
OldLeadingZeros = 0
OldTrailingZeros = 10
NewLeadingZeros = 6
NewTrailingZeros = 4
```

### 转换示例

```
旧格式: [1381234567][0000000000]  (电话号码 + 10个0)
新格式: [000000][1381234567][0000]  (6个0 + 电话号码 + 4个0)
```

---

## 📝 运行示例

```
╔══════════════════════════════════════════════════════════════╗
║  DAT Field Modifier (BigEndianUnicode) - INI Config          ║
╚══════════════════════════════════════════════════════════════╝
Config: config.ini
Input:  in/data.dat
Output: out/data.dat

[#   2] MODIFIED
  Phone-1: [13812345670000000000] → [00000013812345670000]
  Phone-2: [13912345670000000000] → [00000013912345670000]

Summary: 3/4 records modified
```

---

## 📌 技术特点 / Features

- ✅ **INI配置文件** - 规则配置与代码分离
- ✅ **BigEndianUnicode** - 支持 UTF-16BE 编码
- ✅ **流式读写** - 支持处理超大文件
- ✅ **智能检测** - 自动识别已转换的记录
- ✅ **多语言支持** - 中文、日本語配置文件

---

## 📄 License

MIT License
