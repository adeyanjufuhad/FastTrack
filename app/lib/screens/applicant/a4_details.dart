import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../state/scope.dart';
import '../../theme/tokens.dart';
import '../../utils/money.dart';
import '../../widgets/applicant_frame.dart';

class _Field {
  const _Field(this.key, this.label, {this.kind = _Kind.text, this.hint});
  final String key;
  final String label;
  final _Kind kind;
  final String? hint;
}

enum _Kind { text, phone, date, digits11 }

const _individual = [
  _Field('legal_name', 'Legal name (as on ID)'),
  _Field('dob', 'Date of birth', kind: _Kind.date),
  _Field('phone', 'Phone number', kind: _Kind.phone),
  _Field('address', 'Residential address'),
  _Field('occupation', 'Occupation'),
  _Field('next_of_kin_name', 'Next of kin — name'),
  _Field('next_of_kin_phone', 'Next of kin — phone', kind: _Kind.phone),
];

const _corporate = [
  _Field('registered_name', 'Registered company name'),
  _Field('rc_number', 'RC number', hint: 'e.g. RC 1234567'),
  _Field('nature_of_business', 'Nature of business'),
  _Field('registered_address', 'Registered address'),
  _Field('signatory_1_name', 'Signatory 1 — full name'),
  _Field('signatory_1_bvn', 'Signatory 1 — BVN', kind: _Kind.digits11),
  _Field('signatory_2_name', 'Signatory 2 — full name'),
  _Field('signatory_2_bvn', 'Signatory 2 — BVN', kind: _Kind.digits11),
];

/// A4 — stepped form, step 1 of 4. Draft is restored when you come back.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  int _tenor = 12;
  bool _loaded = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    _loaded = true;
    final app = context.appRead;
    await app.ensureApplicant();
    if (!mounted) return;
    final p = app.profile!;
    final a = app.application!;
    for (final f in [..._individual, ..._corporate]) {
      _controllers[f.key] = TextEditingController(text: p.fields[f.key] ?? '');
    }
    _amount.text = a.requestedAmount == null ? '' : groupThousands(a.requestedAmount!);
    _purpose.text = a.purpose ?? '';
    setState(() => _tenor = a.tenorMonths);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  void _collect() {
    final app = context.appRead;
    final p = app.profile!;
    final fields = p.role == ApplicantRole.corporate ? _corporate : _individual;
    for (final f in fields) {
      p.fields[f.key] = _controllers[f.key]!.text.trim();
    }
    final a = app.application!;
    a
      ..requestedAmount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''))
      ..tenorMonths = _tenor
      ..purpose = _purpose.text.trim();
  }

  Future<void> _save({required bool andContinue}) async {
    final app = context.appRead;
    if (app.profile == null) return;
    if (andContinue && !_form.currentState!.validate()) {
      context.toast('Please complete the highlighted fields.');
      return;
    }
    setState(() => _busy = true);
    _collect();
    try {
      await app.saveDraft();
      if (!mounted) return;
      if (andContinue) {
        context.go('/kyc');
      } else {
        context.toast('Draft saved');
      }
    } catch (e) {
      if (mounted) context.toast('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(_Field f, String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Required';
    switch (f.kind) {
      case _Kind.phone:
        if (s.replaceAll(RegExp(r'[^0-9]'), '').length < 10) return 'Enter a valid phone number';
      case _Kind.digits11:
        if (!RegExp(r'^\d{11}$').hasMatch(s)) return 'BVN is 11 digits';
      case _Kind.date:
        if (DateTime.tryParse(s) == null) return 'Pick a date';
      case _Kind.text:
        if (f.key == 'rc_number' && !RegExp(r'\d{4,}').hasMatch(s)) return 'Enter the RC number';
    }
    return null;
  }

  Widget _input(_Field f) {
    final c = _controllers[f.key]!;
    return TextFormField(
      controller: c,
      readOnly: f.kind == _Kind.date,
      keyboardType: switch (f.kind) {
        _Kind.phone => TextInputType.phone,
        _Kind.digits11 => TextInputType.number,
        _ => TextInputType.text,
      },
      inputFormatters: f.kind == _Kind.digits11
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]
          : null,
      decoration: InputDecoration(
        labelText: f.label,
        hintText: f.hint,
        suffixIcon: f.kind == _Kind.date ? const Icon(Icons.calendar_today_outlined, size: 18) : null,
      ),
      validator: (v) => _validate(f, v),
      onTap: f.kind != _Kind.date
          ? null
          : () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(c.text) ?? DateTime(now.year - 30),
                firstDate: DateTime(now.year - 100),
                lastDate: DateTime(now.year - 18, now.month, now.day),
              );
              if (picked != null) c.text = picked.toIso8601String().substring(0, 10);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final profile = app.profile;
    if (profile == null || _controllers.isEmpty) {
      return const ApplicantFrame(step: 1, child: Center(child: CircularProgressIndicator()));
    }
    final corporate = profile.role == ApplicantRole.corporate;
    final fields = corporate ? _corporate : _individual;
    final twoCol = context.width >= 720;

    Widget grid(List<_Field> fs) {
      if (!twoCol) {
        return Column(children: [for (final f in fs) Padding(padding: const EdgeInsets.only(bottom: 14), child: _input(f))]);
      }
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final f in fs)
            LayoutBuilder(builder: (context, box) => SizedBox(width: (box.maxWidth - 14) / 2, child: _input(f))),
        ],
      );
    }

    return ApplicantFrame(
      step: 1,
      back: '/role',
      maxWidth: 760,
      title: corporate ? 'Company details' : 'Your details',
      subtitle: corporate
          ? 'Two signatories are required. Signatory BVNs are checked in the next step and are not stored in full.'
          : 'This replaces the PDF account form. Your progress is saved.',
      actions: [
        if (context.isCompact)
          IconButton(
            tooltip: 'Save draft',
            onPressed: _busy ? null : () => _save(andContinue: false),
            icon: const Icon(Icons.save_outlined),
          )
        else
          TextButton.icon(
            onPressed: _busy ? null : () => _save(andContinue: false),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save draft'),
          ),
      ],
      bottom: ActionBar(
        status: corporate ? 'Corporate track' : 'Individual track',
        action: FilledButton(
          onPressed: _busy ? null : () => _save(andContinue: true),
          child: const Text('Continue to identity'),
        ),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: corporate ? 'Business' : 'Personal',
              trailing: TextButton(
                onPressed: () => context.go('/role'),
                child: const Text('Change track'),
              ),
              child: grid(fields),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Facility',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, _ThousandsFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Amount (optional)',
                      prefixText: 'NGN ',
                      helperText: 'Leave empty to see your maximum.',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Tenor (months)', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: FT.navy)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 6, label: Text('6')),
                      ButtonSegment(value: 12, label: Text('12')),
                      ButtonSegment(value: 24, label: Text('24')),
                    ],
                    selected: {_tenor},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _tenor = v.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _purpose,
                    decoration: const InputDecoration(labelText: 'Purpose', hintText: 'e.g. Rent renewal, working capital'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    final digits = value.text.replaceAll(',', '');
    if (digits.isEmpty) return value.copyWith(text: '');
    final v = int.tryParse(digits);
    if (v == null) return old;
    final text = groupThousands(v);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
