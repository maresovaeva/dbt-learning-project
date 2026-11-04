# Ecommerce Tracking Specification

GA4 funnel events · v0.1 · 4 Oct 2026

> **Repo context.** This spec is platform-neutral by design — it is the contract between analytics and engineering, not a Shopify document. `view_item` and `add_to_cart` from §5 are implemented on the test store and flow through to `fct_shop_funnel`. `begin_checkout` and `purchase` are specified but not built; see the README's Known gaps.

## 1. Purpose and scope

This document defines the GA4 ecommerce events the website must push to the data layer, the parameters each carries, and the conditions under which each fires. It is the contract between analytics and engineering: anything not specified here is undefined behaviour, and anything specified here is testable.

### Events in scope

| # | Event | Fires when |
| --- | --- | --- |
| 1 | `view_item_list` | A list of products becomes visible (category page, search results, recommendations) |
| 2 | `select_item` | A user clicks a product within a list |
| 3 | `view_item` | A product detail page is viewed |
| 4 | `add_to_cart` | A user successfully adds a product to the cart |
| 5 | `begin_checkout` | A user enters the checkout flow |
| 6 | `purchase` | An order is successfully placed |

### Out of scope for this version

`remove_from_cart`, `view_cart`, `add_to_wishlist`, `view_promotion`, `select_promotion`, `search`, and refund events. These are deliberately deferred rather than forgotten — see §8.

### Why these six

They form a closed funnel. Every step has a defined predecessor, so drop-off between any two adjacent steps is measurable without inference. Adding events outside the funnel before the funnel itself is reliable produces more data and less insight.

### What this document does not cover

- Tag configuration in the tag manager (separate document)
- Consent management — assumed to be in place and signalling correctly before any event here fires
- Server-side forwarding or destinations beyond GA4

## 2. Ownership and process

| Role | Responsibility |
| --- | --- |
| **Analytics** | Owns this document. Defines events, parameters and firing conditions. Performs QA against §7 and signs off. |
| **Engineering** | Implements the data layer pushes. Raises ambiguities **before** building rather than resolving them silently. |
| **Analytics + Engineering** | Agree on the source of each value (§5). This is where most specs fail. |
| **Product / Commercial** | Confirms the business definitions — what counts as a purchase, which currency, how discounts are represented. |

### Change process

1. Any change to an event or parameter is made **in this document first**, with a dated entry.
2. Changes that alter the meaning of an existing parameter require a new parameter instead. Silently redefining a field breaks every historical comparison and no one notices for months.
3. Implementation follows the document. If the implementation diverges, the document is wrong or the implementation is — resolve it, do not leave both.

### Definition of done

An event is done when all four hold:

- It fires under every condition in §5, and under no others
- Every required parameter is present and correctly typed
- It has been verified in the browser network request, not only in the tag manager preview
- It appears correctly in GA4 **and** in the raw export

> Verification in the tag manager alone is insufficient. A tag can fire correctly and still deliver nothing — see §7.

## 3. Conventions

### Naming

- Event names: `snake_case`, lowercase, exactly as written in §6. These are GA4 reserved names — spelling variants create separate, useless events.
- Parameter names: `snake_case`, lowercase.
- Values are **not** normalised by GA4. `Mint`, `mint` and `MINT` are three different dimension values.

### Data types

| Field type | Rule |
| --- | --- |
| Monetary (`value`, `price`, `tax`, `shipping`, `discount`) | **Number, not string.** `19.99`, never `"19.99"` |
| Counts (`quantity`, `index`) | Integer |
| Identifiers and names | String |
| Currency | String, ISO 4217 uppercase (`EUR`, `USD`) |

> **Why this matters more than it looks.** A price sent as a string lands in GA4's string parameter namespace rather than the numeric one. It is then either dropped or treated as a text dimension, and revenue reports silently under-report. This is the single most common ecommerce tracking defect.

### Monetary values

- Always the amount **the customer pays**: after discounts, in the currency displayed to them.
- `value` on each event = sum of `price × quantity` across `items[]`, excluding tax and shipping unless stated otherwise in §6.
- Decimal point, never a comma. Never a thousands separator. Never a currency symbol.
- `currency` is **required whenever `value` is present**. Sending `value` without `currency` causes GA4 to discard the revenue entirely.

