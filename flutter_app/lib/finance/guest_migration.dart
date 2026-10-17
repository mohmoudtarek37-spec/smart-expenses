import 'backup_codec.dart';
import 'installment_models.dart';

/// Copies a valid guest snapshot only into a completely empty account.
/// The original guest store must never be deleted by this workflow.
class GuestMigration {
  static InstallmentLedger prepare({
    required InstallmentLedger guest,
    required InstallmentLedger account,
  }) {
    BackupCodec.validate(guest);
    BackupCodec.validate(account);
    if (guest.entries.isEmpty && guest.installments.isEmpty &&
        guest.customCategories.isEmpty) {
      throw StateError('Guest does not contain financial records');
    }
    if (account.entries.isNotEmpty || account.installments.isNotEmpty ||
        account.customCategories.isNotEmpty || account.prefs.isNotEmpty) {
      throw StateError('Destination contains data: refusing to overwrite it');
    }
    return guest;
  }
}
