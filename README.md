# DAT File Modifier / DAT文件修改工具

A tool for batch modifying phone number fields in fixed-length record DAT files.

一个用于批量修改定长记录DAT文件中电话号码字段的工具。

DATファイル内の電話番号フィールドを一括修正するツール。

---

## 📁 文件结构 / File Structure

```
dat-modifier/
├── in/                          ← 输入文件夹 (放置原始DAT文件)
├── out/                         ← 输出文件夹 (自动生成)
├── log/                         ← 日志文件夹 (自动生成)
├── modify_dat_中文版.ps1        ← PowerShell脚本 (中文界面)
├── modify_dat_日文版.ps1        ← PowerShell脚本 (日本語)
├── modify_dat_中文版_详细注释.ps1  ← 带详细注释的学习版
├── modify_dat.py                ← Python版脚本
└── README.md
```

---

## 🚀 快速开始 / Quick Start

### PowerShell (Windows)

```powershell
# 1. 将DAT文件放入 in/ 文件夹
# 2. 运行脚本
.\modify_dat_中文版.ps1 -FileName "yourfile.dat"

# 或使用默认文件名 data.dat
.\modify_dat_中文版.ps1
```

### Python (跨平台)

```bash
# 1. 将DAT文件放入 in/ 文件夹
# 2. 运行脚本
python3 modify_dat.py yourfile.dat
```

---

## ⚙️ 配置说明 / Configuration

### 基本配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `$RecordSize` | `1300` | 每条记录的字节数 |
| `$HeaderMarker` | `0x31` ('1') | Header记录标识符 |
| `$DataMarker` | `0x32` ('2') | 数据记录标识符 |

### 修改规则

在脚本中修改 `$ModifyRules` 数组来配置需要修改的字段：

```powershell
$ModifyRules = @(
    @{
        Name             = "Phone-1"     # 规则名称
        StartByte        = 100           # 起始位置 (1-indexed)
        PhoneLength      = 10            # 电话号码长度
        OldLeadingZeros  = 0             # 旧格式前置0数量
        OldTrailingZeros = 10            # 旧格式后置0数量
        NewLeadingZeros  = 6             # 新格式前置0数量
        NewTrailingZeros = 4             # 新格式后置0数量
    }
    # 添加更多规则...
)
```

### 转换示例

```
旧格式: [1381234567][0000000000]  (电话号码 + 10个0)
新格式: [000000][1381234567][0000]  (6个0 + 电话号码 + 4个0)
```

---

## 📝 输出日志示例 / Log Example

```
╔══════════════════════════════════════════════════════════════╗
║  DAT File Modifier (FileStream)                              ║
╠══════════════════════════════════════════════════════════════╣
║  Time: 2026-01-12 21:30:00                                   ║
║  Input:  in/data.dat                                         ║
║  Output: out/data.dat                                        ║
╚══════════════════════════════════════════════════════════════╝

Records: 5 | Rules: 2
────────────────────────────────────────────────────────────────

[#   1] HEADER - Skipped
[#   2] MODIFIED
  Phone-1: [13812345670000000000] → [00000013812345670000]
  Phone-2: [13912345670000000000] → [00000013912345670000]
[#   3] NO CHANGE
  Phone-1: 没有变化
  Phone-2: 没有变化

────────────────────────────────────────────────────────────────
Summary: Modified 3 / 5 records
────────────────────────────────────────────────────────────────
```

---

## 📌 技术特点 / Features

- ✅ **FileStream流式读写** - 支持处理超大文件，内存占用低
- ✅ **精确字节控制** - 每次精确读取指定字节数
- ✅ **智能检测** - 自动识别已转换的记录，避免重复修改
- ✅ **详细日志** - 记录每条记录的修改前后内容
- ✅ **多语言支持** - 中文、日文界面可选

---

## 📄 License

MIT License
