import 'package:flutter/material.dart';

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
  final scrollController = ScrollController(keepScrollOffset: false);
  late final controller = TextEditingController(text: widget.value.toString());

  @override
  void didUpdateWidget(NumericSettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      controller.text = widget.value.toString();
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
    widget.onChanged(double.parse(controller.text.trim()));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
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
          ? 'Enter a number from ${widget.min} to ${widget.max}'
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
  );
}
