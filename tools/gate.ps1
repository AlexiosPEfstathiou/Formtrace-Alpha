param([string]$Root="C:\Users\L004281\Projects\formtrace-alpha")
$node="$env:LOCALAPPDATA\node\node-v22.11.0-win-x64\node.exe"
$r1=& $node "$Root\tools\check.mjs" 2>&1
$r2=& $node "$Root\tools\toplevel-check.mjs" "$Root\index.html" "$env:TEMP\ft_mod.mjs" 2>&1
$r3=& $node "$Root\tools\render-check.mjs" "$Root\index.html" "$env:TEMP\ft_render.mjs" 2>&1
$ok1=(($r1 -join "`n") -cnotmatch '\bFAIL\b') -and (($r1 -join "`n") -match 'PASSED')
$ok2=(($r2 -join "`n") -match 'TOP-LEVEL OK')
$ok3=(($r3 -join "`n") -match 'RENDER CHECK OK')
if(-not $ok1){ $r1 | Where-Object { $_ -match 'FAIL' } }
if(-not $ok2){ $r2 | Select-Object -First 4 }
if(-not $ok3){ $r3 | Where-Object { $_ -match 'FAIL|RENDER CHECK' } }
Write-Output ("GATE: {0}  (smoke {1} · top-level {2} · renderers {3})" -f ($ok1 -and $ok2 -and $ok3),$ok1,$ok2,$ok3)
exit $(if($ok1 -and $ok2 -and $ok3){0}else{1})