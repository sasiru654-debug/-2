#requires -Version 5.1
# ==============================================================================
# WorkflowStep1Helper.ps1 - Step1: 仕分け用連番フォルダ作成 (UTF-8 BOM / CRLF)
# ==============================================================================

function Test-IsAllowedImportFolderForStep1 {
    param(
        [string]$TargetFolder,
        [hashtable]$Config
    )
    if ($null -eq $Config -or [string]::IsNullOrWhiteSpace($TargetFolder)) { return $false }
    $normTarget = $TargetFolder.Trim().TrimEnd('\')
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($src in @($Config, $Config.Paths)) {
        if ($src -is [hashtable]) {
            foreach ($k in @("ImportRoot1", "ImportRoot2")) {
                $val = [string]$src[$k]
                if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$candidates.Add($val.Trim().TrimEnd('\')) }
            }
        }
    }
    if ($candidates.Count -eq 0) {
        foreach ($src in @($Config, $Config.Paths)) {
            if ($src -is [hashtable]) {
                $val = [string]$src["ImportRoot"]
                if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$candidates.Add($val.Trim().TrimEnd('\')) }
            }
        }
    }
    foreach ($root in $candidates) {
        if (($normTarget -ieq $root) -or $normTarget.StartsWith(($root + "\"), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Invoke-WorkflowStep1 {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolder,
        [Parameter(Mandatory=$true)][int]$Count,
        [hashtable]$Config = $null
    )
    if ($null -ne $Config -and -not (Test-IsAllowedImportFolderForStep1 -TargetFolder $DateFolder -Config $Config)) {
        throw "Step1はカメラ取り込み元 1 またはカメラ取り込み元 2 配下のフォルダでのみ実行できます: $DateFolder"
    }
    if (-not (Test-Path -LiteralPath $DateFolder)) {
        throw "対象フォルダが存在しません: $DateFolder"
    }
    $created = 0
    for ($i = 1; $i -le $Count; $i++) {
        $subName = "{0:D2}" -f $i
        $subPath = Join-Path $DateFolder $subName
        if (-not (Test-Path -LiteralPath $subPath)) {
            New-Item -ItemType Directory -Path $subPath -Force | Out-Null
            $created++
        }
    }
    if (Get-Command Write-PhotoLog -ErrorAction SilentlyContinue) {
        Write-PhotoLog -Message "Step1完了: $DateFolder に $created 個の子フォルダを作成" -ModuleName "WorkflowStep1" -Level "INFO" | Out-Null
    }
    return @{ CreatedCount = $created }
}
