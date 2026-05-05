import 'package:flutter/material.dart';
import 'package:mobile_app/core/models/user.dart';
import 'package:mobile_app/core/services/user_manager.dart';

class UserManagerScreen extends StatefulWidget {
  const UserManagerScreen({super.key});

  @override
  State<UserManagerScreen> createState() => _UserManagerScreenState();
}

class _UserManagerScreenState extends State<UserManagerScreen> {
  final _editFormKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _hardDeleteConfirmController = TextEditingController();

  UserRole? _filterRole;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  String? _nextCursor;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _hardDeleteConfirmController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool reset = true}) async {
    setState(() {
      if (reset) {
        _isLoading = true;
        _error = null;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final result = await UserManagerService.listUsers(
        limit: 5,
        startAfterId: reset ? null : _nextCursor,
        name: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        searchRole: _filterRole?.toApiValue(),
      );

      if (!mounted) return;
      setState(() {
        final fetched = (result["users"] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _users = reset ? fetched : [..._users, ...fetched];
        _nextCursor = result["next_cursor"]?.toString();
        _hasMore = result["has_more"] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        if (reset) {
          _isLoading = false;
        } else {
          _isLoadingMore = false;
        }
      });
    }
  }

  Future<void> _openEditDialog(Map<String, dynamic> user) async {
    final userId = user["user_id"]?.toString() ?? "";
    try {
      final details = await UserManagerService.getUserById(userId);
      _nameController.text = details["name"]?.toString() ?? "";
      _emailController.text = details["email"]?.toString() ?? "";
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error loading user details: $e")));
      return;
    }

    if (!mounted) return;

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Edit User"),
          content: SingleChildScrollView(
            child: Form(
              key: _editFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: userId,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: "User ID"),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: "Name"),
                    validator: (value) {
                      final text = (value ?? "").trim();
                      if (text.isEmpty) return "Name is required";
                      if (text.length < 2)
                        return "Name must be at least 2 characters";
                      if (text.length > 80)
                        return "Name must be 80 characters or less";
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: "Email"),
                    validator: (value) {
                      final text = (value ?? "").trim();
                      if (text.isEmpty) return "Email is required";
                      if (!RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(text)) {
                        return "Enter a valid email";
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                if (_editFormKey.currentState?.validate() != true) {
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (save != true) return;
    final confirmed = await _confirmAction(
      title: "Confirm Edit",
      message: "Save changes to user $userId?",
      confirmLabel: "Confirm Save",
    );
    if (confirmed != true) return;

    try {
      await UserManagerService.editUser(
        userId: userId,
        updates: {
          "name": _nameController.text.trim(),
          "email": _emailController.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("User updated"),
          backgroundColor: Colors.green,
        ),
      );
      _loadUsers(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final userId = user["user_id"]?.toString() ?? "";
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Disable or Hard Delete"),
        content: Text(
          "Choose action for user $userId.\n\nDisable keeps a record and can be reactivated.\nHard delete permanently removes the user.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, "cancel"),
            child: const Text("Cancel"),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, "soft"),
            child: const Text("Disable User"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, "hard"),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Hard Delete"),
          ),
        ],
      ),
    );

    if (action == null || action == "cancel") return;

    bool hardDelete = false;
    if (action == "hard") {
      hardDelete = await _confirmHardDelete(userId);
      if (!hardDelete) return;
    } else {
      final confirmed = await _confirmAction(
        title: "Confirm Disable",
        message: "Disable user $userId?",
        confirmLabel: "Disable",
      );
      if (confirmed != true) return;
    }

    try {
      await UserManagerService.deleteUser(
        userId: userId,
        hardDelete: hardDelete,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hardDelete ? "User hard deleted" : "User disabled"),
          backgroundColor: hardDelete ? Colors.red : Colors.orange,
        ),
      );
      _loadUsers(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reactivateUser(Map<String, dynamic> user) async {
    final userId = user["user_id"]?.toString() ?? "";
    final confirmed = await _confirmAction(
      title: "Confirm Reactivate",
      message: "Reactivate user $userId?",
      confirmLabel: "Reactivate",
    );
    if (confirmed != true) return;
    try {
      await UserManagerService.reactivateUser(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("User reactivated"),
          backgroundColor: Colors.green,
        ),
      );
      _loadUsers(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  String _roleToDisplayName(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return "Admin";
      case UserRole.clinician:
        return "Clinician";
      case UserRole.studyCoordinator:
        return "Study Coordinator";
    }
  }

  Future<bool> _confirmHardDelete(String userId) async {
    _hardDeleteConfirmController.clear();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final expected = "DELETE $userId";
            final isMatch =
                _hardDeleteConfirmController.text.trim() == expected;
            return AlertDialog(
              title: const Text("Permanent Hard Delete"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "This action is irreversible. It removes the user from Firestore and Firebase Auth.",
                  ),
                  const SizedBox(height: 12),
                  Text("Type exactly: $expected"),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _hardDeleteConfirmController,
                    decoration: const InputDecoration(
                      labelText: "Confirmation text",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: isMatch ? () => Navigator.pop(ctx, true) : null,
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("Permanently Delete"),
                ),
              ],
            );
          },
        );
      },
    );
    return result == true;
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("User Manager"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: "Search by name prefix",
                            prefixIcon: Icon(Icons.search),
                          ),
                          onFieldSubmitted: (_) => _loadUsers(reset: true),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<UserRole>(
                                value: _filterRole,
                                decoration: const InputDecoration(
                                  labelText: "Filter role",
                                ),
                                items: [
                                  const DropdownMenuItem<UserRole>(
                                    value: null,
                                    child: Text("All roles"),
                                  ),
                                  ...UserRole.values.map(
                                    (role) => DropdownMenuItem(
                                      value: role,
                                      child: Text(_roleToDisplayName(role)),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  setState(() => _filterRole = val);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () => _loadUsers(reset: true),
                                icon: const Icon(Icons.refresh),
                                label: const Text("Refresh"),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  )
                else if (_users.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("No users found."),
                    ),
                  )
                else ...[
                  ..._users.map(_buildUserCard),
                  const SizedBox(height: 8),
                  if (_hasMore)
                    Center(
                      child: FilledButton.tonalIcon(
                        onPressed: _isLoadingMore
                            ? null
                            : () => _loadUsers(reset: false),
                        icon: _isLoadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more),
                        label: Text(
                          _isLoadingMore ? "Loading..." : "Load More",
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final userId = user["user_id"]?.toString() ?? "unknown";
    final name = user["name"]?.toString() ?? "-";
    final email = user["email"]?.toString() ?? "-";
    final role = user["role"]?.toString() ?? "-";
    final status = user["status"]?.toString() ?? "active";
    final isDisabled = status == "disabled";

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(status),
                  backgroundColor: isDisabled ? Colors.orange : Colors.green,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Email: $email"),
            const SizedBox(height: 4),
            Text("Role: $role"),
            const SizedBox(height: 4),
            Text(
              "User ID: $userId",
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _openEditDialog(user),
                  icon: const Icon(Icons.edit),
                  label: const Text("Edit"),
                ),
                if (isDisabled)
                  FilledButton.icon(
                    onPressed: () => _reactivateUser(user),
                    icon: const Icon(Icons.replay),
                    label: const Text("Reactivate"),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: () => _deleteUser(user),
                    icon: const Icon(Icons.person_off),
                    label: const Text("Disable"),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
