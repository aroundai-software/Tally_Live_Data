import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class SearchBarWidget extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Widget? trailing;
  final EdgeInsetsGeometry? margin;

  const SearchBarWidget({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.trailing,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: false,
                hintText: hintText,
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                hintStyle: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
