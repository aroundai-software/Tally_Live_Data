import 'dart:async';

import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/ledger.dart';
import 'ledger_statement_screen.dart';
import '../providers/company_provider.dart';
import '../utils/company_scope.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/error_handler.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';
import '../widgets/combined_report_widgets.dart';

class LedgerScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const LedgerScreen({super.key, this.onBack});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final SupabaseService _service = SupabaseService();
  List<Ledger> _customers = [];
  List<Ledger> _filteredCustomers = [];
  List<Ledger>? _pendingCustomers;
  /// Precomputed lowercase search blobs aligned with [_customers] (alpha-sorted).
  List<String> _searchHaystacks = const [];
  /// Bit flags aligned with [_customers]: 1 = debtor, 2 = creditor.
  List<int> _typeFlags = const [];
  bool _isLoading = true;
  String? _error;
  /// Full company ledger count from DB (not tied to progressive list pages).
  int? _serverTotalCount;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _typeFilter = 'All';
  String _sortOption = 'Alphabetical';

  bool _initialized = false;
  bool _awaitingFullCustomerList = false;
  Timer? _searchDebounce;

  bool get _showingUnfilteredAll =>
      _typeFilter == 'All' && _searchController.text.trim().isEmpty;

  int get _displayTotalCount {
    if (_showingUnfilteredAll && _serverTotalCount != null) {
      return _serverTotalCount!;
    }
    return _filteredCustomers.length;
  }

  int get _displayActiveCount {
    // Avoid flashing a partial active count under the full total while pages load.
    if (_showingUnfilteredAll &&
        _serverTotalCount != null &&
        _customers.length < _serverTotalCount!) {
      return _serverTotalCount!;
    }
    return _filteredCustomers.where((c) => c.isActive).length;
  }

  /// Special chars first, then digits, then letters (case-insensitive within group).
  int _compareLedgerNames(String a, String b) {
    int category(String s) {
      if (s.isEmpty) return 0;
      final code = s.codeUnitAt(0);
      if (code >= 48 && code <= 57) return 1; // 0-9
      if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) return 2; // A-Z / a-z
      return 0; // special / other
    }

    final ca = category(a);
    final cb = category(b);
    if (ca != cb) return ca.compareTo(cb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pendingCustomers = null;
    super.dispose();
  }

  void _onScroll() {
    if (_pendingCustomers == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels <= 0 || pos.pixels >= pos.maxScrollExtent) {
      _applyPendingData();
    }
  }

  void _applyPendingData() {
    if (_pendingCustomers == null) return;
    _setCustomers(_pendingCustomers!);
    _pendingCustomers = null;
    _applySearchFilter();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), _applySearchFilter);
  }

  String _buildSearchHaystack(Ledger c) {
    // Name-focused: address/city/category matches were surfacing unrelated ledgers.
    final parts = <String>[
      c.name,
      if (c.alias != null && c.alias!.trim().isNotEmpty) c.alias!,
      if (c.mailingName != null && c.mailingName!.trim().isNotEmpty) c.mailingName!,
    ];
    return parts.join('\n').toLowerCase();
  }

  /// Index customers once (sorted A→Z) so search avoids repeated toLowerCase / type scans.
  void _setCustomers(List<Ledger> items) {
    if (items.isEmpty) {
      _customers = const [];
      _searchHaystacks = const [];
      _typeFlags = const [];
      return;
    }
    final sorted = List<Ledger>.of(items)
      ..sort((a, b) => _compareLedgerNames(a.name, b.name));
    final haystacks = List<String>.filled(sorted.length, '', growable: false);
    final flags = List<int>.filled(sorted.length, 0, growable: false);
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      haystacks[i] = _buildSearchHaystack(c);
      var flag = 0;
      if (c.isDebtor) flag |= 1;
      if (c.isCreditor) flag |= 2;
      flags[i] = flag;
    }
    _customers = sorted;
    _searchHaystacks = haystacks;
    _typeFlags = flags;
  }

  void _clearCustomers() {
    _customers = const [];
    _filteredCustomers = const [];
    _searchHaystacks = const [];
    _typeFlags = const [];
    _pendingCustomers = null;
    _serverTotalCount = null;
  }

  void _applySearchFilter() {
    if (!mounted) return;
    final query = _searchController.text.trim().toLowerCase();
    final typeMask = _typeFilter == 'Debtors'
        ? 1
        : _typeFilter == 'Creditors'
            ? 2
            : 0;
    final sortOption = _sortOption;
    final source = _customers;
    final haystacks = _searchHaystacks;
    final flags = _typeFlags;

    // Fast path: no search/type filter + alphabetical → reuse indexed list.
    if (query.isEmpty && typeMask == 0 && sortOption == 'Alphabetical') {
      setState(() => _filteredCustomers = source);
      return;
    }

    final matched = <Ledger>[];
    final n = source.length;
    final hasIndex = haystacks.length == n && flags.length == n;
    for (var i = 0; i < n; i++) {
      if (typeMask != 0) {
        if (hasIndex) {
          if ((flags[i] & typeMask) == 0) continue;
        } else {
          final c = source[i];
          if (typeMask == 1 && !c.isDebtor) continue;
          if (typeMask == 2 && !c.isCreditor) continue;
        }
      }
      if (query.isNotEmpty) {
        if (hasIndex) {
          if (!haystacks[i].contains(query)) continue;
        } else if (!source[i].matchesSearchQuery(query)) {
          continue;
        }
      }
      matched.add(source[i]);
    }

    if (sortOption == 'Recently Active') {
      matched.sort((a, b) => (b.updatedAt ?? DateTime(2000))
          .compareTo(a.updatedAt ?? DateTime(2000)));
    } else if (sortOption == 'Highest Balance') {
      matched.sort(
          (a, b) => b.closingBalance.abs().compareTo(a.closingBalance.abs()));
    }
    // Alphabetical: source is already A→Z, so matched keeps that order.

    setState(() => _filteredCustomers = matched);
  }

  int? _lastSyncTrigger;
  int? _lastCompanyRevision;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final companyState = CompanyProvider.of(context);
    final syncTrigger = companyState.syncTrigger;
    final revision = companyState.companyRevision;
    if (!_initialized) {
      _initialized = true;
      _lastSyncTrigger = syncTrigger;
      _lastCompanyRevision = revision;
      _loadPreferencesAndData();
    } else if (_lastCompanyRevision != revision) {
      _lastCompanyRevision = revision;
      _lastSyncTrigger = syncTrigger;
      _loadGeneration++;
      _searchController.clear();
      _clearCustomers();
      _loadPreferencesAndData();
    } else if (_lastSyncTrigger != syncTrigger) {
      _lastSyncTrigger = syncTrigger;
      _silentRefresh();
    }
  }

  Future<void> _loadPreferencesAndData() async {
    final savedFilter = await UserPreferencesService.loadLedgerTypeFilter();
    if (mounted) {
      setState(() => _typeFilter = savedFilter);
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final generation = ++_loadGeneration;
    final companyState = CompanyProvider.of(context);
    final scopeKey = companyState.scopeKey;
    final isCombined = companyState.isCombinedMode;
    final company = companyState.selectedCompany;
    if (!isCombined && !CompanyScope.isValid(company)) {
      if (mounted) {
        _clearCustomers();
        setState(() {
          _isLoading = false;
          _error = 'No company selected';
        });
      }
      return;
    }
    if (isCombined && !CompanyScope.hasActiveScope(companyState)) {
      if (mounted) {
        _clearCustomers();
        setState(() {
          _isLoading = false;
          _error = 'No companies selected';
        });
      }
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    _awaitingFullCustomerList = true;
    try {
      late final List<Ledger> items;
      late final int count;
      if (isCombined) {
        final companies = companyState.selectedCompanies;
        final countFuture = _service.getCombinedCustomerCount(companyNames: companies);
        items = await _service.getCombinedCustomers(
          companyNames: companies,
          onFirstPage: (first) {
            countFuture.then((c) {
              if (!mounted ||
                  generation != _loadGeneration ||
                  !_awaitingFullCustomerList ||
                  !CompanyScope.stillActiveScope(
                    scopeKey,
                    CompanyProvider.of(context).scopeKey,
                  )) {
                return;
              }
              _setCustomers(first);
              setState(() {
                _serverTotalCount = c;
                _isLoading = false;
              });
              _applySearchFilter();
            }).catchError((_) {
              if (!mounted ||
                  generation != _loadGeneration ||
                  !_awaitingFullCustomerList ||
                  !CompanyScope.stillActiveScope(
                    scopeKey,
                    CompanyProvider.of(context).scopeKey,
                  )) {
                return;
              }
              _setCustomers(first);
              setState(() => _isLoading = false);
              _applySearchFilter();
            });
          },
        );
        count = await countFuture.catchError((_) => items.length);
        _awaitingFullCustomerList = false;
      } else {
        // Count is a cheap head request — paint the real total with the first list page.
        final countFuture = _service.getCustomerCount(companyName: company);
        items = await _service.getCustomers(
          companyName: company,
          onFirstPage: (first) {
            countFuture.then((c) {
              if (!mounted ||
                  generation != _loadGeneration ||
                  !_awaitingFullCustomerList ||
                  !CompanyScope.stillActiveScope(scopeKey, CompanyProvider.of(context).scopeKey)) {
                return;
              }
              _setCustomers(first);
              setState(() {
                _serverTotalCount = c;
                _isLoading = false;
              });
              _applySearchFilter();
            }).catchError((_) {
              if (!mounted ||
                  generation != _loadGeneration ||
                  !_awaitingFullCustomerList ||
                  !CompanyScope.stillActiveScope(scopeKey, CompanyProvider.of(context).scopeKey)) {
                return;
              }
              _setCustomers(first);
              setState(() => _isLoading = false);
              _applySearchFilter();
            });
          },
        );
        count = await countFuture.catchError((_) => _serverTotalCount ?? items.length);
      }
      if (!mounted ||
          generation != _loadGeneration ||
          !CompanyScope.stillActiveScope(scopeKey, CompanyProvider.of(context).scopeKey)) {
        return;
      }
      _setCustomers(items);
      setState(() {
        _awaitingFullCustomerList = false;
        _serverTotalCount = count;
        _pendingCustomers = null;
        _isLoading = false;
      });
      _applySearchFilter();
    } catch (e) {
      _awaitingFullCustomerList = false;
      if (mounted &&
          generation == _loadGeneration &&
          CompanyScope.stillActiveScope(scopeKey, CompanyProvider.of(context).scopeKey)) {
        setState(() { _error = AppErrorHandler.getFriendlyError(e); _isLoading = false; });
      }
    }
  }

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    try {
      final companyState = CompanyProvider.of(context);
      final scopeKey = companyState.scopeKey;
      final isCombined = companyState.isCombinedMode;
      final company = companyState.selectedCompany;
      if (!isCombined && !CompanyScope.isValid(company)) return;
      if (isCombined && !CompanyScope.hasActiveScope(companyState)) return;
      late final List<Ledger> items;
      late final int count;
      if (isCombined) {
        final companies = companyState.selectedCompanies;
        final results = await Future.wait([
          _service.getCombinedCustomers(companyNames: companies),
          _service.getCombinedCustomerCount(companyNames: companies),
        ]);
        items = results[0] as List<Ledger>;
        count = results[1] as int;
      } else {
        final results = await Future.wait([
          _service.getCustomers(companyName: company),
          _service.getCustomerCount(companyName: company),
        ]);
        items = results[0] as List<Ledger>;
        count = results[1] as int;
      }
      if (!mounted ||
          generation != _loadGeneration ||
          !CompanyScope.stillActiveScope(scopeKey, CompanyProvider.of(context).scopeKey)) {
        return;
      }
      _pendingCustomers = items;
      _serverTotalCount = count;
      if (!_scrollController.hasClients) {
        _applyPendingData();
      } else {
        final pos = _scrollController.position;
        if (pos.pixels <= 0 || pos.pixels >= pos.maxScrollExtent) {
          _applyPendingData();
        }
      }
    } catch (_) {
      // Fail silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      primary: false,
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text('Ledgers'),
        backgroundColor: AppTheme.cardColor,
        surfaceTintColor: AppTheme.cardColor,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded, color: AppTheme.primaryColor),
            tooltip: 'Sort By',
            onSelected: (value) {
              setState(() => _sortOption = value);
              _onSearchChanged();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'Alphabetical',
                child: Text('Alphabetical (A-Z)', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              const PopupMenuItem(
                value: 'Recently Active',
                child: Text('Recently Active', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              const PopupMenuItem(
                value: 'Highest Balance',
                child: Text('Highest Balance', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          SearchBarWidget(
            hintText: 'Search customers...',
            controller: _searchController,
            onChanged: (_) => _onSearchChanged(),
          ),
          _buildTypeFilter(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: AppTheme.primaryColor,
              child: CustomScrollView(
                controller: _scrollController,
                cacheExtent: 1500,
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  _buildBody(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoading) return const SizedBox.shrink();
    final activeCount = _displayActiveCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Customers', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('$_displayTotalCount', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                Text('$activeCount active', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.people_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: ['All', 'Debtors', 'Creditors'].map((type) {
          final isSelected = _typeFilter == type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                type,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: AppTheme.primaryColor,
              backgroundColor: AppTheme.cardColor,
              side: BorderSide(color: AppTheme.dividerColor),
              checkmarkColor: Colors.white,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _typeFilter = type);
                  UserPreferencesService.saveLedgerTypeFilter(type);
                  _onSearchChanged();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const SliverFillRemaining(child: ShimmerLoading());
    if (_error != null) return SliverFillRemaining(child: ErrorState(message: _error!, onRetry: _loadData));
    if (_filteredCustomers.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.people_outlined,
          title: 'No Customers Found',
          subtitle: _searchController.text.trim().isNotEmpty ? 'Try a different search term or check filters' : 'Customer data will appear here once synced from Tally',
          onRetry: _loadData,
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final customer = _filteredCustomers[index];
            return _CustomerCard(customer: customer);
          },
          childCount: _filteredCustomers.length,
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Ledger customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LedgerStatementScreen(ledger: customer),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_rounded, color: AppTheme.primaryColor, size: 18),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                    if (CompanyProvider.of(context).isCombinedMode &&
                        customer.companyName != null &&
                        customer.companyName!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      CombinedCompanyChip(companyName: customer.companyName!),
                    ],
                  ],
                ),
              ),
              if (!customer.isActive)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text('Inactive', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
