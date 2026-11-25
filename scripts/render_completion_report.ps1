# Convert the completion report HTML to .docx and .pdf with a NEW hidden Word instance (existing Word windows untouched).
# Usage: powershell -File scripts/render_completion_report.ps1 <report.html>
param([Parameter(Mandatory=$true)][string]$Html)
$ErrorActionPreference = 'Stop'
$src  = (Resolve-Path $Html).Path
$docx = [IO.Path]::ChangeExtension($src, '.docx')
$pdf  = [IO.Path]::ChangeExtension($src, '.pdf')
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
    $doc = $word.Documents.Open($src, $false, $true)          # ConfirmConversions false, ReadOnly true
    $doc.SaveAs2([ref]$docx, [ref]16)                          # wdFormatDocumentDefault
    $doc.Close([ref]0)
    $doc = $word.Documents.Open($docx)
    if ($doc.Windows.Count -gt 0) { $doc.Windows.Item(1).View.Type = 3 }   # print layout (HTML opens in web layout)
    $sec = $doc.Sections.Item(1)
    $sec.PageSetup.TopMargin = 50; $sec.PageSetup.BottomMargin = 50; $sec.PageSetup.LeftMargin = 58; $sec.PageSetup.RightMargin = 58
    $rng = $sec.Footers.Item(1).Range
    $rng.Text = 'NOC PQ-Attest  |  Kalash Bheda  |  Page '
    $rng.Font.Size = 9; $rng.ParagraphFormat.Alignment = 1
    $rng.Collapse(0); [void]$rng.Fields.Add($rng, 33)          # wdFieldPage
    $doc.Save()
    $doc.ExportAsFixedFormat($pdf, 17)                         # wdExportFormatPDF
    "PAGES=" + $doc.ComputeStatistics(2)
    $doc.Close([ref]0)
    "DOCX=$docx"; "PDF=$pdf"
} finally {
    $word.Quit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}
