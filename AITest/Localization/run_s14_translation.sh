#!/bin/bash
# S14 Part A — sequential catalog translation (idempotent, safe to re-run)
set -euo pipefail
ROOT="/Users/karthik_sivam/Documents/My Apps/SmartInventory/smart-inventory"
LOG="/tmp/stoqly_translate_s14.log"
cd "$ROOT"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== S14 translation start ==="
log "Step 1: India languages (ta, te, kn, ml)"
python3 -u AITest/Localization/translate_catalog.py --langs ta,te,kn,ml
log "Step 2: remaining languages (ar, es, pt-BR, fr, zh-Hans, id, de, ru, ja)"
python3 -u AITest/Localization/translate_catalog.py
log "=== S14 translation complete ==="
