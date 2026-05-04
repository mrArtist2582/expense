import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// ─── CONFIG ───────────────────────────────────────────────────────────────────
const kScriptUrl =
    'https://script.google.com/macros/s/AKfycbwuq3gK6T5kHsTbtp7BkqMaEtD8737XNPTvZK7zsZJuDyaK198niAXIf1gcB6n2nzXWIA/exec';

// ─── MODEL ────────────────────────────────────────────────────────────────────
class Transaction {
  final DateTime date;
  final String day;
  final double amount;
  final String type; // Debit / Credit
  final String reason;
  final String mode; // UPI / Cash
  final double balance;

  Transaction({
    required this.date,
    required this.day,
    required this.amount,
    required this.type,
    required this.reason,
    required this.mode,
    required this.balance,
  });

  // col: [0]#  [1]Date  [2]Day  [3]UPI  [4]CASH  [5]Reason  [6]Type  [7]LastMonth  [8]Balance  [9]Month
  factory Transaction.fromRow(List row) {
    final upi = double.tryParse(row[3]?.toString() ?? '0') ?? 0;
    final cash = double.tryParse(row[4]?.toString() ?? '0') ?? 0;
    // Parse date without timezone shift — take date part only
    DateTime parsedDate;
    try {
      final raw = row[1].toString();
      final d = DateTime.parse(raw);
      parsedDate = DateTime(d.year, d.month, d.day);
    } catch (_) {
      parsedDate = DateTime.now();
    }
    return Transaction(
      date: parsedDate,
      day: row[2]?.toString() ?? '',
      amount: upi > 0 ? upi : cash,
      type: row[6]?.toString() ?? 'Debit',
      reason: row[5]?.toString() ?? '',
      mode: upi > 0 ? 'UPI' : 'Cash',
      balance: double.tryParse(row[8]?.toString() ?? '0') ?? 0,
    );
  }
}

// ─── CONTROLLER ───────────────────────────────────────────────────────────────
class FinanceController extends GetxController {
  final isLoading = true.obs;
  final isPosting = false.obs;
  final totalLeft = 0.0.obs;
  final monthlyOutflow = 0.0.obs;
  final errorMsg = ''.obs;
  final transactions = <Transaction>[].obs;

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

  void _processRows(List rows) {
    if (rows.isEmpty) return;
    totalLeft(double.tryParse(rows.last[8]?.toString() ?? '0') ?? 0);

    final list = <Transaction>[];
    final now = DateTime.now();
    double outflow = 0;
    for (final row in rows) {
      try {
        final t = Transaction.fromRow(row as List);
        list.add(t);
        if (t.type == 'Debit' &&
            t.date.year == now.year &&
            t.date.month == now.month) {
          outflow += t.amount;
        }
      } catch (_) {}
    }
    transactions.assignAll(list.reversed.toList()); // newest first
    monthlyOutflow(outflow);
  }

