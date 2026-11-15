Add-Type -AssemblyName System.Drawing

$taskBoardPath = Join-Path $PSScriptRoot 'layout-board.png'
if (Test-Path -LiteralPath $taskBoardPath) { throw 'Preserving existing preview board.' }

$taskBoard = [System.Drawing.Bitmap]::new(1360, 980)
$taskGraphics = [System.Drawing.Graphics]::FromImage($taskBoard)
$taskGraphics.Clear([System.Drawing.Color]::FromArgb(246, 242, 233))
$taskGraphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$taskInk = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(27, 42, 92))
$taskMuted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(92, 102, 119))
$taskTitleFont = [System.Drawing.Font]::new('Segoe UI', 30, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$taskLabelFont = [System.Drawing.Font]::new('Segoe UI', 20, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$taskNoteFont = [System.Drawing.Font]::new('Segoe UI', 18, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

try {
    $taskGraphics.DrawString('Печать на эмали — четыре состояния', $taskTitleFont, $taskInk, 32, 20)
    $taskGraphics.DrawString('Реальные кадры Roblox, одна модель. Названия: 80 px; цифры цены: 88 px. Без уменьшения длинных имён.', $taskNoteFont, $taskMuted, 32, 67)

    $taskCases = @(
        @{ File = '01-shovel-insufficient.jpg'; Label = '01 · Shovel · 8 Cash · денег не хватает'; X = 32; Y = 116 },
        @{ File = '02-snow-pusher-ready.jpg'; Label = '02 · Snow Pusher · 30 Cash · доступно'; X = 688; Y = 116 },
        @{ File = '03-snowblower-ru-insufficient.jpg'; Label = '03 · Снегоуборщик · 100 Cash · денег не хватает'; X = 32; Y = 534 },
        @{ File = '04-shovel-ru-owned-preview.jpg'; Label = '04 · Лопата · куплено — пример состояния'; X = 688; Y = 534 }
    )
    foreach ($taskCase in $taskCases) {
        $taskGraphics.DrawString($taskCase.Label, $taskLabelFont, $taskInk, $taskCase.X, $taskCase.Y)
        $taskImage = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot $taskCase.File))
        try {
            # Same crop and original pixel scale in all four cells. No paintover or scene changes.
            $taskDestination = [System.Drawing.Rectangle]::new($taskCase.X, ($taskCase.Y + 38), 640, 330)
            $taskSource = [System.Drawing.Rectangle]::new(640, 260, 640, 330)
            $taskGraphics.DrawImage($taskImage, $taskDestination, $taskSource, [System.Drawing.GraphicsUnit]::Pixel)
        } finally {
            $taskImage.Dispose()
        }
    }
    $taskGraphics.DrawString('Состояния-превью SurfaceGui: цены, владение, геометрия и материалы не менялись; другие полки не затронуты.', $taskNoteFont, $taskMuted, 32, 935)
    $taskBoard.Save($taskBoardPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $taskGraphics.Dispose()
    $taskBoard.Dispose()
    $taskInk.Dispose()
    $taskMuted.Dispose()
    $taskTitleFont.Dispose()
    $taskLabelFont.Dispose()
    $taskNoteFont.Dispose()
}
Write-Output $taskBoardPath
