# Gen npc_smith.png (16x16) for sand_e economy wave. ASCII art -> System.Drawing PNG.
Add-Type -AssemblyName System.Drawing
$art = @(
"................",
".....oooooo.....",
"....ohhhhhho....",
"...ohssssssho...",
"...ohsessesho...",
"....osssssso....",
".....ohhhho.....",
"...oottttttoo...",
"..tttttttttttt..",
"..oattttttttao..",
"..oattttttttao..",
"..oaaaaaaaaaao..",
"....ttt..ttt....",
"....ttt..ttt....",
"....bbb..bbb....",
"................"
)
$bad = @()
for ($i = 0; $i -lt $art.Count; $i++) {
	if ($art[$i].Length -ne 16) { $bad += ("{0}={1}" -f $i, $art[$i].Length) }
}
if ($bad.Count) { "BAD ROWS: " + ($bad -join " "); exit 1 }
$map = @{
	'o' = [System.Drawing.Color]::FromArgb(255, 26, 20, 18)
	'h' = [System.Drawing.Color]::FromArgb(255, 104, 58, 34)
	's' = [System.Drawing.Color]::FromArgb(255, 216, 164, 124)
	'e' = [System.Drawing.Color]::FromArgb(255, 30, 24, 30)
	't' = [System.Drawing.Color]::FromArgb(255, 74, 88, 128)
	'a' = [System.Drawing.Color]::FromArgb(255, 92, 56, 38)
	'b' = [System.Drawing.Color]::FromArgb(255, 58, 42, 32)
	'.' = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
}
$out = "C:\Users\gazhakv\Documents\deepseek-harness\default-workspace\sand_e\pixel-rpg\assets\npc_smith.png"
$bmp = New-Object System.Drawing.Bitmap 16, 16, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt 16; $y++) {
	$row = $art[$y]
	for ($x = 0; $x -lt 16; $x++) {
		$key = [string]$row[$x]
		if (-not $map.ContainsKey($key)) { "UNKNOWN CHAR '$key' at $x,$y"; exit 1 }
		$bmp.SetPixel($x, $y, $map[$key])
	}
}
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"SAVED: $out $((Get-Item $out).Length) bytes"
