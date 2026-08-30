import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/saved_payment_card.dart';
import '../services/locale_service.dart';
import '../utils/omise_card_token_helper.dart';
import 'card_brand_strip.dart';

class OmiseCardCheckoutScreen extends StatefulWidget {
  const OmiseCardCheckoutScreen({
    super.key,
    required this.sessionId,
    required this.amount,
    this.publicKey,
  });

  final String sessionId;
  final double amount;
  final String? publicKey;

  @override
  State<OmiseCardCheckoutScreen> createState() =>
      _OmiseCardCheckoutScreenState();
}

class _OmiseCardCheckoutScreenState extends State<OmiseCardCheckoutScreen> {
  static const Color _gradientStart = Color(0xFFFFC247);
  static const Color _gradientEnd = Color(0xFFE55A00);

  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvcController = TextEditingController();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  List<SavedPaymentCard> _savedCards = <SavedPaymentCard>[];
  String? _selectedSavedCardId;
  bool _saveCard = true;
  bool _isLoadingCards = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCards();
  }

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    _expiryController.dispose();
    _cvcController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCards() async {
    try {
      final callable = _functions.httpsCallable('listOmiseSavedCards');
      final response = await callable.call();
      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final rawCards = payload['cards'];
      final cards = rawCards is List
          ? rawCards
              .whereType<Map>()
              .map((item) => SavedPaymentCard.fromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .where((card) => card.omiseCardId.isNotEmpty)
              .toList()
          : <SavedPaymentCard>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _savedCards = cards;
        _isLoadingCards = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingCards = false);
      }
    }
  }

  bool get _usingSavedCard => _selectedSavedCardId != null;

  bool get _canSubmit {
    if (_isSubmitting) {
      return false;
    }
    if (_usingSavedCard) {
      return true;
    }
    final number = _numberController.text.replaceAll(RegExp(r'\s+'), '');
    final expiry = _expiryController.text.trim();
    final cvc = _cvcController.text.trim();
    return number.length >= 12 &&
        RegExp(r'^\d{2}/\d{2}$').hasMatch(expiry) &&
        cvc.length >= 3;
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final payload = <String, dynamic>{
        'sessionId': widget.sessionId,
        'saveCard': !_usingSavedCard && _saveCard,
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
      };

      if (_usingSavedCard) {
        payload['savedOmiseCardId'] = _selectedSavedCardId;
      } else {
        final publicKey = widget.publicKey?.trim();
        if (publicKey == null || !publicKey.startsWith('pkey_')) {
          throw Exception(L10n.omisePublicKeyMissing);
        }
        final expiryParts = _expiryController.text.split('/');
        final cardToken = await OmiseCardTokenHelper.createToken(
          publicKey: publicKey,
          cardNumber: _numberController.text.replaceAll(RegExp(r'\s+'), ''),
          cardName: _nameController.text.trim(),
          expirationMonth: expiryParts.first.trim(),
          expirationYear: expiryParts.last.trim(),
          securityCode: _cvcController.text.trim(),
        );
        payload['cardToken'] = cardToken;
      }

      final callable = _functions.httpsCallable('completeOmiseCardPayment');
      final response = await callable.call(payload);
      final result = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(<String, dynamic>{
        'sessionId': widget.sessionId,
        ...result,
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is FirebaseFunctionsException
          ? (error.message?.trim().isNotEmpty == true
              ? error.message!.trim()
              : L10n.cardPaymentUnavailable)
          : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.cardPaymentFailed(message))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: <Widget>[
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (_isLoadingCards)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (_savedCards.isNotEmpty) ...<Widget>[
                      _buildSavedCardsSection(),
                      const SizedBox(height: 16),
                    ],
                    _buildCardForm(),
                    const SizedBox(height: 16),
                    _buildSaveCardCheckbox(),
                    const SizedBox(height: 20),
                    _buildSecurityNotes(),
                    const SizedBox(height: 24),
                    const CardBrandStrip(),
                  ],
                ),
              ),
            ),
          ),
          _buildPayButton(),
        ],
      ),
    );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topInset + 8, 8, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[_gradientStart, _gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          Expanded(
            child: Text(
              L10n.enterCardDetails,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSavedCardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          L10n.savedCards,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF9A3412),
          ),
        ),
        const SizedBox(height: 8),
        for (final card in _savedCards)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    _selectedSavedCardId = card.omiseCardId;
                    _numberController.clear();
                    _expiryController.clear();
                    _cvcController.clear();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _selectedSavedCardId == card.omiseCardId
                          ? _gradientEnd
                          : const Color(0xFFE5E7EB),
                      width: _selectedSavedCardId == card.omiseCardId ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _selectedSavedCardId == card.omiseCardId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _gradientEnd,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${card.brandLabel} ${card.maskedNumber}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              L10n.cardExpires(card.expiryLabel),
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        TextButton(
          onPressed: () => setState(() => _selectedSavedCardId = null),
          child: Text(L10n.useNewCard),
        ),
      ],
    );
  }

  Widget _buildCardForm() {
    if (_usingSavedCard) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          L10n.payWithSavedCardHint,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF6B7280),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _fieldLabel(L10n.cardNumberLabel),
          TextFormField(
            controller: _numberController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              _CardNumberInputFormatter(),
            ],
            decoration: const InputDecoration(
              hintText: 'XXXX XXXX XXXX XXXX',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _fieldLabel(L10n.nameOnCard),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'NAME ON CARD',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _fieldLabel(L10n.expiryDate),
                    TextFormField(
                      controller: _expiryController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        _ExpiryDateInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'MM/YY',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _fieldLabel('CVV/CID'),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: L10n.cvvHint,
                          child: Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _cvcController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        hintText: '•••',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveCardCheckbox() {
    if (_usingSavedCard) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: _saveCard,
            activeColor: _gradientEnd,
            onChanged: (value) => setState(() => _saveCard = value ?? true),
          ),
          Expanded(
            child: Text(
              L10n.saveCardForLater,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityNotes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _securityLine(L10n.pciDssNotice),
        const SizedBox(height: 8),
        _securityLine(L10n.secure3dsNotice),
      ],
    );
  }

  Widget _securityLine(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.verified_outlined, size: 18, color: Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayButton() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _canSubmit ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: _gradientEnd,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    L10n.payAmountBaht(widget.amount.toStringAsFixed(2)),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF374151),
        ),
      ),
    );
  }
}

class _CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ExpiryDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }
    if (digits.length <= 2) {
      return TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    final month = digits.substring(0, 2);
    final year = digits.substring(2, digits.length.clamp(0, 4));
    final formatted = '$month/$year';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
