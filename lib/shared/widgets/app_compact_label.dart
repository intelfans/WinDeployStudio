import 'package:flutter/material.dart';

/// A single-line label for compact controls such as tags, badges, and chips.
///
/// These controls are commonly placed in a [Wrap]. Keeping their text on one
/// line lets the [Wrap] move the complete control to its next run instead of
/// splitting its final character onto a line by itself.
class AppCompactLabel extends StatelessWidget {
  const AppCompactLabel(this.data, {super.key, this.style, this.textAlign});

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }
}
