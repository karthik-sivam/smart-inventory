# Next: promotional pricing on the paywall

**Status:** planned, not started. Deliberately deferred out of the 1.5 release.
**Goal:** run "50% off monthly for 12 months" and have the paywall actually sell it.

## Why this is not just an App Store Connect change

An Introductory Offer configured in ASC applies **automatically** at purchase —
the Buy button needs no code. But the paywall currently renders only
`product.displayPrice`, so a discounted user would see ₹499, tap buy, and be
charged ₹249 having been told nothing.

That is a silent discount: the customer still gets the money off, but the
promotion drives zero extra conversion because nobody saw it before deciding.
Apple also requires the offer terms and the post-offer price to be disclosed on
the purchase screen.

**So the display code is a hard prerequisite, not a nice-to-have.**

## Recommended shape

| Audience | Mechanism | Server work |
|---|---|---|
| Never subscribed | **Introductory Offer**, Pay As You Go, 12 months | none |
| Existing / lapsed | **Offer Code** (custom code, e.g. `STOQLY50`) | none |
| Serious win-back later | Promotional Offer | yes — signing |

With a near-zero paying base today (paywall funnel: 54 viewers → 6 plan taps → 0
attributable purchases), the Introductory Offer alone covers effectively the
whole audience. Add an offer code to mop up the handful of existing subscribers.

Skip Promotional Offers until there is a subscriber base worth winning back —
they need a subscription key and a Cloud Function to sign each offer.

## The work

1. **Offer-aware price block on `ProductCard`** (`SubscriptionManager.swift`).
   Read `product.subscription?.introductoryOffer` and render:
   - the offer price (`offer.displayPrice`) and its period/duration,
   - the follow-on price ("then ₹499/month") from `product.displayPrice`.
2. **Eligibility gate.** Show it only when
   `await product.subscription?.isEligibleForIntroOffer` is true.
3. **Render nothing when there is no offer or the user is ineligible.**

### The rule that matters

Everything displayed must be derived from what StoreKit actually reports —
never a hardcoded claim.

The previous trial UI was removed in 1.5 precisely because it hardcoded
"7-day free trial" as copy. The offer existed only in the local `.storekit`
test file and was never configured in production, so the app advertised
something no user could get. Build this off `introductoryOffer` alone and that
failure mode is structurally impossible.

### Optional, smaller

Offer-code redemption: an `AppStore.presentOfferCodeRedeemSheet()` call behind a
"Have a promo code?" button on the paywall. No server, no signing.

## Decisions for the CEO before building

- **12 months at 50% is a long commitment.** Every subscriber acquired during
  the window keeps ₹249 for a full year. Against myBillBook at ₹349/month that
  undercuts the market — possibly the point, possibly a price anchor that is
  hard to walk back.
- **Eligibility is per subscription *group*, not per product.** Anyone who
  previously took the annual plan is NOT eligible for a monthly introductory
  offer, and needs a code instead.
- **Pick a real App Store price tier** near ₹249; arbitrary amounts are not
  selectable.

## Do not do this first

Do not configure the ASC offer before the display code ships. That is exactly
the silent-discount state described above, and it spends margin for no
conversion lift.
