# ============================================
# DATファイル マルチフィールド修正スクリプト (BigEndianUnicode版)
# 機能：複数フィールド修正 | in/outフォルダ | ログ記録 | ストリーム読み書き
# 対応：UTF-16BE (BigEndianUnicode) エンコード
# ============================================

param(
    [string]$FileName = "data.dat"
)

# ==================== フォルダ設定 ====================
$InFolder  = "in"
$OutFolder = "out"
$LogFolder = "log"

# ==================== レコード設定 ====================
# ==================== 設定ファイル読込 ====================
$ConfigFile = "config.ini"
if (-not (Test-Path $ConfigFile)) { $ConfigFile = "config_日本語.ini" }

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
        } elseif ($line -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            $ini[$section][$key] = $value
        }
    }
    return $ini
}

$ConfigData = Parse-IniFile -FilePath $ConfigFile

# ==================== レコード設定 ====================
# デフォルト値
$RecordSize   = 1300
$HeaderMarker = 0x31
$DataMarker   = 0x32
$ZeroChar     = "0"

# INIから設定を読込
if ($ConfigData.ContainsKey("Settings")) {
    if ($ConfigData["Settings"]["RecordSize"]) { $RecordSize = [int]$ConfigData["Settings"]["RecordSize"] }
    if ($ConfigData["Settings"]["HeaderMarker"]) { $HeaderMarker = [int]$ConfigData["Settings"]["HeaderMarker"] + 0x30 }
    if ($ConfigData["Settings"]["DataMarker"]) { $DataMarker = [int]$ConfigData["Settings"]["DataMarker"] + 0x30 }
}

# ==================== 更新ルール設定 (INIから読込) ====================
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
    # デフォルト値
    $ModifyRules = @(
        @{ Name="Phone-1"; StartByte=100; PhoneLength=10; OldLeadingZeros=0; OldTrailingZeros=10; NewLeadingZeros=6; NewTrailingZeros=4 },
        @{ Name="Phone-2"; StartByte=200; PhoneLength=10; OldLeadingZeros=0; OldTrailingZeros=10; NewLeadingZeros=6; NewTrailingZeros=4 }
    )
}

# ==================== スクリプトロジック ====================
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile  = Join-Path $InFolder $FileName
$OutputFile = Join-Path $OutFolder $FileName
$LogFile    = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

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
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / $RecordSize)

Log "ファイルサイズ: $fileLength バイト"
Log "レコード数: $recordCount | ルール数: $($ModifyRules.Count)"
Log ("─" * 64)
Log ""

$modifiedCount = 0
$recordBuffer = New-Object byte[] $RecordSize

# FileStreamでストリーム読み書き
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        # 1レコード分を読み込む
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] エラー - 読み込みバイト不足: $bytesRead / $RecordSize"
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
                $fieldOffset = $rule.StartByte - 1
                
                # フィールド全体を読み込む
                $totalLen = $rule.OldLeadingZeros + $rule.PhoneLength + $rule.OldTrailingZeros
                $fieldBytes = New-Object byte[] ($totalLen * 2)
                [Array]::Copy($recordBuffer, $fieldOffset, $fieldBytes, 0, $totalLen * 2)
                $oldField = [System.Text.Encoding]::BigEndianUnicode.GetString($fieldBytes)
                
                # 新フォーマットかどうかチェック
                $expectedLeading = "0" * $rule.NewLeadingZeros
                $expectedTrailing = "0" * $rule.NewTrailingZeros
                $expectedLen = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
                
                $isNewFormat = (
                    $oldField.StartsWith($expectedLeading) -and 
                    $oldField.EndsWith($expectedTrailing) -and
                    $oldField.Length -eq $expectedLen
                )
                
                if ($isNewFormat) {
                    $changes += "  $($rule.Name): 変更なし"
                } else {
                    # 旧フォーマットから電話番号を抽出
                    $phoneOffset = $fieldOffset + $rule.OldLeadingZeros * 2
                    $phone = New-Object byte[] ($rule.PhoneLength * 2)
                    [Array]::Copy($recordBuffer, $phoneOffset, $phone, 0, $rule.PhoneLength * 2)
                    
                    # 新フィールドを構築してrecordBufferに書き込む
                    $newLen = $rule.NewLeadingZeros + $rule.PhoneLength + $rule.NewTrailingZeros
                    
                    # 先頭0を埋める (BigEndianUnicode)
                    $leadingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewLeadingZeros)
                    [Array]::Copy($leadingZeros, 0, $recordBuffer, $fieldOffset, $rule.NewLeadingZeros * 2)
                    
                    # 電話番号をコピー
                    [Array]::Copy($phone, 0, $recordBuffer, $fieldOffset + $rule.NewLeadingZeros * 2, $rule.PhoneLength * 2)
                    
                    # 末尾0を埋める (BigEndianUnicode)
                    $trailingZeros = [System.Text.Encoding]::BigEndianUnicode.GetBytes($ZeroChar * $rule.NewTrailingZeros)
                    [Array]::Copy($trailingZeros, 0, $recordBuffer, $fieldOffset + ($rule.NewLeadingZeros + $rule.PhoneLength) * 2, $rule.NewTrailingZeros * 2)
                    
                    $newFieldBytes = New-Object byte[] ($newLen * 2)
                    [Array]::Copy($recordBuffer, $fieldOffset, $newFieldBytes, 0, $newLen * 2)
                    $newFieldStr = [System.Text.Encoding]::BigEndianUnicode.GetString($newFieldBytes)
                    $changes += "  $($rule.Name): [$oldField] → [$newFieldStr]"
                    $hasChange = $true
                }
            }
            
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] 修正済み"
                $modifiedCount++
            } else {
                Log "[#$($recordNum.ToString().PadLeft(4))] 変更なし"
            }
            foreach ($c in $changes) { Log $c }
        }
        
        # 出力ストリームに書き込む（修正有無に関わらず）
        $outputStream.Write($recordBuffer, 0, $RecordSize)
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
