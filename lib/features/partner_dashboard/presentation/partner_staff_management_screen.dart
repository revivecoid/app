import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PartnerStaffManagementScreen extends ConsumerStatefulWidget {
  const PartnerStaffManagementScreen({super.key});

  @override
  ConsumerState<PartnerStaffManagementScreen> createState() => _PartnerStaffManagementScreenState();
}

class _PartnerStaffManagementScreenState extends ConsumerState<PartnerStaffManagementScreen> {
  final _emailController = TextEditingController();
  String _selectedRole = 'partner_staff';
  bool _isLoading = false;
  String? _message;
  bool _isError = false;

  List<Map<String, dynamic>> _staff = [];

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('partner_id')
          .eq('id', user.id)
          .single();
          
      final partnerId = profile['partner_id'];
      if (partnerId == null) return;

      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email, role')
          .eq('partner_id', partnerId)
          .inFilter('role', ['partner_staff', 'partner_driver']);
          
      setState(() {
        _staff = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      debugPrint('Error loading staff: $e');
    }
  }

  Future<void> _addStaff() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final result = await Supabase.instance.client.rpc('add_partner_staff', params: {
        'staff_email': email,
        'staff_role': _selectedRole,
      });

      // The RPC now returns JSONB with { success, error?, user_id?, full_name?, role? }
      final Map<String, dynamic> response = result is Map<String, dynamic>
          ? result
          : (result is String ? {} : {});

      final success = response['success'] == true;

      if (success) {
        setState(() {
          _message = 'Successfully added ${response['full_name'] ?? email} as ${_selectedRole == 'partner_staff' ? 'Staff' : 'Driver'}!';
          _isError = false;
          _emailController.clear();
        });
        _loadStaff();
      } else {
        setState(() {
          _message = response['error']?.toString() ?? 'Failed to add staff member. Please try again.';
          _isError = true;
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error: ${e.toString().replaceAll('PostgrestException', '').trim()}';
        _isError = true;
      });
      debugPrint(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _removeStaff(String profileId, String memberName) async {
    // Confirm before removing
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff Member'),
        content: Text('Remove $memberName from your workshop? They will be reverted to a regular customer account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final result = await Supabase.instance.client.rpc('remove_partner_staff', params: {
        'target_user_id': profileId,
      });

      final Map<String, dynamic> response = result is Map<String, dynamic> ? result : {};
      final success = response['success'] == true;

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${response['removed_user'] ?? memberName} has been removed.'),
            backgroundColor: Colors.orange.shade700,
          ));
        }
        _loadStaff();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(response['error']?.toString() ?? 'Failed to remove staff member.'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error removing staff: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Drivers'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Add Staff Panel
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(24),
              color: cs.surfaceContainerLowest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Invite Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Enter the email address of a registered user to assign them to your workshop.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Staff Email Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'partner_staff', child: Text('Workshop Staff (Floor operations)')),
                      DropdownMenuItem(value: 'partner_driver', child: Text('Driver (Pickup & Delivery valet)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRole = val);
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_message != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isError ? Colors.red.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _isError ? Colors.red.shade200 : Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isError ? Icons.error_outline : Icons.check_circle_outline,
                            size: 18,
                            color: _isError ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_message!, style: TextStyle(color: _isError ? Colors.red.shade900 : Colors.green.shade900)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _addStaff,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFd10721), foregroundColor: Colors.white),
                      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Add Staff Member'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Staff List Panel
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Active Staff Members', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh list',
                        onPressed: _loadStaff,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_staff.isEmpty)
                    const Text('No staff members assigned yet.')
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _staff.length,
                        itemBuilder: (context, index) {
                          final member = _staff[index];
                          final isDriver = member['role'] == 'partner_driver';
                          final memberName = member['full_name'] ?? 'Unknown';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isDriver ? Colors.blue.shade100 : Colors.orange.shade100,
                                child: Icon(isDriver ? Icons.local_shipping : Icons.build, color: isDriver ? Colors.blue.shade900 : Colors.orange.shade900),
                              ),
                              title: Text(memberName),
                              subtitle: Text('${member['email'] ?? ''} · ${isDriver ? 'Driver' : 'Staff'}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                tooltip: 'Remove from workshop',
                                onPressed: () => _removeStaff(member['id'], memberName),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
