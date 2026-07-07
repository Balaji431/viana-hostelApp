import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/styles.dart';
import '../../shared/widgets/skeuomorphic_widgets.dart';
import 'package:provider/provider.dart';
import '../../shared/user_provider.dart';
import '../../core/api_service.dart';
import '../../core/app_logger.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class PaymentPage extends StatefulWidget {
  final String? requestId;
  final String? requestedRoom;
  final double? customAmount;

  const PaymentPage({super.key, this.requestId, this.requestedRoom, this.customAmount});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _expiryDateController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cardholderNameController = TextEditingController();
  bool _isProcessing = false;
  double _sixMonthFee = 70000.0;
  double _oneYearFee = 135000.0;
  bool _isLoadingFees = true;
  late int _selectedMonths;

  @override
  void initState() {
    super.initState();
    _selectedMonths = 12; // Default
    _fetchFees();
  }

  Future<void> _fetchFees() async {
    try {
      final response = await ApiService.getRenewFees();
      if (response['status'] == 'success') {
        final List<dynamic> fees = response['data'] ?? [];
        if (fees.isNotEmpty) {
          setState(() {
            for (var f in fees) {
              final months = int.tryParse(f['months']?.toString() ?? '0') ?? 0;
              final amount = double.tryParse(f['amount']?.toString() ?? '0') ?? 0.0;
              if (months == 6) _sixMonthFee = amount;
              if (months == 12) _oneYearFee = amount;
            }
            _isLoadingFees = false;
          });
          return;
        }
      }
    } catch (e) {
      AppLogger.error("Error fetching payment fees: $e");
    }
    setState(() => _isLoadingFees = false);
  }

  double get _currentAmount {
    if (widget.customAmount != null) return widget.customAmount!;
    return _selectedMonths == 6 ? _sixMonthFee : _oneYearFee;
  }

  String get _paymentType {
    if (widget.requestId != null) return 'Room Change (${widget.requestedRoom})';
    return 'Renewal (${_selectedMonths == 6 ? "6 Months" : "1 Year"})';
  }

  void _handlePayment() async {
    if (_formKey.currentState!.validate()) {
      if (_currentAmount <= 0) {
        _showError("Invalid payment amount (₹${_currentAmount}). Please contact admin to fix the fee.");
        return;
      }
      
      setState(() => _isProcessing = true);
      
      final user = context.read<UserProvider>();
      if (user.dbId == null) {
         _showError("User ID not found. Please log in again.");
         setState(() => _isProcessing = false);
         return;
      }

      final response = await ApiService.processPayment(
        studentId: user.dbId!,
        amount: _currentAmount,
        paymentType: _paymentType,
        paymentMethod: 'Credit Card',
        requestId: widget.requestId,
      );

      if (response['success'] == true) {
        final freshData = await ApiService.getUserData(user.dbId!);
        if (freshData['status'] == 'success') {
          user.setUserData(freshData['data']);
        }
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (ctx) => const PaymentSuccessPage()),
          );
        }
      } else {
         _showError(response['message'] ?? "Payment failed");
         setState(() => _isProcessing = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8E4DB),
      appBar: SkeuomorphicNavBar(
        title: 'Renew Your Stay',
        onBack: () => Navigator.pop(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              EmbossedCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                    ),
                    Text(
                      '₹${_currentAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC5A358)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              
              if (widget.requestId == null)
              EmbossedCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Renewal Period',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPeriodOption('6 Months', 6),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _buildPeriodOption('1 Year', 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.requestId == null)
              const SizedBox(height: 25),

              EmbossedCard(
                padding: const EdgeInsets.all(30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.credit_card, color: Color(0xFFEBC15B), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Card Details',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                            ),
                          ],
                        ),
                        Row(
                          children: const [
                            Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                            SizedBox(width: 4),
                            Text('Secure Payment', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    _buildLabel('Card Number'),
                    _buildValidatedInput(
                      controller: _cardNumberController,
                      hint: '8175 0900 2351 3818',
                      validator: (v) => (v == null || v.replaceAll(' ', '').length != 16) ? 'Enter a valid 16-digit card number' : null,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(16),
                      ],
                      maxCharsLength: 16,
                    ),
                    const SizedBox(height: 25),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Expiry Date'),
                              _buildValidatedInput(
                                controller: _expiryDateController,
                                hint: '02/29',
                                validator: (v) {
                                  if (v == null || !RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(v)) {
                                    return 'Enter valid expiry (MM/YY)';
                                  }
                                  return null;
                                },
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(5),
                                ],
                                maxCharsLength: 5,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('CVV'),
                              _buildValidatedInput(
                                controller: _cvvController,
                                hint: '•••',
                                validator: (v) => (v == null || v.length != 3) ? 'Enter 3-digit CVV' : null,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                maxCharsLength: 3,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    _buildLabel('Cardholder Name'),
                    _buildValidatedInput(
                      controller: _cardholderNameController,
                      hint: 'balaji',
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter cardholder name' : null,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                      ],
                    ),
                    const SizedBox(height: 40),

                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              height: 55,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: const Center(
                                child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: GestureDetector(
                            onTap: (_isProcessing || _isLoadingFees) ? null : _handlePayment,
                            child: Container(
                              height: 55,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: (_isProcessing || _isLoadingFees) 
                                    ? LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade500])
                                    : SkeuomorphicColors.goldGlossyGradient,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 4)),
                                ],
                              ),
                              child: Center(
                                child: (_isProcessing || _isLoadingFees)
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Text(
                                        'Pay ₹${_currentAmount.toStringAsFixed(0)}',
                                        style: const TextStyle(color: Color(0xFF291E1A), fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'This is a simulated payment for demonstration purposes',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodOption(String title, int months) {
    bool isSelected = _selectedMonths == months;
    return GestureDetector(
      onTap: () => setState(() => _selectedMonths = months),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC5A358) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFFC5A358) : Colors.grey.shade300),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)] : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF1B2B48),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D5D5D), fontSize: 15),
      ),
    );
  }

  Widget _buildValidatedInput({
    required TextEditingController controller,
    required String hint,
    required String? Function(String?) validator,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int? maxCharsLength,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      maxLength: maxCharsLength,
      style: const TextStyle(color: Color(0xFF1B2B48), fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        counterText: "",
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.normal),
        filled: true,
        fillColor: const Color(0xFFEBF2FF), 
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFC5A358), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
      ),
    );
  }
}

class PaymentSuccessPage extends StatelessWidget {
  const PaymentSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54, 
      body: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6F1), 
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 20, 15, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Renew Your Stay',
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B2B48),
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 18, color: Colors.grey),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 40),

              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
                  ],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 50),
              ),
              const SizedBox(height: 35),

              const Text(
                'Payment Successful!',
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your renewal has been processed',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 50),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: SkeuomorphicColors.goldGlossyGradient,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Done',
                        style: TextStyle(color: Color(0xFF291E1A), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