### Clearing the ecommerce object

The data layer **merges**; it does not replace. A key set by an earlier push remains visible to every later event on the same page.

Every ecommerce push must therefore be preceded by a clearing push:

```js
window.dataLayer = window.dataLayer || [];
dataLayer.push({ ecommerce: null });
dataLayer.push({
  event: "add_to_cart",
  ecommerce: { … }
});
```

> **Without this, events inherit the previous event's items.** The result is not missing data — which would be noticed — but complete, plausible and wrong data: an `add_to_cart` reporting the product the user viewed three clicks ago. `null` clears only the key named, so any other custom key that could leak must be cleared explicitly too.

### Data layer initialisation

The array must be initialised with `window.dataLayer = window.dataLayer || []`. A bare `window.dataLayer = []` anywhere on the page discards every push made before it **and** disconnects the tag manager's listener, silently, for the remainder of the page.

## 4. The item schema

All six events carry an `items` array using the same object shape. Define it once, implement it once, reuse it everywhere.

| Field | Type | Required | Definition |
| --- | --- | --- | --- |
| `item_id` | string | **Yes** | The SKU actually sold. **Variant-level**, not the parent product — see note below |
| `item_name` | string | **Yes** | Human-readable product name as shown to the customer |
| `price` | number | **Yes** | Unit price the customer pays, after discount, excluding tax |
| `quantity` | integer | **Yes** | See §5.1 for the semantics |
| `item_variant` | string | Where applicable | **Human-readable** variant — `"mint"`, not `"TRDOG6MT"` |
| `item_brand` | string | Where applicable | Brand name |
| `item_category` | string | Recommended | Top-level category. `item_category2` … `item_category5` for deeper levels |
| `discount` | number | Where applicable | Per-unit discount amount, as a positive number |
| `coupon` | string | Where applicable | Coupon code applied to this item |
| `index` | integer | List events only | Position in the list, **1-based** |
| `item_list_id` | string | List events only | Machine identifier of the list |
| `item_list_name` | string | List events only | Human-readable list name |

### Two rules that are routinely broken

> **`item_id` must be variant-level.** If three colours of one product share one `item_id`, no report can ever answer "which colour sells". The data loss is permanent and silent — volumes look correct throughout.

> **`item_name` must be the readable name, not the SKU.** Putting the SKU in both fields is a common defect: GA4's product reports then display `TRDOG6MT` to every stakeholder, and the readable name exists nowhere in the dataset. The two fields have different jobs — one identifies, one labels.

### Worked example

```js
items: [{
  item_id: "TRDOG6MT",
  item_name: "GPS Tracker DOG 6",
  item_variant: "mint",
  item_brand: "Acme",
  item_category: "tracker",
  price: 69.00,
  quantity: 1
}]
```

### Multiple items

Where an event concerns more than one product — `begin_checkout`, `purchase` — the array carries one object per **distinct item**, with `quantity` expressing how many of each. Never repeat the same object to express quantity.

## 5. Event specifications

Each event below states **when** it fires, what it must **not** do, and the parameters it carries. Every push is preceded by `dataLayer.push({ ecommerce: null })` per §3.

---

### 5.1 `view_item_list`

**Fires when** a list of products becomes visible to the user: category and collection pages, search results, recommendation carousels.

**Fires once per list per page view.** If a list is paginated or lazy-loaded, each newly rendered batch fires its own event with the correct `index` values continuing the sequence.

**Does not fire** for lists rendered below the fold that the user never scrolls to, where the implementation can detect visibility. Where it cannot, fire on render and note the limitation here.

| Parameter | Type | Required |
| --- | --- | --- |
| `item_list_id` | string | Yes |
| `item_list_name` | string | Yes |
| `items[]` | array | Yes |

```js
dataLayer.push({ ecommerce: null });
dataLayer.push({
  event: "view_item_list",
  ecommerce: {
    item_list_id: "collection_trackers",
    item_list_name: "Trackers",
    items: [
      { item_id: "TRDOG6MT", item_name: "GPS Tracker DOG 6", item_variant: "mint",
        price: 69.00, quantity: 1, index: 1,
        item_list_id: "collection_trackers", item_list_name: "Trackers" }
    ]
  }
});
```

