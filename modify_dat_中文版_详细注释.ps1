# ============================================
# DAT文件多字段修改脚本 (中文版 - 详细注释版 - BigEndianUnicode)
# 功能说明：
#   1. 从in文件夹读取DAT文件
#   2. 逐条记录处理，修改指定位置的电话号码格式
#   3. 将修改后的文件写入out文件夹
#   4. 生成详细的处理日志到log文件夹
# ============================================

# 定义脚本参数：文件名，默认为 data.dat
# 使用方式: .\script.ps1 -FileName "myfile.dat"
param(
    [string]$FileName = "data.dat"  # 要处理的DAT文件名（不含路径）
)

# ==================== 文件夹配置 ====================
# 这些变量定义了输入、输出和日志文件的存放位置
$InFolder  = "in"   # 输入文件夹：存放原始DAT文件
$OutFolder = "out"  # 输出文件夹：存放修改后的DAT文件
$LogFolder = "log"  # 日志文件夹：存放处理日志

# ==================== 配置文件加载 ====================
$ConfigFile = "config.ini"
# 检查是否存在 config.ini，如果不存在则尝试加载 config_日本語.ini
if (-not (Test-Path $ConfigFile)) {
    $ConfigFile = "config_日本語.ini"
    if (-not (Test-Path $ConfigFile)) {
        Write-Host "警告: 未找到 config.ini 或 config_日本語.ini 文件，将使用默认配置。" -ForegroundColor Yellow
        $ConfigFile = $null # 标记为未找到配置文件
    }
}

# 定义一个函数来解析INI文件
function Parse-IniFile {
    param([string]$FilePath)
    $ini = @{} # 初始化一个哈希表来存储INI内容
    $section = "Global" # 默认节名
    
    # 如果文件不存在，则返回空哈希表
    if (-not (Test-Path $FilePath)) { return $ini }
    
    # 读取文件内容，使用UTF8编码
    Get-Content $FilePath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim() # 移除行首尾空格
        
        # 跳过空行、注释行（以;或#开头）
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(";") -or $line.StartsWith("#")) { return }
        
        # 匹配节头，例如 [SectionName]
        if ($line -match "^\[(.*)\]$") {
            $section = $matches[1] # 提取节名
            $ini[$section] = @{} # 为新节创建一个新的哈希表
        } 
        # 匹配键值对，例如 Key=Value
        elseif ($line -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim() # 提取键名
            $value = $matches[2].Trim() # 提取值
            
            # 如果当前节不存在，则创建它（以防文件格式不规范）
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            $ini[$section][$key] = $value # 将键值对添加到当前节
        }
    }
    return $ini # 返回解析后的INI数据
}

# 加载配置文件
$ConfigData = @{}
if ($ConfigFile) {
    $ConfigData = Parse-IniFile -FilePath $ConfigFile
    if ($ConfigData.Count -gt 0) {
        Write-Host "已加载配置文件: $ConfigFile" -ForegroundColor Green
    } else {
        Write-Host "警告: 配置文件 '$ConfigFile' 为空或解析失败，将使用默认配置。" -ForegroundColor Yellow
    }
}

# ==================== 记录配置 ====================
# 默认值
$RecordSize   = 1300      # 每条记录的固定字节数（大端存储）
$HeaderMarker = 0x31      # Header记录的首字节标识符（ASCII字符'1'的十六进制值）
$DataMarker   = 0x32      # 数据记录的首字节标识符（ASCII字符'2'的十六进制值）
$ZeroChar     = "0"       # 用于填充的0字符（BigEndianUnicode编码使用字符串）

# 从 INI 配置加载设置 (如果存在)
if ($ConfigData.ContainsKey("Settings")) {
    $settings = $ConfigData["Settings"]
    if ($settings["RecordSize"]) { $RecordSize = [int]$settings["RecordSize"] }
    # HeaderMarker 和 DataMarker 在INI中可能配置为字符 '1' 或 '2'，需要转换为十六进制ASCII值
    if ($settings["HeaderMarker"]) { $HeaderMarker = [byte][char]$settings["HeaderMarker"] }
    if ($settings["DataMarker"]) { $DataMarker = [byte][char]$settings["DataMarker"] }
    if ($settings["ZeroChar"]) { $ZeroChar = $settings["ZeroChar"] }
}

# ==================== 修改规则配置 (从INI加载) ====================
# 每条规则定义了一个需要修改的电话号码字段
    #     Name             = "Phone-3"
    #     StartByte        = 300
    #     ...
    # }
)

# ==================== 脚本初始化 ====================

