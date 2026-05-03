import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<AdminUser> _users = [];
  List<InviteCode> _codes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await ApiService.adminGetUsers();
      final codes = await ApiService.adminGetCodes();
      setState(() { _users = users; _codes = codes; });
    } catch (e) {
      _snack('Load failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCode() async {
    try {
      final code = await ApiService.adminCreateCode();
      await Clipboard.setData(ClipboardData(text: code));
      _snack('Code: $code (copied to clipboard)');
      _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<void> _banUser(AdminUser u) async {
    final confirm = await _confirm('Ban ${u.username}?', 'They will be disconnected immediately.');
    if (!confirm) return;
    try {
      await ApiService.adminBanUser(u.id);
      _snack('${u.username} banned');
      _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<void> _unbanUser(AdminUser u) async {
    try {
      await ApiService.adminUnbanUser(u.id);
      _snack('${u.username} unbanned');
      _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<void> _kickUser(AdminUser u) async {
    try {
      await ApiService.adminKickUser(u.id);
      _snack('${u.username} kicked');
      _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<void> _deleteUser(AdminUser u) async {
    final confirm = await _confirm('Delete ${u.username}?', 'This cannot be undone.');
    if (!confirm) return;
    try {
      await ApiService.adminDeleteUser(u.id);
      _snack('${u.username} deleted');
      _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<bool> _confirm(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Users'), Tab(text: 'Invite Codes')],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [_usersTab(), _codesTab()],
            ),
    );
  }

  Widget _usersTab() {
    if (_users.isEmpty) return const Center(child: Text('No users'));
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final u = _users[i];
        final isBanned = u.status == 'banned';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: u.online ? Colors.green : Colors.grey,
            child: Text(u.username[0].toUpperCase()),
          ),
          title: Text(u.username),
          subtitle: Text(
            '${u.role} · ${isBanned ? "BANNED" : u.online ? "online" : "offline"}',
            style: TextStyle(color: isBanned ? Colors.red : u.online ? Colors.green : Colors.grey),
          ),
          trailing: u.role == 'admin'
              ? const Chip(label: Text('admin'))
              : PopupMenuButton<String>(
                  onSelected: (action) {
                    switch (action) {
                      case 'kick':   _kickUser(u);
                      case 'ban':    _banUser(u);
                      case 'unban':  _unbanUser(u);
                      case 'delete': _deleteUser(u);
                    }
                  },
                  itemBuilder: (_) => [
                    if (u.online) const PopupMenuItem(value: 'kick', child: Text('Kick')),
                    if (!isBanned) const PopupMenuItem(value: 'ban', child: Text('Ban', style: TextStyle(color: Colors.orange))),
                    if (isBanned)  const PopupMenuItem(value: 'unban', child: Text('Unban', style: TextStyle(color: Colors.green))),
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                  ],
                ),
        );
      },
    );
  }

  Widget _codesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _createCode,
              icon: const Icon(Icons.add),
              label: const Text('Generate Invite Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _codes.length,
            itemBuilder: (_, i) {
              final c = _codes[i];
              return ListTile(
                leading: Icon(c.used ? Icons.check_circle : Icons.vpn_key,
                    color: c.used ? Colors.grey : Colors.green),
                title: Text(c.code, style: const TextStyle(fontFamily: 'monospace', letterSpacing: 2)),
                subtitle: Text(c.used ? 'Used by: ${c.usedBy}' : 'Available'),
                trailing: !c.used
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: c.code));
                              _snack('Code copied');
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                            onPressed: () async {
                              await ApiService.adminDeleteCode(c.id);
                              _load();
                            },
                          ),
                        ],
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
