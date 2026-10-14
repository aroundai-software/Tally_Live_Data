import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'summary_card.dart';

class CombinedCompanyChip extends StatelessWidget {
  final String companyName;
  final Color? color;

  const CombinedCompanyChip({
    super.key,
    required this.companyName,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Text(
        companyName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }
}

/// Tinted grand-total card used only in Combined Reports.
class CombinedSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const CombinedSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class CombinedReportBreakdown extends StatelessWidget {
  final Map<String, double> totalsByCompany;
  final Color accent;

  const CombinedReportBreakdown({
    super.key,
    required this.totalsByCompany,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (totalsByCompany.isEmpty) return const SizedBox.shrink();
    final entries = totalsByCompany.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    // Slightly different tint from grand total so the two cards are distinct.
    final cardColor = Color.lerp(accent, const Color(0xFF1A1F36), 0.18)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'By company',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cardColor,
            ),
          ),
          const SizedBox(height: 4),
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatCurrency(e.value),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cardColor,
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

class CombinedDateFilterPills extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final List<String> options;

  const CombinedDateFilterPills({
    super.key,
    required this.selected,
    required this.onChanged,
    this.options = const ['all', 'today', 'thisMonth', 'last30'],
  });

  String _label(String key) {
    switch (key) {
      case 'today':
        return 'Today';
      case 'thisMonth':
        return 'This Month';
      case 'last30':
        return 'Last 30 Days';
      default:
        return 'All';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((key) {
          final active = selected == key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_label(key)),
              selected: active,
              onSelected: (_) => onChanged(key),
              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? AppTheme.primaryColor : AppTheme.textSecondary,
              ),
              side: BorderSide(
                color: active ? AppTheme.primaryColor : Colors.grey.shade300,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

bool combinedDateMatches(DateTime? date, String filter) {
  if (filter == 'all' || date == null) return filter == 'all' ? true : false;
  final now = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  switch (filter) {
    case 'today':
      return day.isAtSameMomentAs(today);
    case 'thisMonth':
      return date.year == now.year && date.month == now.month;
    case 'last30':
      final start = today.subtract(const Duration(days: 29));
      return !day.isBefore(start) && !day.isAfter(today);
    default:
      return true;
  }
}
