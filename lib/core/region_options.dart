/// The currencies and timezones a restaurant can be configured with.
///
/// These mirror `components/onboarding-form.tsx` on the web exactly
/// (`CURRENCIES` and `TIMEZONES` there), so a restaurant created on a phone is
/// configurable the same way as one created at a desk.
///
/// **These lists are the allow-list, not a convenience.** Onboarding offers
/// them, and `SettingsRepository.saveGeneral` *rejects* anything outside them
/// (`settingsCurrencies` / `settingsTimezones` alias straight to these).
/// Postgres applies no allow-list of its own, so removing an entry here does
/// not just hide an option — it makes a tenant already running on that value
/// unable to save its own settings. Widen freely; narrow only after checking
/// what live tenants are actually set to.
///
/// Nothing here is a regional default baked into business logic — rule #2 is
/// that region is configurable, and the values a tenant runs on live in
/// `tenant_settings`. These only bound what may be chosen.
library;

const kCurrencyOptions = <String>[
  'USD',
  'EUR',
  'GBP',
  'INR',
  'NPR',
  'AED',
  'SGD',
  'AUD',
  'CAD',
  'JPY',
];

const kTimezoneOptions = <String>[
  'UTC',
  'America/New_York',
  'America/Los_Angeles',
  'Europe/London',
  'Asia/Kolkata',
  'Asia/Kathmandu',
  'Asia/Dubai',
  'Asia/Singapore',
  'Australia/Sydney',
];

const kDefaultCurrency = 'USD';
const kDefaultTimezone = 'UTC';
