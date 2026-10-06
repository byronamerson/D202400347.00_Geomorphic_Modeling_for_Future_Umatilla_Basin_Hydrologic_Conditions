# =============================================================================
# run_pdf_ingest_report.R
# Runner For PDF Ingestion Utility
# =============================================================================
#
# Purpose: Execute the PDF ingestion utility for the DOGAMI O-25-10 report
#          using the default configuration defined in `pdf_ingest_report.R`.
# =============================================================================

source("scripts/pdf_ingest_report.R")

report <- ingest_pdf_report(config)
