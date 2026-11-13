import 'package:flutter/material.dart' as m;
import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../core/i18n.dart';

/// Rebuilds every piece of text when the language changes, and only then.
class LangScope extends InheritedWidget {
  final AppLanguage language;
  const LangScope({super.key, required this.language, required super.child});
  static AppLanguage of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<LangScope>()?.language ?? Lang.current;
  @override
  bool updateShouldNotify(LangScope old) => old.language != language;
}

/// The app's own Text. Same as Flutter's, but shows the words in the chosen language.
/// Every screen uses this one, so a new screen is translated as soon as its words are in the table.
class Text extends StatelessWidget {
  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final String? semanticsLabel;
  final TextScaler? textScaler;
  final StrutStyle? strutStyle;
  final TextWidthBasis? textWidthBasis;

  const Text(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.textScaler,
    this.strutStyle,
    this.textWidthBasis,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.textScaler,
    this.strutStyle,
    this.textWidthBasis,
  }) : data = null;

  @override
  Widget build(BuildContext context) {
    final lang = LangScope.of(context);
    if (textSpan != null) {
      return m.Text.rich(textSpan!,
          style: style,
          textAlign: textAlign,
          softWrap: softWrap,
          overflow: overflow,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textScaler: textScaler,
          strutStyle: strutStyle,
          textWidthBasis: textWidthBasis);
    }
    return m.Text(translate(data!, lang),
        style: style,
        textAlign: textAlign,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel == null ? null : translate(semanticsLabel!, lang),
        textScaler: textScaler,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis);
  }
}

/// The app's own InputDecoration: field names, help lines and hints in the chosen language.
class InputDecoration extends m.InputDecoration {
  InputDecoration({
    String? labelText,
    String? helperText,
    String? hintText,
    String? suffixText,
    super.prefixText,
    super.prefixIcon,
    super.suffixIcon,
    super.helperMaxLines,
    super.hintStyle,
    super.border,
    super.isDense,
    super.errorText,
    super.counterText,
    super.filled,
    super.fillColor,
    super.contentPadding,
  }) : super(
          labelText: labelText == null ? null : translate(labelText),
          helperText: helperText == null ? null : translate(helperText),
          hintText: hintText == null ? null : translate(hintText),
          suffixText: suffixText == null ? null : translate(suffixText),
        );
}

/// For the few places that need a plain translated string (tooltips, menu labels).
String tr(String english) => translate(english);