  // Group transactions by "MMMM yyyy"
  Map<String, List<Transaction>> get groupedByMonth {
    final map = <String, List<Transaction>>{};
    for (final t in transactions) {
      final key = DateFormat('MMMM yyyy').format(t.date);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  Future<bool> addTransaction(
      String mode, String reason, double amount, DateTime date) async {
    isPosting(true);
    try {
      final url = Uri.parse(kScriptUrl).replace(queryParameters: {
        'action': 'add',
        'mode': mode,
        'reason': reason,
        'amount': amount.toString(),
        'date': DateFormat('dd/MM/yyyy').format(date),
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
                      child: CircularProgressIndicator(strokeWidth: 2)),
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
                    width > 480
                        ? Row(children: [
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
                          ])
                        : Column(children: [
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
                          ]),
                    const SizedBox(height: 16),
                    // Statement button — full width, always visible
                    OutlinedButton.icon(
                      onPressed: () => Get.to(() => const StatementScreen()),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('View Statement'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF1565C0)),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
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
  final _reasonCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _paymentMode = 'UPI';
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ctrl = Get.find<FinanceController>();
    final success = await ctrl.addTransaction(
      _paymentMode,
      _reasonCtrl.text.trim(),
      double.parse(_amountCtrl.text.trim()),
      _selectedDate,
    );
    if (success) {
      _reasonCtrl.clear();
      _amountCtrl.clear();
      setState(() => _selectedDate = DateTime.now());
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
              // Date picker
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    DateFormat('dd MMM yyyy').format(_selectedDate),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentMode,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode',
                  prefixIcon: Icon(Icons.payment),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                ],
                onChanged: (v) => setState(() => _paymentMode = v!),
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

// ─── STATEMENT SCREEN ─────────────────────────────────────────────────────────
class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key});

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  final ctrl = Get.find<FinanceController>();
  late String _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedMonth =
        ctrl.groupedByMonth.keys.firstOrNull ?? '';
  }

  List<Transaction> get _currentTxns =>
      ctrl.groupedByMonth[_selectedMonth] ?? [];

  // Daily debit totals for bar chart
  Map<int, double> get _dailyTotals {
    final map = <int, double>{};
    for (final t in _currentTxns) {
      if (t.type == 'Debit') {
        map[t.date.day] = (map[t.date.day] ?? 0) + t.amount;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final months = ctrl.groupedByMonth.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statement'),
        centerTitle: true,
      ),
      body: Obx(() {
        if (ctrl.transactions.isEmpty) {
          return const Center(child: Text('No transactions found.'));
        }
        return Column(
          children: [
            // Month selector
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedMonth.isEmpty ? null : _selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'Select Month',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_month),
                ),
                items: months
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMonth = v!),
              ),
            ),
            const SizedBox(height: 12),
            // Bar chart
            if (_dailyTotals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 0,
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Daily Spending',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 220,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (_dailyTotals.values.reduce((a, b) => a > b ? a : b) * 1.3),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: _dailyTotals.values.reduce((a, b) => a > b ? a : b) / 4,
                                getDrawingHorizontalLine: (_) => const FlLine(
                                  color: Colors.white12,
                                  strokeWidth: 1,
                                ),
                              ),
                              borderData: FlBorderData(
                                show: true,
                                border: const Border(
                                  bottom: BorderSide(color: Colors.white24),
                                  left: BorderSide(color: Colors.white24),
                                ),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                leftTitles: AxisTitles(
                                  axisNameWidget: const Text('₹',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 11)),
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 48,
                                    getTitlesWidget: (v, _) => Text(
                                      v >= 1000
                                          ? '${(v / 1000).toStringAsFixed(1)}k'
                                          : v.toInt().toString(),
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 10),
                                    ),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  axisNameWidget: const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text('Date',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11)),
                                  ),
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 28,
                                    getTitlesWidget: (v, meta) => SideTitleWidget(
                                      meta: meta,
                                      child: Text(
                                        v.toInt().toString(),
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              barTouchData: BarTouchData(
                                enabled: true,
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipColor: (_) => const Color(0xFF1565C0),
                                  tooltipBorderRadius: BorderRadius.circular(8),
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                                      BarTooltipItem(
                                    '${group.x} — ₹${rod.toY.toStringAsFixed(0)}',
                                    const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                              ),
                              barGroups: _dailyTotals.entries
                                  .map((e) => BarChartGroupData(
                                        x: e.key,
                                        barRods: [
                                          BarChartRodData(
                                            toY: e.value,
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF42A5F5),
                                                Color(0xFF1565C0),
                                              ],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                            width: 14,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ],
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Statement list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _currentTxns.length,
                separatorBuilder: (context, index) => const Divider(
                    height: 1, color: Colors.white12),
                itemBuilder: (_, i) {
                  final t = _currentTxns[i];
                  final isDebit = t.type == 'Debit';
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isDebit
                            ? const Color(0xFFC62828).withValues(alpha: 0.15)
                            : const Color(0xFF1B5E20).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                        color: isDebit
                            ? const Color(0xFFEF5350)
                            : const Color(0xFF66BB6A),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      t.reason.isEmpty ? t.mode : t.reason,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '${t.day}  •  ${DateFormat('dd MMM yyyy').format(t.date)}  •  ${t.mode}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isDebit ? '-' : '+'}${fmt.format(t.amount)}',
                          style: TextStyle(
                            color: isDebit
                                ? const Color(0xFFEF5350)
                                : const Color(0xFF66BB6A),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Bal: ${fmt.format(t.balance)}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}
