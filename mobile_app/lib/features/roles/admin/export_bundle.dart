import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_app/core/services/dbmanager.dart';
// import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

class ExportBundleScreen extends StatefulWidget {
  const ExportBundleScreen({super.key});

  @override
  State<ExportBundleScreen> createState() => _ExportBundleScreenState();
}

class _ExportBundleScreenState extends State<ExportBundleScreen> {
  // final _emailController = TextEditingController();
  // String? _userEmail;
  bool _exported = false;
  bool _isLoading = false;
  String? _errorMessage;

  bool includeAllFlag = false;
  final _timestampController = TextEditingController();
  final _expiryDurationController = TextEditingController(
    text: "[Defaults to 1 day]",
  );
  final _urlController = TextEditingController(
    text: "[Signed URL will appear here]",
  );
  final _passwordController = TextEditingController(
    text: "[Generated password will appear here]",
  );

  @override
  void initState() {
    super.initState();
    // _loadUserEmail();
  }

  // Future<void> _loadUserEmail() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final email = prefs.getString("email");
  //   setState(() {
  //     _userEmail = email;
  //     if (email != null) {
  //       _emailController.text = email;
  //     }
  //   });
  // }

  Future<void> _exportBundle() async {
    setState(() {
      _isLoading = true;
    });
    final results = await DbManagerService.exportBundle(
      includeAll: includeAllFlag,
    );

    if (results["status"] == "success") {
      _timestampController.text = results["timestamp"] ?? 'NULL';
      _expiryDurationController.text = results["expiry_days"] != null
          ? "${results["expiry_days"]} day(s)"
          : 'Not specified';
      _urlController.text = results["url"] ?? 'NULL';
      _passwordController.text = results["password"] ?? 'NULL';
      setState(() {
        _exported = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = results["error"] ?? 'An error occurred';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool readOnly = true,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: readOnly
            ? IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: controller.text));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("$label copied")));
                },
              )
            : null,
        border: readOnly ? const OutlineInputBorder() : null,
      ),
      validator: (value) =>
          value == null || value.isEmpty ? "Enter $label" : null,
    );
  }

  void _shareBundle() {
    final timestamp = _timestampController.text;
    final url = _urlController.text;
    final password = _passwordController.text;
    final expiryDuration = _expiryDurationController.text;

    if (url.isEmpty || url.startsWith('[')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No valid URL to share, please try exporting a bundle first.",
          ),
        ),
      );
      return;
    }

    final shareText =
        '''
        📦 *Exported Bundle*
        ⌚ Timestamp: $timestamp
        🔗 URL: $url
        🔑 Password: $password
        ⏳ Expiry Duration: $expiryDuration
        ''';

    SharePlus.instance.share(
      ShareParams(text: shareText, subject: "Exported Bundle"),
    );
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (result == true) {
      onConfirm();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Export Bundle"), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          final maxWidth = isWide ? 800.0 : double.infinity;

          return Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isWide ? 24.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Info Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Export Database Bundle",
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Create a secure, time-limited bundle of the database for backup or transfer purposes.",
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.blue.shade800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Export Options Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.settings_outlined, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  "Export Options",
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: includeAllFlag
                                    ? Colors.orange.withValues(alpha: 0.1)
                                    : Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: includeAllFlag
                                      ? Colors.orange
                                      : Colors.green,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    includeAllFlag
                                        ? Icons.warning_amber_rounded
                                        : Icons.shield_outlined,
                                    color: includeAllFlag
                                        ? Colors.orange
                                        : Colors.green,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Include Sensitive Patient Data?",
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          includeAllFlag
                                              ? "Bundle will contain full patient information"
                                              : "Bundle will exclude sensitive patient data",
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.black87),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: includeAllFlag,
                                    onChanged: (val) {
                                      setState(() => includeAllFlag = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Export Button
                    ElevatedButton.icon(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 24),
                      onPressed: _isLoading
                          ? null
                          : () {
                              _confirmAction(
                                title: "Confirm Export Bundle",
                                message:
                                    "You are about to export a bundle ${includeAllFlag ? "including" : "excluding"} patients' sensitive data. Are you sure you want to proceed?",
                                onConfirm: _exportBundle,
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 24,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      label: Text(
                        _isLoading ? "Exporting..." : "Generate Export Bundle",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Loading Progress Indicator
                    if (_isLoading)
                      Card(
                        elevation: 2,
                        color: Colors.blue.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                "Processing Export Bundle",
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Server is processing cases in batches...",
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.blue.shade800),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        "This may take a few moments for large databases",
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.blue.shade700,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (_isLoading) const SizedBox(height: 24),

                    // Error Message
                    if (_errorMessage != null)
                      Card(
                        elevation: 2,
                        color: Colors.red.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Export Failed",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: Colors.red.shade900,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Export Results
                    if (_exported) ...[
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.green,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Export Successful",
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade900,
                                              ),
                                        ),
                                        Text(
                                          "Bundle created and ready to share",
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.green.shade700,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              _buildTextField(
                                _timestampController,
                                "Timestamp",
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                _expiryDurationController,
                                "Expiry Duration",
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(_urlController, "Signed URL"),
                              const SizedBox(height: 16),
                              _buildTextField(_passwordController, "Password"),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Share Button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.share_rounded, size: 24),
                        onPressed: _shareBundle,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 24,
                          ),
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        label: const Text(
                          "Share Export Bundle",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
