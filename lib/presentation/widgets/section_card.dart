import 'package:flutter/material.dart';

class SectionCard extends StatefulWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.expansionNotifier,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final bool collapsible;
  final bool initiallyExpanded;
  final ValueNotifier<bool>? expansionNotifier;

  @override
  State<SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<SectionCard> {
  static final Map<String, bool> _expansionMemory = <String, bool>{};

  late bool _isExpanded;
  VoidCallback? _notifierListener;

  String get _memoryKey => widget.title;

  bool _readInitialExpansion() {
    final persisted = _expansionMemory[_memoryKey];
    if (persisted != null) {
      return persisted;
    }
    return widget.expansionNotifier?.value ?? widget.initiallyExpanded;
  }

  void _persistExpansion(bool value) {
    _expansionMemory[_memoryKey] = value;
  }

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.collapsible ? _readInitialExpansion() : true;
    _persistExpansion(_isExpanded);
    _updateNotifierListener(
      oldNotifier: null,
      newNotifier: widget.expansionNotifier,
    );
  }

  @override
  void didUpdateWidget(covariant SectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final notifierChanged =
        oldWidget.expansionNotifier != widget.expansionNotifier;
    if (notifierChanged) {
      _updateNotifierListener(
        oldNotifier: oldWidget.expansionNotifier,
        newNotifier: widget.expansionNotifier,
      );
    }

    if (!widget.collapsible && !_isExpanded) {
      setState(() => _isExpanded = true);
      _persistExpansion(true);
      return;
    }

    if (!oldWidget.collapsible && widget.collapsible) {
      final shouldExpand =
          widget.expansionNotifier?.value ?? widget.initiallyExpanded;
      if (_isExpanded != shouldExpand) {
        setState(() => _isExpanded = shouldExpand);
        _persistExpansion(shouldExpand);
      }
      return;
    }

    if (notifierChanged &&
        widget.collapsible &&
        widget.expansionNotifier != null) {
      final shouldExpand = widget.expansionNotifier!.value;
      if (_isExpanded != shouldExpand) {
        setState(() => _isExpanded = shouldExpand);
        _persistExpansion(shouldExpand);
      }
    }
  }

  void _updateNotifierListener({
    ValueNotifier<bool>? oldNotifier,
    ValueNotifier<bool>? newNotifier,
  }) {
    if (oldNotifier != null && _notifierListener != null) {
      oldNotifier.removeListener(_notifierListener!);
    }
    if (newNotifier != null) {
      _notifierListener = () {
        if (!widget.collapsible) return;
        final shouldExpand = newNotifier.value;
        if (_isExpanded != shouldExpand) {
          setState(() => _isExpanded = shouldExpand);
          _persistExpansion(shouldExpand);
        }
      };
      newNotifier.addListener(_notifierListener!);
      if (widget.collapsible) {
        final shouldExpand = newNotifier.value;
        if (_isExpanded != shouldExpand) {
          _isExpanded = shouldExpand;
          _persistExpansion(shouldExpand);
        }
      }
    } else {
      _notifierListener = null;
    }
  }

  @override
  void dispose() {
    if (widget.expansionNotifier != null && _notifierListener != null) {
      widget.expansionNotifier!.removeListener(_notifierListener!);
    }
    super.dispose();
  }

  void _toggleExpanded() {
    if (!widget.collapsible) {
      return;
    }
    final next = !_isExpanded;
    setState(() => _isExpanded = next);
    _persistExpansion(next);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final hasHeaderActions =
                    widget.trailing != null || widget.collapsible;
                final stackHeader =
                    hasHeaderActions && constraints.maxWidth < 460;

                final titleRow = Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );

                final headerActions = hasHeaderActions
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (widget.trailing != null) widget.trailing!,
                          if (widget.collapsible)
                            IconButton(
                              onPressed: _toggleExpanded,
                              tooltip: _isExpanded
                                  ? 'Recolher card'
                                  : 'Expandir card',
                              icon: Icon(
                                _isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                              ),
                            ),
                        ],
                      )
                    : null;

                if (stackHeader) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleRow,
                      if (headerActions case final actions?) ...[
                        const SizedBox(height: 12),
                        actions,
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: titleRow),
                    if (headerActions case final actions?) ...[
                      const SizedBox(width: 12),
                      actions,
                    ],
                  ],
                );
              },
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                style: textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFC3CAD7),
                  height: 1.35,
                ),
              ),
            ],
            AnimatedCrossFade(
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: widget.child,
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 250),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }
}