> `item_list_id` and `item_list_name` appear **both** at the ecommerce level and on each item. GA4 uses the item-level values for attribution, so omitting them there breaks list-performance reporting.

---

### 5.2 `select_item`

**Fires when** the user clicks a product within a list, before navigation begins.

**Carries exactly one item** — the clicked product, with the `index` and list identifiers it had in the list it was clicked from.

**Does not fire** on clicks on list furniture: filters, sort controls, pagination, "load more".

| Parameter | Type | Required |
| --- | --- | --- |
| `item_list_id` | string | Yes |
| `item_list_name` | string | Yes |
| `items[]` | array, exactly 1 | Yes |

> **Implementation note.** The clicked DOM element may be a child of the product link — an image, a price, a label. The implementation must resolve the product from the nearest ancestor that carries the product identity, not from the element that received the click. Reading the identity off the clicked element directly fails intermittently and only for some users.

---

### 5.3 `view_item`

**Fires when** a product detail page is displayed, once per product view.

**Fires again** if the user changes variant on the page without a page reload **and** the price or identity changes. The new push carries the newly selected variant.

**Does not fire** on quick-view modals unless they display full product detail — decide and record the decision in §8.

| Parameter | Type | Required |
| --- | --- | --- |
| `currency` | string | Yes |
| `value` | number | Yes |
| `items[]` | array, exactly 1 | Yes |

```js
dataLayer.push({ ecommerce: null });
dataLayer.push({
  event: "view_item",
  ecommerce: {
    currency: "EUR",
    value: 69.00,
    items: [
      { item_id: "TRDOG6MT", item_name: "GPS Tracker DOG 6",
        item_variant: "mint", item_category: "tracker",
        price: 69.00, quantity: 1 }
    ]
  }
});
```

> **Variant selection is the trap here.** Where variant is selected in a separate control from the add-to-cart action, the page's initial state has a default variant that the user never actively chose. The `item_id` must reflect what is **currently selected**, including that default. Record which variant is the default in §8 — getting it wrong mislabels a large share of traffic silently.

---

### 5.4 `add_to_cart`

**Fires when** the product has been **successfully added**, not when the button is clicked.

> **This distinction is the whole specification.** Firing on click counts failures as successes: out-of-stock items, validation errors, network failures, rapid double-clicks. The event must be triggered by the application's own success response, not by the DOM event.

**Fires once per successful add**, regardless of how many add-to-cart controls exist on the page. Sticky bars, mobile variants and the main button are the same action.

| Parameter | Type | Required |
| --- | --- | --- |
| `currency` | string | Yes |
| `value` | number | Yes |
| `items[]` | array | Yes |

> **`quantity` carries the amount added in this action — not the cart total.** If a user has two in the cart and adds one more, `quantity` is `1`. See §6.1 of the edge cases; this is the most frequently misimplemented field in the entire specification, and the error is invisible in reports because both numbers look plausible.

---

### 5.5 `begin_checkout`

**Fires when** the user enters the checkout flow — the first checkout step is displayed, not when the button to enter it is clicked.

**Fires once per checkout entry.** A user who leaves checkout and returns fires it again; this is correct.

| Parameter | Type | Required |
| --- | --- | --- |
| `currency` | string | Yes |
| `value` | number | Yes |
| `items[]` | array | Yes |
| `coupon` | string | Where applicable |

> **Where checkout is hosted on a different domain or subdomain**, cross-domain measurement must be configured or the user is counted as a new visitor arriving from a referral, and the funnel breaks at precisely the step that matters most. Confirm the checkout domain in §8.

---

### 5.6 `purchase`

**Fires when** an order is confirmed — the application has an order ID.

| Parameter | Type | Required |
| --- | --- | --- |
| `transaction_id` | string | **Yes** |
| `currency` | string | Yes |
| `value` | number | Yes |
| `items[]` | array | Yes |
| `tax` | number | Recommended |
| `shipping` | number | Recommended |
| `coupon` | string | Where applicable |

```js
dataLayer.push({ ecommerce: null });
dataLayer.push({
  event: "purchase",
  ecommerce: {
    transaction_id: "ORD-100493",
    currency: "EUR",
    value: 138.00,
    tax: 27.60,
    shipping: 0,
    items: [
      { item_id: "TRDOG6MT", item_name: "GPS Tracker DOG 6",
        item_variant: "mint", price: 69.00, quantity: 2 }
    ]
  }
});
```

