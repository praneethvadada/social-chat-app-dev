import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import '../theme/colors.dart';

/// Phone-number input: a country-code flag picker + a digits-only field,
/// combined into the full E.164 number the backend expects (e.g.
/// "+919876543210"). Previously the app just had a plain text field where
/// the user had to type that whole prefix themselves — no flag, no picker.
///
/// Defaults to India (spec: default country); Canada is offered as the
/// next quick pick via `favorite` (shown pinned at the top of the picker
/// sheet, right under the current selection) rather than making the user
/// scroll the full country list to find it.
///
/// [controller] always holds the FULL E.164 value (kept in sync
/// automatically as either the dial code or the digits change) — so any
/// existing `controller.text.trim()` read/empty-check at the call site
/// keeps working completely unchanged. Left genuinely empty (not just
/// "+91" with no digits) when nothing's been typed yet, so an
/// empty-field validation check still behaves exactly as before. The user
/// only ever types the LOCAL digits — the country prefix is never part of
/// what they can type, so there's no way to accidentally duplicate it.
///
/// Validation: the real, authoritative check is always the backend's own
/// libphonenumber-based validator (unchanged, still the source of truth —
/// see PhoneNumberValidator.java) — this is a lightweight, best-effort
/// client-side pre-check so obviously-wrong input (too short, non-digits)
/// is caught before ever hitting the network, not a full replacement for
/// it. [onValidityChanged] fires whenever that changes, so a call site can
/// gate submission on it; the field also shows its own inline error text.
class PhoneNumberField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<bool>? onValidityChanged;

  const PhoneNumberField({
    super.key,
    required this.controller,
    this.hintText = 'Phone number',
    this.onValidityChanged,
  });

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  final TextEditingController _digitsCtrl = TextEditingController();
  String _dialCode = '+91';
  String _isoCode = 'IN';
  String? _error;

  /// National-significant-number length rules — deliberately modest, not a
  /// full libphonenumber port (spec's own wording: "validate ... where
  /// possible"; the backend remains the real source of truth). India and
  /// Canada get their real, exact NSN length since both are explicitly
  /// named in the spec; everything else falls back to a generic sanity
  /// range (E.164's own overall 15-digit cap, minus room for the dial
  /// code, floor high enough to catch an obviously-truncated number).
  static const Map<String, int> _exactNsnLength = {
    'IN': 10,
    'CA': 10, // NANP — same as the US
  };

  @override
  void initState() {
    super.initState();
    _digitsCtrl.addListener(_onDigitsChanged);
  }

  void _onDigitsChanged() {
    _syncFullNumber();
    _revalidate();
  }

  void _syncFullNumber() {
    final digits = _digitsCtrl.text.trim();
    widget.controller.text = digits.isEmpty ? '' : '$_dialCode$digits';
  }

  void _revalidate() {
    final digits = _digitsCtrl.text.trim();
    final wasValid = _error == null && digits.isNotEmpty;
    setState(() => _error = _validate(digits));
    final isValid = _error == null && digits.isNotEmpty;
    if (isValid != wasValid) {
      widget.onValidityChanged?.call(isValid);
    }
  }

  /// Null return = valid (or empty — an empty field isn't "invalid input",
  /// it's just not filled in yet; a separate required-field check at the
  /// call site handles that, matching every other field in this app).
  String? _validate(String digits) {
    if (digits.isEmpty) return null;
    if (!RegExp(r'^[0-9]+$').hasMatch(digits)) {
      return 'Digits only, no spaces or symbols';
    }
    final exact = _exactNsnLength[_isoCode];
    if (exact != null) {
      return digits.length == exact ? null : 'Enter a valid $exact-digit number';
    }
    if (digits.length < 6 || digits.length > 14) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  @override
  void dispose() {
    _digitsCtrl.removeListener(_onDigitsChanged);
    _digitsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themed = ThemedColors.of(context);
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _digitsCtrl,
            keyboardType: TextInputType.phone,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: themed.text),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: themed.mutedSolid),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: CountryCodePicker(
                  onInit: (country) {
                    if (country == null) return;
                    _dialCode = country.dialCode ?? '+91';
                    _isoCode = country.code ?? 'IN';
                  },
                  onChanged: (country) => setState(() {
                    _dialCode = country.dialCode ?? '+91';
                    _isoCode = country.code ?? 'IN';
                    _syncFullNumber();
                    _revalidate();
                  }),
                  initialSelection: 'IN',
                  // Pinned at the top of the picker sheet, in this order —
                  // India first (the default), Canada right after it. Keyed
                  // by ISO country code (NOT dial code) deliberately: '+1'
                  // alone would match every NANP country sharing that dial
                  // code (Canada, the US, the Dominican Republic, and more)
                  // — 'CA' picks out Canada specifically, confirmed by
                  // actually opening the picker and checking (it initially
                  // pulled in all of them).
                  favorite: const ['IN', 'CA'],
                  showCountryOnly: false,
                  showOnlyCountryWhenClosed: false,
                  alignLeft: false,
                  padding: EdgeInsets.zero,
                  textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: themed.text),
                  dialogTextStyle: TextStyle(color: themed.text),
                  searchStyle: TextStyle(color: themed.text),
                  backgroundColor: themed.surface,
                  barrierColor: Colors.black54,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(_error!, style: TextStyle(color: themed.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
