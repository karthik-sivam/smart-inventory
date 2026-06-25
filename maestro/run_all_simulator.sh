#!/usr/bin/env bash
# Run each flow in run_all.yaml on a specific simulator; continue on failure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${1:-7352454A-356D-4518-8C0B-C732B77F769A}"
LOG="${ROOT}/maestro_simulator_results.log"
: > "$LOG"

# Fresh app install for deterministic seed data (flows 07+08 create Test Warehouse + item).
echo "Resetting app state on $UDID..." | tee -a "$LOG"
APP="$(find ~/Library/Developer/Xcode/DerivedData -name "SmartInventory.app" -path "*/Build/Products/Debug-iphonesimulator/*" ! -path "*/Index.noindex/*" 2>/dev/null | head -1)"
if [[ -z "$APP" ]]; then
  echo "ERROR: SmartInventory.app not found — run xcodebuild first" | tee -a "$LOG"
  exit 1
fi
xcrun simctl uninstall "$UDID" com.vishuddhi.stoqly 2>/dev/null || true
if ! xcrun simctl install "$UDID" "$APP"; then
  echo "ERROR: Failed to install $APP" | tee -a "$LOG"
  exit 1
fi
echo "Installed $APP" | tee -a "$LOG"

flows=(
  flows/01_onboarding.yaml
  flows/02_onboarding_skip.yaml
  flows/04_signin.yaml
  flows/05_signin_wrong_password.yaml
  flows/06_forgot_password.yaml
  flows/11_dashboard.yaml
  flows/07_add_storage.yaml
  flows/08_add_item.yaml
  flows/25_global_search.yaml
  flows/27_category_filter.yaml
  flows/28_swipe_actions_items.yaml
  flows/29_swipe_actions_storages.yaml
  flows/30_category_explorer.yaml
  flows/32_quick_count_placeholder.yaml
  flows/33_activity_feed.yaml
  flows/12_items_tab.yaml
  flows/26_audit_tab.yaml
  flows/09_quick_count.yaml
  flows/10_full_count.yaml
  flows/13_export_csv.yaml
  flows/14_export_pdf.yaml
  flows/15_settings.yaml
  flows/16_profile.yaml
  flows/19_delete_storage.yaml
  flows/07_add_storage.yaml
  flows/08_add_item.yaml
  flows/20_signout.yaml
  flows/21_low_stock_detection.yaml
  flows/31_reorder_list.yaml
  flows/50_attention_banner.yaml
  flows/24_low_stock_export.yaml
  flows/22_out_of_stock_detection.yaml
  flows/77_reorder_item_tap.yaml
  # Import flows skipped per test plan — run in isolation only:
  # flows/78_bulk_import_settings_entry.yaml
  # flows/79_bulk_import_add_storage_autoselect.yaml
  # flows/80_bulk_import_add_storage_color.yaml
  flows/23_edit_item.yaml
  # flows/34_post_login_onboarding.yaml  # NOT RUNNABLE — requires pristine onboarding state
  flows/35_deletion_toast.yaml
  flows/36_batch_expiry.yaml
  flows/37_edit_storage.yaml
  flows/38_storage_detail.yaml
  flows/39_item_detail_full.yaml
  flows/40_add_item_full.yaml
  flows/41_add_item_validation.yaml
  flows/42_mark_out_of_stock.yaml
  flows/43_count_with_reason_notes.yaml
  flows/44_large_change_alert.yaml
  flows/45_audit_tab_filters.yaml
  flows/46_expiry_timeline.yaml
  flows/47_add_item_with_expiry.yaml
  flows/48_dashboard_health_card.yaml
  flows/49_dashboard_see_all_activity.yaml
  flows/51_search_history.yaml
  flows/52_search_sku_category.yaml
  flows/53_search_no_results.yaml
  flows/54_audit_empty_state.yaml
  flows/55_empty_storage_state.yaml
  flows/56_currency_change.yaml
  flows/57_restock_cycle_e2e.yaml
  flows/58_business_day_e2e.yaml
  flows/59_cross_tab_navigation.yaml
  flows/60_team_members_view.yaml
  flows/61_product_catalog.yaml
  flows/62_count_negative_input.yaml
  flows/63_templates_settings_entry.yaml
  flows/64_create_template.yaml
  flows/65_template_validation.yaml
  flows/66_edit_template_no_links.yaml
  flows/67_save_as_template.yaml
  flows/68_use_template_add_item.yaml
  flows/69_edit_template_with_links.yaml
  flows/70_delete_template_with_links.yaml
  flows/71_delete_template_confirmed.yaml
  flows/72_audit_session_progress.yaml
  flows/73_audit_last_counted.yaml
  flows/74_health_card_drilldown.yaml
  flows/75_value_by_category.yaml
  flows/76_smart_insights.yaml
)

pass=0
fail=0
for f in "${flows[@]}"; do
  name="$(basename "$f")"
  echo "======== $name ========" | tee -a "$LOG"
  if (cd "$ROOT" && maestro test --device "$UDID" "maestro/$f" >> "$LOG" 2>&1); then
    echo "RESULT: PASS $name" | tee -a "$LOG"
    ((pass++)) || true
  else
    echo "RESULT: FAIL $name" | tee -a "$LOG"
    ((fail++)) || true
  fi
done
echo "SUMMARY: PASS=$pass FAIL=$fail TOTAL=$((pass+fail))" | tee -a "$LOG"