**Three mandatory properties:**

> **1. `transaction_id` is the real order identifier**, the same value used in the order management system. It must never be generated client-side, never be a timestamp, never be random. It is the join key between analytics and finance, and the only thing allowing anyone to reconcile the two.

> **2. `value` excludes tax and shipping** unless the business explicitly decides otherwise and records that decision in §8. Whichever is chosen must be applied consistently — the comparison that breaks is not against a standard, it is against last year.

> **3. The event must fire exactly once per order.** A customer who refreshes the confirmation page, or returns to it from their email, must not generate a second `purchase`. GA4 deduplicates on `transaction_id` within a limited window, which is a safety net and not a substitute for firing once.

## 6. Edge cases and decisions

Each of these must be decided before implementation begins, and the decision recorded here. Left undecided, each will be resolved silently by whoever writes the code — and discovered months later in a report that does not reconcile.

### 6.1 Quantity semantics on `add_to_cart`

**Decision required:** does `quantity` mean the amount added in this action, or the resulting cart total for that item?

**This specification says: the amount added.** Both produce plausible numbers, which is exactly why the error survives QA. If the cart already holds two and the user adds one, the event carries `1`.

**Test that distinguishes them:** add a single item to an empty cart, then add the same item again. Correct behaviour is two events each carrying `1`. Incorrect behaviour is events carrying `1` then `2`.

### 6.2 Variant identity

**Decision required:** which field carries the variant, and in what form?

- `item_id` carries the **variant-level SKU** — the identifier of the thing actually sold
- `item_variant` carries the **human-readable** variant — `"mint"`, not `"TRDOG6MT"`

Where the site exposes variant in the URL and in the page markup, confirm the two agree. They often do not: the URL may carry a readable value while the markup carries the SKU, and both are needed.

**Also record:** which variant is selected by default when the user has not chosen one, and whether the identifier changes when they do.

### 6.3 Interactions without a page load

Cart drawers, quick-view modals, lazy-loaded lists and single-page navigation all change what the user sees **without a page load**. No page-load event fires, so anything depending on one will not run.

**Consequence:** events for these interactions must be pushed by the application at the moment the interaction completes. They cannot be inferred from page views.

**Decision required:** list every such interaction in the purchase funnel and confirm which pushes its own event.

### 6.4 Pre-existing platform integrations

**Decision required:** does the platform, a theme, or an installed app already send ecommerce events to the same analytics property?

Many commerce platforms ship their own analytics integration. Where one exists and is active, implementing this specification on top produces **duplicate events** — most damagingly duplicate `purchase`, which inflates revenue.

**Resolution, in order of preference:**

1. Disable the platform integration and own the implementation here
2. Keep the platform integration and implement only events it does not send
3. Send to separate properties — acceptable only as a transitional state

**Verification:** inspect the outbound network requests and check the initiator of every analytics hit. A hit initiated by a script other than the tag manager is coming from somewhere this specification does not control.

### 6.5 Unavailable products

Out-of-stock or otherwise unpurchasable products still render a product page and often still render a disabled add-to-cart control.

- `view_item` **does** fire — the product was viewed
- `add_to_cart` **does not** fire — nothing was added

**Implementation note:** availability must not be inferred from the control's visible text. Labels vary by state and by language, and any logic reading them breaks on translation.

### 6.6 Consent

Where consent has been refused, these events still fire and still send, but carry no persistent identifier. Each page load is treated as a new user.

**Consequence for reporting:** funnel and retention analysis covers consented traffic only. Modelled figures shown in the analytics interface are not present in the raw data export, so interface and warehouse will legitimately disagree. Record the expected gap rather than treating it as a defect.

### 6.7 Tax, shipping and discounts

**Decision required**, and apply consistently across all events:

| Question | This specification's default |
| --- | --- |
| Does `value` include tax? | No |
| Does `value` include shipping? | No |
| Is `price` before or after discount? | After — what the customer pays |
| How is the discount recorded? | `discount`, per unit, as a positive number |

Whichever is chosen, changing it later breaks every year-on-year comparison.

