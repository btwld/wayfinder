/// One profile release, named by its profile name and version pair.
///
/// Resolution pivots on this pair: a bundle's declared release either matches
/// an available manifest release or degrades. Equality is by value.
final class OkfProfileRelease {
  /// Creates a release reference from its name and version.
  const OkfProfileRelease({required this.name, required this.version});

  /// The profile name.
  final String name;

  /// The profile release version.
  final String version;

  @override
  bool operator ==(Object other) =>
      other is OkfProfileRelease &&
      other.name == name &&
      other.version == version;

  @override
  int get hashCode => Object.hash(name, version);

  @override
  String toString() => '$name/$version';
}
