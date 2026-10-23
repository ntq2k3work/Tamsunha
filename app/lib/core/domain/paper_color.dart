/// Stable paper color values exchanged with the backend.
///
/// Flutter colors belong in the presentation layer; these values are domain
/// identifiers and must remain stable in JSON and database contracts.
enum PaperColor {
  pink('pink'),
  butter('butter'),
  sage('sage'),
  blue('blue'),
  lilac('lilac');

  const PaperColor(this.wireValue);

  final String wireValue;

  static PaperColor fromJson(Object? value) {
    if (value is! String) {
      throw const FormatException('paper_color must be a string.');
    }
    for (final paperColor in PaperColor.values) {
      if (paperColor.wireValue == value) return paperColor;
    }
    throw FormatException('Unsupported paper_color: $value.');
  }
}
