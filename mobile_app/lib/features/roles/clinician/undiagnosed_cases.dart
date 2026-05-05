// List of undiagnosed cases, button for refreshing list
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_app/core/services/dbmanager.dart';
import 'package:mobile_app/features/roles/clinician/diagnose_case.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UndiagnosedCasesScreen extends StatefulWidget {
  const UndiagnosedCasesScreen({super.key});

  @override
  State<UndiagnosedCasesScreen> createState() => _UndiagnosedCasesScreenState();
}

class _UndiagnosedCasesScreenState extends State<UndiagnosedCasesScreen> {
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _message;
  final List<Map<String, dynamic>> _cases = [];
  bool _isCancelled = false;

  // Filter parameters
  int _currentLimit = 50; // Start with 50, can load more
  int _daysBack = 30; // Default to 30 days
  int _totalLoaded = 0;
  bool _hasMore = true; // Assume there might be more cases initially

  // Date range options
  final List<Map<String, dynamic>> _dateRangeOptions = [
    {'label': 'Last 7 days', 'value': 7},
    {'label': 'Last 30 days', 'value': 30},
    {'label': 'Last 90 days', 'value': 90},
    {'label': 'Last 180 days', 'value': 180},
    {'label': 'Last year', 'value': 365},
  ];

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  @override
  void dispose() {
    // Cancel any ongoing loading operations
    _isCancelled = true;
    super.dispose();
  }

