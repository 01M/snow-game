# Type checks both places. Each place is analyzed with its own sourcemap together with src/shared,
# so shared code is checked against both; an error reported by both places is printed once.
# Delete .luau-lsp/ to download fresh Roblox types.
Set-Location (Split-Path $PSScriptRoot)

$dir = ".luau-lsp"
$types = "$dir/globalTypes.d.luau"
New-Item -ItemType Directory -Force $dir | Out-Null
if (-not (Test-Path $types)) {
	Invoke-WebRequest "https://luau-lsp.pages.dev/type-definitions/globalTypes.None.d.luau" -OutFile $types -ErrorAction Stop
}

$failed = $false
$errors = [ordered]@{}
foreach ($place in "lobby", "house") {
	$sourcemap = "$dir/sourcemap.$place.json"
	rojo sourcemap "$place.project.json" --include-non-scripts --output $sourcemap | Out-Null
	if ($LASTEXITCODE -ne 0) {
		$failed = $true
		continue
	}

	$current = $null
	$output = luau-lsp analyze --platform roblox --sourcemap $sourcemap --defs $types "src/$place" src/shared 2>&1
	if ($LASTEXITCODE -ne 0) {
		$failed = $true
	}
	foreach ($line in $output | ForEach-Object { "$_" }) {
		if ($line -match "^\[(INFO|WARN)\]") {
			continue
		}
		if ($line -match "\(\d+,\d+\): " -or $null -eq $current) {
			if ($null -ne $current) {
				$errors[$current] = $true
			}
			$current = $line
		} else {
			$current += "`n$line"
		}
	}
	if ($null -ne $current) {
		$errors[$current] = $true
	}
}

$errors.Keys | ForEach-Object { $_ -replace " \[game/[^\]]*\]", "" }
Write-Output "$($errors.Count) error(s)"
if ($failed) {
	exit 1
}
