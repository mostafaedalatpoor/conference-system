import 'dart:async';

import 'package:flutter/material.dart';

import '../normalize.dart';
import '../theme/firouzeh.dart';

/// مهلت برگرداندن کار تازه (طراحی ۰۷-Done و ۱۳-MealOk).
const undoWindow = Duration(seconds: 8);

/// نوار «اشتباه زدم؟ برگردان ۸ ثانیه» با شمارش معکوس و نوار پیشرفت.
/// تا [deadline] نمایش داده می‌شود و بعد خودش ناپدید می‌شود.
/// قطعه‌ی تازه در سیستم Firouzeh؛ رنگ‌ها و اندازه‌ها از FirouzehColors و FirouzehSize.
class UndoBar extends StatefulWidget {
  final DateTime deadline;
  final VoidCallback onUndo;
  final String label;
  const UndoBar({super.key, required this.deadline, required this.onUndo, this.label = 'اشتباه زدم؟'});

  @override
  State<UndoBar> createState() => _UndoBarState();
}

class _UndoBarState extends State<UndoBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().isAfter(widget.deadline)) _tick?.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.deadline.difference(DateTime.now());
    if (left.isNegative) return const SizedBox.shrink();
    final x = FirouzehColors.of(context);
    final theme = Theme.of(context);
    final secs = (left.inMilliseconds / 1000).ceil();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: const BoxConstraints(minHeight: FirouzehSize.tapMin),
        padding: const EdgeInsets.symmetric(horizontal: FirouzehSize.space3),
        decoration: BoxDecoration(color: x.surface, borderRadius: BorderRadius.circular(FirouzehSize.radiusSm)),
        child: Row(children: [
          Icon(Icons.undo_rounded, size: 20, color: x.inkMuted),
          const SizedBox(width: FirouzehSize.space2),
          Expanded(child: Text(widget.label, style: theme.textTheme.bodyMedium)),
          OutlinedButton(
            onPressed: widget.onUndo,
            child: Text('برگردان  ${faDigits(secs)} ثانیه'),
          ),
        ]),
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          minHeight: 4,
          value: left.inMilliseconds / undoWindow.inMilliseconds,
          color: x.inkMuted,
          backgroundColor: x.line,
        ),
      ),
    ]);
  }
}
