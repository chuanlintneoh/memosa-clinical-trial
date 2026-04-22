import 'package:flutter/material.dart';
import 'package:mobile_app/core/services/auth.dart';
import 'package:mobile_app/features/roles/screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String email;
  final String role;
  final String name;
  const HomeScreen({
    super.key,
    required this.userId,
    required this.email,
    required this.role,
    required this.name,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isExpanded = false;

  String _formatRole(String role) {
    switch (role) {
      case "study_coordinator":
        return "Study Coordinator";
      case "clinician":
        return "Clinician";
      case "admin":
        return "Admin";
      default:
        return role;
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, "/", (_) => false);
    }
  }

  List<Widget> _buildMenuItems() {
    switch (widget.role) {
      case "study_coordinator":
        return [
          _buildNavButton(Icons.drafts, "Draft Cases"),
          _buildNavButton(Icons.list, "Browse Cases"),
          _buildNavButton(Icons.edit, "Edit Case"),
        ];
      case "clinician":
        return [_buildNavButton(Icons.search, "Undiagnosed Cases")];
      case "admin":
        return [
          _buildNavButton(Icons.key, "Invite Code Manager"),
          _buildNavButton(Icons.manage_accounts, "User Manager"),
          _buildNavButton(Icons.file_download, "Export Bundle"),
        ];
      default:
        return [const Text("Unknown role")];
    }
  }

  Widget _buildNavButton(IconData icon, String label) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _isExpanded ? 12 : 8,
        vertical: 4,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            switch (label) {
              case "Draft Cases":
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DraftCasesScreen()),
                );
                break;
              case "Browse Cases":
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CasesListScreen()),
                );
                break;
              case "Edit Case":
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditCaseScreen()),
                );
                break;
              case "Undiagnosed Cases":
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UndiagnosedCasesScreen(),
                  ),
                );
                break;
              case "Invite Code Manager":
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InviteCodeManagerScreen(),
                  ),
                );
                break;
              case "User Manager":
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserManagerScreen()),
                );
                break;
              case "Export Bundle":
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExportBundleScreen()),
                );
                break;
              default:
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PageNotFoundScreen()),
                );
                break;
            }
          },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isExpanded ? 16 : 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: _isExpanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                if (_isExpanded) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
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

  List<Widget> _buildQuickActions() {
    switch (widget.role) {
      case "study_coordinator":
        return [
          _buildQuickAction(Icons.drafts, "Draft & Create Cases", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DraftCasesScreen()),
            );
          }),
          _buildQuickAction(Icons.list, "Browse Cases", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CasesListScreen()),
            );
          }),
          _buildQuickAction(Icons.edit, "Search & Edit Case", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditCaseScreen()),
            );
          }),
        ];
      case "clinician":
        return [
          _buildQuickAction(Icons.search, "Undiagnosed Cases", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UndiagnosedCasesScreen()),
            );
          }),
        ];
      case "admin":
        return [
          _buildQuickAction(Icons.key, "Invite Code Manager", () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const InviteCodeManagerScreen(),
              ),
            );
          }),
          _buildQuickAction(Icons.manage_accounts, "User Manager", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserManagerScreen()),
            );
          }),
          _buildQuickAction(Icons.file_download, "Export Bundle", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExportBundleScreen()),
            );
          }),
        ];
      default:
        return [];
    }
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return Card(
      elevation: 2,
      shadowColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: 0.2),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content Area - hidden when sidebar is expanded on mobile
            Row(
              children: [
                // Collapsed sidebar space
                SizedBox(width: _isExpanded && !isTablet ? 0 : 80),

                // Main Content Area
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.03),
                          theme.colorScheme.surface,
                        ],
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        // Constrain content width for tablets
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Logo
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 400,
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 3.5,
                                      child: Image.asset(
                                        'assets/images/logo_crmy.webp',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),

                                // Welcome Card
                                Card(
                                  elevation: 4,
                                  shadowColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          theme.colorScheme.primaryContainer
                                              .withValues(alpha: 0.4),
                                          theme.colorScheme.secondaryContainer
                                              .withValues(alpha: 0.3),
                                        ],
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(28),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  Icons.waving_hand,
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimary,
                                                  size: 28,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Flexible(
                                                child: Text(
                                                  "Welcome, ${widget.name}!",
                                                  textAlign: TextAlign.center,
                                                  style: theme
                                                      .textTheme
                                                      .headlineSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurface,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            "MeMoSA Clinical Platform",
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 16),
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 16,
                                            runSpacing: 12,
                                            children: [
                                              _buildInfoChip(
                                                theme,
                                                Icons.badge_outlined,
                                                _formatRole(widget.role),
                                              ),
                                              _buildInfoChip(
                                                theme,
                                                Icons.email_outlined,
                                                widget.email,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 40),

                                // Quick Actions Section
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.bolt,
                                        color: theme.colorScheme.onPrimary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      "Quick Actions",
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Quick Action Cards
                                ..._buildQuickActions().map(
                                  (action) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: action,
                                  ),
                                ),

                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Sidebar - overlays on mobile when expanded
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: 0,
              top: 0,
              bottom: 0,
              width: _isExpanded ? (isTablet ? 240 : screenWidth) : 80,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // User Avatar & Info
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: _isExpanded ? 32 : 24,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              child: Icon(
                                Icons.person,
                                size: _isExpanded ? 32 : 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (_isExpanded) ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                widget.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _formatRole(widget.role),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                widget.email,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Divider
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _isExpanded ? 16 : 12,
                      ),
                      child: Divider(
                        color: Colors.white.withValues(alpha: 0.3),
                        thickness: 1,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Menu Items
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: _buildMenuItems(),
                      ),
                    ),

                    // Divider
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _isExpanded ? 16 : 12,
                      ),
                      child: Divider(
                        color: Colors.white.withValues(alpha: 0.3),
                        thickness: 1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Logout Button
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _isExpanded ? 12 : 8,
                        vertical: 4,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _logout,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: _isExpanded ? 16 : 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            child: Row(
                              mainAxisSize: _isExpanded
                                  ? MainAxisSize.max
                                  : MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.logout,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                if (_isExpanded) ...[
                                  const SizedBox(width: 16),
                                  const Expanded(
                                    child: Text(
                                      "Logout",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Toggle Button
                    Center(
                      child: IconButton(
                        icon: Icon(
                          _isExpanded
                              ? Icons.chevron_left
                              : Icons.chevron_right,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: () =>
                            setState(() => _isExpanded = !_isExpanded),
                        tooltip: _isExpanded ? 'Collapse' : 'Expand',
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