## 7. QA acceptance criteria

An event is not accepted because a tag fired. **A tag can fire correctly, send a request successfully, and still deliver nothing usable.** Each layer must be verified separately.

### The three layers

| Layer | Question | Where |
| --- | --- | --- |
| 1 | Did the push reach the data layer with the right shape? | Tag manager preview → Data Layer tab |
| 2 | Did the request leave the browser with the right values? | Browser network tab |
| 3 | Did the analytics platform accept it? | Debug view, then the raw export |

A failure at each layer looks different, and knowing which layer broke is most of the diagnosis.

### Per-event checklist

For each of the six events:

- [ ] Fires under every condition in §5
- [ ] Does **not** fire under the stated exclusions
- [ ] Fires exactly once per occurrence — verified by counting events, not by observing one
- [ ] All required parameters present
- [ ] Monetary values are numbers, not strings
- [ ] `currency` present wherever `value` is
- [ ] `item_id` is variant-level
- [ ] `item_name` is the readable name, not the SKU
- [ ] `ecommerce` cleared before the push

### Cross-event checks

- [ ] **No inherited data.** Trigger a sequence of different events and confirm each carries only its own items. The test is a deliberate sequence — view product A, then add product B — and checking B's event does not mention A
- [ ] **One analytics ID.** Filter network requests by measurement ID and confirm exactly one distinct ID appears, and that it is the right one
- [ ] **No duplicates from other sources.** Check the initiator of every analytics request. Anything not initiated by the tag manager comes from an integration outside this specification
- [ ] **`transaction_id` matches** the order ID in the order management system, for a real test order
- [ ] **Funnel monotonicity.** Over a day of test traffic, each step's count should be less than or equal to the step before. An increase means an event is firing more than once

### Checks that catch silent failures

These are the ones worth doing because the defect produces plausible data rather than missing data:

> **Variable resolution.** Before trusting any value read from the data layer, confirm the variable actually returns something. A misspelled key returns undefined, the tag fires happily, and the parameter is simply absent from the hit. No error appears anywhere.

> **Parameter presence vs event presence.** Normal event volume with a missing parameter means the event is being sent by something other than the tag you configured. Check which source is sending it before debugging the tag.

> **Identifier persistence.** Where consent is granted, the user identifier must be stable across page loads. Comparing two requests from the same page load proves nothing — they always match. Reload between comparisons.

> **Quantity semantics.** Run the two-add test from §6.1 explicitly. No other check distinguishes the two interpretations.

### Sign-off

QA is complete when all six events pass all three layers, the cross-event checks pass, and the funnel reconciles against the order management system for a full day of test traffic.

## 8. Open questions

To be answered before implementation starts. Each has a named owner, and an unanswered question blocks the event it affects.

| # | Question | Owner | Blocks |
| --- | --- | --- | --- |
| 1 | Does the platform already send ecommerce events to this property? If so, which? | Engineering | All events |
| 2 | Is the checkout hosted on the same domain? | Engineering | `begin_checkout`, `purchase` |
| 3 | Which variant is selected by default on a product page? | Product | `view_item`, `add_to_cart` |
| 4 | Does `value` include tax and shipping? | Commercial | All events with `value` |
| 5 | Do quick-view modals count as `view_item`? | Analytics | `view_item` |
| 6 | Which lists exist, and what are their stable identifiers? | Product + Engineering | `view_item_list`, `select_item` |
| 7 | Can the application expose an add-to-cart success callback? | Engineering | `add_to_cart` |
| 8 | Is there a server-side order ID available on the confirmation page? | Engineering | `purchase` |

### Deferred to a later version

`remove_from_cart`, `view_cart`, `add_to_wishlist`, `view_promotion`, `select_promotion`, `search`, refunds, and user-level identifiers for logged-in customers.

These are deferred deliberately. The funnel in §5 must be reliable before anything is built on top of it — extra events on an unreliable base produce more data and less insight.

### Revision history

| Version | Date | Change | Author |
| --- | --- | --- | --- |
| 0.1 | 2026-10-04 | Initial draft — six funnel events, pending answers to §8 | Analytics |

### Sign-off

| Role | Name | Date |
| --- | --- | --- |
| Analytics | | |
| Engineering | | |
| Product | | |
