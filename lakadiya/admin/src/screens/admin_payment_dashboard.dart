import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lakadiya/core/services/api_service.dart';

class AdminPaymentDashboard extends StatefulWidget {
  const AdminPaymentDashboard({Key? key}) : super(key: key);

  @override
  State<AdminPaymentDashboard> createState() => _AdminPaymentDashboardState();
}

class _AdminPaymentDashboardState extends State<AdminPaymentDashboard> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _addMoneyTransactions = [];
  List<Map<String, dynamic>> _withdrawRequests = [];
  bool _loadingAddMoney = false;
  bool _loadingWithdrawals = false;
  String _withdrawalFilter = 'pending'; // pending, success, failed

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    _fetchAddMoneyTransactions();
    _fetchWithdrawalRequests();
  }

  Future<void> _fetchAddMoneyTransactions() async {
    try {
      setState(() => _loadingAddMoney = true);
      final apiService = ApiService();
      final response = await apiService.get('/payments/admin/transactions');
      if (mounted) {
        setState(() {
          _addMoneyTransactions = (response.data as List)
              .map((item) => item as Map<String, dynamic>)
              .toList();
          _loadingAddMoney = false;
        });
      }
    } catch (e) {
      print('[AdminDashboard] Error fetching add money: $e');
      if (mounted) {
        setState(() => _loadingAddMoney = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _fetchWithdrawalRequests() async {
    try {
      setState(() => _loadingWithdrawals = true);
      final apiService = ApiService();
      final response = await apiService.get(
        '/payments/admin/withdrawals',
        params: {'status': _withdrawalFilter},
      );
      if (mounted) {
        setState(() {
          _withdrawRequests = (response.data as List)
              .map((item) => item as Map<String, dynamic>)
              .toList();
          _loadingWithdrawals = false;
        });
      }
    } catch (e) {
      print('[AdminDashboard] Error fetching withdrawals: $e');
      if (mounted) {
        setState(() => _loadingWithdrawals = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _approveWithdrawal(String transactionId) async {
    try {
      final apiService = ApiService();
      await apiService.post(
        '/payments/admin/withdrawals/$transactionId/approve',
        data: {},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Withdrawal approved'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchWithdrawalRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectWithdrawal(String transactionId, String reason) async {
    try {
      final apiService = ApiService();
      await apiService.post(
        '/payments/admin/withdrawals/$transactionId/reject',
        data: {'reason': reason},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Withdrawal rejected'),
          backgroundColor: Colors.orange,
        ),
      );
      _fetchWithdrawalRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payment Management'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Add Money'),
              Tab(text: 'Withdrawals'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Add Money Tab
            _buildAddMoneyTab(),
            // Withdrawals Tab
            _buildWithdrawalsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildAddMoneyTab() {
    return RefreshIndicator(
      onRefresh: _fetchAddMoneyTransactions,
      child: _loadingAddMoney
          ? const Center(child: CircularProgressIndicator())
          : _addMoneyTransactions.isEmpty
              ? const Center(child: Text('No transactions'))
              : ListView.builder(
                  itemCount: _addMoneyTransactions.length,
                  itemBuilder: (context, index) {
                    final tx = _addMoneyTransactions[index];
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text('${tx['username']} - ₹${tx['amount']}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx['email'] ?? 'N/A'),
                            Text(
                              DateFormat('MMM dd, yyyy HH:mm').format(
                                DateTime.parse(tx['created_at']),
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(tx['status']),
                          backgroundColor: tx['status'] == 'success'
                              ? Colors.green.shade200
                              : Colors.orange.shade200,
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildWithdrawalsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _withdrawalFilter,
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'success', child: Text('Approved')),
                    DropdownMenuItem(value: 'failed', child: Text('Rejected')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _withdrawalFilter = value);
                      _fetchWithdrawalRequests();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _fetchWithdrawalRequests,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchWithdrawalRequests,
            child: _loadingWithdrawals
                ? const Center(child: CircularProgressIndicator())
                : _withdrawRequests.isEmpty
                    ? const Center(child: Text('No withdrawal requests'))
                    : ListView.builder(
                        itemCount: _withdrawRequests.length,
                        itemBuilder: (context, index) {
                          final wr = _withdrawRequests[index];
                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: ListTile(
                              title: Text('${wr['username']} - ₹${wr['amount']}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(wr['email'] ?? 'N/A'),
                                  Text(
                                    DateFormat('MMM dd, yyyy HH:mm').format(
                                      DateTime.parse(wr['created_at']),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: wr['status'] == 'pending'
                                  ? PopupMenuButton(
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          child: const Text('Approve'),
                                          onTap: () => _approveWithdrawal(wr['id']),
                                        ),
                                        PopupMenuItem(
                                          child: const Text('Reject'),
                                          onTap: () => _showRejectDialog(wr['id']),
                                        ),
                                      ],
                                    )
                                  : Chip(
                                      label: Text(wr['status']),
                                      backgroundColor: wr['status'] == 'success'
                                          ? Colors.green.shade200
                                          : Colors.red.shade200,
                                    ),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  void _showRejectDialog(String transactionId) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Withdrawal'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Enter rejection reason'),
          minLines: 3,
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectWithdrawal(transactionId, reasonController.text);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
