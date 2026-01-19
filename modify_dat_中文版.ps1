# ============================================
# DAT文件多字段修改脚本 (v3 - BigEndianUnicode)
# 支持：多字段修改 | in/out文件夹 | 日志记录 | UTF-16BE编码
# ============================================

param(
    [string]$FileName = "data.dat"
)

# ==================== 文件夹配置 ====================
$BaseDir = $PSScriptRoot
$InFolder = Join-Path $BaseDir "in"
$OutFolder = Join-Path $BaseDir "out"
$LogFolder = Join-Path $BaseDir "log"

# ==================== 记录配置 ====================
# ==================== 配置文件加载 ====================
$ConfigFile = Join-Path $BaseDir "config.ini"
if (-not (Test-Path $ConfigFile)) { $ConfigFile = Join-Path $BaseDir "config_日本語.ini" }

function Parse-IniFile {
    param([string]$FilePath)
    $ini = @{}
    $section = "Global"
    if (-not (Test-Path $FilePath)) { return $ini }
    
    Get-Content $FilePath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(";") -or $line.StartsWith("#")) { return }
        if ($line -match "^\[(.*)\]$") {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        elseif ($line -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            $ini[$section][$key] = $value
        }
    }
    return $ini
}

$ConfigData = Parse-IniFile -FilePath $ConfigFile

# ==================== 记录配置 ====================
# 默认值
$RecordSize = 1300
$HeaderMarker = 0x31
$DataMarker = 0x32
$ZeroChar = "0"

# 从INI加载设置
if ($ConfigData.ContainsKey("Settings")) {
    if ($ConfigData["Settings"]["RecordSize"]) { $RecordSize = [int]$ConfigData["Settings"]["RecordSize"] }
    if ($ConfigData["Settings"]["HeaderMarker"]) { $HeaderMarker = [int]$ConfigData["Settings"]["HeaderMarker"] + 0x30 }
    if ($ConfigData["Settings"]["DataMarker"]) { $DataMarker = [int]$ConfigData["Settings"]["DataMarker"] + 0x30 }
}

# ==================== 修改规则配置 (从INI加载) ====================
$ModifyRules = @()
foreach ($key in $ConfigData.Keys) {
    if ($key -like "Rule-*") {
        $ModifyRules += @{
            Name             = $ConfigData[$key]["Name"]
            StartByte        = [int]$ConfigData[$key]["StartByte"]
            PhoneLength      = [int]$ConfigData[$key]["PhoneLength"]
            OldLeadingZeros  = [int]$ConfigData[$key]["OldLeadingZeros"]
            OldTrailingZeros = [int]$ConfigData[$key]["OldTrailingZeros"]
            NewLeadingZeros  = [int]$ConfigData[$key]["NewLeadingZeros"]
            NewTrailingZeros = [int]$ConfigData[$key]["NewTrailingZeros"]
        }
    }
}

if ($ModifyRules.Count -eq 0) {
    # 默认值
    $ModifyRules = @(
        @{ Name = "Phone-1"; StartByte = 100; PhoneLength = 10; OldLeadingZeros = 0; OldTrailingZeros = 10; NewLeadingZeros = 6; NewTrailingZeros = 4 },
        @{ Name = "Phone-2"; StartByte = 200; PhoneLength = 10; OldLeadingZeros = 0; OldTrailingZeros = 10; NewLeadingZeros = 6; NewTrailingZeros = 4 }
    )
}

# ==================== 脚本逻辑 ====================
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile = Join-Path $InFolder $FileName
$OutputFile = Join-Path $OutFolder $FileName
$LogFile = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null 
    }
}

if (-not (Test-Path $InputFile)) {
    Write-Host "错误: 文件 '$InputFile' 不存在！" -ForegroundColor Red
    exit 1
}

# 日志函数
$logContent = [System.Text.StringBuilder]::new()
function Log($msg) {
    [void]$logContent.AppendLine($msg)
    Write-Host $msg
}

# 开始处理
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT File Modifier v3 (FileStream)                           ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  Input:  $($InputFile.PadRight(50))║"
Log "║  Output: $($OutputFile.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / $RecordSize)

