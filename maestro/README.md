# Smart Inventory — Maestro Test Suite

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

```bash
cd /Users/karthik_sivam/Documents/My\ Apps/SmartInventory/smart-inventory

# Run a single flow (env vars must be passed explicitly for individual flows)
maestro test --env TEST_EMAIL=test@vishuddhi.in --env TEST_PASSWORD=Test@1234 maestro/flows/04_signin.yaml

# Run all flows (config.yaml env vars are picked up automatically)
maestro test maestro/run_all.yaml

# Open visual studio (record flows by tapping)
maestro studio
```

> **Note:** `config.yaml` env vars are only applied when running `run_all.yaml`. For individual flows, always pass `--env TEST_EMAIL=... --env TEST_PASSWORD=...` explicitly.

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

## Before First Run

- Create a Firebase test account with `test@vishuddhi.in` / `Test@1234`
- Or update credentials in `config.yaml`
- Flows 17 & 18 (paywall limits) are commented out in `run_all.yaml` — run manually after seeding data

## Tips

- If a flow fails, Maestro saves a screenshot of the failure
- Run `maestro studio` to visually record new flows by tapping through the app
- Each flow is independent — you can run any single one at any time
