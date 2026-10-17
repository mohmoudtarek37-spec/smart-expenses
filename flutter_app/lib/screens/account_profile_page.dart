import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../security/device_biometric_lock.dart';

class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({
    super.key,
    required this.initial,
    required this.scope,
    required this.isEnglish,
    this.email,
  });

  final Map<String, dynamic> initial;
  final String scope;
  final bool isEnglish;
  final String? email;

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  String _birthday = '';
  String _gender = '';
  String _photo = '';
  bool _lockEnabled = false;
  bool _lockAvailable = false;
  bool _lockBusy = false;
  String _message = '';

  String _tr(String ar, String en) => widget.isEnglish ? en : ar;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial['name']?.toString() ?? '');
    _phone = TextEditingController(text: widget.initial['phone']?.toString() ?? '');
    _birthday = widget.initial['birthday']?.toString() ?? '';
    _gender = widget.initial['gender']?.toString() ?? '';
    _photo = widget.initial['photo']?.toString() ?? '';
    _loadSecurity();
  }

  Future<void> _loadSecurity() async {
    final service = DeviceBiometricLock.instance;
    try {
      final available = await service.available();
      final enabled = await service.isEnabled(widget.scope);
      if (mounted) {
        setState(() {
        _lockAvailable = available;
        _lockEnabled = enabled;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _lockAvailable = false);
      }
    }
  }

  Future<void> _toggleLock(bool next) async {
    if (_lockBusy) return;
    setState(() { _lockBusy = true; _message = ''; });
    try {
      final ok = await DeviceBiometricLock.instance.change(
        widget.scope, next, _tr(
          'أكد هويتك لتغيير قفل حساباتي',
          'Verify your identity to change Hesabaty app lock',
        ),
      );
      if (!mounted) return;
      setState(() {
        if (ok) {
          _lockEnabled = next;
        } else {
          _message = _tr(
          'لم يتم تغيير القفل. تأكد من تسجيل البصمة أو الوجه على موبايلك.',
          'App lock unchanged. Check that device biometrics are enrolled.');
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = _tr(
          'تعذر تغيير قفل التطبيق.', 'Could not change app lock.'));
      }
    } finally {
      if (mounted) {
        setState(() => _lockBusy = false);
      }
    }
  }

  Future<void> _pickPhoto() async {
    try {
      const type = XTypeGroup(label: 'Profile photo',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp']);
      final image = await openFile(acceptedTypeGroups: [type]);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 256 * 1024) {
        if (mounted) {
          setState(() => _message = _tr(
            'الصورة أكبر من 256 كيلوبايت؛ اختار صورة أصغر.',
            'Photo is larger than 256 KB. Choose a smaller image.'));
        }
        return;
      }
      if (mounted) {
        setState(() {
          _photo = base64Encode(bytes);
          _message = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = _tr(
          'تعذر فتح الصورة.', 'Could not open the photo.'));
      }
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_birthday) ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (selected == null || !mounted) return;
    setState(() => _birthday =
      '${selected.year.toString().padLeft(4,'0')}-'
      '${selected.month.toString().padLeft(2,'0')}-'
      '${selected.day.toString().padLeft(2,'0')}');
  }

  void _save() {
    if (_name.text.trim().length > 60 || _phone.text.trim().length > 25) {
      setState(() => _message = _tr(
          'اسم المستخدم أو رقم الهاتف أطول من المسموح.',
          'Name or phone number is too long.'));
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'birthday': _birthday,
      'gender': _gender,
      'photo': _photo,
    });
  }

  Widget _avatar() {
    Uint8List? image;
    try {
      if (_photo.isNotEmpty) image = base64Decode(_photo);
    } catch (_) {
      image = null;
    }
    return CircleAvatar(radius: 48,
      backgroundImage: image == null ? null : MemoryImage(image),
      child: image == null ? const Icon(Icons.person_outline, size: 40) : null,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_tr('الحساب', 'Account'))),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Center(child: Column(children: [
          _avatar(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('profile-photo'),
            onPressed: _pickPhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_tr('إضافة أو تغيير الصورة', 'Add or change photo')),
          ),
          if (_photo.isNotEmpty)
            TextButton(onPressed: () => setState(() => _photo = ''),
              child: Text(_tr('حذف الصورة', 'Remove photo'))),
        ])),
        const SizedBox(height: 16),
        TextField(
          key: const Key('profile-name'),
          controller: _name,
          maxLength: 60,
          decoration: InputDecoration(
            labelText: _tr('اسم المستخدم', 'Username'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (widget.email != null)
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(widget.email!),
            subtitle: Text(_tr('البريد المسجل بالحساب', 'Account email')),
          ),
        const SizedBox(height: 12),
        Text(_tr('التفاصيل', 'Details'),
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          key: const Key('profile-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 25,
          decoration: InputDecoration(
            labelText: _tr('رقم الهاتف (اختياري)', 'Phone (optional)'),
            border: const OutlineInputBorder(),
          ),
        ),
        ListTile(
          key: const Key('profile-birthday'),
          leading: const Icon(Icons.cake_outlined),
          title: Text(_tr('تاريخ الميلاد', 'Date of birth')),
          subtitle: Text(_birthday.isEmpty
              ? _tr('اختياري', 'Optional') : _birthday),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: _pickBirthday,
        ),
        if (_birthday.isNotEmpty)
          Align(alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => setState(() => _birthday = ''),
              child: Text(_tr('مسح تاريخ الميلاد', 'Clear birthday')),
            )),
        DropdownButtonFormField<String>(
          key: const Key('profile-gender'),
          initialValue: _gender.isEmpty ? '' : _gender,
          decoration: InputDecoration(
            labelText: _tr('النوع (اختياري)', 'Gender (optional)'),
            border: const OutlineInputBorder()),
          items: [
            DropdownMenuItem(value: '', child: Text(_tr('غير محدد', 'Not specified'))),
            DropdownMenuItem(value: 'male', child: Text(_tr('ذكر', 'Male'))),
            DropdownMenuItem(value: 'female', child: Text(_tr('أنثى', 'Female'))),
          ],
          onChanged: (value) => setState(() => _gender = value ?? ''),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          key: const Key('profile-biometric'),
          secondary: const Icon(Icons.fingerprint),
          title: Text(_tr('فتح التطبيق بالبصمة أو الوجه', 'Biometric app lock')),
          subtitle: Text(_lockAvailable
              ? _tr('حسب الإمكانيات المسجلة في موبايلك',
                    'Uses the biometric method set up on your phone')
              : _tr('سجّل بصمة أو وجه في إعدادات الموبايل أولًا',
                    'Set up fingerprint or face unlock on your phone first')),
          value: _lockEnabled,
          onChanged: (_lockAvailable || _lockEnabled) && !_lockBusy
              ? _toggleLock : null,
        ),
        Text(_tr('القفل بيحمي فتح التطبيق على الجهاز ده، '
          'ومش بديل عن كلمة مرور حسابك.',
          'This protects opening the app on this device. '
          'It does not replace your account password.'),
          style: Theme.of(context).textTheme.bodySmall),
        if (_message.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_message, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const Key('profile-save'),
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_tr('حفظ التعديلات', 'Save changes')),
        ),
      ],
    )),
  );
}