  Future<void> _loadCases({bool refresh = true}) async {
    try {
      // Reset cancellation flag when starting a new load
      _isCancelled = false;

      setState(() {
        _isLoading = true;
        if (refresh) {
          _cases.clear();
          _totalLoaded = 0;
          _hasMore = true;
        }
        _message = null;
      });

      final prefs = await SharedPreferences.getInstance();
      final String userId =
          prefs.getString("userId") ??
          FirebaseAuth.instance.currentUser?.uid ??
          "unknown";
      if (userId == "unknown") {
        throw Exception("User ID not found. Please log in and try again.");
      }

      final newCases = await DbManagerService.getUndiagnosedCases(
        clinicianID: userId,
        limit: _currentLimit,
        daysBack: _daysBack,
        onCaseProcessed: (caseResult) {
          // Progressive rendering: add each case as it's ready
          if (!_isCancelled && mounted && !caseResult.containsKey("error")) {
            setState(() {
              _cases.add(caseResult);
            });
          }
        },
      );

      // Check if loading was cancelled before final update
      if (_isCancelled) return;

      // Update pagination state
      if (mounted) {
        setState(() {
          _totalLoaded = _cases.length;
          // If we got fewer cases than requested, there are no more
          _hasMore = newCases.length >= _currentLimit;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = "Error loading undiagnosed cases: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreCases() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;

    try {
      setState(() => _isLoadingMore = true);

      final prefs = await SharedPreferences.getInstance();
      final String userId =
          prefs.getString("userId") ??
          FirebaseAuth.instance.currentUser?.uid ??
          "unknown";

      // Increase limit to fetch more cases
      final newLimit = _currentLimit + 50;

      final allCases = await DbManagerService.getUndiagnosedCases(
        clinicianID: userId,
        limit: newLimit,
        daysBack: _daysBack,
      );

      if (mounted && !_isCancelled) {
        setState(() {
          _cases.clear();
          _cases.addAll(allCases);
          _currentLimit = newLimit;
          _totalLoaded = allCases.length;
          // Check if we got all available cases
          _hasMore = allCases.length >= newLimit;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading more cases: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _changeDateRange(int days) {
    setState(() {
      _daysBack = days;
      _currentLimit = 50; // Reset limit when changing date range
    });
    _loadCases(refresh: true);
  }

  Future<void> _openDiagnoseCase({
    required Map<String, dynamic> caseInfo,
    required int index,
  }) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DiagnoseCaseScreen(caseInfo: caseInfo, caseIndex: index),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result['action'] == 'diagnosed') {
          if (result['index'] != null) {
            _cases.removeAt(result['index']);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final crossAxisCount = isTablet ? (screenWidth >= 900 ? 3 : 2) : 1;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isLoading,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isLoading) {
          // Cancel loading and allow navigation
          _isCancelled = true;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Undiagnosed Cases"),
          elevation: 0,
          actions: [
            if (!_isLoading && _cases.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadCases,
                tooltip: 'Refresh',
              ),
          ],
        ),
        body: _isLoading && _cases.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      "Loading cases...",
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            : _cases.isEmpty && !_isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _message != null
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: isTablet ? 120 : 80,
                      color: _message != null
                          ? Colors.orange.withValues(alpha: 0.5)
                          : colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _message ?? "All cases are diagnosed",
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_message == null) ...[
                      const SizedBox(height: 12),
                      Text(
                        "Tap the refresh button to check again",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: _loadCases,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Refresh"),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Date Range Filter
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      border: Border(
                        bottom: BorderSide(
                          color: colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.filter_list,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Filter by date range:",
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _dateRangeOptions.map((option) {
                              final isSelected =
                                  _daysBack == option['value'] as int;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(option['label'] as String),
                                  selected: isSelected,
                                  onSelected: _isLoading
                                      ? null
                                      : (_) => _changeDateRange(
                                            option['value'] as int,
                                          ),
                                  selectedColor:
                                      colorScheme.primaryContainer,
                                  checkmarkColor: colorScheme.primary,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Case Count Info
                  if (_cases.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "${_cases.length} undiagnosed case${_cases.length == 1 ? '' : 's'} ${_isLoading ? 'loaded (loading more...)' : 'pending'}",
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                          if (_isLoading)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (isTablet) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        childAspectRatio: 2.5,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                      ),
                                  itemCount: _cases.length,
                                  itemBuilder: (context, index) {
                                    final caseInfo = _cases[index];
                                    return _buildCaseCard(
                                      caseInfo,
                                      index,
                                      colorScheme,
                                    );
                                  },
                                ),
                                if (_hasMore && !_isLoading) ...[
                                  const SizedBox(height: 24),
                                  _buildLoadMoreButton(colorScheme),
                                ],
                                if (_isLoadingMore) ...[
                                  const SizedBox(height: 24),
                                  CircularProgressIndicator(
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Loading more cases...",
                                    style: Theme.of(context).textTheme.bodyMedium
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                ],
                                const SizedBox(height: 80), // Space for FAB
                              ],
                            ),
                          );
                        } else {
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: _cases.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _cases.length) {
                                // Load more button at the end
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: _isLoadingMore
                                      ? Center(
                                          child: Column(
                                            children: [
                                              CircularProgressIndicator(
                                                color: colorScheme.primary,
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                "Loading more cases...",
                                                style: Theme.of(context)
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                      color: Colors.grey[600],
                                                    ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : _buildLoadMoreButton(colorScheme),
                                );
                              }
                              final caseInfo = _cases[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildCaseCard(
                                  caseInfo,
                                  index,
                                  colorScheme,
                                ),
                              );
                            },
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
        floatingActionButton: _cases.isEmpty && !_isLoading
            ? null
            : FloatingActionButton.extended(
                onPressed: _isLoading ? null : _loadCases,
                icon: const Icon(Icons.refresh),
                label: Text(isTablet ? "Refresh Cases" : "Refresh"),
                elevation: 4,
              ),
      ),
    );
  }

  Widget _buildCaseCard(
    Map<String, dynamic> caseInfo,
    int index,
    ColorScheme colorScheme,
  ) {
    final caseId = caseInfo['case_id'] ?? 'Unknown Case ID';
    final submittedAt = caseInfo['submitted_at'] ?? 'Unknown';

    String formattedDate = submittedAt;
    try {
      final dateTime = DateTime.parse(submittedAt);
      formattedDate =
          '${dateTime.day}/${dateTime.month}/${dateTime.year} '
          '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      // Keep original string if parsing fails
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openDiagnoseCase(caseInfo: caseInfo, index: index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.medical_information_outlined,
                  color: colorScheme.onErrorContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      caseId,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pending_outlined,
                      size: 14,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pending',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton(ColorScheme colorScheme) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: _isLoadingMore ? null : _loadMoreCases,
        icon: const Icon(Icons.expand_more),
        label: Text(
          "Load More Cases (${_cases.length} loaded)",
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          side: BorderSide(
            color: colorScheme.primary,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