# 生成时间戳，用于日志文件名
# 格式：2026-01-12_21-30-00
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# 构建完整的文件路径
$InputFile  = Join-Path $InFolder $FileName                                   # 输入文件完整路径
$OutputFile = Join-Path $OutFolder $FileName                                  # 输出文件完整路径
$LogFile    = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"  # 日志文件路径

# 确保输出文件夹和日志文件夹存在
# 如果不存在则自动创建
foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) {                           # 检查文件夹是否存在
        New-Item -ItemType Directory -Path $folder -Force | Out-Null  # 创建文件夹，-Force确保父目录也会被创建
    }
}

# 检查输入文件是否存在
if (-not (Test-Path $InputFile)) {
    Write-Host "错误: 文件 '$InputFile' 不存在！" -ForegroundColor Red  # 红色显示错误信息
    exit 1  # 退出脚本，返回错误码1
}

# ==================== 日志函数定义 ====================

# 创建一个StringBuilder对象用于收集日志内容
# StringBuilder比字符串拼接效率更高，适合频繁追加的场景
$logContent = [System.Text.StringBuilder]::new()

# 定义日志函数：同时输出到控制台和收集到StringBuilder
function Log($msg) {
    [void]$logContent.AppendLine($msg)  # 追加到StringBuilder，[void]用于忽略返回值
    Write-Host $msg                      # 同时输出到控制台
}

# ==================== 显示脚本信息头 ====================

# 使用Unicode框线字符绘制美观的信息框
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT File Modifier (FileStream) - 中文详细注释版             ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  输入:  $($InputFile.PadRight(50))║"   # PadRight确保对齐
Log "║  输出: $($OutputFile.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""

# ==================== 获取文件信息 ====================

# 获取输入文件的详细信息
$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length  # 文件总字节数

# 计算记录总数：文件大小 ÷ 每条记录大小
# [Math]::Floor 用于向下取整（确保只处理完整的记录）
$recordCount = [Math]::Floor($fileLength / $RecordSize)

# 显示文件统计信息
Log "文件大小: $fileLength 字节"
Log "记录总数: $recordCount | 规则数量: $($ModifyRules.Count)"
Log ("─" * 64)  # 打印64个横线作为分隔符
Log ""

# ==================== 初始化计数器和缓冲区 ====================

$modifiedCount = 0                               # 已修改的记录计数
$recordBuffer = New-Object byte[] $RecordSize    # 创建字节数组作为记录缓冲区

# ==================== 打开文件流 ====================

# 使用FileStream进行流式读写，相比ReadAllBytes：
# 优点：内存占用低，支持处理超大文件
# 原理：每次只读取一条记录（1300字节）到内存

$inputStream = [System.IO.File]::OpenRead($InputFile)    # 以只读模式打开输入流
$outputStream = [System.IO.File]::Create($OutputFile)    # 创建输出文件流（会覆盖已存在的文件）

# ==================== 主处理循环 ====================

