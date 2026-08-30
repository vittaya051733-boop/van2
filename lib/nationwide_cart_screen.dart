import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cart_screen.dart';
import 'l10n/l10n.dart';
import 'map_picker_screen.dart';
import 'services/nationwide_shipping_service.dart';
import 'storage_helper.dart';
import 'utils/app_check_guard.dart';
import 'widgets/cached_app_image.dart';

class NationwideCartScreen extends StatefulWidget {
  const NationwideCartScreen({
    super.key,
    required this.cartItems,
    required this.onRemoveItem,
    required this.onOrderCreated,
    required this.onBackToCatalog,
  });

  final List<CartLineItem> cartItems;
  final void Function(int index) onRemoveItem;
  final Future<void> Function(List<String> orderIds) onOrderCreated;
  final VoidCallback onBackToCatalog;

  @override
  State<NationwideCartScreen> createState() => _NationwideCartScreenState();
}

class _NationwideCartScreenState extends State<NationwideCartScreen> {
  static const _savedAddressesPrefsKey = 'nationwide_delivery_addresses_v1';
  static const _selectedAddressPrefsKey =
      'nationwide_selected_delivery_address_v1';
  static const _maxSavedAddressCount = 5;

  final _formKey = GlobalKey<FormState>();
  final _shippingService = const NationwideShippingService();
  final _recipientController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _subDistrictController = TextEditingController();
  final _districtController = TextEditingController();
  final _provinceController = TextEditingController();
  final _postalCodeController = TextEditingController();
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  String? _googleFormattedAddress;
  List<_SavedNationwideAddress> _savedAddresses =
      const <_SavedNationwideAddress>[];
  NationwideDeliveryAddress? _confirmedAddress;
  String? _selectedSavedAddressId;
  bool _showAddressForm = true;
  bool _isResolvingAddress = false;
  bool _isLoadingSavedAddresses = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedAddresses());
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _subDistrictController.dispose();
    _districtController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  NationwideDeliveryAddress? _readAddress({bool validate = false}) {
    if (validate && !(_formKey.currentState?.validate() ?? false)) {
      return null;
    }

    return NationwideDeliveryAddress(
      recipientName: _recipientController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      addressLine: _addressController.text.trim(),
      subDistrict: _subDistrictController.text.trim(),
      district: _districtController.text.trim(),
      province: _provinceController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
      latitude: _deliveryLatitude,
      longitude: _deliveryLongitude,
      formattedAddress: _googleFormattedAddress,
    );
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList =
          prefs.getStringList(_savedAddressesPrefsKey) ?? const <String>[];
      final addresses = rawList
          .map(_SavedNationwideAddress.tryDecode)
          .whereType<_SavedNationwideAddress>()
          .toList(growable: false);
      final selectedId = prefs.getString(_selectedAddressPrefsKey);

      if (!mounted) {
        return;
      }

      setState(() {
        _savedAddresses = addresses;
        _selectedSavedAddressId = selectedId;
        _isLoadingSavedAddresses = false;
      });

      final selectedAddress = addresses
          .cast<_SavedNationwideAddress?>()
          .firstWhere(
            (address) => address?.id == selectedId,
            orElse: () => addresses.isNotEmpty ? addresses.first : null,
          );
      if (selectedAddress != null) {
        _useSavedAddress(selectedAddress);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingSavedAddresses = false);
      }
    }
  }

  Future<void> _persistSavedAddresses(
    List<_SavedNationwideAddress> addresses, {
    String? selectedId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _savedAddressesPrefsKey,
      addresses.map((address) => address.encode()).toList(growable: false),
    );
    if (selectedId == null) {
      await prefs.remove(_selectedAddressPrefsKey);
    } else {
      await prefs.setString(_selectedAddressPrefsKey, selectedId);
    }
  }

  void _fillAddressForm(NationwideDeliveryAddress address) {
    _recipientController.text = address.recipientName;
    _phoneController.text = address.phoneNumber;
    _addressController.text = address.addressLine;
    _subDistrictController.text = address.subDistrict;
    _districtController.text = address.district;
    _provinceController.text = address.province;
    _postalCodeController.text = address.postalCode;
    _deliveryLatitude = address.latitude;
    _deliveryLongitude = address.longitude;
    _googleFormattedAddress = address.formattedAddress;
  }

  void _useSavedAddress(_SavedNationwideAddress savedAddress) {
    final address = savedAddress.address;
    setState(() {
      _fillAddressForm(address);
      _confirmedAddress = address;
      _selectedSavedAddressId = savedAddress.id;
      _showAddressForm = false;
    });
  }

  void _editSavedAddress(_SavedNationwideAddress savedAddress) {
    setState(() {
      _fillAddressForm(savedAddress.address);
      _selectedSavedAddressId = savedAddress.id;
      _showAddressForm = true;
    });
  }

  void _startAddingAddress() {
    setState(() {
      _recipientController.clear();
      _phoneController.clear();
      _addressController.clear();
      _subDistrictController.clear();
      _districtController.clear();
      _provinceController.clear();
      _postalCodeController.clear();
      _deliveryLatitude = null;
      _deliveryLongitude = null;
      _googleFormattedAddress = null;
      _selectedSavedAddressId = null;
      _showAddressForm = true;
    });
  }

  Future<_SavedNationwideAddress> _saveAddressForReuse(
    NationwideDeliveryAddress address,
  ) async {
    final now = DateTime.now();
    final id = _savedAddressIdFor(address);
    final savedAddress = _SavedNationwideAddress(
      id: id,
      address: address,
      updatedAt: now,
    );
    final nextAddresses = <_SavedNationwideAddress>[
      savedAddress,
      for (final existing in _savedAddresses)
        if (existing.id != id) existing,
    ].take(_maxSavedAddressCount).toList(growable: false);

    setState(() {
      _savedAddresses = nextAddresses;
      _confirmedAddress = address;
      _selectedSavedAddressId = id;
      _showAddressForm = false;
    });
    await _persistSavedAddresses(nextAddresses, selectedId: id);
    return savedAddress;
  }

  String _savedAddressIdFor(NationwideDeliveryAddress address) {
    final key = <String>[
      address.recipientName,
      address.phoneNumber,
      address.addressLine,
      address.subDistrict,
      address.district,
      address.province,
      address.postalCode,
    ].map((value) => value.trim().toLowerCase()).join('|');
    return base64Url.encode(utf8.encode(key)).replaceAll('=', '');
  }

  Future<void> _saveCurrentAddressFromButton() async {
    final address = _readAddress(validate: true);
    if (address == null) {
      return;
    }
    await _saveAddressForReuse(address);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.addressSavedForLater)),
    );
  }

  Future<void> _confirmCurrentAddress() async {
    final address = _readAddress(validate: true);
    if (address == null) {
      return;
    }
    await _saveAddressForReuse(address);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.deliveryAddressConfirmed)));
  }

  Future<void> _deleteSavedAddress(_SavedNationwideAddress savedAddress) async {
    final nextAddresses = _savedAddresses
        .where((address) => address.id != savedAddress.id)
        .toList(growable: false);
    final isDeletingSelected = savedAddress.id == _selectedSavedAddressId;
    final nextSelectedId = isDeletingSelected
        ? (nextAddresses.isEmpty ? null : nextAddresses.first.id)
        : _selectedSavedAddressId;
    setState(() {
      _savedAddresses = nextAddresses;
      if (isDeletingSelected) {
        _selectedSavedAddressId = nextSelectedId;
        _confirmedAddress = nextAddresses.isEmpty
            ? null
            : nextAddresses.first.address;
        if (nextAddresses.isEmpty) {
          _showAddressForm = true;
        } else {
          _fillAddressForm(nextAddresses.first.address);
        }
      }
    });
    await _persistSavedAddresses(nextAddresses, selectedId: nextSelectedId);
  }

  Future<void> _showSavedAddressSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  L10n.deliveryAddress,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (_savedAddresses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(L10n.noSavedAddresses),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _savedAddresses.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final savedAddress = _savedAddresses[index];
                        final isPrimary =
                            savedAddress.id == _selectedSavedAddressId;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isPrimary
                                ? Icons.check_circle
                                : Icons.location_on_outlined,
                            color: isPrimary ? const Color(0xFFF57C00) : null,
                          ),
                          title: Text(
                            isPrimary
                                ? L10n.savedAddressPrimary(
                                    savedAddress.address.recipientName,
                                  )
                                : savedAddress.address.recipientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            savedAddress.address.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _useSavedAddress(savedAddress);
                            unawaited(
                              _persistSavedAddresses(
                                _savedAddresses,
                                selectedId: savedAddress.id,
                              ),
                            );
                          },
                          trailing: SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                IconButton(
                                  tooltip: L10n.editThisAddress,
                                  onPressed: () {
                                    Navigator.of(sheetContext).pop();
                                    _editSavedAddress(savedAddress);
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: L10n.deleteThisAddress,
                                  onPressed: () {
                                    Navigator.of(sheetContext).pop();
                                    unawaited(
                                      _deleteSavedAddress(savedAddress),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _startAddingAddress();
                    },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: Text(L10n.addNewAddress),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_saveCurrentAddressFromButton());
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(L10n.saveCurrentFormAsPrimary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDeliveryLocation() async {
    if (_isResolvingAddress) {
      return;
    }

    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (context) => MapPickerScreen(
          title: L10n.pinDeliveryLocation,
          confirmLabel: L10n.useTheseCoordinates,
          initialLocation:
              _deliveryLatitude != null && _deliveryLongitude != null
              ? PickedLocation(
                  latitude: _deliveryLatitude!,
                  longitude: _deliveryLongitude!,
                  title: _googleFormattedAddress?.trim().isNotEmpty == true
                      ? _googleFormattedAddress!.trim()
                      : L10n.deliveryCoordinates,
                )
              : null,
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }

    setState(() => _isResolvingAddress = true);
    try {
      await AppCheckGuard.ensureCheckoutReady();
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('reverseGeocodeDeliveryLocation');
      final response = await callable.call(<String, dynamic>{
        'latitude': picked.latitude,
        'longitude': picked.longitude,
      });
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};

      _deliveryLatitude =
          (data['latitude'] as num?)?.toDouble() ?? picked.latitude;
      _deliveryLongitude =
          (data['longitude'] as num?)?.toDouble() ?? picked.longitude;
      _googleFormattedAddress = (data['formattedAddress'] ?? '').toString();
      _addressController.text = _prefer(
        data['addressLine'],
        _addressController.text,
      );
      _subDistrictController.text = _prefer(
        data['subDistrict'],
        _subDistrictController.text,
      );
      _districtController.text = _prefer(
        data['district'],
        _districtController.text,
      );
      _provinceController.text = _prefer(
        data['province'],
        _provinceController.text,
      );
      _postalCodeController.text = _prefer(
        data['postalCode'],
        _postalCodeController.text,
      );
      if ((_addressController.text.trim()).isEmpty &&
          _googleFormattedAddress?.trim().isNotEmpty == true) {
        _addressController.text = _googleFormattedAddress!.trim();
      }

      if (!mounted) {
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.addressFetchedFromCoordinates),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.addressFetchFailed(error))));
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  String _prefer(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isNotEmpty ? text : fallback.trim();
  }

  NationwideDeliveryAddress? _readCheckoutAddress() {
    if (!_showAddressForm && _confirmedAddress != null) {
      return _confirmedAddress;
    }
    return _readAddress(validate: true);
  }

  Future<void> _showNationwideScanPayDialog({
    required double grandTotal,
  }) async {
    if (_isSubmitting || widget.cartItems.isEmpty) {
      return;
    }
    final address = _readCheckoutAddress();
    if (address == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final viewport = MediaQuery.of(context).size;
        return PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: viewport.height * 0.78,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      L10n.scanPay,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.nationwideScanPayHint,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: viewport.height * 0.56,
                      child: TrueMoneyQrDialogContent(
                        grandTotal: grandTotal,
                        initialAttachedSlip: null,
                        onAttachedSlipChanged: (_) {},
                        onCloseRequested: () => Navigator.of(context).pop(),
                        onSubmitPromptPaySlip: _submitNationwidePromptPaySlip,
                        onSubmissionCompleted: widget.onOrderCreated,
                        onSubmissionSucceeded: () {},
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(L10n.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<PaymentSlipSubmissionResult> _submitNationwidePromptPaySlip(
    PaymentSlipSubmissionRequest request,
  ) async {
    if (_isSubmitting || widget.cartItems.isEmpty) {
      throw Exception(L10n.nationwideCartEmptyError);
    }
    final address = _readCheckoutAddress();
    if (address == null) {
      throw Exception(L10n.confirmAddressBeforePay);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception(L10n.signInRequiredBeforeOrder);
    }
    if (request.bytes.isEmpty) {
      throw Exception(L10n.emptySlipFile);
    }

    setState(() => _isSubmitting = true);
    try {
      final paymentGroupId = 'NWPAY-${DateTime.now().millisecondsSinceEpoch}';
      final sanitizedFileName = _sanitizeSlipFileName(request.fileName);
      final storagePath =
          'payment_slips/${user.uid}/$paymentGroupId/$sanitizedFileName';
      final uploadTask = await StorageHelper.instance
          .ref(storagePath)
          .putData(
            request.bytes,
            SettableMetadata(
              contentType: request.contentType ?? 'image/jpeg',
              customMetadata: <String, String>{
                'uploadedBy': user.uid,
                'paymentGroupId': paymentGroupId,
                'checkoutType': 'nationwide_parcel',
              },
            ),
          );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('verifyStandalonePaymentSlip');
      final response = await callable.call(<String, dynamic>{
        'storagePath': storagePath,
        'paymentGroupId': paymentGroupId,
        'fileName': sanitizedFileName,
        'expectedAmount': request.grandTotal,
        if (request.contentType != null) 'contentType': request.contentType,
      });
      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final status = (payload['status'] ?? 'submitted').toString().trim();
      final message = (payload['message'] ?? '').toString().trim();

      if (status != 'verified') {
        return PaymentSlipSubmissionResult(
          orderIds: const <String>[],
          verificationStatus: status,
          message: message.isEmpty ? L10n.slipNotVerified : message,
        );
      }

      final orderIds = await _createNationwideOrders(
        user: user,
        address: address,
        paymentGroupId: paymentGroupId,
        slipStoragePath: storagePath,
        slipDownloadUrl: downloadUrl,
        slipFileName: sanitizedFileName,
        slipContentType: request.contentType,
        slipSizeBytes: request.sizeBytes,
        expectedCombinedAmount: request.grandTotal,
        verificationFeedbackId: (payload['feedbackId'] ?? '').toString(),
        verifiedSlipAmount: (payload['verifiedSlipAmount'] as num?)?.toDouble(),
        verificationMessage: message,
      );
      await _saveAddressForReuse(address);

      return PaymentSlipSubmissionResult(
        orderIds: orderIds,
        verificationStatus: status,
        message: message.isEmpty
            ? L10n.nationwideSlipVerifiedAndCreated(widget.cartItems.length)
            : L10n.nationwideOrderCreatedWithMessage(
                message,
                orderIds.length,
              ),
      );
    } catch (error) {
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _sanitizeSlipFileName(String fileName) {
    final trimmed = fileName.trim();
    final safe = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty) {
      return 'slip_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    return safe;
  }

  Future<List<String>> _createNationwideOrders({
    required User user,
    required NationwideDeliveryAddress address,
    required String paymentGroupId,
    required String slipStoragePath,
    required String slipDownloadUrl,
    required String slipFileName,
    required String? slipContentType,
    required int slipSizeBytes,
    required double expectedCombinedAmount,
    required String verificationFeedbackId,
    required double? verifiedSlipAmount,
    required String verificationMessage,
  }) async {
    await AppCheckGuard.ensureCheckoutReady();
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).httpsCallable('createNationwideParcelOrders');
    final response = await callable.call(<String, dynamic>{
      'items': widget.cartItems
          .map(
            (item) => <String, dynamic>{
              'productId': item.productId,
              'shopId': item.shopId,
              'quantity': item.quantity,
              'selectedToppings': item.selectedToppings,
              'parcelWeightGrams': item.parcelWeightGrams,
              if (item.parcelLengthCm != null)
                'parcelLengthCm': item.parcelLengthCm,
              if (item.parcelWidthCm != null)
                'parcelWidthCm': item.parcelWidthCm,
              if (item.parcelHeightCm != null)
                'parcelHeightCm': item.parcelHeightCm,
            },
          )
          .toList(growable: false),
      'deliveryAddress': address.toJson(),
      'paymentGroupId': paymentGroupId,
      'verificationFeedbackId': verificationFeedbackId,
      'slipStoragePath': slipStoragePath,
      'slipDownloadUrl': slipDownloadUrl,
      'slipFileName': slipFileName,
      if (slipContentType != null) 'slipContentType': slipContentType,
      'slipSizeBytes': slipSizeBytes,
      'expectedCombinedAmount': expectedCombinedAmount,
      if (verifiedSlipAmount != null) 'verifiedSlipAmount': verifiedSlipAmount,
      'verificationMessage': verificationMessage,
    });

    final payload = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};
    final orderIds =
        (payload['orderIds'] as List?)
            ?.map((id) => id.toString())
            .toList(growable: false) ??
        const <String>[];
    if (orderIds.isEmpty) {
      throw Exception(L10n.createNationwideOrderFailed);
    }
    return orderIds;
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.cartItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + (item.unitPrice * item.quantity),
    );
    final draftAddress = _showAddressForm
        ? _readAddress()
        : (_confirmedAddress ?? _readAddress());
    final quote = _shippingService.estimateManualQuote(
      items: widget.cartItems,
      address:
          draftAddress ??
          const NationwideDeliveryAddress(
            recipientName: '',
            phoneNumber: '',
            addressLine: '',
            subDistrict: '',
            district: '',
            province: '',
            postalCode: '',
          ),
    );
    final grandTotal = subtotal + quote.shippingFee;

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: widget.onBackToCatalog,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      L10n.nationwideCartTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isLoadingSavedAddresses
                        ? null
                        : _showSavedAddressSheet,
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(L10n.deliveryAddress),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.cartItems.isEmpty
                  ? Center(child: Text(L10n.nationwideCartEmpty))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: <Widget>[
                        for (
                          var index = 0;
                          index < widget.cartItems.length;
                          index++
                        )
                          _NationwideCartItemTile(
                            item: widget.cartItems[index],
                            onRemove: () => widget.onRemoveItem(index),
                          ),
                        if (_showAddressForm ||
                            _confirmedAddress == null) ...<Widget>[
                          const SizedBox(height: 12),
                          _AddressForm(
                            formKey: _formKey,
                            recipientController: _recipientController,
                            phoneController: _phoneController,
                            addressController: _addressController,
                            subDistrictController: _subDistrictController,
                            districtController: _districtController,
                            provinceController: _provinceController,
                            postalCodeController: _postalCodeController,
                            isResolvingAddress: _isResolvingAddress,
                            deliveryLatitude: _deliveryLatitude,
                            deliveryLongitude: _deliveryLongitude,
                            onPickLocation: _pickDeliveryLocation,
                            onConfirmAddress: _confirmCurrentAddress,
                            onChanged: () => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _NationwideQuoteCard(
                          subtotal: subtotal,
                          quote: quote,
                          grandTotal: grandTotal,
                        ),
                      ],
                    ),
            ),
            if (widget.cartItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _showNationwideScanPayDialog(
                            grandTotal: grandTotal,
                          ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.qr_code_2_rounded),
                    label: Text(L10n.scanPay),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedNationwideAddress {
  const _SavedNationwideAddress({
    required this.id,
    required this.address,
    required this.updatedAt,
  });

  final String id;
  final NationwideDeliveryAddress address;
  final DateTime updatedAt;

  String encode() => jsonEncode(<String, dynamic>{
    'id': id,
    'updatedAt': updatedAt.toIso8601String(),
    'address': address.toJson(),
  });

  static _SavedNationwideAddress? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final data = Map<String, dynamic>.from(decoded);
      final addressData = data['address'];
      if (addressData is! Map) {
        return null;
      }
      final address = _addressFromJson(Map<String, dynamic>.from(addressData));
      final id = (data['id'] ?? '').toString().trim();
      if (id.isEmpty) {
        return null;
      }
      return _SavedNationwideAddress(
        id: id,
        address: address,
        updatedAt:
            DateTime.tryParse((data['updatedAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  static NationwideDeliveryAddress _addressFromJson(Map<String, dynamic> data) {
    return NationwideDeliveryAddress(
      recipientName: (data['recipientName'] ?? '').toString(),
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      addressLine: (data['addressLine'] ?? '').toString(),
      subDistrict: (data['subDistrict'] ?? '').toString(),
      district: (data['district'] ?? '').toString(),
      province: (data['province'] ?? '').toString(),
      postalCode: (data['postalCode'] ?? '').toString(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      formattedAddress: (data['formattedAddress'] ?? '').toString(),
    );
  }
}

class _NationwideCartItemTile extends StatelessWidget {
  const _NationwideCartItemTile({required this.item, required this.onRemove});

  final CartLineItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl?.trim();
    final lineTotal = item.unitPrice * item.quantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 82,
                height: 82,
                child: imageUrl == null || imageUrl.isEmpty
                    ? Container(
                        color: const Color(0xFFFFF7ED),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFFF57C00),
                          size: 34,
                        ),
                      )
                    : CachedAppImage(
                        imageUrl: imageUrl,
                        width: 82,
                        height: 82,
                        fit: BoxFit.cover,
                        lightweight: true,
                        placeholder: Container(
                          color: const Color(0xFFFFF7ED),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: Container(
                          color: const Color(0xFFFFF7ED),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFFF57C00),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onRemove,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.selectedToppings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      L10n.optionsLine(item.selectedToppings.join(', ')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _InfoPill(
                        icon: Icons.sell_outlined,
                        label: L10n.pricePerPiece(item.unitPrice),
                      ),
                      _InfoPill(
                        icon: Icons.shopping_bag_outlined,
                        label: L10n.quantityPieces(item.quantity),
                      ),
                      _InfoPill(
                        icon: Icons.scale_outlined,
                        label: L10n.parcelWeightKg(
                          item.parcelWeightGrams * item.quantity / 1000,
                        ),
                      ),
                      if (_dimensionLabel.isNotEmpty)
                        _InfoPill(
                          icon: Icons.straighten,
                          label: _dimensionLabel,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Text(
                        L10n.lineSubtotal,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '฿${_formatMoney(lineTotal)}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFFE55A00),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _dimensionLabel {
    final length = item.parcelLengthCm;
    final width = item.parcelWidthCm;
    final height = item.parcelHeightCm;
    if (length == null || width == null || height == null) {
      return '';
    }
    return L10n.parcelDimensions(
      '${_formatDimension(length)}x${_formatDimension(width)}x${_formatDimension(height)}',
    );
  }

  String _formatMoney(num amount) {
    return amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _formatDimension(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: const Color(0xFFF57C00)),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF9A3412),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressForm extends StatelessWidget {
  const _AddressForm({
    required this.formKey,
    required this.recipientController,
    required this.phoneController,
    required this.addressController,
    required this.subDistrictController,
    required this.districtController,
    required this.provinceController,
    required this.postalCodeController,
    required this.isResolvingAddress,
    required this.onPickLocation,
    required this.onConfirmAddress,
    required this.onChanged,
    this.deliveryLatitude,
    this.deliveryLongitude,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController recipientController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController subDistrictController;
  final TextEditingController districtController;
  final TextEditingController provinceController;
  final TextEditingController postalCodeController;
  final bool isResolvingAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final VoidCallback onPickLocation;
  final VoidCallback onConfirmAddress;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                L10n.deliveryAddress,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isResolvingAddress ? null : onPickLocation,
                  icon: isResolvingAddress
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_location_alt_outlined),
                  label: Text(
                    isResolvingAddress
                        ? L10n.fetchingAddressFromGoogle
                        : L10n.pinAndAutoFillAddress,
                  ),
                ),
              ),
              if (deliveryLatitude != null && deliveryLongitude != null) ...[
                const SizedBox(height: 6),
                Text(
                  L10n.deliveryCoordinatesFormatted(
                    deliveryLatitude!,
                    deliveryLongitude!,
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _field(recipientController, L10n.recipientName),
              _field(
                phoneController,
                L10n.phoneNumber,
                keyboardType: TextInputType.phone,
              ),
              _field(addressController, L10n.streetAddress),
              Row(
                children: <Widget>[
                  Expanded(child: _field(subDistrictController, L10n.subDistrict)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(districtController, L10n.district)),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(child: _field(provinceController, L10n.province)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(
                      postalCodeController,
                      L10n.postalCode,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isResolvingAddress ? null : onConfirmAddress,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(L10n.confirmDeliveryAddress),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) => onChanged(),
        validator: (value) {
          if ((value ?? '').trim().isEmpty) {
            return L10n.fieldRequired(label);
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _NationwideQuoteCard extends StatelessWidget {
  const _NationwideQuoteCard({
    required this.subtotal,
    required this.quote,
    required this.grandTotal,
  });

  final double subtotal;
  final NationwideShippingQuote quote;
  final double grandTotal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: <Widget>[
            _row(L10n.subtotalLabel, subtotal),
            _row(L10n.estimatedShippingFee, quote.shippingFee),
            const Divider(height: 20),
            _row(L10n.total, grandTotal, isTotal: true),
            const SizedBox(height: 6),
            Text(
              L10n.mockShippingNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double amount, {bool isTotal = false}) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '฿${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
            color: isTotal ? const Color(0xFFE55A00) : const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}