Log "File Size: $fileLength bytes"
Log "Records: $recordCount | Rules: $($ModifyRules.Count)"
Log ("─" * 64)
Log ""

$modifiedCount = 0
$recordBuffer = New-Object byte[] $RecordSize

# 使用FileStream流式读写
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        # 读取一条完整记录
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] ERROR - 读取字节不足: $bytesRead / $RecordSize"
            continue
        }
        
        $recordNum = $i + 1
        $firstByte = $recordBuffer[0]
        
        if ($firstByte -eq $HeaderMarker) {
            Log "[#$($recordNum.ToString().PadLeft(4))] HEADER - Skipped"
        }
        elseif ($firstByte -eq $DataMarker) {
            $changes = @()
            $hasChange = $false
            
            foreach ($rule in $ModifyRules) {
                $fieldOffset = $rule.StartByte - 1
                
                # 读取整个字段 (BigEndianUnicode: 每字符2字节)
                $totalCharLen = $rule.OldLeadingZeros + $rule.PhoneLength + $rule.OldTrailingZeros
                $totalByteLen = $totalCharLen * 2
                $fieldBytes = New-Object byte[] $totalByteLen
                [Array]::Copy($recordBuffer, $fieldOffset, $fieldBytes, 0, $totalByteLen)
                $oldField = [System.Text.Encoding]::BigEndianUnicode.GetString($fieldBytes)
                
                # 检查是否已经是新格式
                $expectedLeading = "0" * $rule.NewLeadingZeros
                $expectedTrailing = "0" * $rule.NewTrailingZeros
                $expectedLen = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
                
                $isNewFormat = (
                    $oldField.StartsWith($expectedLeading) -and 
                    $oldField.EndsWith($expectedTrailing) -and
                    $oldField.Length -eq $expectedLen
                )
                
                if ($isNewFormat) {
                    $changes += "  $($rule.Name): 没有变化"
                }
                else {
                    # 按旧格式提取电话号码 (BigEndianUnicode)
                    $phoneCharOffset = $fieldOffset + ($rule.OldLeadingZeros * 2)
                    $phoneByteLen = $rule.PhoneLength * 2
                    $phone = New-Object byte[] $phoneByteLen
                    [Array]::Copy($recordBuffer, $phoneCharOffset, $phone, 0, $phoneByteLen)
                    
                    # 构建新字段并写入recordBuffer (BigEndianUnicode)
                    $newCharLen = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
                    
                    # 填充前置0
                    $leadingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewLeadingZeros)
                    [Array]::Copy($leadingZeros, 0, $recordBuffer, $fieldOffset, $leadingZeros.Length)
                    
                    # 复制电话号码
                    [Array]::Copy($phone, 0, $recordBuffer, $fieldOffset + $leadingZeros.Length, $phoneByteLen)
                    
                    # 填充后置0
                    $trailingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewTrailingZeros)
                    [Array]::Copy($trailingZeros, 0, $recordBuffer, $fieldOffset + $leadingZeros.Length + $phoneByteLen, $trailingZeros.Length)
                    
                    $newByteLen = $newCharLen * 2
                    $newFieldBytes = New-Object byte[] $newByteLen
                    [Array]::Copy($recordBuffer, $fieldOffset, $newFieldBytes, 0, $newByteLen)
                    $newFieldStr = [System.Text.Encoding]::BigEndianUnicode.GetString($newFieldBytes)
                    $changes += "  $($rule.Name): [$oldField] → [$newFieldStr]"
                    $hasChange = $true
                }
            }
            
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] MODIFIED"
                $modifiedCount++
            }
            else {
                Log "[#$($recordNum.ToString().PadLeft(4))] NO CHANGE"
            }
            foreach ($c in $changes) { Log $c }
        }
        
        # 写入输出流（无论是否修改）
        $outputStream.Write($recordBuffer, 0, $RecordSize)
    }
}
finally {
    $inputStream.Close()
    $outputStream.Close()
}

Log ""
Log ("─" * 64)
Log "Summary: Modified $modifiedCount / $recordCount records"
Log ("─" * 64)

[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

Write-Host ""
Write-Host "✓ Output: $OutputFile" -ForegroundColor Green
Write-Host "✓ Log:    $LogFile" -ForegroundColor Green
