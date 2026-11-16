import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app/app_state.dart';
import '../../core/app/theme.dart';
import '../../core/calendar/badi.dart';
import '../desktop/widgets.dart';

/// The Alláh-u-Abhá counter (GTK `counter.py`): Space or Enter counts, Backspace undoes, Ctrl+0 starts over, Esc goes
/// back. A tap anywhere outside the other controls also counts, with a light tap of the phone's vibration, so the
/// count can be kept without looking for the button. The count is kept only while the app runs; it is not a record. The target is remembered.
class CounterView extends StatefulWidget {
  const CounterView({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<CounterView> createState() => _CounterViewState();
}

/// One count for the whole run of the app, like the GTK app's.
Counter? _counter;

class _CounterViewState extends State<CounterView> {
  final focus = FocusNode();
  final custom = TextEditingController();
  final customFocus = FocusNode();
  late Counter counter;
  bool customShown = false;

  @override
  void initState() {
    super.initState();
    counter = _counter ??= Counter(AppScope.read(context).settings.counterTarget);
    customShown = !Counter.presets.contains(counter.target);
    if (customShown) custom.text = '${counter.target}';
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  void dispose() {
    focus.dispose();
    custom.dispose();
    customFocus.dispose();
    super.dispose();
  }

  /// A count from the button or a tap on the page. A tap while typing a target only closes the keyboard.
  void _count() {
    if (customFocus.hasFocus) return focus.requestFocus();
    HapticFeedback.lightImpact();
    setState(counter.add);
  }

  void _setTarget(Object? value) {
    if (counter.setTarget(value)) {
      AppScope.read(context).setCounterTarget(counter.target);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = ReaderColors.of(context);
    final verse = state.library?.byId.values.where((x) => x.id.endsWith('aqdas:Paragraphs:18')).firstOrNull;
    final serif = TextStyle(fontFamily: readingFonts.first, fontFamilyFallback: readingFonts.sublist(1));
    return CallbackShortcuts(
      bindings: {
        // Not while typing a custom target, and holding a key counts once.
        const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false): () =>
            customFocus.hasFocus ? null : setState(counter.add),
        const SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false): () =>
            customFocus.hasFocus ? null : setState(counter.add),
        const SingleActivator(LogicalKeyboardKey.backspace, includeRepeats: false): () =>
            customFocus.hasFocus ? null : setState(counter.undo),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => setState(counter.reset),
        const SingleActivator(LogicalKeyboardKey.escape): widget.onBack,
      },
      child: Focus(
        focusNode: focus,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _count,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    Text(
                      'Alláh-u-Abhá',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.accentText),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: counter.done || (counter.count > 0 && counter.count % 19 == 0),
                      label: '$counter',
                      child: Text(
                        '${counter.count}',
                        style: serif.copyWith(
                          fontSize: 96,
                          height: 1.1,
                          color: counter.done ? p.accentText : p.foreground,
                        ),
                      ),
                    ),
                    Text('$counter'),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: SizedBox(
                        width: double.infinity,
                        height: 72,
                        child: FilledButton(
                          onPressed: _count,
                          style: FilledButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          child: Text(counter.done ? 'Complete' : 'Count'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Or tap anywhere on the page', style: dimStyle(context, size: 13.5)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        const Text('Target'),
                        DropdownButton<String>(
                          value: customShown ? 'custom' : '${counter.target}',
                          underline: const SizedBox(),
                          items: [
                            for (final n in Counter.presets) DropdownMenuItem(value: '$n', child: Text('$n')),
                            const DropdownMenuItem(value: 'custom', child: Text('Custom…')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => customShown = v == 'custom');
                            if (v != 'custom') _setTarget(v);
                          },
                        ),
                        if (customShown)
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: custom,
                              focusNode: customFocus,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: 'Number', contentPadding: EdgeInsets.all(10)),
                              onChanged: _setTarget,
                              onSubmitted: (_) => focus.requestFocus(),
                            ),
                          ),
                        OutlinedButton(onPressed: () => setState(counter.undo), child: const Text('Undo')),
                        OutlinedButton(onPressed: () => setState(counter.reset), child: const Text('Reset')),
                        Tooltip(
                          message: 'Back to where you were (Esc)',
                          child: OutlinedButton(onPressed: widget.onBack, child: const Text('Back')),
                        ),
                      ],
                    ),
                    if (verse != null) ...[
                      const SizedBox(height: 28),
                      Text(
                        verse.unnumbered,
                        style: serif.copyWith(fontSize: (state.settings.textSize - 4).clamp(15, 40)),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('— ${verse.citation}', style: dimStyle(context, size: 13.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
