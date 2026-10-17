# Hesabaty Android translation status — 2026-10-17

The user's current logo (black H with green wallet) is approved and used by
Android launcher icons and in the Flutter AppBar. New preview APKs automatically
regenerate adaptive and legacy icons from the committed brand asset.

## English available in Flutter preview
- Tabs and navigation, selected-language persistence and LTR/RTL direction
- Dashboard totals, spending ratio, categories, dates and due alerts
- Transactions list, filters, search, input labels, standard categories
- Installments cards, due state, add/edit forms and action labels
- Six-month analytics headings, monthly comparison narrative and key metrics
- Main settings, backups, account and privacy navigation
- SMS import review messages and Premium subscription screen
- Separate signup flow already uses a bilingual registration form

## Still requires review before calling it 100% bilingual
- Some dialogs, snackbars, server errors, manual backup conflict
  conversations, payment-linking prompts and login recovery feedback
- PDF content / exported report language (PDF remains Arabic)
- Financial text extracted from bank SMS must remain in the original message
  language, not auto-translated
- User-entered category names, notes, bank names and installment names must
  remain unchanged in storage or display, unless explicitly user-edited
- Formal ARB-based localization audit, accessibility, RTL screenshots and
  small Android display visual QA

Tests: widget_test.dart includes an English dashboard/editor regression test.
Launch CI on branch flutter-v2 to inspect the latest APK output.
