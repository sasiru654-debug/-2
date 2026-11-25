# UTF-8 with BOM
function Invoke-WorkflowStep5 {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolderName,
        [Parameter(Mandatory=$true)][hashtable]$Config
    )
    $periodInfo = Get-ArchivePeriodSubPath -DateFolderName $DateFolderName -Config $Config
    $devSrc = Join-Path $Config.Paths.DevelopedRoot $DateFolderName
    $rawSrc = Join-Path $Config.Paths.RawSaveRoot $DateFolderName

    $devDestParent = Join-Path $Config.Paths.DevelopedArchiveRoot $periodInfo.RelativePeriodPath
    $rawDestParent = Join-Path $Config.Paths.RawArchiveRoot $periodInfo.RelativePeriodPath
    $devDest = Join-Path $devDestParent $DateFolderName
    $rawDest = Join-Path $rawDestParent $DateFolderName

    if (Test-Path -LiteralPath $devSrc) {
        if (Test-Path -LiteralPath $devDest) { throw "移動先に既に存在します: $devDest" }
        New-Item -ItemType Directory -Path $devDestParent -Force | Out-Null
        Move-Item -LiteralPath $devSrc -Destination $devDest -Force
        if (Get-Command Update-PhotoLedgerPathsAfterMove -ErrorAction SilentlyContinue) {
            Update-PhotoLedgerPathsAfterMove -OldBasePath $devSrc -NewBasePath $devDest -ColumnType "Developed" -Config $Config
        }
    }

    if (Test-Path -LiteralPath $rawSrc) {
        if (Test-Path -LiteralPath $rawDest) { throw "移動先に既に存在します: $rawDest" }
        New-Item -ItemType Directory -Path $rawDestParent -Force | Out-Null
        Move-Item -LiteralPath $rawSrc -Destination $rawDest -Force
        if (Get-Command Update-PhotoLedgerPathsAfterMove -ErrorAction SilentlyContinue) {
            Update-PhotoLedgerPathsAfterMove -OldBasePath $rawSrc -NewBasePath $rawDest -ColumnType "RAW" -Config $Config
        }
    }

    Write-PhotoLog -Message "Step5完了: アーカイブ移動($($periodInfo.RelativePeriodPath)\$DateFolderName)および台帳追従完了" -Level "INFO"
    return @{ ArchiveDevelopedPath = $devDest; ArchiveRawPath = $rawDest }
}
