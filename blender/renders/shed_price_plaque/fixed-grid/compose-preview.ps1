Add-Type -AssemblyName System.Drawing

$taskInk = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(27, 42, 92))
$taskMuted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(92, 102, 119))
$taskTitleFont = [System.Drawing.Font]::new('Segoe UI', 29, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$taskLabelFont = [System.Drawing.Font]::new('Segoe UI', 19, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$taskNoteFont = [System.Drawing.Font]::new('Segoe UI', 17, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

function Add-TaskCaptureCrop($Graphics, [string]$File, [int]$X, [int]$Y, [System.Drawing.Rectangle]$Crop) {
    $taskImage = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot $File))
    try {
        # Identical source crops at native pixel scale; no paintover or image enlargement.
        $taskDestination = [System.Drawing.Rectangle]::new($X, $Y, $Crop.Width, $Crop.Height)
        $Graphics.DrawImage($taskImage, $taskDestination, $Crop, [System.Drawing.GraphicsUnit]::Pixel)
    } finally {
        $taskImage.Dispose()
    }
}

function New-TaskBoard([string]$Name, [int]$Width, [int]$Height, [scriptblock]$Draw) {
    $taskPath = Join-Path $PSScriptRoot $Name
    if (Test-Path -LiteralPath $taskPath) { throw "Preserving existing board: $taskPath" }
    $taskBoard = [System.Drawing.Bitmap]::new($Width, $Height)
    $taskGraphics = [System.Drawing.Graphics]::FromImage($taskBoard)
    try {
        $taskGraphics.Clear([System.Drawing.Color]::FromArgb(246, 242, 233))
        $taskGraphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        & $Draw $taskGraphics
        $taskBoard.Save($taskPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $taskGraphics.Dispose()
        $taskBoard.Dispose()
    }
    Write-Output $taskPath
}

try {
    New-TaskBoard 'normal-states.png' 1222 492 {
        param($g)
        $g.DrawString('Одна табличка — три реальных состояния', $taskTitleFont, $taskInk, 32, 20)
        $g.DrawString('Игровая дистанция, одна камера. Кадры Roblox Play; кропы без увеличения.', $taskNoteFont, $taskMuted, 32, 64)
        $taskCases = @(
            @{ File = '01-normal-insufficient-en.jpg'; Label = 'Не хватает · баланс 5 Cash'; X = 32 },
            @{ File = '02-normal-buy-en.jpg'; Label = 'Купить · баланс 10 Cash'; X = 426 },
            @{ File = '03-normal-owned-en.jpg'; Label = 'Куплено · баланс 2 Cash'; X = 820 }
        )
        foreach ($taskCase in $taskCases) {
            $g.DrawString($taskCase.Label, $taskLabelFont, $taskInk, $taskCase.X, 105)
            Add-TaskCaptureCrop $g $taskCase.File $taskCase.X 138 ([System.Drawing.Rectangle]::new(380, 190, 370, 300))
        }
        $g.DrawString('Цена всегда слева, статус справа. Покупка через E: 10 → 2 Cash; прежняя цена 8 остаётся справочной.', $taskNoteFont, $taskMuted, 32, 457)
    }

    New-TaskBoard 'face-layouts.png' 1226 862 {
        param($g)
        $g.DrawString('Лицевая поверхность — короткие и длинные названия', $taskTitleFont, $taskInk, 32, 20)
        $g.DrawString('Реальные кадры Roblox. Одинаковые кропы без увеличения; геометрия и материалы сохранены.', $taskNoteFont, $taskMuted, 32, 64)
        $taskCases = @(
            @{ File = '05-front-short-preview.jpg'; Label = 'Shovel · 8 · не хватает — превью'; X = 32; Y = 111 },
            @{ File = '06-front-snow-pusher-preview.jpg'; Label = 'Snow Pusher · 30 · купить — превью'; X = 629; Y = 111 },
            @{ File = '07-front-snowblower-ru-preview.jpg'; Label = 'Снегоуборщик · 100 · не хватает — превью'; X = 32; Y = 465 },
            @{ File = '08-front-owned-ru.jpg'; Label = 'Лопата · 8 · куплено — после покупки'; X = 629; Y = 465 }
        )
        foreach ($taskCase in $taskCases) {
            $g.DrawString($taskCase.Label, $taskLabelFont, $taskInk, $taskCase.X, $taskCase.Y)
            Add-TaskCaptureCrop $g $taskCase.File $taskCase.X ($taskCase.Y + 32) ([System.Drawing.Rectangle]::new(280, 205, 565, 300))
        }
        $g.DrawString('Превью меняет только печать на этой модели: реальные названия и цены из Config. Другие полки не изменены.', $taskNoteFont, $taskMuted, 32, 823)
    }
} finally {
    $taskInk.Dispose()
    $taskMuted.Dispose()
    $taskTitleFont.Dispose()
    $taskLabelFont.Dispose()
    $taskNoteFont.Dispose()
}
