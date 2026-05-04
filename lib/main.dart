import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// ─── CONFIG ───────────────────────────────────────────────────────────────────
// Sheet columns (0-based): [0]Transaction [1]Date [2]Day [3]UPI [4]CASH
//                          [5]Reason [6]Credit/Debit [7]LastMonth [8]TotalLeft [9]Month
const kScriptUrl =
    'https://script.google.com/macros/s/AKfycbwuq3gK6T5kHsTbtp7BkqMaEtD8737XNPTvZK7zsZJuDyaK198niAXIf1gcB6n2nzXWIA/exec';

// ─── CONTROLLER ───────────────────────────────────────────────────────────────
class FinanceController extends GetxController {
  final isLoading = true.obs;
  final isPosting = false.obs;
  final totalLeft = 0.0.obs;
  final monthlyOutflow = 0.0.obs;
  final errorMsg = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchData();
  }

  Future<void> fetchData() async {
    isLoading(true);
    errorMsg('');
    try {
      final res = await http.get(Uri.parse(kScriptUrl));
      if (res.statusCode == 200) {
        _processRows(jsonDecode(res.body) as List);
      } else {
        errorMsg('Server error: ${res.statusCode}');
      }
    } catch (_) {
      errorMsg('Failed to load. Check connection.');
    } finally {
      isLoading(false);
    }
  }

  // Apps Script doGet returns raw arrays — read by index
  void _processRows(List rows) {
    if (rows.isEmpty) return;

    // col I (index 8) of last row = Total left
    totalLeft(double.tryParse(rows.last[8]?.toString() ?? '0') ?? 0);

    final now = DateTime.now();
    double outflow = 0;
    for (final row in rows) {
      try {
        // col G (index 6) = "Debit" / "Credit"
        if (row[6]?.toString() != 'Debit') continue;
        // col B (index 1) = Date object serialised as ISO string by Apps Script
        final date = DateTime.parse(row[1].toString());
        // col D (index 3) = UPI amount
        final amount = double.tryParse(row[3]?.toString() ?? '0') ?? 0;
        if (date.year == now.year && date.month == now.month) {
          outflow += amount;
        }
      } catch (_) {}
    }
    monthlyOutflow(outflow);
  }

  Future<bool> addTransaction(String upi, String reason, double amount) async {
    isPosting(true);
    try {
      final url = Uri.parse(kScriptUrl).replace(queryParameters: {
        'action': 'add',
        'upi': upi,
        'reason': reason,
        'amount': amount.toString(),
      });
      final res = await http.get(url);
      if (res.statusCode == 200) {
        await fetchData();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      isPosting(false);
    }
  }
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────
void main() => runApp(const FinanceApp());

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Finance Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: const DashboardScreen(),
    );
  }
}

// ─── DASHBOARD ────────────────────────────────────────────────────────────────
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(FinanceController());
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final width = MediaQuery.of(context).size.width;
    // Constrain content width on large screens (tablet/desktop)
    final contentWidth = width > 600 ? 560.0 : double.infinity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Dashboard'),
        centerTitle: true,
        actions: [
          Obx(() => ctrl.isLoading.value
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: ctrl.fetchData,
                )),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (ctrl.errorMsg.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(ctrl.errorMsg.value,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: ctrl.fetchData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: ctrl.fetchData,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // On wide screens show cards side by side
                    width > 480
                        ? Row(
                            children: [
                              Expanded(
                                child: _BalanceCard(
                                  label: 'Total Balance',
                                  value: fmt.format(ctrl.totalLeft.value),
                                  icon: Icons.account_balance_wallet,
                                  color: const Color(0xFF1565C0),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _BalanceCard(
                                  label: 'Monthly Outflow',
                                  value: fmt.format(ctrl.monthlyOutflow.value),
                                  icon: Icons.trending_down,
                                  color: const Color(0xFFC62828),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _BalanceCard(
                                label: 'Total Balance',
                                value: fmt.format(ctrl.totalLeft.value),
                                icon: Icons.account_balance_wallet,
                                color: const Color(0xFF1565C0),
                              ),
                              const SizedBox(height: 12),
                              _BalanceCard(
                                label: 'Monthly Outflow',
                                value: fmt.format(ctrl.monthlyOutflow.value),
                                icon: Icons.trending_down,
                                color: const Color(0xFFC62828),
                              ),
                            ],
                          ),
                    const SizedBox(height: 24),
                    const _AddTransactionForm(),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── BALANCE CARD ─────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _BalanceCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = MediaQuery.of(context).size.width < 360 ? 20.0 : 24.0;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── ADD TRANSACTION FORM ─────────────────────────────────────────────────────
class _AddTransactionForm extends StatefulWidget {
  const _AddTransactionForm();

  @override
  State<_AddTransactionForm> createState() => _AddTransactionFormState();
}

class _AddTransactionFormState extends State<_AddTransactionForm> {
  final _formKey = GlobalKey<FormState>();
  final _upiCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _upiCtrl.dispose();
    _reasonCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ctrl = Get.find<FinanceController>();
    final success = await ctrl.addTransaction(
      _upiCtrl.text.trim(),
      _reasonCtrl.text.trim(),
      double.parse(_amountCtrl.text.trim()),
    );
    if (success) {
      _upiCtrl.clear();
      _reasonCtrl.clear();
      _amountCtrl.clear();
      Get.snackbar('Success', 'Transaction added!',
          backgroundColor: Colors.green.shade800,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    } else {
      Get.snackbar('Error', 'Failed to add transaction.',
          backgroundColor: Colors.red.shade800,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<FinanceController>();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add Transaction',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _upiCtrl,
                decoration: const InputDecoration(
                  labelText: 'UPI ID',
                  prefixIcon: Icon(Icons.payment),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter UPI ID' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter reason' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter amount';
                  if (double.tryParse(v.trim()) == null) return 'Invalid amount';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Obx(() => FilledButton.icon(
                    onPressed: ctrl.isPosting.value ? null : _submit,
                    icon: ctrl.isPosting.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add),
                    label: Text(ctrl.isPosting.value
                        ? 'Submitting...'
                        : 'Add Transaction'),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
