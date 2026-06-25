# Stoqly — Maestro Test Suite

## Setup

1. Install Maestro (one time):
```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
echo 'export PATH="$PATH:$HOME/.maestro/bin"' >> ~/.zshrc
source ~/.zshrc
```

2. Install Java (required by Maestro):
```bash
brew install --cask temurin
```

3. Build and run the app in Xcode on a Simulator (any iPhone simulator).

## Running Tests

Default test credentials are set in each flow’s `env:` block (`test@smartinventory.dev` / `Test@1234`) and in `run_all.yaml`, so **individual flows work without extra flags**. Override when needed:

```bash
cd /Users/karthik_sivam/Documents/My\ Apps/SmartInventory/smart-inventory

# Single flow (uses built-in defaults)
maestro test maestro/flows/04_signin.yaml

# Override credentials
maestro test -e TEST_EMAIL=you@example.com -e TEST_PASSWORD='YourPass' maestro/flows/04_signin.yaml

# Full suite
maestro test maestro/run_all.yaml

# Open visual studio (record flows by tapping)
maestro studio
```

> **Note:** Flows that sign in (`00_signin_helper.yaml`, `04_signin.yaml`, `03_signup.yaml`, etc.) include the same `env:` defaults. `00_signin_helper` supplies credentials for any flow that includes it (e.g. dashboard, add item) when run alone.

### Helpers: login state

| File | Behavior |
|------|----------|
| `00_signin_helper.yaml` | **Does not sign out.** Launches the app, switches from Sign Up → Sign In if needed, fills credentials only when `"Welcome back"` is visible, then waits for the dashboard. If already logged in (KPIs visible), it only waits for `"Total Storages"`. |
| `00_signout_helper.yaml` | **Conditional sign-out.** Signs out via Profile **only when** `"Total Storages"` is visible (logged-in main app). Used by flows that must start on the auth screen (e.g. wrong password, forgot password). If you are already on auth, it does nothing after launch. |

## Flow Index

| File | What it tests |
|------|--------------|
| 01_onboarding.yaml | Full 4-page onboarding walkthrough |
| 02_onboarding_skip.yaml | Skip button goes to auth |
| 03_signup.yaml | Create new account |
| 04_signin.yaml | Sign in with valid credentials |
| 05_signin_wrong_password.yaml | Error shown for wrong password |
| 06_forgot_password.yaml | Password reset email sent |
| 07_add_storage.yaml | Create a new storage area |
| 08_add_item.yaml | Add item inside a storage |
| 09_quick_count.yaml | Quick count button on item row |
| 10_full_count.yaml | Full count form from Count tab |
| 11_dashboard.yaml | Dashboard KPI cards visible |
| 12_items_tab.yaml | Items tab browse and search |
| 13_export_csv.yaml | Export CSV file |
| 14_export_pdf.yaml | Export PDF report |
| 15_settings.yaml | Settings screen navigation |
| 16_profile.yaml | Profile screen and privacy policy |
| 17_paywall_storage_limit.yaml | Paywall on 6th storage (manual) |
| 18_paywall_item_limit.yaml | Paywall on 51st item (manual) |
| 19_delete_storage.yaml | Delete storage with confirmation |
| 20_signout.yaml | Sign out and return to auth |
| 21_low_stock_detection.yaml | Add item with min qty, count below min, verify Low Stock card |
| 22_out_of_stock_detection.yaml | Count item to 0, verify Out of Stock card and filtered list |
| 23_edit_item.yaml | Edit item quantity and min quantity, verify saved |
| 24_low_stock_export.yaml | Export Low Stock List CSV with low stock item present |

## Before First Run

- Create a Firebase test account matching the defaults in `run_all.yaml` / flow `env:` blocks (`test@smartinventory.dev` / `Test@1234`), or change those values in the YAML files you run.
- Flows 17 & 18 (paywall limits) are commented out in `run_all.yaml` — run manually after seeding data

## Tips

- If a flow fails, Maestro saves a screenshot of the failure
- Run `maestro studio` to visually record new flows by tapping through the app
- Each flow is independent — you can run any single one at any time
