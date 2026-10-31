# Type checks both places. Each place is analyzed with its own sourcemap together with src/shared,
# so shared code is checked against both; an error reported by both places is printed once.
# Exits 0 only when there are no errors.
Set-Location (Split-Path $PSScriptRoot)

# Roblox types are pinned to the luau-lsp release from rokit.toml. Change both together.
$typesVersion = "1.70.1"
$dir = ".luau-lsp"
$types = "$dir/globalTypes.$typesVersion.d.luau"
New-Item -ItemType Directory -Force $dir | Out-Null
if (-not (Test-Path $types)) {
	Invoke-WebRequest "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$typesVersion/scripts/globalTypes.None.d.luau" -OutFile $types -ErrorAction Stop
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
if ($failed -or $errors.Count -gt 0) {
	exit 1
}
exit 0
