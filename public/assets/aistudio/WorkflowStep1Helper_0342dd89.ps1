# UTF-8 with BOM
function Invoke-WorkflowStep1 {
    param(
        [Parameter(Mandatory=$true)][string]$DateFolder,
        [Parameter(Mandatory=$true)][int]$Count
    )
    if (-not (Test-Path -LiteralPath $DateFolder)) { throw "対象フォルダが存在しません: $DateFolder" }
    $created = 0
    for ($i = 1; $i -le $Count; $i++) {
        $subName = "{0:D2}" -f $i
        $subPath = Join-Path $DateFolder $subName
        if (-not (Test-Path -LiteralPath $subPath)) {
            New-Item -ItemType Directory -Path $subPath -Force | Out-Null
            $created++
        }
    }
    Write-PhotoLog -Message "Step1完了: $DateFolder に $created 個の子フォルダを作成" -Level "INFO"
    return @{ CreatedCount = $created }
}
