import 'package:flutter/material.dart';

/// Up to six decimals (~0.1 m of latitude) without float noise or trailing zeros.
String formatSetting(double value) {
  final fixed = value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  return fixed == '-0' ? '0' : fixed;
}

/// Keeps an uncommitted draft while unrelated simulation settings change.
class NumericSettingField extends StatefulWidget {
  const NumericSettingField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix,
  });

  final String label;
  final double value, min, max;
  final String? suffix;
  final ValueChanged<double> onChanged;

  @override
  State<NumericSettingField> createState() => _NumericSettingFieldState();
}

class _NumericSettingFieldState extends State<NumericSettingField> {
  final fieldKey = GlobalKey<FormFieldState<String>>();
  String? applied;
  final scrollController = ScrollController(keepScrollOffset: false);
  late final controller = TextEditingController(
    text: formatSetting(widget.value),
  );

  @override
  void didUpdateWidget(NumericSettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      controller.text = formatSetting(widget.value);
      applied = null;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void apply() {
    if (!fieldKey.currentState!.validate()) return;
    applied = controller.text.trim();
    widget.onChanged(double.parse(applied!));
    FocusScope.of(context).unfocus();
  }

  /// Leaving the field applies a valid edit instead of silently dropping it;
  /// an invalid draft stays with its error shown.
  void applyOnBlur(bool focused) {
    final text = controller.text.trim();
    if (focused || text == applied || text == formatSetting(widget.value)) {
      return;
    }
    if (fieldKey.currentState!.validate()) {
      applied = text;
      widget.onChanged(double.parse(text));
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    skipTraversal: true,
    onFocusChange: applyOnBlur,
    child: TextFormField(
      key: fieldKey,
      controller: controller,
      scrollController: scrollController,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: widget.min < 0,
      ),
      textInputAction: TextInputAction.done,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (text) {
        final value = double.tryParse(text?.trim() ?? '');
        return value == null ||
                !value.isFinite ||
                value < widget.min ||
                value > widget.max
            ? 'Enter a number from ${formatSetting(widget.min)} to ${formatSetting(widget.max)}'
            : null;
      },
      onFieldSubmitted: (_) => apply(),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: widget.label,
        suffixText: widget.suffix,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: 'Apply ${widget.label.toLowerCase()}',
          onPressed: apply,
          icon: const Icon(Icons.check),
        ),
      ),
    ),
  );
}
