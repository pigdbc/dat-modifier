# ============================================
# DATファイル マルチフィールド修正スクリプト (BigEndianUnicode版)
# 機能：複数フィールド修正 | in/outフォルダ | ログ記録 | ストリーム読み書き
# 対応：UTF-16BE (BigEndianUnicode) エンコード
# ============================================

param(
    [string]$FileName = "data.dat"
)

# ==================== フォルダ設定 ====================
$BaseDir = $PSScriptRoot
$InFolder = Join-Path $BaseDir "in"
$OutFolder = Join-Path $BaseDir "out"
$LogFolder = Join-Path $BaseDir "log"

# ==================== 設定ファイル読込 ====================
$ConfigFile = Join-Path $BaseDir "config.ini"
if ($args.Count -gt 0) { $ConfigFile = Join-Path $BaseDir $args[0] }

if (-not (Test-Path $ConfigFile)) {
    Write-Host "エラー: 設定ファイル '$ConfigFile' が見つかりません！" -ForegroundColor Red
    exit 1
}

function Parse-IniFile {
    param([string]$FilePath)
    $ini = @{}
    $section = "Global"
    
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

# ==================== レコード設定 (INIから読込) ====================
if ($ConfigData.ContainsKey("Settings")) {
    $RecordSizeChars = if ($ConfigData["Settings"]["RecordSize"]) { [int]$ConfigData["Settings"]["RecordSize"] } else { 1300 }
    $HeaderMarker = if ($ConfigData["Settings"]["HeaderMarker"]) { [int]$ConfigData["Settings"]["HeaderMarker"] + 0x30 } else { 0x31 }
    $DataMarker = if ($ConfigData["Settings"]["DataMarker"]) { [int]$ConfigData["Settings"]["DataMarker"] + 0x30 } else { 0x32 }
}
else {
    $RecordSizeChars = 1300
    $HeaderMarker = 0x31
    $DataMarker = 0x32
}

# ==================== 修正ルール設定 (INIから読込) ====================
$ModifyRules = @()
foreach ($key in $ConfigData.Keys) {
    if ($key -like "Rule-*") {
        $section = $ConfigData[$key]
        if (
            $section["StartByte"] -and
            $section["PhoneLength"] -and
            $section["OldLeadingZeros"] -and
            $section["OldTrailingZeros"] -and
            $section["NewLeadingZeros"] -and
            $section["NewTrailingZeros"]
        ) {
            $ModifyRules += @{
                Name             = if ($section["Name"]) { $section["Name"] } else { $key }
                StartByte        = [int]$section["StartByte"]
                PhoneLength      = [int]$section["PhoneLength"]
                OldLeadingZeros  = [int]$section["OldLeadingZeros"]
                OldTrailingZeros = [int]$section["OldTrailingZeros"]
                NewLeadingZeros  = [int]$section["NewLeadingZeros"]
                NewTrailingZeros = [int]$section["NewTrailingZeros"]
            }
        }
    }
}

if ($ModifyRules.Count -eq 0) {
    Write-Host "エラー: 設定ファイルに修正ルールがありません！" -ForegroundColor Red
    exit 1
}

$ModifyRules = $ModifyRules | Sort-Object StartByte

foreach ($rule in $ModifyRules) {
    $oldTotal = $rule.OldLeadingZeros + $rule.PhoneLength + $rule.OldTrailingZeros
    $newTotal = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
    if ($oldTotal -ne $newTotal) {
        Write-Host "エラー: ルール '$($rule.Name)' の旧/新フォーマット総文字数が一致しません！" -ForegroundColor Red
        exit 1
    }
}

$ZeroChar = '0'

# ==================== スクリプトロジック ====================
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile = Join-Path $InFolder $FileName
$OutputFile = Join-Path $OutFolder $FileName
$LogFile = Join-Path $LogFolder "$(($FileName -replace '\.dat$',''))_$timestamp.log"

foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null 
    }
}

if (-not (Test-Path $InputFile)) {
    Write-Host "エラー: ファイル '$InputFile' が存在しません！" -ForegroundColor Red
    exit 1
}

# ログ関数
$logContent = [System.Text.StringBuilder]::new()
function Log($msg) {
    [void]$logContent.AppendLine($msg)
    Write-Host $msg
}

# 処理開始
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT File Modifier (FileStream) - 日本語版                   ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  入力:  $($InputFile.PadRight(50))║"
Log "║  出力: $($OutputFile.PadRight(50))║"
Log "║  設定: $($ConfigFile.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / ($RecordSizeChars * 2))

