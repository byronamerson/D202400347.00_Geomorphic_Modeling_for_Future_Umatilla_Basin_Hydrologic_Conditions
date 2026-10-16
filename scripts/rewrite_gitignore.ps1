# =============================================================================
# rewrite_gitignore.ps1
# Umatilla River Discharge-Channel Migration Analysis
# Rewrite .gitignore as UTF-8 without a byte-order mark.
# =============================================================================
#
# Why: the existing .gitignore is valid UTF-8 through its first several blocks,
# then the final entry was appended as UTF-16LE -- visible as null bytes between
# characters in a hex dump. Git classifies the file as binary and will not diff
# it, and the corrupted trailing pattern (docs/*_files/) never took effect, which
# is why a rendered _files/ directory shows as untracked.
#
# Nothing here is new content except the three entries noted below. Every other
# line is transcribed from the existing file's readable bytes.
#
# Added:  *.docx     (Word renders stay out of the repo -- Byron, 2026-10-16)
#         .venv/     (Python environment, open item since 2026-10-15)
#         *.bak      (reflow script backups)
#
# Run from the repository root. Verify with: git status --short
# =============================================================================

$gitignore = @'
# Data files
data/
*.csv
*.xlsx
*.rds
*.parquet

data_in/
*.csv
*.xlsx
*.rds
*.parquet

data_out/
*.csv
*.xlsx
*.rds
*.parquet

docs/derived/

# Plots and figures
plots/
*.png
*.pdf
*.jpg

# Document build artifacts (keep the .md source, not the renders)
*.aux
*.docx
docs/*.tex
docs/*.html

# R environment
.Rproj.user/
.Rhistory
.RData
.Rprofile
.positai

# Python environment
.venv/

# Reference material and staging, not part of the analysis chain
bmorph/
Claude outputs/

# Generated / packaged / presentation artifacts
docs/byrons_llm_context_docs.zip
scripts_io_scan.json
*.pptx
docs/byrons_llm_context_docs/
docs/*_files/

# Editor and tool backups
*.bak
'@

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\.gitignore", $gitignore, $utf8NoBom)

Write-Host "Wrote .gitignore as UTF-8 (no BOM)."