try {
    # 遍历每一条记录
    for ($i = 0; $i -lt $recordCount; $i++) {
        
        # 从输入流读取一条完整记录（1300字节）到缓冲区
        # Read方法返回实际读取的字节数
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        # 检查是否读取了完整的记录
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] 错误 - 读取字节不足: $bytesRead / $RecordSize"
            continue  # 跳过这条不完整的记录
        }
        
        $recordNum = $i + 1                  # 记录序号（从1开始，用于显示）
        $firstByte = $recordBuffer[0]        # 获取记录的第一个字节（标识符）
        
        # 根据首字节判断记录类型
        if ($firstByte -eq $HeaderMarker) {
            # 首字节是'1'（0x31），这是Header记录，跳过不处理
            Log "[#$($recordNum.ToString().PadLeft(4))] HEADER - 已跳过"
        }
        elseif ($firstByte -eq $DataMarker) {
            # 首字节是'2'（0x32），这是数据记录，需要处理
            
            $changes = @()        # 存储本条记录的修改详情
            $hasChange = $false   # 标记本条记录是否有任何修改
            
            # 遍历每条修改规则
            foreach ($rule in $ModifyRules) {
                
                # 计算字段在记录中的偏移量
                # StartByte是1-indexed（从1开始），数组是0-indexed，所以减1
                $fieldOffset = $rule.StartByte - 1
                
                # 计算字段总长度（前置0 + 电话号码 + 后置0）
                $totalLen = $rule.OldLeadingZeros + $rule.PhoneLength + $rule.OldTrailingZeros
                
                # 从缓冲区读取原始字段内容，转换为BigEndianUnicode字符串
                # BigEndianUnicode每个字符占2字节，所以读取长度要乘以2
                $fieldBytes = New-Object byte[] ($totalLen * 2)
                [Array]::Copy($recordBuffer, $fieldOffset, $fieldBytes, 0, $totalLen * 2)
                $oldField = [System.Text.Encoding]::BigEndianUnicode.GetString($fieldBytes)
                
                # ========== 检查是否已经是新格式 ==========
                # 新格式特征：以指定数量的0开头，以指定数量的0结尾
                $expectedLeading = "0" * $rule.NewLeadingZeros    # 期望的前置0字符串
                $expectedTrailing = "0" * $rule.NewTrailingZeros  # 期望的后置0字符串
                $expectedLen = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros  # 期望的总长度
                
                # 判断条件：前缀匹配 AND 后缀匹配 AND 长度匹配
                $isNewFormat = (
                    $oldField.StartsWith($expectedLeading) -and 
                    $oldField.EndsWith($expectedTrailing) -and
                    $oldField.Length -eq $expectedLen
                )
                
                if ($isNewFormat) {
                    # 已经是新格式，无需修改
                    $changes += "  $($rule.Name): 没有变化"
                } else {
                    # ========== 执行格式转换 ==========
                    
                    # 计算电话号码在字段中的起始位置（BigEndianUnicode每字符2字节）
                    $phoneOffset = $fieldOffset + $rule.OldLeadingZeros * 2
                    
                    # 创建字节数组存储提取的电话号码（长度*2因为BigEndianUnicode）
                    $phone = New-Object byte[] ($rule.PhoneLength * 2)
                    
                    # 从recordBuffer复制电话号码到phone数组
                    # 参数：源数组, 源起始索引, 目标数组, 目标起始索引, 复制长度
                    [Array]::Copy($recordBuffer, $phoneOffset, $phone, 0, $rule.PhoneLength * 2)
                    
                    # 计算新字段的总长度
                    $newLen = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
                    
                    # ===== 直接在recordBuffer中构建新字段 =====
                    
                    # 步骤1：填充前置0（使用BigEndianUnicode编码）
                    $leadingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewLeadingZeros)
                    [Array]::Copy($leadingZeros, 0, $recordBuffer, $fieldOffset, $rule.NewLeadingZeros * 2)
                    
                    # 步骤2：复制电话号码到新位置（偏移量按字节计算）
                    [Array]::Copy($phone, 0, $recordBuffer, $fieldOffset + $rule.NewLeadingZeros * 2, $rule.PhoneLength * 2)
                    
                    # 步骤3：填充后置0（使用BigEndianUnicode编码）
                    $trailingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewTrailingZeros)
                    [Array]::Copy($trailingZeros, 0, $recordBuffer, $fieldOffset + ($rule.NewLeadingZeros + $rule.PhoneLength) * 2, $rule.NewTrailingZeros * 2)
                    
                    # 读取修改后的字段内容（用于日志显示）
                    $newFieldBytes = New-Object byte[] ($newLen * 2)
                    [Array]::Copy($recordBuffer, $fieldOffset, $newFieldBytes, 0, $newLen * 2)
                    $newFieldStr = [System.Text.Encoding]::BigEndianUnicode.GetString($newFieldBytes)
                    
                    # 记录修改详情
                    $changes += "  $($rule.Name): [$oldField] → [$newFieldStr]"
                    $hasChange = $true  # 标记本条记录有修改
                }
            }
            
            # 输出本条记录的处理结果
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] 已修改"
                $modifiedCount++  # 增加已修改计数
            } else {
                Log "[#$($recordNum.ToString().PadLeft(4))] 无变化"
            }
            
            # 输出每个字段的详细修改信息
            foreach ($c in $changes) { Log $c }
        }
        
        # ========== 写入输出流 ==========
        # 无论是否修改，都要将记录写入输出文件
        # 这确保了输出文件包含完整的所有记录
        $outputStream.Write($recordBuffer, 0, $RecordSize)
    }
}
finally {
    # ========== 确保流被正确关闭 ==========
    # finally块确保即使发生异常，流也会被关闭
    # 这是防止资源泄露的最佳实践
    $inputStream.Close()
    $outputStream.Close()
}

# ==================== 输出处理摘要 ====================

Log ""
Log ("─" * 64)
Log "处理摘要: 修改了 $modifiedCount / $recordCount 条记录"
Log ("─" * 64)

# ==================== 保存日志文件 ====================

# 将收集的日志内容写入文件
[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

# ==================== 显示完成信息 ====================

Write-Host ""
Write-Host "✓ 输出文件: $OutputFile" -ForegroundColor Green
Write-Host "✓ 日志文件: $LogFile" -ForegroundColor Green