Log "ファイルサイズ: $fileLength バイト"
Log "レコード数: $recordCount | ルール数: $($ModifyRules.Count)"
Log ("─" * 64)
Log ""

$modifiedCount = 0
$RecordSizeBytes = $RecordSizeChars * 2
$recordBuffer = New-Object byte[] $RecordSizeBytes

# FileStreamでストリーム読み書き
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        # 1レコード分を読み込む
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSizeBytes)
        
        if ($bytesRead -ne $RecordSizeBytes) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] エラー - 読み込みバイト不足: $bytesRead / $RecordSizeBytes"
            continue
        }
        
        $recordNum = $i + 1
        $firstByte = $recordBuffer[0]
        
        if ($firstByte -eq $HeaderMarker) {
            Log "[#$($recordNum.ToString().PadLeft(4))] ヘッダー - スキップ"
        }
        elseif ($firstByte -eq $DataMarker) {
            $changes = @()
            $hasChange = $false
            
            foreach ($rule in $ModifyRules) {
                $fieldOffset = ($rule.StartByte - 1) * 2
                
                # フィールド全体を読み込む (文字数 -> バイト数)
                $totalLenChars = $rule.OldLeadingZeros + $rule.PhoneLength + $rule.OldTrailingZeros
                $totalLenBytes = $totalLenChars * 2
                $fieldBytes = New-Object byte[] $totalLenBytes
                [Array]::Copy($recordBuffer, $fieldOffset, $fieldBytes, 0, $totalLenBytes)
                $oldField = [System.Text.Encoding]::BigEndianUnicode.GetString($fieldBytes)
                
                # 新フォーマットかどうかチェック (文字数)
                $expectedLeading = "0" * $rule.NewLeadingZeros
                $expectedTrailing = "0" * $rule.NewTrailingZeros
                $expectedLenChars = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
                
                $isNewFormat = (
                    $oldField.StartsWith($expectedLeading) -and 
                    $oldField.EndsWith($expectedTrailing) -and
                    $oldField.Length -eq $expectedLenChars
                )
                
                if ($isNewFormat) {
                    $changes += "  $($rule.Name): 変更なし"
                }
                else {
                    # 旧フォーマットから電話番号を抽出
                    $phoneOffset = $fieldOffset + ($rule.OldLeadingZeros * 2)
                    $phoneLenBytes = $rule.PhoneLength * 2
                    $phone = New-Object byte[] $phoneLenBytes
                    [Array]::Copy($recordBuffer, $phoneOffset, $phone, 0, $phoneLenBytes)
                    
                    # 先頭0を埋める (BigEndianUnicode)
                    $leadingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewLeadingZeros)
                    [Array]::Copy($leadingZeros, 0, $recordBuffer, $fieldOffset, $rule.NewLeadingZeros * 2)
                    
                    # 電話番号をコピー
                    [Array]::Copy($phone, 0, $recordBuffer, $fieldOffset + ($rule.NewLeadingZeros * 2), $phoneLenBytes)
                    
                    # 末尾0を埋める (BigEndianUnicode)
                    $trailingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewTrailingZeros)
                    [Array]::Copy($trailingZeros, 0, $recordBuffer, $fieldOffset + (($rule.NewLeadingZeros + $rule.PhoneLength) * 2), $rule.NewTrailingZeros * 2)
                    
                    $newLenChars = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
                    $newLenBytes = $newLenChars * 2
                    $newFieldBytes = New-Object byte[] $newLenBytes
                    [Array]::Copy($recordBuffer, $fieldOffset, $newFieldBytes, 0, $newLenBytes)
                    $newFieldStr = [System.Text.Encoding]::BigEndianUnicode.GetString($newFieldBytes)
                    $changes += "  $($rule.Name): [$oldField] → [$newFieldStr]"
                    $hasChange = $true
                }
            }
            
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] 修正済み"
                $modifiedCount++
            }
            else {
                Log "[#$($recordNum.ToString().PadLeft(4))] 変更なし"
            }
            foreach ($c in $changes) { Log $c }
        }
        
        # 出力ストリームに書き込む（修正有無に関わらず）
        $outputStream.Write($recordBuffer, 0, $RecordSizeBytes)
    }
}
finally {
    $inputStream.Close()
    $outputStream.Close()
}

Log ""
Log ("─" * 64)
Log "サマリー: $modifiedCount / $recordCount レコードを修正"
Log ("─" * 64)

[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

Write-Host ""
Write-Host "✓ 出力: $OutputFile" -ForegroundColor Green
Write-Host "✓ ログ: $LogFile" -ForegroundColor Green
