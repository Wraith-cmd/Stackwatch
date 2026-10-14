# Deploys StackWatch from this repo into the WoW AddOns folder.
#
# Copies only the files the game loads (StackWatch.toc, the .lua files the
# .toc lists, media\, LICENSE) and removes everything else from the target
# folder, so AddOns\StackWatch never holds repo files.
#
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Target "E:\Games\World of Warcraft\_retail_\Interface\AddOns\StackWatch"
#
# After deploying: /reload in game, or restart the client if a file was added
# to or removed from the .toc.

param(
	[string]$Target = "D:\Wow shit\World of Warcraft\_retail_\Interface\AddOns\StackWatch"
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$toc = Join-Path $repo "StackWatch.toc"

# Safety: only ever write to a folder named AddOns\StackWatch, and never to the repo itself.
$targetFull = [System.IO.Path]::GetFullPath($Target).TrimEnd("\")
if ($targetFull -notmatch '\\Interface\\AddOns\\StackWatch$') {
	throw "Refusing to deploy: target must end in Interface\AddOns\StackWatch (got $targetFull)."
}
if ($targetFull -ieq $repo.TrimEnd("\")) {
	throw "Refusing to deploy: target is the repo itself."
}

# Build the shipped file list from the .toc.
$luaFiles = Get-Content -LiteralPath $toc |
	ForEach-Object { $_.Trim() } |
	Where-Object { $_ -and -not $_.StartsWith("#") -and $_ -match '\.lua$' }
if (-not $luaFiles) {
	throw "No .lua files found in StackWatch.toc."
}
$shipped = @("StackWatch.toc", "LICENSE", "media") + $luaFiles

# Every shipped file must exist before anything is deleted.
foreach ($item in $shipped) {
	if (-not (Test-Path -LiteralPath (Join-Path $repo $item))) {
		throw "Missing shipped file in repo: $item"
	}
}

if (-not (Test-Path -LiteralPath $targetFull)) {
	New-Item -ItemType Directory -Path $targetFull | Out-Null
}

# Remove everything in the target that is not shipped (including hidden
# items such as .git), and the old media folder so it is mirrored exactly.
$keep = @{}
foreach ($item in $shipped) {
	if ($item -ne "media") {
		$keep[$item.ToLowerInvariant()] = $true
	}
}
Get-ChildItem -LiteralPath $targetFull -Force | ForEach-Object {
	if (-not $keep.ContainsKey($_.Name.ToLowerInvariant())) {
		Remove-Item -LiteralPath $_.FullName -Recurse -Force
	}
}

foreach ($item in $shipped) {
	Copy-Item -LiteralPath (Join-Path $repo $item) -Destination $targetFull -Recurse -Force
}

Write-Host "Deployed to $targetFull"
Get-ChildItem -LiteralPath $targetFull -Recurse -Force -File |
	ForEach-Object { "  " + $_.FullName.Substring($targetFull.Length + 1) }
