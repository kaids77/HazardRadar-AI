import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A flat square profile photo. Without a photo it shows the initials of [name] on
/// the panel color, or a person icon when there is no name (guests).
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.name, this.photo, this.size = 40});

  final String? name;
  final Uint8List? photo;
  final double size;

  /// Up to two initials: "Charlie Mangyao" gives "CM", "ana" gives "A".
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    final first = words.first.characters.first;
    final last = words.length > 1 ? words.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final photo = this.photo;
    final letters = name == null ? '' : initials(name!);
    return Semantics(
      image: true,
      label: name == null ? 'Profile photo' : 'Profile photo of $name',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: palette.sage, border: Border.all(color: palette.ink)),
        clipBehavior: Clip.hardEdge,
        alignment: Alignment.center,
        child: photo != null
            ? Image.memory(
                photo,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallback(palette, letters),
              )
            : _fallback(palette, letters),
      ),
    );
  }

  Widget _fallback(AppPalette palette, String letters) => letters.isEmpty
      ? Icon(Icons.person_outline, color: palette.ink, size: size * 0.6)
      : Text(
          letters,
          style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: size * 0.42, color: palette.ink, height: 1),
        );
}
